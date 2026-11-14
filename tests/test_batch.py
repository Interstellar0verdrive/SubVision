"""
Batch runner (activity 1.5): events in the expected order, outputs next to
the videos, timestamp suffix on a second run, stop with scope file / all,
a failing file that does not stop the batch, bad parameters refused.
F6: the stop meant for one file (by batch index or path), the fields of a
failed file (`text`, `log`) and two really damaged videos.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import threading
from pathlib import Path

import pytest

from subvision import batch, core
from subvision.batch import BatchControl, run_batch
from subvision.core import EngineError, OcrParams

from conftest import FAST_PROFILE, FAST_PROFILE_LINES, damage_head, damage_tail


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
    assert first["report"] == tmp_path / "ep01.review.html"
    first["srt"].write_text("1\n")
    import datetime
    second = batch.output_paths(video, now=datetime.datetime(2026, 11, 12, 22, 30, 5))
    assert second["srt"] == tmp_path / "ep01_20261112_223005.srt" and second["existed"]
    assert second["log"] == tmp_path / "ep01_20261112_223005.log"
    assert second["report"] == tmp_path / "ep01_20261112_223005.review.html"
    assert batch.output_paths(video, qc_report=False)["report"] is None


def test_bad_params_are_refused_before_starting(tmp_path: Path):
    rec = Recorder()
    with pytest.raises(EngineError) as exc:
        run_batch([tmp_path / "x.mp4"], _params(lang_hint="Klingon"), None, "it", rec)
    assert exc.value.code == "bad_params" and exc.value.args_["field"] == "lang_hint"
    # field and reason travel as `data`, the detail is "field: reason" with nothing appended
    d = exc.value.details()
    assert d["data"] == {"field": "lang_hint", "reason": exc.value.args_["reason"]}
    assert "not supported by Vision" in d["data"]["reason"]
    assert d["detail"] == f"lang_hint: {d['data']['reason']}"
    assert exc.value.describe() == f"bad_params ({d['detail']})"
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


# ---------------------------------------------------------------- stop for one file
def test_control_stops_only_the_file_in_progress(tmp_path: Path):
    c = BatchControl()
    # between two videos nothing is in progress: a stop with `file` finds nothing
    assert c.current is None
    assert c.stop("file", file=0) is False and not c._file.is_set()
    ev0 = c._begin_file(0, tmp_path / "a.mkv")
    assert c.current == 0
    assert c.stop("file", file=1) is False and not ev0.is_set()
    assert c.stop("file", file=str(tmp_path / "b.mkv")) is False and not ev0.is_set()
    assert c.stop("file", file=0) is True and ev0.is_set()
    # the next video: the stop of the previous one does not reach it
    ev1 = c._begin_file(1, tmp_path / "b.mkv")
    assert not ev1.is_set() and c.current == 1
    assert c.stop("file", file=0) is False and not ev1.is_set()
    assert c.stop("file", file=str(tmp_path / "a.mkv")) is False and not ev1.is_set()
    # by path too (the same file spelled differently)
    assert c.stop("file", file=str(tmp_path / "x" / ".." / "b.mkv")) is False
    assert c.stop("file", file=str(tmp_path) + "//b.mkv") is True and ev1.is_set()
    # over: nothing to stop, and the event of the next video is a fresh one
    c._end_file()
    assert c.current is None and c.stop("file", file=1) is False
    ev2 = c._begin_file(2, tmp_path / "c.mkv")
    assert not ev2.is_set()
    # without `file` it is the stop of 1.5: whatever is in progress
    assert c.stop("file") is True and ev2.is_set()
    assert not c.stop_all


def test_control_scope_all_ignores_file(tmp_path: Path):
    c = BatchControl()
    ev = c._begin_file(3, tmp_path / "a.mkv")
    assert c.stop("all", file=0) is True          # not the file in progress: stopped anyway
    assert ev.is_set() and c.stop_all
    assert c._begin_file(4, tmp_path / "b.mkv").is_set()
    c2 = BatchControl()
    assert c2.stop("all", file=object()) is True and c2.stop_all      # not even looked at


def test_control_refuses_a_file_of_the_wrong_kind(tmp_path: Path):
    c = BatchControl()
    ev = c._begin_file(1, tmp_path / "a.mkv")
    for bad in (1.0, True, [1], {"idx": 1}):
        with pytest.raises(TypeError):
            c.stop("file", file=bad)
    with pytest.raises(ValueError):
        c.stop("next", file=1)
    assert not ev.is_set() and not c.stop_all


def test_a_stop_for_one_file_never_lands_on_the_next():
    """
    The batch moves through 300 videos as fast as it can while another
    thread keeps asking to stop video 150: only the event of video 150 may
    ever be set, and only when the stop said True.
    """
    c = BatchControl()
    target, total = 150, 300
    events: dict[int, threading.Event] = {}
    taken: list[bool] = []
    over = threading.Event()

    def stopper() -> None:
        while not over.is_set():
            taken.append(c.stop("file", file=target))

    th = threading.Thread(target=stopper)
    th.start()
    try:
        for idx in range(total):
            events[idx] = c._begin_file(idx, f"/videos/{idx}.mkv")
            for _ in range(200):        # the video "runs" for a moment
                pass
            c._end_file()
    finally:
        over.set()
        th.join()
    hit = [idx for idx, ev in events.items() if ev.is_set()]
    assert hit in ([], [target]), hit
    assert any(taken) == (hit == [target])
    assert not c.stop_all


def test_stop_for_one_file_in_a_real_batch(two_clips: list[Path], tmp_path: Path):
    control = BatchControl()
    answers: dict[str, object] = {}

    def emit(event: str, data: dict) -> None:
        rec(event, data)
        if event == "batch.step" and data["step"] == "ocr":
            if data["idx"] == 0 and "first" not in answers:
                # video 0 is running: a stop for video 1 (index or path) is refused...
                answers["other"] = control.stop("file", file=1)
                answers["other_path"] = control.stop("file", file=str(two_clips[1]))
                answers["during"] = control.current
                # ...and the one for video 0 is taken
                answers["first"] = control.stop("file", file=0)
            elif data["idx"] == 1 and "late" not in answers:
                # video 1 is running by now: the stop meant for video 0 comes late
                answers["late"] = control.stop("file", file=0)
                answers["late_path"] = control.stop("file", file=str(two_clips[0]))

    rec = Recorder()
    done = run_batch(two_clips, _params(), None, "it", emit, stop=control, tmp_root=tmp_path / "tmp")
    assert answers == {"other": False, "other_path": False, "during": 0, "first": True,
                       "late": False, "late_path": False}
    assert rec.of("batch.file.stopped") == [{"idx": 0}]
    assert [d["idx"] for d in rec.of("batch.file.done")] == [1]
    assert done["done"] == 1 and done["stopped"] == 1 and done["failed"] == 0
    assert control.current is None and control.stop("file", file=1) is False
    assert not two_clips[0].with_suffix(".srt").exists()
    assert len(core.parse_srt(two_clips[1].with_suffix(".srt"))) > 0


# ---------------------------------------------------------------- error fields
def test_error_info_text_has_no_type_name_and_no_prefix():
    # an unexpected exception: its own message; the type name only in `detail`
    info = batch.error_info(ValueError("the disk is full"), path="/v/a.mkv")
    assert info["code"] == "unknown" and info["message"] == "unknown"
    assert info["text"] == "the disk is full"
    assert info["detail"] == "ValueError: the disk is full"
    assert info["error"] == "unknown (ValueError: the disk is full)" and info["path"] == "/v/a.mkv"
    # no message at all: the type name is all there is
    assert batch.error_info(RuntimeError())["text"] == "RuntimeError"
    assert batch.error_info(KeyError())["text"] == "KeyError"
    # several lines: the first one; a very long one is cut
    assert batch.error_info(OSError("\n first line \nsecond"))["text"] == "first line"
    long = batch.error_info(ValueError("x" * 1000))["text"]
    assert len(long) == 300 and long.endswith("…")
    # an engine error: the first line of the detail, nothing when there is none
    e = EngineError("probe_failed", tool="ffprobe", path="/v/a.mkv",
                    detail="moov atom not found\n/v/a.mkv: Invalid data found when processing input")
    info = batch.error_info(e)
    assert info["code"] == "probe_failed" and info["text"] == "moov atom not found"
    assert info["detail"].count("\n") == 1 and "\n" not in info["error"]
    assert "text" not in batch.error_info(EngineError("vision_unavailable", tool="vision"))
    # the prefix of the alert ("Something went wrong: ...") belongs to the app
    for exc in (ValueError("boom"), RuntimeError(), e, EngineError("vision_unavailable")):
        text = batch.error_info(exc).get("text", "")
        for prefix in ("Qualcosa", "Something", "ERRORE", "ERROR", "Error:", "unknown"):
            assert not text.startswith(prefix), text


def test_error_info_of_a_tool_that_exits_with_an_error():
    cmd = ["/opt/bin/ffmpeg", "-hide_banner", "-i", "/v/a.mkv", "/tmp/f_%08d.jpg"]
    stderr = ("[mov,mp4,m4a,3gp,3g2,mj2 @ 0x7a61008600] UDTA parsing failed retrying raw\n"
              "[vist#0:0/h264 @ 0x7a61] [dec:h264 @ 0x7a60] Error submitting packet to decoder: "
              "Invalid data found when processing input\n"
              "[vist#0:0/h264 @ 0x7a61] [dec:h264 @ 0x7a60] Decode error rate 0.88 exceeds maximum 0.666667\n"
              "[vist#0:0/h264 @ 0x7a61] Terminating thread with return code -1145393733 "
              "(Error number -1145393733 occurred)\n"
              "Conversion failed!\n")
    info = batch.error_info(subprocess.CalledProcessError(69, cmd, stderr=stderr), path="/v/a.mkv")
    assert info["code"] == "unknown" and info["tool"] == "ffmpeg" and info["path"] == "/v/a.mkv"
    # not the command line: the tool, the exit status and what it complained about
    assert info["text"] == "ffmpeg exited with status 69: Decode error rate 0.88 exceeds maximum 0.666667"
    assert info["error"] == f"unknown ({info['text']})"
    assert info["detail"].startswith("CalledProcessError: Command '['/opt/bin/ffmpeg'")
    assert "Decode error rate 0.88 exceeds maximum 0.666667" in info["detail"]
    assert "@ 0x" not in info["detail"]
    # without stderr, and for a tool that is not ours
    bare = batch.error_info(subprocess.CalledProcessError(1, ["/usr/bin/true"]))
    assert bare["text"] == "true exited with status 1" and "tool" not in bare


def test_error_info_words_its_own_texts_in_the_batch_language():
    # 11.3.4: with the app in Italian the row of a failed file is in Italian too
    stderr = "[dec:h264 @ 0x7a60] Decode error rate 0.88 exceeds maximum 0.666667\nConversion failed!\n"
    exc = subprocess.CalledProcessError(69, ["/opt/bin/ffmpeg", "-i", "/v/a.mkv"], stderr=stderr)
    it = batch.error_info(exc, path="/v/a.mkv", lang="it")
    assert it["text"] == "ffmpeg è uscito con il codice 69: Decode error rate 0.88 exceeds maximum 0.666667"
    # the parts, for the app to word the sentence in its own language
    assert it["program"] == "ffmpeg" and it["status"] == 69 and it["tool"] == "ffmpeg"
    assert it["reason"] == "Decode error rate 0.88 exceeds maximum 0.666667"
    en = batch.error_info(exc, path="/v/a.mkv", lang="en")
    assert en["text"].startswith("ffmpeg exited with status 69: ")
    # an unknown language falls back to English, as the default does
    assert batch.error_info(exc, lang="fr")["text"] == en["text"] == batch.error_info(exc)["text"]
    # a known errno of the file system, with the file it is about
    full = OSError(28, "No space left on device", "/v/a.srt")
    assert batch.error_info(full, lang="it")["text"] == "Il disco è pieno: /v/a.srt"
    assert batch.error_info(full, lang="en")["text"] == "The disk is full: /v/a.srt"
    assert batch.error_info(PermissionError(13, "Permission denied"), lang="it")["text"] == "Permesso negato"
    # a message of Python stays as it is; the code stays `unknown` for all of them
    assert batch.error_info(ValueError("boom"), lang="it")["text"] == "boom"
    assert {batch.error_info(x, lang="it")["code"] for x in (exc, full, ValueError("boom"))} == {"unknown"}



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
        assert report == clip.with_suffix(".review.html") == Path(started["report"])
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
    assert st["report"] == st["srt"][:-4] + ".review.html"
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
    assert not two_clips[0].with_suffix(".review.html").exists()
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
    # F6: the log of the file and a short text for its row (what ffprobe said)
    assert failed[0]["log"] == str(bogus.with_suffix(".log"))
    assert failed[0]["text"] == failed[0]["detail"].splitlines()[0]
    assert "Command" not in failed[0]["detail"] and "probe_failed" not in failed[0]["text"]
    assert [d["idx"] for d in rec.of("batch.file.done")] == [1]
    assert done["failed"] == 1 and done["done"] == 1 and done["stopped"] == 0
    assert "ERROR: probe_failed" in bogus.with_suffix(".log").read_text(encoding="utf-8")
    assert not bogus.with_suffix(".srt").exists()
    assert good.with_suffix(".srt").exists()


# ---------------------------------------------------------------- damaged videos
def test_damaged_video_refused_by_the_probe(demo_ita: Path, ffmpeg_bin: str, tmp_path: Path):
    """Recipe (a), conftest.damage_head: no index, ffprobe refuses the file."""
    if not core.vision_available():
        pytest.skip("Apple Vision (ocrmac) not available")
    video = damage_head(demo_ita, tmp_path / "no-index.mp4")
    rec = Recorder()
    done = run_batch([video], _params(), None, "en", rec, tmp_root=tmp_path / "tmp")
    assert done["failed"] == 1 and done["done"] == 0
    failed = rec.of("batch.file.failed")[0]
    assert failed["code"] == "probe_failed" and failed["tool"] == "ffprobe"
    assert failed["at_step"] == "extract:bottom" and failed["path"] == str(video)
    assert failed["text"] == "moov atom not found"
    assert failed["detail"].splitlines()[0] == "moov atom not found"
    assert "Invalid data found when processing input" in failed["detail"]
    assert failed["log"] == str(video.with_suffix(".log")) and Path(failed["log"]).is_file()
    assert "batch.step" not in rec.names()
    assert not video.with_suffix(".srt").exists()


def test_damaged_video_fails_in_the_middle_of_the_extraction(demo_ita: Path, ffmpeg_bin: str,
                                                             tmp_path: Path):
    """
    Recipe (b), conftest.damage_tail: the probe is happy (the index is
    intact), ffmpeg extracts the first seconds and then gives up. The file
    fails with the tool and its words, the batch goes on with the next one.
    """
    if not core.vision_available():
        pytest.skip("Apple Vision (ocrmac) not available")
    video = damage_tail(demo_ita, tmp_path / "damaged.mp4")
    good = tmp_path / demo_ita.name
    shutil.copyfile(demo_ita, good)
    # the probe sees a normal video
    assert core.ffprobe_duration(str(video)) == pytest.approx(55.0, abs=0.5)
    assert core.ffprobe_fps(str(video)) == pytest.approx(24.0, abs=0.1)

    rec = Recorder()
    done = run_batch([video, good], _params(), None, "en", rec, tmp_root=tmp_path / "tmp")
    assert done["failed"] == 1 and done["done"] == 1 and done["stopped"] == 0
    failed = rec.of("batch.file.failed")
    assert len(failed) == 1 and failed[0]["idx"] == 0
    f = failed[0]
    assert f["code"] == "unknown" and f["message"] == "unknown" and f["tool"] == "ffmpeg"
    assert f["at_step"] == "extract:bottom" and f["path"] == str(video)
    assert re.fullmatch(r"ffmpeg exited with status \d+: Decode error rate 0\.\d+ exceeds maximum 0\.\d+",
                        f["text"]), f["text"]
    assert f["error"] == f"unknown ({f['text']})"
    assert f["detail"].startswith("CalledProcessError: Command ")
    assert "Decode error rate" in f["detail"] and "Conversion failed!" in f["detail"]
    # ffmpeg did write frames before giving up (the "frame=" line of its summary)
    frames = re.search(r"frame=\s*(\d+)", f["detail"])
    assert frames and 0 < int(frames.group(1)) < 330 * 0.34
    # the log of the file tells the same story; nothing else is left behind
    log = Path(f["log"])
    assert log == video.with_suffix(".log")
    text = log.read_text(encoding="utf-8")
    assert f"ERROR: unknown ({f['text']})" in text and "RESULT" not in text
    assert not video.with_suffix(".srt").exists()
    assert not video.with_suffix(".review.html").exists()
    assert not list((tmp_path / "tmp").glob("voc26_*"))
    # and the next video is processed as usual
    assert [d["idx"] for d in rec.of("batch.file.done")] == [1]
    assert rec.of("batch.file.done")[0]["segments"] == FAST_PROFILE_LINES
    # the long gaps of the report travel with the event, as [start, end] pairs
    gaps = rec.of("batch.file.done")[0]["gaps"]
    assert isinstance(gaps, list) and all(len(g) == 2 and g[0] < g[1] for g in gaps)


def test_a_step_with_nothing_to_do_still_has_a_time(tmp_path: Path):
    """The refinement of a band without text sends no progress: it still gets
    0 s, so the next file has an estimate for every step (the app's "the batch
    ends around")."""
    p = OcrParams(top_band=True, refine_timing=True)
    plan = batch.step_plan(p)
    log = batch._FileLog(tmp_path / "x.log", "it")
    tracker = batch._StepTracker(plan, p, log, batch._LOG_I18N["it"], lambda *_: None, 0)
    for step in ("extract", "group", "ocr", "refine"):
        tracker.on_progress(core.ProgressEvent(step, "bottom", 1.0, 1, 1, "frames"))
    for step in ("extract", "group", "ocr"):          # the signs band: no refine progress
        tracker.on_progress(core.ProgressEvent(step, "top", 1.0, 1, 1, "frames"))
    tracker.finish_all()
    times = tracker.times()
    assert set(times) == {f"{st['key']}:{st['band']}" for st in plan}
    assert times["refine:top"] == 0
