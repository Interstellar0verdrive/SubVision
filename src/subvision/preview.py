"""
Preview page of the app: sample frames of a video and the OCR test on one
of them.

`find_frames` is the "Find 20 frames" of SubVision 1.0 (app.py), moved
into the engine: the video is split into `n` zones and from each one a
WHOLE frame is taken (the app draws the bands on it), trying up to
`tries` timestamps per zone until a quick OCR of the dialogue band (or of
the signs band, when enabled) finds some text. The frames are JPEGs in
`<state>/tmp/preview/<hash of path+mtime+size>/NNN.jpg`; preview folders
older than 7 days are deleted at every call.

`test_frame` is the "Try OCR on this frame" of 1.0: it crops the bands
with the current parameters, runs the variants and the vote exactly as
the pipeline does, and returns text, confidence, agreement, alternatives,
final text (after postprocess, with {\\an8} for the signs band) and the
time taken, per band.

The cooperative stop (`Stopped`, `_check_stop`, `_run_ffmpeg`) and the
ffmpeg/ffprobe executables (`core.FFMPEG`/`core.FFPROBE`, set once by the
sidecar or the CLI through `core.set_tools`) come from core.py.
"""

from __future__ import annotations

import hashlib
import shutil
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

from PIL import Image

from subvision import core
from subvision.core import OcrParams, crop_band
from subvision.lists import Lists
from subvision.paths import state_paths

EmitCallback = Callable[[str, Dict[str, Any]], None]

PREVIEW_MAX_AGE = 7 * 86400     # seconds: older preview folders are removed
TRY_FRACTIONS = (0.5, 0.2, 0.8)  # positions tried inside a zone (center, start, end)
OCR_WORKERS = 4
QUICK_MIN_CONF = 0.25           # confidence floor of the quick "is there text?" OCR


# re-exported for the callers (and the tests) that catch the stop here
Stopped = core.Stopped
_check_stop = core._check_stop
_run_ffmpeg = core._run_ffmpeg


# ---------------------------------------------------------------- folders
def preview_dir(video: Path | str, state: Optional[Path | str] = None) -> Path:
    """`<state>/tmp/preview/<hash>` for this video (path + mtime + size)."""
    v = Path(video)
    try:
        st = v.stat()
        key = f"{v.resolve()}|{int(st.st_mtime)}|{st.st_size}"
    except OSError:
        key = str(v)
    digest = hashlib.sha1(key.encode("utf-8")).hexdigest()[:16]
    return state_paths(state).preview / digest


def clean_old(state: Optional[Path | str] = None, max_age: float = PREVIEW_MAX_AGE) -> int:
    """Removes the preview folders older than `max_age` seconds; returns how many."""
    root = state_paths(state).preview
    if not root.is_dir():
        return 0
    now = time.time()
    removed = 0
    for d in root.iterdir():
        try:
            if d.is_dir() and now - d.stat().st_mtime > max_age:
                shutil.rmtree(d, ignore_errors=True)
                removed += 1
        except OSError:
            continue
    return removed


def _duration(ffprobe: str, video: str) -> float:
    """Duration through the given ffprobe (core.ffprobe_duration with a temporary tool)."""
    if ffprobe == core.FFPROBE:
        return core.ffprobe_duration(video)
    out = subprocess.run([ffprobe, "-v", "error", "-show_entries", "format=duration",
                          "-of", "default=nw=1:nk=1", video], check=False,
                         capture_output=True, text=True, timeout=60, stdin=subprocess.DEVNULL)
    try:
        return float(out.stdout.strip())
    except ValueError as e:
        raise core.EngineError("probe_failed", path=video, error=out.stderr.strip()) from e


# ---------------------------------------------------------------- frames
def find_frames(video: Path | str, params: OcrParams, n: int = 20, tries: int = 3,
                emit: Optional[EmitCallback] = None,
                stop: Optional[threading.Event] = None,
                state: Optional[Path | str] = None,
                ffmpeg: Optional[str] = None, ffprobe: Optional[str] = None,
                ) -> List[Dict[str, Any]]:
    """
    Samples `n` whole frames of `video`, one per zone, preferring the
    timestamps where a quick OCR finds text in the dialogue band (or in the
    signs band when params.top_band). Emits `preview.progress`
    {done, total, found} after every zone and returns the frames in order:
    [{path, band, has_text, width, height, ts}] (band: "bottom" | "top" |
    None). Raises EngineError("invalid_duration") when ffprobe cannot read
    the video, Stopped when `stop` is set (checked while ffmpeg runs and
    before every OCR; no ffmpeg child survives).
    """
    video = str(video)
    paths = state_paths(state).ensure()
    # the executables configured by core.set_tools(), unless overridden here
    ffmpeg = ffmpeg or core.FFMPEG
    ffprobe = ffprobe or core.FFPROBE
    clean_old(paths.root)

    try:
        dur = _duration(ffprobe, video)
    except core.EngineError as e:
        raise core.EngineError("invalid_duration", path=video, error=str(e.args_.get("error", ""))) from e
    if dur <= 0:
        raise core.EngineError("invalid_duration", path=video)

    outdir = preview_dir(video, paths.root)
    shutil.rmtree(outdir, ignore_errors=True)
    outdir.mkdir(parents=True, exist_ok=True)

    use_vision = core.vision_available()
    langs = core.resolve_langs(params.lang_hint)
    if use_vision:
        core.warmup(langs, "fast")
    n = max(1, int(n))
    tries = max(1, min(len(TRY_FRACTIONS), int(tries)))
    fractions = TRY_FRACTIONS[:tries] if use_vision else TRY_FRACTIONS[:1]
    lo, hi = dur * 0.02, dur * 0.98
    edges = [lo + (hi - lo) * i / n for i in range(n + 1)]

    def grab(ts: float, out: Path) -> bool:
        cmd = [ffmpeg, "-hide_banner", "-nostats", "-loglevel", "error", "-y",
               "-ss", f"{ts:.3f}", "-i", video, "-frames:v", "1", "-q:v", "2", str(out)]
        try:
            _run_ffmpeg(cmd, stop, poll=0.05)
        except Stopped:
            raise
        except Exception:
            return False
        return out.is_file()

    def quick_band(im: Image.Image, band: str) -> bool:
        txt, _ = core.ocr_conf(crop_band(im, params, band), langs, "fast", QUICK_MIN_CONF)
        return bool(txt.strip())

    def probe_zone(i: int) -> Dict[str, Any]:
        a, b = edges[i], edges[i + 1]
        final = outdir / f"{i:03d}.jpg"
        made: List[Path] = []
        chosen: Optional[Tuple[Path, float, Optional[str]]] = None
        fallback: Optional[Tuple[Path, float]] = None
        try:
            for k, f in enumerate(fractions):
                _check_stop(stop)
                ts = a + (b - a) * f
                fp = outdir / f"{i:03d}_{k}.jpg"
                if not grab(ts, fp):
                    continue
                made.append(fp)
                if fallback is None:
                    fallback = (fp, ts)
                if not use_vision:
                    break
                _check_stop(stop)
                try:
                    im = Image.open(fp).convert("RGB")
                    if quick_band(im, "bottom"):
                        chosen = (fp, ts, "bottom")
                        break
                    if params.top_band and quick_band(im, "top"):
                        chosen = (fp, ts, "top")
                        break
                except Stopped:
                    raise
                except Exception:
                    continue
            if chosen is None and fallback is not None:
                chosen = (fallback[0], fallback[1], None)
            if chosen is None:
                return {"i": i, "path": None}
            fp, ts, band = chosen
            fp.replace(final)
            with Image.open(final) as im:
                width, height = im.size
            return {"i": i, "path": str(final), "band": band, "has_text": band is not None,
                    "width": width, "height": height, "ts": round(ts, 3)}
        finally:
            # also the half-written output of an ffmpeg terminated by the stop
            for fp in set(made) | set(outdir.glob(f"{i:03d}_*.jpg")):
                fp.unlink(missing_ok=True)

    frames: List[Optional[Dict[str, Any]]] = [None] * n
    done = found = 0
    ex = ThreadPoolExecutor(max_workers=OCR_WORKERS)
    try:
        futs = [ex.submit(probe_zone, i) for i in range(n)]
        for fut in as_completed(futs):
            try:
                res = fut.result()
            except Stopped:
                raise
            except Exception:
                res = None
            if res and res.get("path"):
                frames[res["i"]] = res
                found += int(res["has_text"])
            done += 1
            if emit:
                emit("preview.progress", {"done": done, "total": n, "found": found})
            _check_stop(stop)
    finally:
        ex.shutdown(wait=True, cancel_futures=True)

    out: List[Dict[str, Any]] = []
    for fr in frames:
        if fr:
            fr = dict(fr)
            fr.pop("i", None)
            out.append(fr)
    return out


# ---------------------------------------------------------------- OCR test
def test_frame(frame_path: Path | str, params: OcrParams,
               lists: Optional[Lists] = None) -> Dict[str, Any]:
    """
    OCR test on one whole frame with the current parameters. Returns
    {bands: {bottom: {text, conf, agree, alts, final, ms, empty}, top?: {...}}}:
    `text` is the voted raw reading, `final` the text after postprocess
    (corrections, wrap, ignore list; "{\\an8}" prefix for the signs band),
    `empty` True when nothing usable remains, `ms` the OCR time.
    Raises EngineError("vision_unavailable") without Apple Vision.
    """
    if not core.vision_available():
        raise core.EngineError("vision_unavailable")
    ignore_lines, corrections = lists or ([], [])
    langs = core.resolve_langs(params.lang_hint)
    core.warmup(langs, params.recognition_level)
    im = Image.open(frame_path).convert("RGB")

    def run_band(band: str) -> Dict[str, Any]:
        crop = crop_band(im, params, band)
        t0 = time.time()
        cands = [core.ocr_conf(v, langs, params.recognition_level, params.min_confidence, fw)
                 for _, v, fw in core.gen_variants(crop, params.multi_variant)]
        text, conf, agree, alts = core.vote_texts(cands)
        ms = (time.time() - t0) * 1000
        clean = core.postprocess(core.sanitize(text, ignore_lines), params.wrap_width,
                                 ignore_lines, corrections, lang_hint=params.lang_hint)
        final = ("{\\an8}" + clean) if (clean and band == "top") else clean
        return {"text": text, "conf": round(conf, 4), "agree": round(agree, 4),
                "alts": list(alts), "final": final, "ms": round(ms, 1),
                "variants": len(cands), "empty": not final}

    bands = {"bottom": run_band("bottom")}
    if params.top_band:
        bands["top"] = run_band("top")
    return {"bands": bands}
