"""
The command-line interface (activity 1.9) through `python -m subvision.cli`
in the test venv, and the launcher's lock marker without network.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from subvision import core

from conftest import FAST_PROFILE_LINES, ROOT

LAUNCHER = ROOT / "subvision"
DEV_STATE = Path.home() / "Library" / "Application Support" / "SubVision-dev"


def _cli(args: list[str], state: Path, ffmpeg: str | None = None, **kw) -> subprocess.CompletedProcess:
    env = {**os.environ, "SUBVISION_STATO": str(state)}
    if ffmpeg:
        env["SUBVISION_FFMPEG"] = ffmpeg
    return subprocess.run([sys.executable, "-m", "subvision.cli", *args],
                          capture_output=True, text=True, env=env, timeout=300, **kw)


def test_version_and_help(tmp_path: Path):
    res = _cli(["--version"], tmp_path / "state")
    assert res.returncode == 0 and res.stdout.strip() == f"subvision {core.__version__}"
    res = _cli([], tmp_path / "state")
    assert res.returncode == 2 and "extract" in res.stderr and "serve" in res.stderr
    res = _cli(["extract", "--help"], tmp_path / "state")
    assert res.returncode == 0 and "--skip-hamming" in res.stdout and "--no-top" in res.stdout


def test_extract_then_fix(demo_ita: Path, ffmpeg_bin: str, tmp_path: Path):
    if not core.vision_available():
        pytest.skip("Apple Vision (ocrmac) not available")
    clip = tmp_path / demo_ita.name
    shutil.copyfile(demo_ita, clip)
    state = tmp_path / "state"
    res = _cli(["extract", str(clip), "--fps", "6", "--skip-hamming", "1",
                "--no-refine", "--no-top", "--no-multi"], state, ffmpeg_bin)
    assert res.returncode == 0, res.stderr
    srt = clip.with_suffix(".srt")
    assert srt.exists() and len(core.parse_srt(srt)) == FAST_PROFILE_LINES
    assert res.stdout.splitlines() == [str(srt), str(clip.with_suffix(".review.html"))]
    assert "[1/1] " + clip.name in res.stderr
    assert "extract · bottom:" in res.stderr and "ocr · bottom:" in res.stderr
    assert f"done: {FAST_PROFILE_LINES} lines" in res.stderr
    assert "batch: 1 done, 0 failed, 0 stopped" in res.stderr
    assert clip.with_suffix(".log").exists()
    assert (state / "ignore.txt").exists()           # lists created from the defaults
    assert not list((state / "tmp").glob("voc26_*"))

    res = _cli(["fix", str(srt), "--min-dur", "0.2"], state)
    assert res.returncode == 0, res.stderr
    out = Path(res.stdout.strip())
    assert out.exists() and "-fixed-" in out.name and out.parent == clip.parent
    assert len(core.parse_srt(out)) == FAST_PROFILE_LINES
    assert res.stderr.strip().startswith(f"{FAST_PROFILE_LINES} lines -> ")

    res = _cli(["fix", str(tmp_path / "missing.srt")], state)
    assert res.returncode == 2 and "not_found" in res.stderr


def test_extract_errors(tmp_path: Path, ffmpeg_bin: str):
    res = _cli(["extract", str(tmp_path / "missing.mp4")], tmp_path / "state", ffmpeg_bin)
    assert res.returncode == 2 and "not found" in res.stderr
    bogus = tmp_path / "bogus.mp4"
    bogus.write_bytes(b"nope")
    res = _cli(["extract", str(bogus), "--lang", "Klingon", "--no-top"], tmp_path / "state", ffmpeg_bin)
    assert res.returncode == 2 and "bad_params" in res.stderr
    if core.vision_available():
        res = _cli(["extract", str(bogus), "--no-top"], tmp_path / "state", ffmpeg_bin)
        assert res.returncode == 1 and "FAILED at extract:bottom: probe_failed" in res.stderr
        assert "batch: 0 done, 1 failed" in res.stderr


# ---------------------------------------------------------------- launcher
def _launcher(state: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    env = {k: v for k, v in os.environ.items() if not k.startswith("UV_")}
    env["SUBVISION_STATO"] = str(state)
    if check:
        env["SUBVISION_LAUNCHER_CHECK"] = "1"
    return subprocess.run([str(LAUNCHER), *args], capture_output=True, text=True,
                          env=env, timeout=120)


@pytest.fixture
def launcher_state(tmp_path: Path) -> Path:
    """
    A state folder with the dev uv and a copy of the dev venv (symlinks to
    the managed Python kept), so the launcher can decide without network.
    """
    uv = DEV_STATE / "bin" / "uv"
    venv = DEV_STATE / ".venv"
    if not uv.is_file() or not (venv / "bin" / "python").exists():
        pytest.skip("dev state (uv + venv) not available under SubVision-dev")
    state = tmp_path / "state"
    (state / "bin").mkdir(parents=True)
    shutil.copy2(uv, state / "bin" / "uv")
    shutil.copytree(venv, state / ".venv", symlinks=True)
    return state


def test_launcher_marker_decides_the_sync(launcher_state: Path):
    assert os.access(LAUNCHER, os.X_OK)
    marker = launcher_state / ".venv" / ".subvision-lock-sha256"
    lock_sha = hashlib.sha256((ROOT / "uv.lock").read_bytes()).hexdigest()
    # no marker: the environment must be (re)synced
    res = _launcher(launcher_state, "--version")
    assert res.returncode == 0 and "launcher: sync needed" in res.stderr, res.stderr
    # a stale marker (another uv.lock): resync
    marker.write_text("0" * 64 + "\n")
    res = _launcher(launcher_state, "--version")
    assert "launcher: sync needed" in res.stderr
    # the right marker and a working venv: ready, no sync
    marker.write_text(lock_sha + "\n")
    res = _launcher(launcher_state, "--version")
    assert res.returncode == 0 and "launcher: environment ready" in res.stderr, res.stderr
    # and the real launch runs the CLI from that venv without uv
    res = _launcher(launcher_state, "--version", check=False)
    assert res.returncode == 0 and res.stdout.strip() == f"subvision {core.__version__}", res.stderr
    assert "sync" not in res.stderr.lower()
    # a venv that no longer imports THIS checkout's code is not "ready"
    pths = list((launcher_state / ".venv").glob("lib/python*/site-packages/*subvision*.pth"))
    assert pths, "no editable .pth of subvision in the copied venv"
    for pth in pths:
        pth.write_text("/nowhere\n")
    res = _launcher(launcher_state, "--version")
    assert "launcher: sync needed" in res.stderr, res.stderr


def test_launcher_reads_the_saved_language(launcher_state: Path):
    (launcher_state / "records").mkdir()
    (launcher_state / "records" / "settings.json").write_text('{"language": "it"}')
    (launcher_state / ".venv" / ".subvision-lock-sha256").write_text("x\n")
    # with a stale marker the launcher announces the resync, in Italian, before it would sync
    res = _launcher(launcher_state, "--version")
    assert "launcher: sync needed" in res.stderr
    assert "Aggiornamento: risincronizzo l'ambiente Python" in res.stderr, res.stderr
    (launcher_state / "records" / "settings.json").write_text('{"language": "en"}')
    res = _launcher(launcher_state, "--version")
    assert "Update: re-syncing the Python environment" in res.stderr, res.stderr
