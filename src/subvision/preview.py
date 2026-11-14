"""
Preview page of the app: sample frames of a video and the OCR test on one
of them.

`find_frames` is the "Find 20 frames" of SubVision 1.0 (app.py), moved
into the engine: the video is split into `n` zones and from each one a
WHOLE frame is taken (the app draws the bands on it), trying up to
`tries` timestamps per zone to find one with text in the dialogue band
and, when enabled, in the signs band (see probe_bands). The frames are
JPEGs in `<state>/tmp/preview/<hash of path+mtime+size>/NNN.jpg`; preview
folders older than 7 days are deleted at every call.

"Is there text?" is two readings of the band crop: a quick one (the `fast`
level of Vision) that must find at least two real letters, then, only when
it does, a confirmation with the `accurate` level at the minimum
confidence of the parameters, which must find two letters too. The quick
reading alone reads words into busy drawings (an anime scene gave "I'ii"
in the dialogue band, "Ji?" and "li?" in the signs band of the demo clips);
the accurate one reads nothing there and is what the batch will see.

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
from typing import Any, Callable, Dict, Iterable, List, Optional, Tuple

from PIL import Image

from subvision import core
from subvision.core import OcrParams, crop_band
from subvision.lists import Lists
from subvision.paths import state_paths

EmitCallback = Callable[[str, Dict[str, Any]], None]

PREVIEW_MAX_AGE = 7 * 86400     # seconds: older preview folders are removed
TRY_FRACTIONS = (0.5, 0.2, 0.8)  # positions tried inside a zone (center, start, end)
OCR_WORKERS = 4
QUICK_MIN_CONF = 0.3            # confidence floor of the quick "is there text?" OCR
# The quick OCR ("fast" level) only ever answers with confidence 0.3 or 0.5,
# and what it invents on a frame without subtitles ("r", "i", "*", "(",
# "Ji?", "I'ii") gets the same values as a real line: the confidence cannot
# tell them apart, so the floor is just the lowest value it gives. A reading
# counts as text from two LETTERS on (digits and punctuation are what the
# texture of a picture gives), and it must be confirmed by the accurate OCR.
QUICK_MIN_LETTERS = 2
CONFIRM_LEVEL = "accurate"      # level of the confirmation (min confidence: params.min_confidence)
BANDS_ORDER = ("bottom", "top")


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
        raise core.EngineError("probe_failed", path=video, tool="ffprobe",
                               detail=out.stderr.strip()) from e


# ---------------------------------------------------------------- frames
def looks_like_text(text: str) -> bool:
    """
    True when a reading is worth calling "text": at least QUICK_MIN_LETTERS
    letters, or one ideograph/kana/hangul (a one-character line is normal
    in Chinese, Japanese and Korean). A lone Latin letter, digits or
    punctuation are what Vision sees in the texture of a frame without
    subtitles.
    """
    letters = [c for c in text if c.isalpha()]
    return len(letters) >= QUICK_MIN_LETTERS or any(ord(c) >= 0x2E80 for c in letters)


def probe_bands_of(params: OcrParams) -> List[str]:
    """The bands find_frames looks at: the signs band only with params.top_band."""
    return list(BANDS_ORDER) if params.top_band else ["bottom"]


def quick_bands(image: Image.Image, params: OcrParams, langs: List[str]) -> List[str]:
    """Bands of a whole frame where the quick (`fast`) OCR reads some letters."""
    out = []
    for band in probe_bands_of(params):
        txt, _ = core.ocr_conf(crop_band(image, params, band), langs, "fast", QUICK_MIN_CONF)
        if looks_like_text(txt):
            out.append(band)
    return out


def confirm_band(image: Image.Image, params: OcrParams, langs: List[str], band: str) -> bool:
    """The accurate OCR of the band (at params.min_confidence) reads some letters too."""
    txt, _ = core.ocr_conf(crop_band(image, params, band), langs, CONFIRM_LEVEL,
                           params.min_confidence)
    return looks_like_text(txt)


def probe_bands(image: Image.Image, params: OcrParams, langs: List[str]) -> List[str]:
    """
    Bands of a whole frame with text, in the order of BANDS_ORDER (a subset
    of ["bottom", "top"]; "top" only with params.top_band): the quick reading
    finds letters and the accurate one confirms them. [] = no text.
    """
    return [b for b in quick_bands(image, params, langs) if confirm_band(image, params, langs, b)]


def _better(new: List[str], old: Optional[List[str]]) -> bool:
    """For the choice of a zone's frame: any text beats none, dialogue beats signs only."""
    if not new:
        return False
    if old is None:
        return True
    return "bottom" in new and "bottom" not in old


def find_frames(video: Path | str, params: OcrParams, n: int = 20, tries: int = 3,
                emit: Optional[EmitCallback] = None,
                stop: Optional[threading.Event] = None,
                state: Optional[Path | str] = None,
                ffmpeg: Optional[str] = None, ffprobe: Optional[str] = None,
                zones: Optional[Iterable[int]] = None,
                ) -> List[Dict[str, Any]]:
    """
    Samples `n` whole frames of `video`, one per zone, preferring the
    timestamps with text (see probe_bands). Both bands are checked when
    params.top_band is on, only the dialogue band otherwise. The frame of a
    zone is the first timestamp with text in both bands; otherwise the first
    with any text (dialogue preferred over signs only); otherwise the first
    frame grabbed, without text.
    Emits `preview.progress` {done, total, found, found_top, zone, frame}
    after every zone (found: frames with text in any band; found_top:
    frames with text in the signs band; zone: the zone just searched;
    frame: its frame, or None when no timestamp of the zone could be read)
    and returns the frames in order:
    [{zone, path, bands, has_text, width, height, ts}] where `bands` is a
    subset of ["bottom", "top"] in this order ([] = no text) and has_text =
    bool(bands). A zone whose timestamps cannot be read has no frame.
    `zones` resumes a search (C3, board A1): only those zones (0-based, of
    `n`) are searched, the frames of the others stay in the folder, `done`
    starts from the zones not searched now and found/found_top count only
    the zones searched now. Without it every zone is searched from an empty
    folder. The zones look at the same timestamps every time
    (TRY_FRACTIONS), so a zone searched again gives the same frame.
    Raises EngineError("invalid_duration") when ffprobe cannot read the
    video, Stopped when `stop` is set (checked while ffmpeg runs and before
    every OCR; no ffmpeg child survives). The progress events sent before
    the stop carry the frames found so far.
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
        raise core.EngineError("invalid_duration", path=video, tool="ffprobe",
                               detail=str(e.args_.get("detail", ""))) from e
    if dur <= 0:
        raise core.EngineError("invalid_duration", path=video, tool="ffprobe",
                               detail="ffprobe reported no duration")

    n = max(1, int(n))
    outdir = preview_dir(video, paths.root)
    if zones is None:
        todo = list(range(n))
        shutil.rmtree(outdir, ignore_errors=True)
    else:
        todo = sorted({int(z) for z in zones if 0 <= int(z) < n})
        for i in todo:
            for old in outdir.glob(f"{i:03d}*.jpg"):
                old.unlink(missing_ok=True)
    outdir.mkdir(parents=True, exist_ok=True)

    use_vision = core.vision_available()
    langs = core.resolve_langs(params.lang_hint)
    if use_vision:
        core.warmup(langs, "fast")
        core.warmup(langs, CONFIRM_LEVEL)
    wanted = probe_bands_of(params)
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

    def probe_zone(i: int) -> Dict[str, Any]:
        a, b = edges[i], edges[i + 1]
        final = outdir / f"{i:03d}.jpg"
        made: List[Path] = []
        chosen: Optional[Tuple[Path, float, List[str]]] = None   # text in every wanted band
        best: Optional[Tuple[Path, float, List[str]]] = None     # the best one seen so far
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
                    quick = quick_bands(im, params, langs)
                    # the accurate confirmation only where it can change the choice
                    if not _better(quick, best[2] if best else None) and quick != wanted:
                        continue
                    bands = []
                    for band in quick:
                        _check_stop(stop)
                        if confirm_band(im, params, langs, band):
                            bands.append(band)
                    if bands == wanted:
                        chosen = (fp, ts, bands)
                        break
                    if _better(bands, best[2] if best else None):
                        best = (fp, ts, bands)
                except Stopped:
                    raise
                except Exception:
                    continue
            if chosen is None:
                chosen = best
            if chosen is None and fallback is not None:
                chosen = (fallback[0], fallback[1], [])
            if chosen is None:
                return {"zone": i, "path": None}
            fp, ts, bands = chosen
            fp.replace(final)
            with Image.open(final) as im:
                width, height = im.size
            return {"zone": i, "path": str(final), "bands": list(bands), "has_text": bool(bands),
                    "width": width, "height": height, "ts": round(ts, 3)}
        finally:
            # also the half-written output of an ffmpeg terminated by the stop
            for fp in set(made) | set(outdir.glob(f"{i:03d}_*.jpg")):
                fp.unlink(missing_ok=True)

    frames: Dict[int, Dict[str, Any]] = {}
    done = n - len(todo)
    found = found_top = 0
    ex = ThreadPoolExecutor(max_workers=OCR_WORKERS)
    try:
        futs = {ex.submit(probe_zone, i): i for i in todo}
        for fut in as_completed(futs):
            try:
                res = fut.result()
            except Stopped:
                raise
            except Exception:
                res = None
            frame = res if res and res.get("path") else None
            if frame:
                frames[frame["zone"]] = frame
                found += int(frame["has_text"])
                found_top += int("top" in frame["bands"])
            done += 1
            if emit:
                emit("preview.progress", {"done": done, "total": n, "found": found,
                                          "found_top": found_top, "zone": futs[fut],
                                          "frame": dict(frame) if frame else None})
            _check_stop(stop)
    finally:
        ex.shutdown(wait=True, cancel_futures=True)

    return [frames[i] for i in sorted(frames)]


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
        raise core.EngineError("vision_unavailable", tool="vision")
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
