"""
Cooperative cancellation (activity 1.3, design from spike S3): a stop set
during extract, OCR or refine makes process_video raise Stopped within 1 s,
with no ffmpeg left behind, the workdir removed and no SRT written. A full
run in the same process afterwards still gives the 12 lines.
"""

from __future__ import annotations

import shutil
import subprocess
import threading
import time
from pathlib import Path

import pytest

from subvision import core
from subvision.core import LogEvent, OcrParams, ProgressEvent, Stopped

from conftest import FAST_PROFILE, FAST_PROFILE_LINES


def _ffmpeg_on(clip_name: str) -> list[str]:
    """ffmpeg/ffprobe processes whose command line names the clip."""
    try:
        out = subprocess.run(["pgrep", "-fl", "ffmpeg|ffprobe"],
                             capture_output=True, text=True).stdout
    except OSError:
        return []
    return [ln for ln in out.splitlines() if clip_name in ln]


def _run_with_stop(video: Path, tmp_path: Path, trigger, **overrides):
    """
    Runs process_video in a thread; `trigger(ProgressEvent) -> bool` sets the
    stop event at the first matching event. Returns (error, seconds between
    the stop and the end of the thread, events seen).
    """
    if not core.vision_available():
        pytest.skip("Apple Vision (ocrmac) not available")
    p = OcrParams(**{**FAST_PROFILE, **overrides})
    out = video.with_suffix(".srt")
    stop = threading.Event()
    seen: list[ProgressEvent] = []
    stopped_at = [0.0]
    result: dict = {}

    def on_progress(ev: ProgressEvent):
        seen.append(ev)
        if not stop.is_set() and trigger(ev):
            stopped_at[0] = time.monotonic()
            stop.set()

    def worker():
        try:
            core.process_video(str(video), str(out), p, progress_cb=on_progress,
                               tmp_root=tmp_path / "tmp", stop=stop)
            result["error"] = None
        except Exception as e:      # noqa: BLE001 - the test inspects it
            result["error"] = e

    th = threading.Thread(target=worker)
    th.start()
    th.join(timeout=120)
    assert not th.is_alive(), "process_video did not return"
    ended = time.monotonic()
    assert stop.is_set(), f"trigger never fired; steps seen: {[(e.step, e.band) for e in seen]}"
    return result["error"], ended - stopped_at[0], seen, out


def _assert_clean_stop(err, delay: float, out: Path, tmp_path: Path, clip: str):
    assert isinstance(err, Stopped), repr(err)
    assert delay <= 1.0, f"stopped {delay:.3f}s after the event"
    assert _ffmpeg_on(clip) == []
    time.sleep(0.3)
    assert _ffmpeg_on(clip) == [], "ffmpeg still alive 0.3 s later"
    assert not list((tmp_path / "tmp").glob("voc26_*")), "workdir not removed"
    assert not out.exists(), "an SRT was written despite the stop"
    assert not out.with_suffix(".revisione.html").exists()


@pytest.fixture
def clip(demo_ita: Path, ffmpeg_bin: str, tmp_path: Path) -> Path:
    dst = tmp_path / demo_ita.name
    shutil.copyfile(demo_ita, dst)
    assert _ffmpeg_on(dst.name) == [], "stray ffmpeg before the test"
    return dst


def test_stop_during_extract(clip: Path, tmp_path: Path):
    # the 55 s demo is extracted in < 1 s: the first extract event comes from
    # the ffmpeg poll (0.1 s) or, at worst, from the final 1.0 right after
    err, delay, seen, out = _run_with_stop(clip, tmp_path, lambda e: e.step == "extract")
    _assert_clean_stop(err, delay, out, tmp_path, clip.name)
    assert all(e.step == "extract" for e in seen)


def test_stop_during_ocr(clip: Path, tmp_path: Path):
    err, delay, seen, out = _run_with_stop(clip, tmp_path, lambda e: e.step == "ocr")
    _assert_clean_stop(err, delay, out, tmp_path, clip.name)
    assert seen[-1].step == "ocr" and seen[-1].ratio < 1.0


def test_stop_during_refine(clip: Path, tmp_path: Path):
    err, delay, seen, out = _run_with_stop(clip, tmp_path, lambda e: e.step == "refine",
                                           refine_timing=True)
    _assert_clean_stop(err, delay, out, tmp_path, clip.name)
    assert any(e.step == "refine" for e in seen)
    assert seen[-1].ratio < 1.0 or seen[-1].step != "refine"


def test_full_run_after_stops(clip: Path, tmp_path: Path):
    # same process, same engine state: a run after the stops is still clean
    err, delay, seen, out = _run_with_stop(clip, tmp_path, lambda e: e.step == "ocr")
    assert isinstance(err, Stopped)
    stop = threading.Event()        # never set
    segs, stats = core.process_video(str(clip), str(out), OcrParams(**FAST_PROFILE),
                                     tmp_root=tmp_path / "tmp", stop=stop)
    assert len(segs) == FAST_PROFILE_LINES
    assert len(core.parse_srt(out)) == FAST_PROFILE_LINES
    assert _ffmpeg_on(clip.name) == []
    assert not list((tmp_path / "tmp").glob("voc26_*"))


def test_stop_already_set_does_nothing(clip: Path, tmp_path: Path):
    stop = threading.Event()
    stop.set()
    out = clip.with_suffix(".srt")
    if not core.vision_available():
        pytest.skip("Apple Vision (ocrmac) not available")
    with pytest.raises(Stopped):
        core.process_video(str(clip), str(out), OcrParams(**FAST_PROFILE),
                           tmp_root=tmp_path / "tmp", stop=stop)
    assert not out.exists()
    assert not list((tmp_path / "tmp").glob("voc26_*"))


def test_probe_failures_raise(tmp_path: Path, ffmpeg_bin: str):
    bogus = tmp_path / "not_a_video.mp4"
    bogus.write_bytes(b"this is not a video")
    with pytest.raises(core.EngineError) as exc:
        core.ffprobe_duration(str(bogus))
    assert exc.value.code == "probe_failed"
    with pytest.raises(core.EngineError) as exc:
        core.ffprobe_fps(str(bogus))
    assert exc.value.code == "probe_failed"
    with pytest.raises(core.EngineError) as exc:
        core.ffprobe_duration(str(tmp_path / "missing.mp4"))
    assert exc.value.code == "probe_failed"


def test_set_tools_is_used(tmp_path: Path, ffmpeg_bin: str, monkeypatch):
    # a wrong ffprobe path must surface as probe_failed, not fall back to PATH
    real = (core.FFMPEG, core.FFPROBE)
    try:
        core.set_tools(core.FFMPEG, str(tmp_path / "no-such-ffprobe"))
        with pytest.raises(core.EngineError) as exc:
            core.ffprobe_duration(str(tmp_path / "x.mp4"))
        assert exc.value.code == "probe_failed"
    finally:
        core.set_tools(*real)


def test_broken_report_keeps_the_srt(clip: Path, tmp_path: Path, monkeypatch):
    if not core.vision_available():
        pytest.skip("Apple Vision (ocrmac) not available")

    def boom(*a, **k):
        raise OSError("disk full")

    monkeypatch.setattr(core, "write_qc_html", boom)
    logs: list[LogEvent] = []
    out = clip.with_suffix(".srt")
    segs, stats = core.process_video(str(clip), str(out), OcrParams(**FAST_PROFILE),
                                     log_cb=logs.append, tmp_root=tmp_path / "tmp")
    assert len(segs) == FAST_PROFILE_LINES and out.exists()
    assert stats.qc_path == ""
    assert not out.with_suffix(".revisione.html").exists()
    codes = [e.code for e in logs]
    assert codes[-2:] == ["srt_written", "report_failed"], codes
    assert "disk full" in logs[-1].args["error"]
