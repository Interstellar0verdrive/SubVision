"""
Batch runner (activity 1.5): events in the expected order, outputs next to
the videos, timestamp suffix on a second run, stop with scope file / all,
a failing file that does not stop the batch, bad parameters refused.
"""

from __future__ import annotations

import re
import shutil
import threading
from pathlib import Path

import pytest

from subvision import batch, core
from subvision.batch import BatchControl, run_batch
from subvision.core import EngineError, OcrParams

from conftest import FAST_PROFILE, FAST_PROFILE_LINES


class Recorder:
    def __init__(self, control: BatchControl | None = None, trigger=None):
        self.events: list[tuple[str, dict]] = []
        self.control = control
        self.trigger = trigger          # (event, data) -> "file" | "all" | None

    def __call__(self, event: str, data: dict) -> None:
        self.events.append((event, dict(data)))
        if self.trigger and self.control:
            scope = self.trigger(event, data)
            if scope:
                self.control.stop(scope)
                self.trigger = None

    def names(self) -> list[str]:
        return [e for e, _ in self.events]

    def of(self, name: str) -> list[dict]:
        return [d for e, d in self.events if e == name]


@pytest.fixture
def two_clips(demo_ita: Path, demo_eng: Path, ffmpeg_bin: str, tmp_path: Path) -> list[Path]:
    if not core.vision_available():
        pytest.skip("Apple Vision (ocrmac) not available")
    out = []
    for src in (demo_ita, demo_eng):
        dst = tmp_path / src.name
        shutil.copyfile(src, dst)
        out.append(dst)
    return out


def _params(**over) -> OcrParams:
    return OcrParams(**{**FAST_PROFILE, **over})


# ---------------------------------------------------------------- pure parts
def test_step_plan_follows_the_params():
    assert batch.step_plan(_params()) == [
        {"key": "extract", "band": "bottom"}, {"key": "group", "band": "bottom"},
        {"key": "ocr", "band": "bottom"}]
    keys = [(s["key"], s["band"]) for s in batch.step_plan(_params(top_band=True, refine_timing=True))]
    assert keys == [("extract", "bottom"), ("group", "bottom"), ("ocr", "bottom"), ("refine", "bottom"),
                    ("extract", "top"), ("group", "top"), ("ocr", "top"), ("refine", "top")]


def test_output_paths_add_a_timestamp_when_the_srt_exists(tmp_path: Path):
    video = tmp_path / "ep01.mkv"
    video.write_bytes(b"")
    first = batch.output_paths(video)
    assert first["srt"] == tmp_path / "ep01.srt" and not first["existed"]
    assert first["log"] == tmp_path / "ep01.log"
    assert first["report"] == tmp_path / "ep01.revisione.html"
    first["srt"].write_text("1\n")
    import datetime
    second = batch.output_paths(video, now=datetime.datetime(2026, 11, 12, 22, 30, 5))
    assert second["srt"] == tmp_path / "ep01_20261112_223005.srt" and second["existed"]
    assert second["log"] == tmp_path / "ep01_20261112_223005.log"
    assert second["report"] == tmp_path / "ep01_20261112_223005.revisione.html"
    assert batch.output_paths(video, qc_report=False)["report"] is None


def test_bad_params_are_refused_before_starting(tmp_path: Path):
    rec = Recorder()
    with pytest.raises(EngineError) as exc:
        run_batch([tmp_path / "x.mp4"], _params(lang_hint="Klingon"), None, "it", rec)
    assert exc.value.code == "bad_params" and exc.value.args_["field"] == "lang_hint"
    with pytest.raises(EngineError) as exc:
        run_batch([tmp_path / "x.mp4"], _params(fps=0), None, "it", rec)
    assert exc.value.args_["field"] == "fps"
    with pytest.raises(EngineError) as exc:
        run_batch([tmp_path / "x.mp4"], _params(bottom_keep_pct=0), None, "it", rec)
    assert exc.value.args_["field"] == "bottom_keep_pct"
    assert rec.events == [] and not list(tmp_path.glob("*.log"))
    # explicit codes pass too (case-insensitive)
    batch.validate_params(_params(lang_hint="it-IT"))
    batch.validate_params(_params(lang_hint="English"))


def test_log_catalogues_are_aligned():
    assert set(batch._LOG_I18N["it"]) == set(batch._LOG_I18N["en"])
    # every LogEvent code of the engine has a log line
    for code in ("frames_extracted", "ocr_targets", "ocr_error", "refining",
                 "boundaries_moved", "srt_written", "report_written", "report_failed"):
        assert code in batch._LOG_I18N["it"]


# ---------------------------------------------------------------- real runs
def _check_file_events(rec: Recorder, idx: int, name: str, plan_len: int):
    started = [d for d in rec.of("batch.file.started") if d["idx"] == idx][0]
    assert started["name"] == name and started["total"] == 2
    assert [s["key"] for s in started["steps"]] == ["extract", "group", "ocr"]
    steps = [d for d in rec.of("batch.step") if d["idx"] == idx]
    assert steps, "no batch.step for the file"
    order = []
    for d in steps:
        sid = f"{d['step']}:{d['band']}"
        if not order or order[-1] != sid:
            order.append(sid)
        assert 0 <= d["ratio"] <= 1 and d["elapsed"] >= 0
        assert d["unit"] in ("frames", "targets", "segments")
        assert d["eta"] is None or d["eta"] >= 0
        assert d["rate"] is None or d["rate"] > 0
    assert order == ["extract:bottom", "group:bottom", "ocr:bottom"]
    # ETA appears mid-step, never at the end
    assert all(d["eta"] is None for d in steps if d["ratio"] >= 0.999)
    return started


def test_two_videos_then_a_second_run(two_clips: list[Path], tmp_path: Path):
    lists = {"ignore": ["Traduzione a cura di"], "corrections": [("Flamilion", "Hamilton")]}
    rec = Recorder()
    done = run_batch(two_clips, _params(), lists, "it", rec, tmp_root=tmp_path / "tmp")
    names = rec.names()
    # order: started(0) steps... done(0) started(1) steps... done(1) batch.done
    assert names[0] == "batch.file.started" and names[-1] == "batch.done"
    firsts = [i for i, n in enumerate(names) if n == "batch.file.started"]
    dones = [i for i, n in enumerate(names) if n == "batch.file.done"]
    assert len(firsts) == 2 and len(dones) == 2
    assert firsts[0] < dones[0] < firsts[1] < dones[1] < len(names) - 1
    assert set(names[firsts[0] + 1:dones[0]]) == {"batch.step"}
    assert "batch.file.failed" not in names and "batch.file.stopped" not in names
    assert done == rec.of("batch.done")[0]
    assert done["done"] == 2 and done["failed"] == 0 and done["stopped"] == 0 and done["skipped"] == 0
    assert done["elapsed"] > 0

    for idx, clip in enumerate(two_clips):
        started = _check_file_events(rec, idx, clip.name, 3)
        fd = [d for d in rec.of("batch.file.done") if d["idx"] == idx][0]
        srt, log, report = Path(fd["srt"]), Path(fd["log"]), Path(fd["report"])
        assert srt == clip.with_suffix(".srt") == Path(started["srt"])
        assert log == clip.with_suffix(".log") == Path(started["log"])
        assert report == clip.with_suffix(".revisione.html") == Path(started["report"])
        assert srt.exists() and log.exists() and report.exists()
        assert fd["segments"] == len(core.parse_srt(srt)) and not fd["empty"]
        assert set(fd["times"]) == {"extract:bottom", "group:bottom", "ocr:bottom"}
        assert all(v >= 0 for v in fd["times"].values())
        assert fd["elapsed"] >= sum(fd["times"].values()) * 0.5
        text = log.read_text(encoding="utf-8")
        assert re.search(r"^\[\d\d:\d\d:\d\d\] video=" + re.escape(clip.name), text, re.M)
        assert "STEP 1/3 — Estrazione fotogrammi · dialoghi ▶ inizio" in text
        assert "STEP 3/3 — OCR x1 letture · dialoghi ✅" in text
        assert "[bottom] " in text and "SRT scritto: " in text and "Report di revisione: " in text
        assert text.rstrip().endswith("totale " + core.fmt_hms(fd["elapsed"])) or "RISULTATO: " in text
        assert "ERRORE" not in text and "INTERROTTO" not in text
        # the second file gets the estimates of the first
        if idx == 1:
            assert all(s["estimate"] is not None and s["estimate"] >= 0 for s in started["steps"])
        else:
            assert all(s["estimate"] is None for s in started["steps"])
    ita = [d for d in rec.of("batch.file.done") if d["idx"] == 0][0]
    assert ita["segments"] == FAST_PROFILE_LINES

    # ---- second run: the SRT exists -> timestamped names, in English
    rec2 = Recorder()
    run_batch(two_clips[:1], _params(), None, "en", rec2, tmp_root=tmp_path / "tmp")
    st = rec2.of("batch.file.started")[0]
    assert re.fullmatch(r".*/sintel_ita_hardsub_demo_\d{8}_\d{6}\.srt", st["srt"]), st["srt"]
    assert st["log"] == st["srt"][:-4] + ".log"
    assert st["report"] == st["srt"][:-4] + ".revisione.html"
    assert Path(st["srt"]).exists() and Path(st["log"]).exists() and Path(st["report"]).exists()
    assert two_clips[0].with_suffix(".srt").exists()          # the first one is untouched
    text = Path(st["log"]).read_text(encoding="utf-8")
    assert "the SRT already existed: new name " in text
    assert "STEP 1/3 — Frame extraction · dialogue ▶ start" in text
    assert "RESULT: " in text and "Review report: " in text
    assert '<html lang="en">' in Path(st["report"]).read_text(encoding="utf-8")


def test_stop_scope_file_moves_on(two_clips: list[Path], tmp_path: Path):
    control = BatchControl()
    rec = Recorder(control, lambda e, d: "file" if e == "batch.step" and d["step"] == "ocr" and d["idx"] == 0 else None)
    done = run_batch(two_clips, _params(), None, "it", rec, stop=control, tmp_root=tmp_path / "tmp")
    names = rec.names()
    assert rec.of("batch.file.stopped") == [{"idx": 0}]
    assert [d["idx"] for d in rec.of("batch.file.done")] == [1]
    assert names.index("batch.file.stopped") < names.index("batch.file.started", 1)
    assert "batch.file.failed" not in names
    assert done["done"] == 1 and done["stopped"] == 1 and done["failed"] == 0 and done["skipped"] == 0
    assert not two_clips[0].with_suffix(".srt").exists()
    assert not two_clips[0].with_suffix(".revisione.html").exists()
    assert two_clips[1].with_suffix(".srt").exists()
    log0 = two_clips[0].with_suffix(".log").read_text(encoding="utf-8")
    assert "❌ interrotto" in log0 and "INTERROTTO dall'utente" in log0
    assert not list((tmp_path / "tmp").glob("voc26_*"))


def test_stop_scope_all_ends_the_batch(two_clips: list[Path], tmp_path: Path):
    control = BatchControl()
    rec = Recorder(control, lambda e, d: "all" if e == "batch.step" and d["step"] == "ocr" else None)
    done = run_batch(two_clips, _params(), None, "it", rec, stop=control, tmp_root=tmp_path / "tmp")
    assert rec.of("batch.file.stopped") == [{"idx": 0}]
    assert [d["idx"] for d in rec.of("batch.file.started")] == [0]
    assert rec.names()[-2:] == ["batch.file.stopped", "batch.done"]
    assert done["done"] == 0 and done["stopped"] == 1 and done["skipped"] == 1
    assert not any(c.with_suffix(".srt").exists() for c in two_clips)
    assert not two_clips[1].with_suffix(".log").exists()


def test_plain_event_means_stop_all(two_clips: list[Path], tmp_path: Path):
    stop = threading.Event()
    stop.set()
    rec = Recorder()
    done = run_batch(two_clips, _params(), None, "it", rec, stop=stop, tmp_root=tmp_path / "tmp")
    assert rec.names() == ["batch.done"]
    assert done["skipped"] == 2 and done["done"] == 0


def test_failed_file_does_not_stop_the_batch(demo_ita: Path, ffmpeg_bin: str, tmp_path: Path):
    if not core.vision_available():
        pytest.skip("Apple Vision (ocrmac) not available")
    bogus = tmp_path / "broken.mp4"
    bogus.write_bytes(b"not a video at all")
    good = tmp_path / demo_ita.name
    shutil.copyfile(demo_ita, good)
    rec = Recorder()
    done = run_batch([bogus, good], _params(), None, "en", rec, tmp_root=tmp_path / "tmp")
    failed = rec.of("batch.file.failed")
    assert len(failed) == 1 and failed[0]["idx"] == 0
    assert failed[0]["error"].startswith("probe_failed")
    assert failed[0]["at_step"] == "extract:bottom"
    # error details for the app: code (translated), tool, path, detail
    assert failed[0]["code"] == "probe_failed" and failed[0]["message"] == "probe_failed"
    assert failed[0]["tool"] == "ffprobe" and failed[0]["path"] == str(bogus)
    assert failed[0]["detail"]
    assert "line" not in failed[0]
    assert [d["idx"] for d in rec.of("batch.file.done")] == [1]
    assert done["failed"] == 1 and done["done"] == 1 and done["stopped"] == 0
    assert "ERROR: probe_failed" in bogus.with_suffix(".log").read_text(encoding="utf-8")
    assert not bogus.with_suffix(".srt").exists()
    assert good.with_suffix(".srt").exists()
