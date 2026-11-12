"""
Structured progress/log events emitted by process_video (activity 1.2):
order of the steps, ratio growing from 0 to 1, bands, log codes.
"""

from __future__ import annotations

import shutil
from pathlib import Path

import pytest

from subvision import core
from subvision.core import LogEvent, OcrParams, ProgressEvent

from conftest import FAST_PROFILE, FAST_PROFILE_LINES


def _run(video: Path, tmp_path: Path, **overrides):
    if not core.vision_available():
        pytest.skip("Apple Vision (ocrmac) not available")
    progress: list[ProgressEvent] = []
    logs: list[LogEvent] = []
    p = OcrParams(**{**FAST_PROFILE, **overrides})
    out = video.with_suffix(".srt")
    segs, stats = core.process_video(str(video), str(out), p,
                                     progress_cb=progress.append,
                                     log_cb=logs.append,
                                     tmp_root=tmp_path / "tmp")
    return segs, stats, progress, logs, out


def _check_progress(progress: list[ProgressEvent], bands: list[str],
                    steps: list[str], optional_steps: tuple[str, ...] = ()):
    assert progress, "no progress events"
    for ev in progress:
        assert isinstance(ev, ProgressEvent)
        assert ev.step in core.STEPS and ev.band in core.BANDS
        assert 0.0 <= ev.ratio <= 1.0
        assert 0 <= ev.count <= max(ev.total, ev.count) and ev.total >= 0
        assert ev.unit in ("frames", "targets", "segments")
    # bands come one after the other, in the order the engine processes them
    seen_bands = []
    for ev in progress:
        if not seen_bands or seen_bands[-1] != ev.band:
            seen_bands.append(ev.band)
    assert seen_bands == bands
    for band in bands:
        evs = [e for e in progress if e.band == band]
        # steps in pipeline order, each one contiguous
        seen_steps = []
        for ev in evs:
            if not seen_steps or seen_steps[-1] != ev.step:
                seen_steps.append(ev.step)
        # refine is skipped by the engine when a band has no kept segment
        # (the signs band of the demo clip): allowed only for optional steps
        expected = [st for st in steps if st in seen_steps or st not in optional_steps]
        assert seen_steps == expected, (band, seen_steps)
        for step in seen_steps:
            ratios = [e.ratio for e in evs if e.step == step]
            assert ratios == sorted(ratios), (band, step, ratios)
            assert ratios[-1] == 1.0, (band, step, ratios)
            last = [e for e in evs if e.step == step][-1]
            assert last.count == last.total or step == "group"
        # extract ends with "n/n frames", group with "targets/frames"
        ext = [e for e in evs if e.step == "extract"][-1]
        assert ext.unit == "frames" and ext.count == ext.total > 0
        grp = [e for e in evs if e.step == "group"][-1]
        assert grp.unit == "targets" and 0 < grp.count <= grp.total
        ocr = [e for e in evs if e.step == "ocr"][-1]
        assert ocr.unit == "frames" and ocr.count == ocr.total == grp.count


def test_events_fast_profile(demo_ita_copy: Path, ffmpeg_bin: str, tmp_path: Path):
    segs, stats, progress, logs, out = _run(demo_ita_copy, tmp_path)
    assert len(segs) == FAST_PROFILE_LINES
    _check_progress(progress, ["bottom"], ["extract", "group", "ocr"])
    # the very first event starts at (or near) zero
    assert progress[0].step == "extract" and progress[0].ratio < 1.0

    assert all(isinstance(e, LogEvent) and isinstance(e.args, dict) for e in logs)
    codes = [e.code for e in logs]
    assert codes == ["frames_extracted", "ocr_targets", "srt_written", "report_written"], codes
    by_code = {e.code: e.args for e in logs}
    assert by_code["frames_extracted"]["band"] == "bottom"
    assert by_code["frames_extracted"]["n"] == stats.frames
    assert by_code["frames_extracted"]["fps"] == 6.0
    assert by_code["ocr_targets"]["frames"] == stats.frames
    assert 0 < by_code["ocr_targets"]["targets"] <= stats.frames
    assert by_code["srt_written"]["path"] == str(out)
    assert by_code["srt_written"]["segments"] == FAST_PROFILE_LINES
    assert by_code["srt_written"]["ocr"] == stats.ocr_calls
    assert by_code["report_written"]["path"] == stats.qc_path
    # no formatted text anywhere in the events
    for e in logs:
        assert all(not isinstance(v, str) or "{" not in v for v in e.args.values())


def test_events_refine_and_signs_band(demo_ita: Path, ffmpeg_bin: str, tmp_path: Path):
    video = tmp_path / demo_ita.name
    shutil.copyfile(demo_ita, video)
    segs, stats, progress, logs, out = _run(video, tmp_path, refine_timing=True, top_band=True)
    assert out.exists() and len(segs) >= FAST_PROFILE_LINES
    _check_progress(progress, ["bottom", "top"], ["extract", "group", "ocr", "refine"],
                    optional_steps=("refine",))
    ref = [e for e in progress if e.step == "refine" and e.band == "bottom"]
    assert ref, "no refine events on the dialogue band"
    assert ref[-1].unit == "segments" and ref[-1].count == ref[-1].total >= FAST_PROFILE_LINES
    codes = [e.code for e in logs]
    bottom = [e.code for e in logs if e.args.get("band") == "bottom"]
    top = [e.code for e in logs if e.args.get("band") == "top"]
    assert bottom == ["frames_extracted", "ocr_targets", "refining", "boundaries_moved"], codes
    assert top[:2] == ["frames_extracted", "ocr_targets"], codes
    assert top in (top[:2], top[:2] + ["refining", "boundaries_moved"]), codes
    assert codes == bottom + top + ["srt_written", "report_written"], codes
    assert logs[2].args["fps"] > 1.0
    assert sum(e.args["n"] for e in logs if e.code == "boundaries_moved") == stats.refined


def test_vision_unavailable_is_an_engine_error(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(core, "_VISION_OK", False)
    with pytest.raises(core.EngineError) as exc:
        core.process_video("missing.mp4", str(tmp_path / "x.srt"), OcrParams(),
                           tmp_root=tmp_path / "tmp")
    assert exc.value.code == "vision_unavailable"
    assert not (tmp_path / "x.srt").exists()


def test_no_localized_strings_left_in_the_engine():
    assert not hasattr(core, "_CORE_I18N")
    assert core.FLAG_TOO_SHORT == "too_short"
    assert core.FLAG_NOISE == "noise"
    assert core.FLAG_MERGED_FADE == "merged_fade"
