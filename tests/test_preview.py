"""Tests of the preview module on the ita demo clip (frames and OCR test)."""

from __future__ import annotations

import os
import subprocess
import threading
import time
from pathlib import Path

import pytest

from subvision import core, preview
from subvision.core import OcrParams

from conftest import FAST_PROFILE


def _ffmpeg_processes(needle: str) -> list[str]:
    out = subprocess.run(["ps", "-axo", "command"], capture_output=True, text=True).stdout
    return [ln for ln in out.splitlines() if "ffmpeg" in ln and needle in ln]


@pytest.fixture
def params() -> OcrParams:
    return OcrParams(**FAST_PROFILE)


@pytest.fixture
def vision() -> None:
    if not core.vision_available():
        pytest.skip("Apple Vision (ocrmac) not available")


# ---------------------------------------------------------------- folders
def test_preview_dir_depends_on_path_and_mtime(tmp_path: Path) -> None:
    v = tmp_path / "a.mp4"
    v.write_bytes(b"x" * 10)
    d1 = preview.preview_dir(v, tmp_path)
    assert d1.parent == tmp_path / "tmp" / "preview" and len(d1.name) == 16
    assert preview.preview_dir(v, tmp_path) == d1
    os.utime(v, (1_000_000, 1_000_000))
    assert preview.preview_dir(v, tmp_path) != d1


def test_clean_old_removes_week_old_folders(tmp_path: Path) -> None:
    root = tmp_path / "tmp" / "preview"
    old, fresh = root / "old", root / "fresh"
    old.mkdir(parents=True)
    fresh.mkdir()
    (old / "000.jpg").write_bytes(b"")
    past = time.time() - 8 * 86400
    os.utime(old, (past, past))
    assert preview.clean_old(tmp_path) == 1
    assert not old.exists() and fresh.exists()
    assert preview.clean_old(tmp_path) == 0
    assert preview.clean_old(tmp_path / "nowhere") == 0


# ---------------------------------------------------------------- frames + OCR test
def test_find_frames_and_test_frame(demo_ita: Path, params: OcrParams, tmp_path: Path,
                                    ffmpeg_bin: str, vision) -> None:
    events: list[dict] = []
    t0 = time.time()
    frames = preview.find_frames(demo_ita, params, n=20, tries=3,
                                 emit=lambda name, data: events.append((name, data)),
                                 state=tmp_path)
    elapsed = time.time() - t0
    assert len(frames) == 20
    with_text = [f for f in frames if f["has_text"]]
    assert len(with_text) >= 10, f"only {len(with_text)} frames with text in {elapsed:.1f}s"
    outdir = preview.preview_dir(demo_ita, tmp_path)
    assert [Path(f["path"]).name for f in frames] == [f"{i:03d}.jpg" for i in range(20)]
    assert sorted(p.name for p in outdir.iterdir()) == [f"{i:03d}.jpg" for i in range(20)]
    for f in frames:
        assert Path(f["path"]).is_file() and Path(f["path"]).parent == outdir
        assert f["width"] > 0 and f["height"] > 0
        assert f["band"] in ("bottom", None)          # no signs band in the fast profile
        assert f["has_text"] == (f["band"] is not None)
    ts = [f["ts"] for f in frames]
    assert ts == sorted(ts) and 0 < ts[0] < ts[-1] < 60
    # whole frames: the demo clip is landscape, the band would be much flatter
    assert frames[0]["width"] > frames[0]["height"]
    # progress: one event per zone, done growing to 20, found never above done
    assert [n for n, _ in events] == ["preview.progress"] * 20
    dones = [d["done"] for _, d in events]
    assert dones == list(range(1, 21))
    assert all(d["found"] <= d["done"] and d["total"] == 20 for _, d in events)
    assert events[-1][1]["found"] == len(with_text)

    # OCR test on a frame with text: raw and final text, time, no top band
    res = preview.test_frame(with_text[0]["path"], params, lists=([], []))
    bottom = res["bands"]["bottom"]
    assert set(res["bands"]) == {"bottom"}
    assert bottom["text"].strip() and bottom["final"].strip() and not bottom["empty"]
    assert 0 < bottom["conf"] <= 1 and 0 < bottom["agree"] <= 1
    assert bottom["ms"] > 0 and bottom["variants"] == 1
    # with the signs band and the variants on: the top band appears, {\an8} only with text
    p2 = OcrParams(**{**FAST_PROFILE, "top_band": True, "multi_variant": True})
    res2 = preview.test_frame(with_text[0]["path"], p2, lists=([], []))
    assert set(res2["bands"]) == {"bottom", "top"}
    assert res2["bands"]["bottom"]["variants"] == 3
    top = res2["bands"]["top"]
    assert top["empty"] == (not top["final"])
    if top["final"]:
        assert top["final"].startswith("{\\an8}")
    # a correction and the ignore list reach `final`
    word = bottom["final"].split()[0].strip(".,!?")
    res3 = preview.test_frame(with_text[0]["path"], params, lists=([], [(word, "XYZ")]))
    assert "XYZ" in res3["bands"]["bottom"]["final"]
    res4 = preview.test_frame(with_text[0]["path"], params, lists=([bottom["text"]], []))
    assert res4["bands"]["bottom"]["empty"] and res4["bands"]["bottom"]["text"] == bottom["text"]


def test_find_frames_invalid_video(tmp_path: Path, params: OcrParams, ffmpeg_bin: str) -> None:
    bad = tmp_path / "bad.mp4"
    bad.write_bytes(b"not a video")
    with pytest.raises(core.EngineError) as exc:
        preview.find_frames(bad, params, n=4, state=tmp_path)
    assert exc.value.code == "invalid_duration"


def test_stop_midway_leaves_no_ffmpeg(demo_ita_copy: Path, params: OcrParams,
                                      tmp_path: Path, ffmpeg_bin: str, vision) -> None:
    stop = threading.Event()
    events: list[dict] = []

    def emit(name: str, data: dict) -> None:
        events.append(data)
        stop.set()                 # stop at the first completed zone

    t0 = time.time()
    with pytest.raises(preview.Stopped):
        preview.find_frames(demo_ita_copy, params, n=20, tries=3, emit=emit,
                            stop=stop, state=tmp_path)
    after = time.time() - t0
    assert events and events[0]["done"] == 1
    assert len(events) < 20
    assert _ffmpeg_processes(demo_ita_copy.name) == []
    time.sleep(0.5)
    assert _ffmpeg_processes(demo_ita_copy.name) == []
    assert after < 15, f"stop took {after:.1f}s"
    # no half-made files (NNN_k.jpg) are left behind
    outdir = preview.preview_dir(demo_ita_copy, tmp_path)
    assert all("_" not in p.name for p in outdir.iterdir())


def test_stop_during_ffmpeg(demo_ita_copy: Path, tmp_path: Path, ffmpeg_bin: str) -> None:
    """_run_ffmpeg terminates the child when the event is set while it runs."""
    stop = threading.Event()
    out = tmp_path / "slow.mp4"
    # a full re-encode of the clip takes a few seconds: enough to stop it
    cmd = ["ffmpeg", "-hide_banner", "-nostats", "-y", "-i", str(demo_ita_copy),
           "-vf", "scale=iw*2:ih*2", "-c:v", "libx264", "-preset", "veryslow", str(out)]
    threading.Timer(0.5, stop.set).start()
    t0 = time.time()
    with pytest.raises(preview.Stopped):
        preview._run_ffmpeg(cmd, stop, poll=0.05)
    assert time.time() - t0 < 5
    assert _ffmpeg_processes(demo_ita_copy.name) == []
