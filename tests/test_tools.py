"""
Tests of the ffmpeg/ffprobe downloader against a local HTTP server that
serves a fake zip (a shell script that answers `-version`). The real 57 MB
are never downloaded here.
"""

from __future__ import annotations

import hashlib
import io
import os
import stat
import threading
import time
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

from subvision import tools

FAKE_VERSION = tools.FFMPEG_VERSION


def fake_zip(name: str, padding: int = 0) -> bytes:
    """A zip with one executable `name`: a sh script printing a version line."""
    script = (f"#!/bin/sh\necho 'ffmpeg version {FAKE_VERSION}-test Copyright (c) test'\n"
              + ("#" * padding + "\n" if padding else ""))
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_STORED) as z:
        info = zipfile.ZipInfo(name)
        info.external_attr = (stat.S_IFREG | 0o755) << 16
        z.writestr(info, script)
    return buf.getvalue()


class Server:
    """
    Serves `files` ({path: bytes}) with Range support. `truncate_first`
    cuts the first full response of a path after N bytes (then closes);
    `chunk_delay` slows the stream down so a stop can land in the middle.
    """

    def __init__(self, files: dict[str, bytes], truncate_first: int = 0,
                 chunk_delay: float = 0.0, chunk: int = 1 << 16) -> None:
        self.files = files
        self.truncate_first = truncate_first
        self.chunk_delay = chunk_delay
        self.chunk = chunk
        self.requests: list[tuple[str, str | None]] = []   # (path, Range header)
        self.truncated: set[str] = set()
        outer = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *a) -> None:   # quiet
                pass

            def do_GET(self) -> None:
                data = outer.files.get(self.path)
                rng = self.headers.get("Range")
                outer.requests.append((self.path, rng))
                if data is None:
                    self.send_error(404)
                    return
                start = 0
                if rng and rng.startswith("bytes="):
                    start = int(rng[6:].rstrip("-"))
                    if start >= len(data):
                        self.send_response(416)
                        self.send_header("Content-Length", "0")
                        self.end_headers()
                        return
                    self.send_response(206)
                    self.send_header("Content-Range", f"bytes {start}-{len(data)-1}/{len(data)}")
                else:
                    self.send_response(200)
                body = data[start:]
                self.send_header("Content-Type", "application/zip")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                cut = None
                if outer.truncate_first and self.path not in outer.truncated and not rng:
                    outer.truncated.add(self.path)
                    cut = outer.truncate_first
                try:
                    sent = 0
                    while sent < len(body):
                        piece = body[sent:sent + outer.chunk]
                        if cut is not None and sent + len(piece) > cut:
                            piece = piece[:cut - sent]
                        self.wfile.write(piece)
                        self.wfile.flush()
                        sent += len(piece)
                        if cut is not None and sent >= cut:
                            break
                        if outer.chunk_delay:
                            time.sleep(outer.chunk_delay)
                finally:
                    if cut is not None:
                        self.close_connection = True

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"

    def close(self) -> None:
        self.httpd.shutdown()
        self.httpd.server_close()


@pytest.fixture
def fake_tools(monkeypatch):
    """Replaces TOOLS with specs served by a local server; yields (server, blobs)."""
    blobs = {"ffmpeg": fake_zip("ffmpeg", padding=300_000),
             "ffprobe": fake_zip("ffprobe", padding=200_000)}
    made: list[Server] = []

    def make(**kw) -> Server:
        srv = Server({f"/{k}.zip": v for k, v in blobs.items()}, **kw)
        made.append(srv)
        monkeypatch.setattr(tools, "TOOLS", {
            k: tools.ToolSpec(url=f"{srv.url}/{k}.zip",
                              sha256=hashlib.sha256(v).hexdigest(),
                              size=len(v), version=FAKE_VERSION)
            for k, v in blobs.items()})
        return srv

    yield make, blobs
    for s in made:
        s.close()


class Events:
    def __init__(self) -> None:
        self.items: list[tuple] = []

    def __call__(self, key, state, done, total, error=None, detail=None) -> None:
        self.items.append((key, state, done, total, error))
        self.details = getattr(self, "details", {})
        if detail:
            self.details[key] = detail

    def states(self, key: str) -> list[str]:
        return [s for k, s, *_ in self.items if k == key]

    def last_error(self, key: str):
        return [e for k, s, _, _, e in self.items if k == key and s == "failed"][-1]


# ---------------------------------------------------------------- download
def test_install_full_download(fake_tools, tmp_path: Path) -> None:
    make, blobs = fake_tools
    srv = make()
    ev = Events()
    assert tools.install(None, tmp_path, ev) is True
    for key in ("ffmpeg", "ffprobe"):
        binary = tmp_path / "bin" / key
        assert binary.is_file() and os.access(binary, os.X_OK)
        assert tools.tool_version(binary) == FAKE_VERSION
        assert not (tmp_path / "bin" / f"{key}.part").exists()
        assert not (tmp_path / "bin" / f"{key}.zip").exists()
        st = ev.states(key)
        assert st[0] == "waiting" and st[-1] == "done" and "running" in st
        # the running events carry the real total from the server
        running = [(d, t) for k, s, d, t, _ in ev.items if k == key and s == "running" and d > 0]
        assert running and running[-1] == (len(blobs[key]), len(blobs[key]))
    # order: both announced waiting first, then one at a time
    assert [k for k, s, *_ in ev.items[:2]] == ["ffmpeg", "ffprobe"]
    assert all(s == "waiting" for _, s, *_ in ev.items[:2])
    assert all(r[1] is None for r in srv.requests)      # no Range on a fresh download
    status = tools.status(tmp_path)
    assert status["ffmpeg"]["present"] and status["ffprobe"]["present"]
    assert status["ffmpeg"]["version"] == FAKE_VERSION
    assert tools.missing(tmp_path) == []


def test_resume_from_part(fake_tools, tmp_path: Path) -> None:
    make, blobs = fake_tools
    cut = 100_000
    srv = make(truncate_first=cut)
    ev = Events()
    # first attempt: the server closes after `cut` bytes -> network error, .part kept
    assert tools.install(["ffmpeg"], tmp_path, ev) is False
    assert ev.last_error("ffmpeg") == "network"
    part = tmp_path / "bin" / "ffmpeg.part"
    assert part.is_file() and part.stat().st_size == cut
    assert not (tmp_path / "bin" / "ffmpeg").exists()
    # second attempt: Range from `cut`, 206, complete and verified
    ev2 = Events()
    assert tools.install(["ffmpeg"], tmp_path, ev2) is True
    assert not part.exists()
    assert tools.tool_version(tmp_path / "bin" / "ffmpeg") == FAKE_VERSION
    ranges = [r for p, r in srv.requests if p == "/ffmpeg.zip"]
    assert ranges == [None, f"bytes={cut}-"]
    # the resumed progress starts from the bytes already on disk
    first_running = [d for k, s, d, t, _ in ev2.items if k == "ffmpeg" and s == "running" and d > 0][0]
    assert first_running > cut


def test_wrong_checksum_deletes_archive(fake_tools, tmp_path: Path, monkeypatch) -> None:
    make, blobs = fake_tools
    make()
    bad = {k: tools.ToolSpec(s.url, "0" * 64, s.size, s.version) for k, s in tools.TOOLS.items()}
    monkeypatch.setattr(tools, "TOOLS", bad)
    ev = Events()
    assert tools.install(["ffprobe"], tmp_path, ev) is False
    assert ev.last_error("ffprobe") == "checksum"
    assert not (tmp_path / "bin" / "ffprobe.part").exists()
    assert not (tmp_path / "bin" / "ffprobe").exists()
    # the next tool was never started: it stays "waiting"
    ev2 = Events()
    assert tools.install(["ffprobe", "ffmpeg"], tmp_path, ev2) is False
    assert ev2.states("ffmpeg") == ["waiting"]


def test_stop_midway_keeps_part(fake_tools, tmp_path: Path) -> None:
    make, blobs = fake_tools
    make(chunk_delay=0.05, chunk=16_384)
    stop = threading.Event()
    ev = Events()

    def progress(key, state, done, total, error=None, detail=None):
        ev(key, state, done, total, error)
        if state == "running" and done > 0:
            stop.set()

    assert tools.install(["ffmpeg"], tmp_path, progress, stop) is False
    assert ev.last_error("ffmpeg") == "interrupted"
    part = tmp_path / "bin" / "ffmpeg.part"
    assert part.is_file()
    assert 0 < part.stat().st_size < len(blobs["ffmpeg"])
    assert not (tmp_path / "bin" / "ffmpeg").exists()
    # a new attempt (no stop) resumes and completes
    stop.clear()
    assert tools.install(["ffmpeg"], tmp_path, Events(), stop) is True
    assert tools.tool_version(tmp_path / "bin" / "ffmpeg") == FAKE_VERSION


def test_missing_file_is_a_network_error(fake_tools, tmp_path: Path, monkeypatch) -> None:
    make, _ = fake_tools
    srv = make()
    monkeypatch.setattr(tools, "TOOLS", {
        "ffmpeg": tools.ToolSpec(f"{srv.url}/nope.zip", "0" * 64, 1, FAKE_VERSION)})
    ev = Events()
    assert tools.install(["ffmpeg"], tmp_path, ev) is False
    assert ev.last_error("ffmpeg") == "network"


def test_wrong_version_is_rejected(fake_tools, tmp_path: Path, monkeypatch) -> None:
    make, _ = fake_tools
    make()
    other = {k: tools.ToolSpec(s.url, s.sha256, s.size, "8.0") for k, s in tools.TOOLS.items()}
    monkeypatch.setattr(tools, "TOOLS", other)
    ev = Events()
    assert tools.install(["ffmpeg"], tmp_path, ev) is False
    assert ev.last_error("ffmpeg") == "version"
    assert not (tmp_path / "bin" / "ffmpeg").exists()


# ---------------------------------------------------------------- paths
def test_tool_paths(tmp_path: Path, ffmpeg_bin: str) -> None:
    # nothing installed, no custom: None
    assert tools.ffmpeg_path(tmp_path) is None
    assert tools.ffprobe_path(tmp_path) is None
    # custom ffmpeg (Homebrew) that answers -version, ffprobe next to it
    assert tools.ffmpeg_path(tmp_path, ffmpeg_bin) == ffmpeg_bin
    assert tools.ffprobe_path(tmp_path, ffmpeg_bin) == str(Path(ffmpeg_bin).with_name("ffprobe"))
    # custom path that is not an ffmpeg: ignored
    bogus = tmp_path / "ffmpeg"
    bogus.write_text("#!/bin/sh\necho hello\n")
    bogus.chmod(0o755)
    assert tools.ffmpeg_path(tmp_path, str(bogus)) is None
    assert tools.tool_version(bogus) is None
    # the state copy wins when there is no custom
    own = tmp_path / "bin" / "ffmpeg"
    own.parent.mkdir()
    own.write_text("#!/bin/sh\necho 'ffmpeg version 9.0.2-x'\n")
    own.chmod(0o755)
    assert tools.ffmpeg_path(tmp_path) == str(own)
    assert tools.ffmpeg_path(tmp_path, str(bogus)) == str(own)
    assert tools.status(tmp_path)["ffmpeg"] == {"present": True, "path": str(own), "version": "9.0.2"}


def test_real_specs_are_pinned() -> None:
    for key, spec in tools.TOOLS.items():
        assert spec.url.endswith(f"/{key}.zip")
        assert len(spec.sha256) == 64 and spec.version == tools.FFMPEG_VERSION
        assert spec.size > 20_000_000
