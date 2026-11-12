"""
Batch runner: processes a list of videos with the engine, one after the
other, and reports through the sidecar events of the protocol (plan, table
1.4). Replaces the orchestration of the 1.0 Streamlit page.

    run_batch(videos, params, lists, lang, emit, stop)

- `emit(event: str, data: dict)` receives, in order:
    batch.file.started {idx, total, name, srt, log, report, steps:[{key, band, estimate}]}
    batch.step         {idx, step, band, ratio, count, total, unit, elapsed, eta, rate}
    batch.file.done    {idx, segments, dropped, refined, elapsed, times:{"step:band": sec},
                        srt, report, log, empty}
    batch.file.failed  {idx, error, at_step, code, message, detail?, tool?, path?, line?}
    batch.file.stopped {idx}
    batch.done         {done, failed, stopped, skipped, elapsed}
- `stop` is a BatchControl: stop("file") moves on to the next video,
  stop("all") ends the batch (the current file is stopped, the others are
  never started and counted as `skipped`). A plain threading.Event means
  "all".
- a failing file (`batch.file.failed`) never stops the batch; `Stopped`
  from the engine is a `batch.file.stopped`, never a failure.
- outputs go next to the video: `<name>.srt` (or `<name>_YYYYMMDD_HHMMSS.srt`
  when it exists already), `<name>.revisione.html`, `<name>.log`.

The per-file log is the only text for the user that the engine writes,
because it is a file next to the video: `lang` ("it" | "en") picks its
language (small catalogue below, same strings as 1.0). Everything else is
numbers and codes: the app formats them.
"""

from __future__ import annotations

import dataclasses
import datetime
import threading
import time
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Sequence

from subvision import core
from subvision.core import EngineError, LogEvent, OcrParams, ProgressEvent, Stopped

Emit = Callable[[str, Dict[str, Any]], None]


# ---------------------------------------------------------------- stop control
class BatchControl:
    """
    Stop control shared between the batch thread and the caller.
    stop("file") stops only the video in progress (the batch goes on);
    stop("all") stops the video in progress and the whole batch.
    """

    def __init__(self) -> None:
        self._all = threading.Event()
        self._file = threading.Event()
        self._lock = threading.Lock()

    def stop(self, scope: str = "file") -> None:
        if scope not in ("file", "all"):
            raise ValueError(f"unknown stop scope: {scope!r}")
        with self._lock:
            if scope == "all":
                self._all.set()
            self._file.set()

    @property
    def stop_all(self) -> bool:
        return self._all.is_set()

    def _begin_file(self) -> threading.Event:
        """A fresh per-file event (already set when the batch is being stopped)."""
        with self._lock:
            self._file = threading.Event()
            if self._all.is_set():
                self._file.set()
            return self._file


# ---------------------------------------------------------------- log texts
# Same strings as the 1.0 per-file log (app.py + _CORE_I18N); "it" stays
# byte-identical to the historical ones.
_LOG_I18N = {
    "it": {
        "header": "video={name} fps={fps} variants={variants} refine={refine} "
                  "top_band={top_band} crop={crop_h}/{crop_w} skip={skip}",
        "step_start": "STEP {i}/{n} — {label} ▶ inizio",
        "step_done": "STEP {i}/{n} — {label} ✅ {last} — concluso in {dur}{rate}",
        "step_aborted": "STEP {i}/{n} — {label} ❌ interrotto",
        "rate_avg": " — media {rate:.1f} {unit}",
        "unit_rows_s": "righe/s", "unit_fps": "fps",
        "step_extract": "Estrazione fotogrammi", "step_group": "Analisi ridondanza",
        "step_ocr": "OCR x{n} letture", "step_refine": "Raffinamento tempi",
        "band_bottom": "dialoghi", "band_top": "cartelli",
        "last_extract": "{n} frame estratti",
        "last_group": "{count}/{total} frame da leggere",
        "last_ocr": "{count}/{total} frame",
        "last_refine": "{count}/{total} righe",
        "times_summary": "⏱ {times}",
        "log_result": "RISULTATO: {segments} righe, {dropped} scartate "
                      "(nel report di revisione), {refined} confini raffinati, "
                      "totale {elapsed}",
        "log_error": "ERRORE: {e}",
        "log_stopped": "INTERROTTO dall'utente",
        "srt_existed": "l'SRT esisteva già: nuovo nome {name}",
        # LogEvent codes of the engine
        "frames_extracted": "[{band}] {n} frame @ {fps}fps",
        "ocr_targets": "[{band}] {targets}/{frames} frame da OCR-are",
        "ocr_error": "[{band}] OCR errore su un frame: {error}",
        "refining": "[{band}] raffinamento confini a {fps:.3f} fps nativi…",
        "boundaries_moved": "[{band}] {n} confini spostati",
        "srt_written": "SRT scritto: {path} ({segments} righe, {ocr} OCR, "
                       "{refined} confini raffinati, {elapsed:.1f}s)",
        "report_written": "Report di revisione: {path}",
        "report_failed": "Report di revisione NON scritto ({path}): {error}",
    },
    "en": {
        "header": "video={name} fps={fps} variants={variants} refine={refine} "
                  "top_band={top_band} crop={crop_h}/{crop_w} skip={skip}",
        "step_start": "STEP {i}/{n} — {label} ▶ start",
        "step_done": "STEP {i}/{n} — {label} ✅ {last} — finished in {dur}{rate}",
        "step_aborted": "STEP {i}/{n} — {label} ❌ aborted",
        "rate_avg": " — average {rate:.1f} {unit}",
        "unit_rows_s": "lines/s", "unit_fps": "fps",
        "step_extract": "Frame extraction", "step_group": "Redundancy analysis",
        "step_ocr": "OCR x{n} readings", "step_refine": "Timing refinement",
        "band_bottom": "dialogue", "band_top": "signs",
        "last_extract": "{n} frames extracted",
        "last_group": "{count}/{total} frames to read",
        "last_ocr": "{count}/{total} frames",
        "last_refine": "{count}/{total} lines",
        "times_summary": "⏱ {times}",
        "log_result": "RESULT: {segments} lines, {dropped} dropped "
                      "(in the review report), {refined} boundaries refined, "
                      "total {elapsed}",
        "log_error": "ERROR: {e}",
        "log_stopped": "STOPPED by the user",
        "srt_existed": "the SRT already existed: new name {name}",
        "frames_extracted": "[{band}] {n} frames @ {fps}fps",
        "ocr_targets": "[{band}] {targets}/{frames} frames to OCR",
        "ocr_error": "[{band}] OCR error on one frame: {error}",
        "refining": "[{band}] refining boundaries at {fps:.3f} native fps…",
        "boundaries_moved": "[{band}] {n} boundaries moved",
        "srt_written": "SRT written: {path} ({segments} lines, {ocr} OCR, "
                       "{refined} boundaries refined, {elapsed:.1f}s)",
        "report_written": "Review report: {path}",
        "report_failed": "Review report NOT written ({path}): {error}",
    },
}


class _FileLog:
    """Appends timestamped lines to `<name>.log`; never raises."""

    def __init__(self, path: Path, lang: str) -> None:
        self.path = path
        self.tr = _LOG_I18N.get(lang) or _LOG_I18N["it"]

    def write(self, msg: str) -> None:
        try:
            with open(self.path, "a", encoding="utf-8") as f:
                f.write(f"[{datetime.datetime.now():%H:%M:%S}] {msg}\n")
        except Exception:
            pass

    def code(self, code: str, **args: Any) -> None:
        fmt = self.tr.get(code)
        if fmt is None:
            self.write(f"{code} {args}")
            return
        try:
            self.write(fmt.format(**args))
        except (KeyError, IndexError, ValueError):
            self.write(f"{code} {args}")


# ---------------------------------------------------------------- plan
def step_plan(params: OcrParams) -> List[Dict[str, str]]:
    """The steps of one file, in order: [{key, band}] (plan, batch.file.started)."""
    bands = ["bottom"] + (["top"] if params.top_band else [])
    plan: List[Dict[str, str]] = []
    for band in bands:
        for key in ("extract", "group", "ocr"):
            plan.append({"key": key, "band": band})
        if params.refine_timing:
            plan.append({"key": "refine", "band": band})
    return plan


def _step_id(key: str, band: str) -> str:
    return f"{key}:{band}"


def output_paths(video: Path, qc_report: bool = True,
                 now: Optional[datetime.datetime] = None) -> Dict[str, Optional[Path]]:
    """
    SRT, log and report paths next to the video. When the SRT exists already
    the new one gets a `_YYYYMMDD_HHMMSS` suffix (and so do its log and report).
    """
    srt = video.with_suffix(".srt")
    existed = srt.exists()
    if existed:
        ts = (now or datetime.datetime.now()).strftime("%Y%m%d_%H%M%S")
        srt = srt.with_name(f"{srt.stem}_{ts}.srt")
    return {
        "srt": srt,
        "log": srt.with_suffix(".log"),
        "report": srt.with_suffix(".revisione.html") if qc_report else None,
        "existed": existed,
    }


# ---------------------------------------------------------------- validation
def validate_params(params: OcrParams) -> None:
    """Raises EngineError("bad_params", field=..., reason=...) before any work."""
    def bad(field: str, reason: str) -> None:
        raise EngineError("bad_params", field=field, detail=f"{field}: {reason}")

    if not (0.5 <= float(params.fps) <= 60):
        bad("fps", "must be between 0.5 and 60")
    for name in ("bottom_keep_pct", "keep_w_pct", "top_keep_pct", "top_keep_w_pct"):
        v = int(getattr(params, name))
        if not (1 <= v <= 100):
            bad(name, "must be between 1 and 100")
    if int(params.workers) < 1:
        bad("workers", "must be at least 1")
    if float(params.min_duration) < 0 or float(params.merge_gap) < 0:
        bad("min_duration", "must not be negative")
    if int(params.wrap_width) < 10:
        bad("wrap_width", "must be at least 10")
    if int(params.skip_hamming) < 0:
        bad("skip_hamming", "must not be negative")
    code = core.resolve_langs(params.lang_hint)[0]
    supported = core.vision_languages()
    if supported and code.lower() not in {c.lower() for c in supported}:
        bad("lang_hint", f"language {code!r} not supported by Vision on this Mac")


def _apply_lists(params: OcrParams, lists: Any) -> OcrParams:
    """A copy of `params` with the ignore/corrections lists applied."""
    if lists is None:
        return dataclasses.replace(params)
    if isinstance(lists, dict):
        ignore = lists.get("ignore") or lists.get("ignore_lines") or []
        corrections = lists.get("corrections") or []
    else:
        ignore = getattr(lists, "ignore_lines", None) or getattr(lists, "ignore", None) or []
        corrections = getattr(lists, "corrections", None) or []
    return dataclasses.replace(params, ignore_lines=list(ignore),
                               corrections=[tuple(c) for c in corrections])


# ---------------------------------------------------------------- the batch
def run_batch(videos: Sequence[str | Path], params: OcrParams, lists: Any,
              lang: str, emit: Emit, stop: Optional[BatchControl | threading.Event] = None,
              tmp_root: Optional[Path] = None, ui_lang: Optional[str] = None,
              ) -> Dict[str, Any]:
    """
    Processes `videos` in order. Returns the data of `batch.done`.
    `lang` is the language of the per-file logs (and of the review reports,
    unless `ui_lang` says otherwise). Raises EngineError("bad_params") before
    starting when the parameters are invalid (nothing is emitted).
    """
    validate_params(params)
    p = _apply_lists(params, lists)
    control = stop if isinstance(stop, BatchControl) else BatchControl()
    plain_event = stop if isinstance(stop, threading.Event) else None
    plan = step_plan(p)
    tr = _LOG_I18N.get(lang) or _LOG_I18N["it"]
    report_lang = ui_lang or lang
    t_batch = time.monotonic()
    estimates: Dict[str, float] = {}       # "step:band" -> seconds, from the previous file
    counts = {"done": 0, "failed": 0, "stopped": 0, "skipped": 0}

    for idx, item in enumerate(videos):
        video = Path(item)
        if control.stop_all or (plain_event is not None and plain_event.is_set()):
            counts["skipped"] += 1
            continue
        # a plain Event means "stop all": the engine takes it as it is
        file_stop = plain_event if plain_event is not None else control._begin_file()

        paths = output_paths(video, qc_report=p.qc_report)
        srt, logp, report = paths["srt"], paths["log"], paths["report"]
        log = _FileLog(logp, lang)
        steps = [{"key": st["key"], "band": st["band"],
                  "estimate": estimates.get(_step_id(st["key"], st["band"]))}
                 for st in plan]
        emit("batch.file.started", {
            "idx": idx, "total": len(videos), "name": video.name,
            "srt": str(srt), "log": str(logp), "report": str(report) if report else None,
            "steps": steps,
        })
        log.code("header", name=video.name, fps=p.fps, variants=p.multi_variant,
                 refine=p.refine_timing, top_band=p.top_band,
                 crop_h=p.bottom_keep_pct, crop_w=p.keep_w_pct, skip=p.skip_hamming)
        if paths["existed"]:
            log.code("srt_existed", name=srt.name)

        tracker = _StepTracker(plan, p, log, tr, emit, idx)
        t_file = time.monotonic()
        try:
            segs, stats = core.process_video(
                str(video), str(srt), p,
                progress_cb=tracker.on_progress, log_cb=tracker.on_log,
                tmp_root=tmp_root, ui_lang=report_lang, stop=file_stop)
        except Stopped:
            tracker.abort()
            log.code("log_stopped")
            counts["stopped"] += 1
            emit("batch.file.stopped", {"idx": idx})
            continue
        except Exception as e:      # noqa: BLE001 - any engine error fails this file only
            at_step = tracker.current_step()
            tracker.abort()
            info = error_info(e, path=str(video))
            log.code("log_error", e=info["error"])
            counts["failed"] += 1
            emit("batch.file.failed", {"idx": idx, "at_step": at_step, **info})
            continue

        tracker.finish_all()
        times = tracker.times()
        estimates.update(times)
        log.code("times_summary", times=" · ".join(
            f"{tracker.label(sid)} {core.fmt_hms(sec)}" for sid, sec in times.items()))
        log.code("log_result", segments=stats.segments, dropped=stats.dropped,
                 refined=stats.refined, elapsed=core.fmt_hms(stats.elapsed))
        counts["done"] += 1
        emit("batch.file.done", {
            "idx": idx, "segments": stats.segments, "dropped": stats.dropped,
            "refined": stats.refined, "elapsed": round(time.monotonic() - t_file, 3),
            "times": times, "srt": str(srt),
            "report": stats.qc_path or None, "log": str(logp),
            "empty": not segs,
        })

    done = {**counts, "elapsed": round(time.monotonic() - t_batch, 3)}
    emit("batch.done", done)
    return done


def error_info(e: Exception, path: Optional[str] = None) -> Dict[str, Any]:
    """
    The error fields of an event: `code` (stable, translated by the app),
    `message` (= code), `error` (one line with the details, for logs), plus
    `detail`, `tool`, `path`, `line` when known. Unexpected exceptions are
    `unknown` with the exception text as detail.
    """
    if isinstance(e, EngineError):
        info: Dict[str, Any] = {"code": e.code, "message": e.code, "error": e.describe(),
                                **e.details()}
    else:
        detail = f"{type(e).__name__}: {e}"
        info = {"code": "unknown", "message": "unknown", "error": f"unknown ({detail})",
                "detail": detail}
    if path and "path" not in info:
        info["path"] = path
    return info


class _StepTracker:
    """
    Turns the engine's ProgressEvents into `batch.step` events with elapsed,
    ETA and rate, keeps the per-step durations and writes the step lines of
    the per-file log (as the 1.0 page did).
    """

    def __init__(self, plan: List[Dict[str, str]], p: OcrParams, log: _FileLog,
                 tr: Dict[str, str], emit: Emit, idx: int) -> None:
        self.order = [_step_id(st["key"], st["band"]) for st in plan]
        self.p, self.log, self.tr, self.emit, self.idx = p, log, tr, emit, idx
        self.rows: Dict[str, Dict[str, Any]] = {
            sid: {"start": None, "done": False, "dur": 0.0, "count": 0, "last": ""}
            for sid in self.order}

    # ---- labels (log only)
    def label(self, sid: str) -> str:
        key, band = sid.split(":")
        step = {"extract": self.tr["step_extract"], "group": self.tr["step_group"],
                "ocr": self.tr["step_ocr"].format(n=3 if self.p.multi_variant else 1),
                "refine": self.tr["step_refine"]}[key]
        return f"{step} · {self.tr['band_' + band]}"

    def _unit(self, sid: str) -> str:
        return self.tr["unit_rows_s"] if sid.startswith("refine") else self.tr["unit_fps"]

    # ---- engine callbacks
    def on_log(self, ev: LogEvent) -> None:
        self.log.code(ev.code, **ev.args)

    def on_progress(self, ev: ProgressEvent) -> None:
        sid = _step_id(ev.step, ev.band)
        row = self.rows.get(sid)
        if row is None:
            return
        # a new step starts -> the previous ones are done
        for prev in self.order[:self.order.index(sid)]:
            self._finish(prev)
        now = time.monotonic()
        if row["start"] is None:
            row["start"] = now
            self.log.code("step_start", i=self.order.index(sid) + 1,
                          n=len(self.order), label=self.label(sid))
        row["count"] = ev.count
        row["last"] = self._last_text(ev)
        elapsed = now - row["start"]
        eta = (elapsed / ev.ratio - elapsed) if 0.02 < ev.ratio < 0.999 else None
        rate = (ev.count / elapsed) if ev.count and elapsed > 1.0 else None
        self.emit("batch.step", {
            "idx": self.idx, "step": ev.step, "band": ev.band,
            "ratio": round(float(ev.ratio), 4), "count": ev.count, "total": ev.total,
            "unit": ev.unit, "elapsed": round(elapsed, 3),
            "eta": round(eta, 1) if eta is not None else None,
            "rate": round(rate, 2) if rate is not None else None,
        })
        if ev.ratio >= 1.0:
            self._finish(sid)

    def _last_text(self, ev: ProgressEvent) -> str:
        if ev.step == "extract":
            return self.tr["last_extract"].format(n=ev.count)
        return self.tr["last_" + ev.step].format(count=ev.count, total=ev.total)

    # ---- bookkeeping
    def _finish(self, sid: str) -> None:
        row = self.rows[sid]
        if row["done"]:
            return
        row["done"] = True
        dur = (time.monotonic() - row["start"]) if row["start"] else 0.0
        row["dur"] = dur
        rate = ""
        if row["count"] and dur > 1.0:
            rate = self.tr["rate_avg"].format(rate=row["count"] / dur, unit=self._unit(sid))
        self.log.code("step_done", i=self.order.index(sid) + 1, n=len(self.order),
                      label=self.label(sid), last=row["last"],
                      dur=core.fmt_hms(dur), rate=rate)

    def finish_all(self) -> None:
        for sid in self.order:
            self._finish(sid)

    def abort(self) -> None:
        for sid in self.order:
            row = self.rows[sid]
            if not row["done"] and row["start"] is not None:
                row["done"] = True
                row["dur"] = time.monotonic() - row["start"]
                self.log.code("step_aborted", i=self.order.index(sid) + 1,
                              n=len(self.order), label=self.label(sid))

    def current_step(self) -> Optional[str]:
        """The step in progress, or the first one not started yet."""
        for sid in self.order:
            row = self.rows[sid]
            if row["start"] is not None and not row["done"]:
                return sid
        for sid in self.order:
            if self.rows[sid]["start"] is None:
                return sid
        return None

    def times(self) -> Dict[str, float]:
        return {sid: round(self.rows[sid]["dur"], 3) for sid in self.order
                if self.rows[sid]["start"] is not None}
