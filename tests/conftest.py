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
    """
    Path of ffmpeg (PATH or /opt/homebrew/bin); skips when missing. Also
    configures the engine (core.set_tools) with ffmpeg and ffprobe, so every
    test that needs the tools just requests this fixture.
    """
    from subvision import core
    ffmpeg, ffprobe = _find_tool("ffmpeg"), _find_tool("ffprobe")
    if not ffmpeg or not ffprobe:
        pytest.skip("ffmpeg/ffprobe not found (PATH or /opt/homebrew/bin)")
    core.set_tools(ffmpeg, ffprobe)
    return ffmpeg


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


# ---------------------------------------------------------------- damaged videos
# Two repeatable ways to damage a demo clip (the "corrupted video" QA scenario
# of the app uses the same recipes, see the shell commands in the docstrings).
HEALTHY_HEAD = 1_000_000      # bytes of the clip left intact by damage_tail()


def damage_head(src: Path, dst: Path, cut: int = 100_000) -> Path:
    """
    A video that ffprobe refuses ("moov atom not found"): the clip without
    its first `cut` bytes, where the index of an .mp4 lives.

        tail -c +100001 sintel_ita_hardsub_demo.mp4 > no-index.mp4
    """
    dst.write_bytes(src.read_bytes()[cut:])
    return dst


def damage_tail(src: Path, dst: Path, keep: int = HEALTHY_HEAD) -> Path:
    """
    A video that ffprobe accepts (the index is intact: 55 s, 1280x544) but
    that fails in the middle of the extraction: the first `keep` bytes of
    the clip, then zeros up to the original size. ffmpeg writes the first
    seconds, then gives up with exit status 69 because more than 2/3 of the
    frames cannot be decoded ("Decode error rate ... exceeds maximum").
    With less damage (say, zeros from the middle on, or a truncated file)
    ffmpeg ends well and the result is a shorter SRT, not an error.

        SRC=sintel_ita_hardsub_demo.mp4
        { head -c 1000000 "$SRC"; head -c $(( $(stat -f%z "$SRC") - 1000000 )) /dev/zero; } > damaged.mp4
    """
    data = src.read_bytes()
    dst.write_bytes(data[:keep] + bytes(len(data) - keep))
    return dst


@pytest.fixture
def demo_ita_copy(demo_ita: Path, tmp_path: Path) -> Path:
    """A private copy of the ita clip: the engine writes its outputs next to it."""
    dst = tmp_path / demo_ita.name
    shutil.copyfile(demo_ita, dst)
    return dst
