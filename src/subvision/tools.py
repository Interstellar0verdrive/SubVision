"""
ffmpeg/ffprobe for the SubVision app: pinned static builds downloaded into
the state folder, with resume and sha256 verification.

Adapted from `strumenti.scarica` / `setup.py` of AnimeUp 2.1 (MIT licensed
pieces by the same author): same release, same URLs, same checksums, same
checks (sha256, static binary via `otool -L`, `-version`). What changes:
the archive is downloaded straight into `<state>/bin/<key>.part` and the
binary is extracted from there (no download cache), the progress callback
is a plain function with the fields of the `tools.progress` event, and the
stop signal is a `threading.Event`.

A pinned RELEASE with its checksum, not "the latest snapshot": two
installations made a week apart must run the same ffmpeg, otherwise a
defect cannot be reproduced. Changing the version is a choice to make here,
testing it, together with a SubVision release.
"""

from __future__ import annotations

import hashlib
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, Iterable, List, Optional

from subvision import __version__

FFMPEG_VERSION = "9.0.2"
_FFMPEG_BASE = "https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2"

# Progress callback: progress(key, state, bytes, total, error=None, detail=None)
# with state in waiting | running | done | failed. The sidecar turns it into
# the `tools.progress` event; `error` is one of the ToolsError codes below,
# `detail` the technical text that goes with it.
ProgressCallback = Callable[..., None]

CHUNK = 1 << 16          # download block; the stop event is checked per block
TIMEOUT = 60             # seconds, per socket operation
STATES = ("waiting", "running", "done", "failed")


@dataclass(frozen=True)
class ToolSpec:
    url: str
    sha256: str
    size: int            # bytes of the archive (shown before the server says the real total)
    version: str


TOOLS: Dict[str, ToolSpec] = {
    "ffmpeg": ToolSpec(
        url=f"{_FFMPEG_BASE}/ffmpeg.zip",
        sha256="c8ed4c4e6978a03c485edbfe4e0a5dc2380f8a30bba5150531b31b094492d924",
        size=28_395_699, version=FFMPEG_VERSION),
    "ffprobe": ToolSpec(
        url=f"{_FFMPEG_BASE}/ffprobe.zip",
        sha256="fcbe839537485eaee7a7a8bc5cbc0f90d53617e80943e8a5b2e31cb851197ea6",
        size=28_317_701, version=FFMPEG_VERSION),
}


class ToolsError(Exception):
    """
    Installation error with a stable `code`:
      checksum     archive complete but with the wrong sha256 (deleted)
      network      HTTP error or connection closed early (`.part` kept)
      interrupted  stop event set (`.part` kept)
      archive      the binary is not in the archive
      not_static   the binary depends on non-system libraries
      version      the binary does not answer `-version`
    """

    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(f"{code}: {detail}" if detail else code)
        self.code = code
        self.detail = detail


# ---------------------------------------------------------------- helpers
def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def tool_version(binary: Path | str) -> Optional[str]:
    """
    The version declared by `ffmpeg -version` / `ffprobe -version`
    ("ffmpeg version 9.0.2-https://www.martin-riedl.de Copyright ..." ->
    "9.0.2"), None when the file does not run or does not look like ffmpeg.
    """
    try:
        line = subprocess.run([str(binary), "-hide_banner", "-version"],
                              capture_output=True, text=True, timeout=30,
                              check=False).stdout.split("\n", 1)[0]
    except (OSError, subprocess.SubprocessError):
        return None
    parts = line.split()
    if len(parts) < 3 or parts[1] != "version":
        return None
    return parts[2].split("-", 1)[0]


def is_static(binary: Path) -> Optional[bool]:
    """
    True when the binary depends only on system libraries (`otool -L`),
    None when otool is not available (the check is skipped).
    """
    try:
        out = subprocess.run(["otool", "-L", str(binary)], capture_output=True,
                             text=True, check=False, timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    deps = [ln.strip().split(" ")[0] for ln in out.splitlines()[1:] if ln.strip()]
    return all(d.startswith("/usr/lib/") or d.startswith("/System/") for d in deps)


def remove_quarantine(path: Path) -> None:
    """Drops the com.apple.quarantine attribute, tolerant (absent attribute, no xattr)."""
    try:
        subprocess.run(["xattr", "-d", "com.apple.quarantine", str(path)],
                       capture_output=True, check=False, timeout=30)
    except (OSError, subprocess.SubprocessError):
        pass


def extract_binary(archive: Path, name: str, dest: Path) -> bool:
    """Extracts the file `name` from the zip into `dest` (executable)."""
    if not zipfile.is_zipfile(archive):
        return False
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        with zipfile.ZipFile(archive) as z:
            z.extractall(tmpdir)
        for candidate in tmpdir.rglob(name):
            if candidate.is_file():
                shutil.copy2(candidate, dest)
                dest.chmod(0o755)
                return True
    return False


def _stopped(stop: Optional[threading.Event]) -> bool:
    return stop is not None and stop.is_set()


# ---------------------------------------------------------------- download
def download(url: str, part: Path, sha256: str,
             progress: Callable[[int, int], None],
             stop: Optional[threading.Event] = None) -> Path:
    """
    Downloads `url` into `part` (a `.part` file), resuming what is already
    there with an HTTP Range request, and verifies the sha256 once the file
    is complete. Returns `part` verified. Raises ToolsError: `network` and
    `interrupted` keep the partial file for the next attempt, `checksum`
    deletes it (a complete archive with the wrong hash is never installed).
    progress(bytes_done, bytes_total) with total 0 when unknown.
    """
    part.parent.mkdir(parents=True, exist_ok=True)
    have = part.stat().st_size if part.is_file() else 0
    headers = {"User-Agent": f"subvision/{__version__}", "Accept": "*/*"}
    if have:
        headers["Range"] = f"bytes={have}-"
    request = urllib.request.Request(url, headers=headers)
    try:
        response = urllib.request.urlopen(request, timeout=TIMEOUT)
    except urllib.error.HTTPError as exc:
        if exc.code == 416 and have:          # already complete: verified below
            response = None
        else:
            raise ToolsError("network", f"HTTP {exc.code}") from exc
    except (urllib.error.URLError, OSError) as exc:
        raise ToolsError("network", str(exc)) from exc

    if response is not None:
        with response:
            resumed = bool(have) and response.status == 206
            if not resumed:
                have = 0
            length = int(response.headers.get("Content-Length") or 0)
            total = have + length if length else 0
            done = have
            with part.open("ab" if resumed else "wb") as f:
                while True:
                    if _stopped(stop):
                        raise ToolsError("interrupted")
                    try:
                        block = response.read(CHUNK)
                    except (OSError, ValueError) as exc:   # ValueError: IncompleteRead-like
                        raise ToolsError("network", str(exc)) from exc
                    if not block:
                        break
                    f.write(block)
                    done += len(block)
                    progress(done, total or done)
            if total and done < total:
                # the server closed early: keep the partial file, resume later
                raise ToolsError("network", f"connection closed at {done}/{total} bytes")

    if sha256_of(part) != sha256:
        part.unlink(missing_ok=True)
        raise ToolsError("checksum", part.name)
    return part


# ---------------------------------------------------------------- install
def bin_dir(state_dir: Path | str) -> Path:
    return Path(state_dir) / "bin"


def status(state_dir: Path | str) -> Dict[str, Dict[str, object]]:
    """{key: {"present": bool, "path": str, "version": str|None}} for every tool."""
    out: Dict[str, Dict[str, object]] = {}
    for key, spec in TOOLS.items():
        path = bin_dir(state_dir) / key
        version = tool_version(path) if path.is_file() else None
        out[key] = {"present": version == spec.version, "path": str(path),
                    "version": version}
    return out


def missing(state_dir: Path | str) -> List[str]:
    return [k for k, s in status(state_dir).items() if not s["present"]]


def install_one(key: str, state_dir: Path | str,
                progress: Callable[[int, int], None],
                stop: Optional[threading.Event] = None,
                check_static: bool = True) -> Path:
    """
    Downloads, verifies and installs one tool into `<state>/bin/<key>`.
    Raises ToolsError (see the codes on the class).
    """
    spec = TOOLS[key]
    bdir = bin_dir(state_dir)
    bdir.mkdir(parents=True, exist_ok=True)
    part = bdir / f"{key}.part"
    dest = bdir / key
    archive = download(spec.url, part, spec.sha256, progress, stop)
    try:
        if not extract_binary(archive, key, dest):
            raise ToolsError("archive", f"{key} not found in {archive.name}")
    finally:
        archive.unlink(missing_ok=True)
    remove_quarantine(dest)
    if check_static and is_static(dest) is False:
        dest.unlink(missing_ok=True)
        raise ToolsError("not_static", key)
    version = tool_version(dest)
    if version != spec.version:
        dest.unlink(missing_ok=True)
        raise ToolsError("version", f"{key} answered {version!r}, expected {spec.version!r}")
    return dest


def install(keys: Optional[Iterable[str]], state_dir: Path | str,
            progress: Optional[ProgressCallback] = None,
            stop: Optional[threading.Event] = None,
            check_static: bool = True) -> bool:
    """
    Installs the requested tools (default: the missing ones), one after the
    other. progress(key, state, bytes, total, error=None): every tool is
    announced `waiting`, then `running` with the bytes, then `done` or
    `failed` (error = ToolsError code). Stops at the first failure: the
    others stay `waiting`, a new call starts again from there. Returns True
    when everything is installed (at once, with nothing to do). Never raises
    for the expected failures.
    """
    todo = [k for k in (list(keys) if keys is not None else missing(state_dir)) if k in TOOLS]

    def emit(key: str, state: str, done: int = 0, total: int = 0,
             error: Optional[str] = None, detail: Optional[str] = None) -> None:
        if progress:
            progress(key, state, done, total, error, detail)

    for key in todo:
        emit(key, "waiting", 0, TOOLS[key].size)
    for key in todo:
        last = [0.0]

        def step(done: int, total: int, key: str = key) -> None:
            now = time.monotonic()
            if now - last[0] < 0.2 and done < total:
                return
            last[0] = now
            emit(key, "running", done, total)

        emit(key, "running", 0, TOOLS[key].size)
        try:
            install_one(key, state_dir, step, stop, check_static)
        except ToolsError as exc:
            emit(key, "failed", 0, 0, exc.code, exc.detail or None)
            return False
        except Exception as exc:  # noqa: BLE001 - zip format, disk, ...
            emit(key, "failed", 0, 0, "unknown", f"{type(exc).__name__}: {exc}")
            return False
        emit(key, "done", TOOLS[key].size, TOOLS[key].size)
    return True


# ---------------------------------------------------------------- paths
def ffmpeg_path(state_dir: Path | str, custom: Optional[str] = None) -> Optional[str]:
    """
    The ffmpeg to use: `custom` ("Use my own ffmpeg" in Settings) when it
    answers `-version`, otherwise `<state>/bin/ffmpeg` when present. None
    when neither is usable.
    """
    return _tool_path("ffmpeg", state_dir, custom)


def ffprobe_path(state_dir: Path | str, custom: Optional[str] = None) -> Optional[str]:
    """
    The ffprobe to use: the `ffprobe` next to a valid custom ffmpeg (or the
    custom path itself when it is an ffprobe), otherwise `<state>/bin/ffprobe`.
    """
    if custom:
        c = Path(custom)
        if c.name != "ffprobe":
            c = c.with_name("ffprobe")
        if c.is_file() and tool_version(c):
            return str(c)
    return _tool_path("ffprobe", state_dir, None)


def _tool_path(key: str, state_dir: Path | str, custom: Optional[str]) -> Optional[str]:
    if custom:
        c = Path(custom)
        if c.is_file() and tool_version(c):
            return str(c)
    own = bin_dir(state_dir) / key
    if own.is_file():
        return str(own)
    return None
