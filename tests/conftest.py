"""
Shared pytest fixtures for the SubVision engine.

Dev setup (see tests/README.md for the full commands): the engine runs in a
self-contained uv 0.11.4 + CPython 3.13.12 environment under
~/Library/Application Support/SubVision-dev, never in a system Python.

The demo clips live in demo/ at the repo root (a symlink or a copy of the
release assets): tests that need them skip when they are missing. Nothing is
ever written next to the clips: tests copy them into tmp_path first.
"""

from __future__ import annotations

import os
import shutil
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
DEMO_DIR = ROOT / "demo"
DEMO_ITA = DEMO_DIR / "sintel_ita_hardsub_demo.mp4"
DEMO_ENG = DEMO_DIR / "sintel_eng_hardsub_demo.mp4"

# Fast profile used throughout the tests (12 lines expected on the ita clip):
# fps 6, skip near-identical frames, single variant, no refine, no signs band.
FAST_PROFILE = dict(fps=6.0, lang_hint="Italian", top_band=False,
                    multi_variant=False, skip_hamming=1, refine_timing=False,
                    workers=4, qc_report=True)
FAST_PROFILE_LINES = 12


def _find_tool(name: str) -> str | None:
    found = shutil.which(name)
    if found:
        return found
    brew = Path("/opt/homebrew/bin") / name
    return str(brew) if brew.exists() else None


@pytest.fixture(scope="session")
def ffmpeg_bin() -> str:
    """Path of ffmpeg (PATH or /opt/homebrew/bin); skips when missing."""
    path = _find_tool("ffmpeg")
    if not path or not _find_tool("ffprobe"):
        pytest.skip("ffmpeg/ffprobe not found (PATH or /opt/homebrew/bin)")
    return path


@pytest.fixture(scope="session", autouse=True)
def _tools_on_path(request) -> None:
    """
    The engine still calls ffmpeg/ffprobe by name (configurable paths arrive
    in F1.4): make /opt/homebrew/bin visible to the whole session.
    """
    brew = "/opt/homebrew/bin"
    if Path(brew).is_dir() and brew not in os.environ.get("PATH", "").split(os.pathsep):
        os.environ["PATH"] = brew + os.pathsep + os.environ.get("PATH", "")


@pytest.fixture(scope="session")
def demo_ita() -> Path:
    if not DEMO_ITA.exists():
        pytest.skip(f"demo clip missing: {DEMO_ITA}")
    return DEMO_ITA


@pytest.fixture(scope="session")
def demo_eng() -> Path:
    if not DEMO_ENG.exists():
        pytest.skip(f"demo clip missing: {DEMO_ENG}")
    return DEMO_ENG


@pytest.fixture
def demo_ita_copy(demo_ita: Path, tmp_path: Path) -> Path:
    """A private copy of the ita clip: the engine writes its outputs next to it."""
    dst = tmp_path / demo_ita.name
    shutil.copyfile(demo_ita, dst)
    return dst
