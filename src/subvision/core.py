#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SubVision — core pipeline (no UI).

Extracts hardsubs (subtitles burned into the video) and converts them to
.srt using Apple Vision (macOS native OCR framework, via the `ocrmac`
wrapper).

Philosophy: MAXIMUM ACCURACY, speed is not a priority. The goal is to
minimize manual rework (skipped subtitles, imprecise timing, typos), so:

1. MULTI-VARIANT OCR with voting: every frame is OCRed in several versions
   (raw, contrast+sharpen, grayscale) and the text is decided by a majority
   weighted by confidence. No single variant always wins alone (measured).
2. SEGMENT VOTING: the final text of a subtitle is the one that gathered
   the most weight across all the frames of the segment (not "the longest").
3. TIMING REFINEMENT: the start/end boundaries are recomputed at the
   video's NATIVE frame rate (~1 frame precision, ~±20ms).
4. Optional TOP BAND for translated signs/banners ({\\an8}).
5. REVIEW REPORT (.review.html): every line carries its confidence,
   agreement between variants and a thumbnail; doubtful lines, dropped
   flashes and long gaps end up in an HTML report/editor for guided
   manual review.

This module does not import streamlit: it can be tested/run headless.
"""

from __future__ import annotations

import io
import os
import re
import time
import base64
import shutil
import hashlib
import tempfile
import subprocess
import threading
import datetime
from pathlib import Path
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Tuple

from PIL import Image, ImageOps, ImageEnhance, ImageFilter

from subvision import __version__  # single source of truth: subvision/__init__.py

REPO_URL = "https://github.com/Interstellar0verdrive/SubVision"

# ocrmac is imported lazily inside the OCR functions so the module loads
# even where Apple Vision is not available (useful for SRT-only tests).

# ---------------------------------------------------------------- Languages
LANG_MAP = {
    "italian": "it-IT", "italiano": "it-IT",
    "english": "en-US", "inglese": "en-US",
    "spanish": "es-ES", "spagnolo": "es-ES",
    "french": "fr-FR", "francese": "fr-FR",
    "german": "de-DE", "tedesco": "de-DE",
    "portuguese": "pt-BR", "portoghese": "pt-BR",
    "japanese": "ja-JP", "giapponese": "ja-JP",
    "korean": "ko-KR", "coreano": "ko-KR",
    "chinese": "zh-Hans", "cinese": "zh-Hans",
}


def resolve_langs(lang_hint: str) -> List[str]:
    key = (lang_hint or "").strip().lower()
    if not key:
        return ["it-IT"]
    if key in LANG_MAP:
        return [LANG_MAP[key]]
    return [lang_hint.strip()]


# ---------------------------------------------------------------- Events
# The engine never formats text for the user: progress and log callbacks
# receive codes and numbers, and the caller (sidecar, CLI, app) formats them
# in its own language. The only localized texts left here are the ones of
# the review report (_QC_I18N), because the report is generated here.
STEPS = ("extract", "group", "ocr", "refine")
BANDS = ("bottom", "top")


@dataclass(frozen=True)
class ProgressEvent:
    """
    Progress of one step of one band. `ratio` grows from 0 to 1 within the
    step; `count`/`total` are the numbers behind it (`unit`: what they count,
    e.g. "frames" during extract/group/ocr, "targets" for the frames selected
    for OCR at the end of group, "segments" during refine).
    """
    step: str          # one of STEPS
    band: str          # one of BANDS
    ratio: float       # 0.0 .. 1.0
    count: int
    total: int
    unit: str


@dataclass(frozen=True)
class LogEvent:
    """
    One line of the per-file log, as a code plus its arguments. Codes:
      frames_extracted  {band, n, fps}
      ocr_targets       {band, targets, frames}
      ocr_error         {band, error}
      refining          {band, fps}
      boundaries_moved  {band, n}
      srt_written       {path, segments, ocr, refined, elapsed}
      report_written    {path}
      report_failed     {path, error}
    """
    code: str
    args: Dict[str, Any] = field(default_factory=dict)


ProgressCallback = Callable[[ProgressEvent], None]
LogCallback = Callable[[LogEvent], None]
# Low-level step callback used inside the band pipeline: (ratio, count, total).
_StepCallback = Callable[[float, int, int], None]


class EngineError(RuntimeError):
    """
    Engine error with a stable `code` (the message is the code itself) and
    optional details for the app: `detail` (technical text: exception,
    stderr), `tool` ("ffmpeg" | "ffprobe" | "vision" | "uv" when a tool is
    involved), `path` (the file concerned), `line` (for parse errors), and
    for `bad_params` the pair `field` / `reason` (the parameter refused and
    why), which travels as `data: {field, reason}`. Any other keyword ends
    up in `args_` and in the detail text.
    """

    DETAIL_KEYS = ("detail", "tool", "path", "line")
    DATA_KEYS = ("field", "reason")

    def __init__(self, code: str, **args: Any) -> None:
        super().__init__(code)
        self.code = code
        self.args_ = args

    def details(self) -> Dict[str, Any]:
        """
        {detail, tool, path, line, data} when present; `data` is
        {field, reason}; other args are folded into detail.
        """
        out = {k: self.args_[k] for k in self.DETAIL_KEYS if self.args_.get(k) is not None}
        data = {k: self.args_[k] for k in self.DATA_KEYS if self.args_.get(k) is not None}
        if data:
            out["data"] = data
        extra = ", ".join(f"{k}={v}" for k, v in self.args_.items()
                          if k not in self.DETAIL_KEYS and k not in self.DATA_KEYS)
        if extra:
            out["detail"] = f"{out['detail']} ({extra})" if out.get("detail") else extra
        return out

    def describe(self) -> str:
        """`code` plus the details in one line (logs, CLI)."""
        d = self.details()
        parts = [f"{k}={d[k]}" for k in ("tool", "path", "line") if k in d]
        if d.get("detail"):
            parts.append(" · ".join(ln.strip() for ln in str(d["detail"]).splitlines() if ln.strip()))
        elif d.get("data"):
            parts.append(": ".join(str(v) for v in d["data"].values()))
        return self.code + (f" ({'; '.join(parts)})" if parts else "")


def tool_stderr(e: BaseException) -> str:
    """
    What a failed ffmpeg/ffprobe said, for the `detail` of an error: its
    stderr without the `[demuxer @ 0x...]` prefixes (the first line is then
    the reason itself), or the exception text when there is no stderr.
    """
    err = getattr(e, "stderr", None)
    if isinstance(err, bytes):
        err = err.decode("utf-8", "replace")
    lines = [re.sub(r"^(\[[^\]]*\]\s*)+", "", ln).strip() for ln in (err or "").splitlines()]
    lines = [ln for ln in lines if ln]
    return "\n".join(lines) if lines else str(e)


# Flags attached to the segments (SegInfo.flags). Codes only: the review
# report translates them through _QC_I18N["<lang>"]["flags"].
FLAG_TOO_SHORT = "too_short"
FLAG_NOISE = "noise"
FLAG_MERGED_FADE = "merged_fade"


# ---------------------------------------------------------------- Parameters
@dataclass
class OcrParams:
    """
    Defaults = MAXIMUM ACCURACY (high fps, no skipping, 3 variants, signs
    band enabled, timing refinement). With these values a 20-24 min episode
    takes ~1.5-2 hours. For a fast profile (~10-15 min):
    fps=6, skip_hamming=1, multi_variant=False, top_band=False.
    """
    fps: float = 12.0                  # frames/sec analyzed (12 = max precision
                                       # in detecting very short subs and boundaries)
    lang_hint: str = "Italian"
    # bottom band (dialogue)
    bottom_keep_pct: int = 28          # height kept from the bottom (%)
    keep_w_pct: int = 96               # centered width kept (%)
    # top band (signs / banners / translator notes)
    top_band: bool = True              # ON by default: captures {\an8} signs
    top_keep_pct: int = 22             # height kept from the top (%)
    top_keep_w_pct: int = 100          # centered width of the signs band (%)
                                       # (reduce to exclude watermarks in the corners)
    # OCR
    recognition_level: str = "accurate"
    min_confidence: float = 0.30
    multi_variant: bool = True         # OCR in 3 variants + voting (recommended)
    # skip redundant frames (dhash vs previous frame):
    # 0 = OCR EVERY frame, no assumptions (max accuracy, default);
    # 1 = skip near-identical ones (~20-30% faster, measured identical timing);
    # >=2 = faster but the base boundaries drift (refinement recovers them).
    skip_hamming: int = 0
    # timing
    refine_timing: bool = True         # refine start/end at the native frame rate
    # segments
    min_duration: float = 0.20         # below this duration -> dropped (but kept in the review report)
    merge_gap: float = 0.6             # merge nearby segments with similar text
    wrap_width: int = 42
    workers: int = 4
    # QC
    qc_report: bool = True
    qc_gap_warn: float = 6.0           # gaps without subs longer than X sec go in the review report
    qc_conf_warn: float = 0.80         # below this confidence -> "yellow" line
    qc_agree_warn: float = 0.70        # below this variant agreement -> "yellow"
    ignore_lines: List[str] = field(default_factory=list)
    # automatic "wrong => right" corrections (from corrections.txt):
    # for the RECURRING typos the OCR will never fix (e.g. proper nouns on
    # impossible fonts: "Flamilion => Hamilton"). Applied at pipeline end.
    corrections: List[Tuple[str, str]] = field(default_factory=list)


@dataclass
class SegInfo:
    start: float
    end: float
    text: str
    conf: float = 1.0                  # weighted average confidence of the winning text
    agree: float = 1.0                 # vote share of the winning text (0-1)
    nframes: int = 0                   # frames that make up the segment
    top: bool = False                  # True = top band (sign)
    thumb: str = ""                    # base64 JPEG thumbnail (for the review report)
    alts: List[str] = field(default_factory=list)   # discarded alternative readings
    flags: List[str] = field(default_factory=list)  # QC notes


@dataclass
class RunStats:
    frames: int = 0
    ocr_calls: int = 0
    segments: int = 0
    dropped: int = 0
    refined: int = 0
    elapsed: float = 0.0
    qc_path: str = ""
    # long gaps without subtitles (start, end) in seconds, as the report lists them
    gaps: List[Tuple[float, float]] = field(default_factory=list)


# ---------------------------------------------------------------- stop
# Cooperative cancellation (design from spike S3): the caller passes a
# threading.Event; the pipeline checks it at its stop points (every ffmpeg
# poll, every 50 frames of dhash, before every OCR task and variant, before
# every refined row) and raises Stopped within ~1 s, after terminating its
# ffmpeg children. No partial result: no SRT, no report, workdir removed.
class Stopped(Exception):
    """
    Raised at a cooperative stop point when the caller's `stop` event is set.
    Subclass of Exception on purpose (a BaseException would slip through the
    ThreadPoolExecutor's future machinery in surprising ways), so every
    generic `except Exception` on the stop path must re-raise it explicitly.
    """


def _check_stop(stop: Optional[threading.Event]) -> None:
    """STOP POINT: cheap check, raises Stopped if the event is set."""
    if stop is not None and stop.is_set():
        raise Stopped()


def _stop_proc(proc: subprocess.Popen, grace: float = 1.0) -> None:
    """
    Terminates a child: SIGTERM, wait up to `grace`, then SIGKILL. Always
    reaps the process (communicate) so no zombie and no open pipe is left.
    """
    if proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.communicate(timeout=grace)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()


def _run_ffmpeg(cmd: list, stop: Optional[threading.Event] = None,
                on_poll: Optional[Callable[[], None]] = None,
                poll: float = 0.1) -> str:
    """
    The only place that starts ffmpeg: Popen, polled every `poll` seconds.
    STOP POINT: at every poll, if `stop` is set the child is terminated
    (SIGTERM -> SIGKILL after 1 s) and Stopped is raised.
    stderr is drained continuously by communicate(timeout=...) (an ffmpeg
    that writes more than the pipe buffer would otherwise block forever).
    Returns stderr; raises CalledProcessError on a non-zero exit.
    """
    proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                            stderr=subprocess.PIPE, text=True)
    try:
        while True:
            try:
                _, err = proc.communicate(timeout=poll)
                break
            except subprocess.TimeoutExpired:
                pass
            if stop is not None and stop.is_set():
                _stop_proc(proc)
                raise Stopped()
            if on_poll:
                on_poll()
    except BaseException:
        # any other exception (KeyboardInterrupt, bug in on_poll): no orphan
        _stop_proc(proc)
        raise
    if proc.returncode != 0:
        raise subprocess.CalledProcessError(proc.returncode, cmd, stderr=err)
    return err or ""


# ---------------------------------------------------------------- ffmpeg
# Paths of the tools, set by the app/CLI (tools.py) via set_tools(); the
# bare names fall back to PATH, which an app launched from the Finder does
# not have, hence the explicit configuration.
FFMPEG = "ffmpeg"
FFPROBE = "ffprobe"


def set_tools(ffmpeg: str, ffprobe: str) -> None:
    """Sets the ffmpeg/ffprobe executables used by every call of the engine."""
    global FFMPEG, FFPROBE
    FFMPEG = str(ffmpeg)
    FFPROBE = str(ffprobe)


def _run(cmd: list) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, capture_output=True, text=True,
                          stdin=subprocess.DEVNULL)


def ffprobe_duration(video: str) -> float:
    """
    Duration in seconds. Raises EngineError("probe_failed") when ffprobe
    fails or prints no number (the old version returned 0.0 and the
    pipeline went on with no progress estimate and a cryptic ffmpeg error).
    """
    try:
        out = _run([FFPROBE, "-v", "error", "-show_entries", "format=duration",
                    "-of", "default=nw=1:nk=1", video]).stdout
        return float(out.strip())
    except (subprocess.CalledProcessError, OSError, ValueError) as e:
        raise EngineError("probe_failed", path=video, tool="ffprobe",
                          detail=tool_stderr(e)) from e


def ffprobe_fps(video: str) -> float:
    """
    Native frame rate of the video (for boundary refinement). Raises
    EngineError("probe_failed") when ffprobe cannot read the video stream.
    """
    last_err: Optional[Exception] = None
    for entry in ("avg_frame_rate", "r_frame_rate"):
        try:
            val = _run([FFPROBE, "-v", "error", "-select_streams", "v:0",
                        "-show_entries", f"stream={entry}",
                        "-of", "default=nk=1:nw=1", video]).stdout.strip()
            if "/" in val:
                n, d = val.split("/")
                fps = float(n) / (float(d) or 1.0)
            else:
                fps = float(val)
            if fps > 0.1:
                return fps
        except (subprocess.CalledProcessError, OSError, ValueError) as e:
            last_err = e
            continue
    raise EngineError("probe_failed", path=video, tool="ffprobe",
                      detail=tool_stderr(last_err) if last_err else "no frame rate")


def band_crop(p: OcrParams, band: str) -> str:
    """ffmpeg crop expression for the requested band ('bottom' | 'top')."""
    if band == "top":
        vb = max(1, min(100, int(p.top_keep_pct)))
        kw = max(1, min(100, int(p.top_keep_w_pct)))
        crop_w = "iw" if kw >= 100 else f"iw*{kw}/100"
        crop_x = "0" if kw >= 100 else f"(iw-iw*{kw}/100)/2"
        return f"crop={crop_w}:ih*{vb}/100:{crop_x}:0"
    vb = max(1, min(100, int(p.bottom_keep_pct)))
    kw = max(1, min(100, int(p.keep_w_pct)))
    crop_w = "iw" if kw >= 100 else f"iw*{kw}/100"
    crop_x = "0" if kw >= 100 else f"(iw-iw*{kw}/100)/2"
    return f"crop={crop_w}:ih*{vb}/100:{crop_x}:ih-ih*{vb}/100"


def band_box(p: OcrParams, band: str, width: int, height: int
             ) -> Tuple[int, int, int, int]:
    """
    Pixel box (left, top, right, bottom) of the requested band on a full
    frame of the given size: the same geometry as band_crop(), for callers
    that work on whole frames in PIL (preview, OCR test).
    """
    if band == "top":
        vb = max(1, min(100, int(p.top_keep_pct)))
        kw = max(1, min(100, int(p.top_keep_w_pct)))
    else:
        vb = max(1, min(100, int(p.bottom_keep_pct)))
        kw = max(1, min(100, int(p.keep_w_pct)))
    w = width if kw >= 100 else int(width * kw / 100)
    h = int(height * vb / 100)
    left = 0 if kw >= 100 else int((width - width * kw / 100) / 2)
    top = 0 if band == "top" else height - h
    return left, top, left + w, top + h


def crop_band(im: Image.Image, p: OcrParams, band: str) -> Image.Image:
    """The band of a full frame, cropped in PIL (see band_box)."""
    return im.crop(band_box(p, band, im.width, im.height))


def extract_frames(video: str, outdir: Path, p: OcrParams, band: str,
                   progress_cb: Optional[_StepCallback] = None,
                   stop: Optional[threading.Event] = None,
                   ) -> Tuple[List[Path], float]:
    """
    Extracts the frames of the requested band, WITHOUT enhancement filters:
    the raw image reads better (measured); the variants are generated in PIL
    at OCR time, so they can vote.
    progress_cb(ratio, frames_so_far, frames_expected).
    STOP POINT: `stop` is polled every 0.1 s while ffmpeg runs; on stop the
    child is terminated and Stopped is raised (partial frames stay in
    outdir, the caller removes the workdir).
    """
    _check_stop(stop)
    outdir.mkdir(parents=True, exist_ok=True)
    vf = f"fps={p.fps},{band_crop(p, band)}"
    pattern = str(outdir / "f_%08d.jpg")
    # -nostats: no progress line every 0.5 s on stderr (we count files instead)
    cmd = [FFMPEG, "-hide_banner", "-nostats", "-y", "-i", video, "-vf", vf,
           "-fps_mode", "passthrough", "-q:v", "2", pattern]
    duration = ffprobe_duration(video)
    expected = max(1, int(duration * p.fps)) if duration else 0
    last = [0.0]

    def on_poll():
        # progress every ~0.3 s as before (the stop poll is every 0.1 s)
        now = time.monotonic()
        if progress_cb and expected and now - last[0] >= 0.3:
            last[0] = now
            cnt = sum(1 for _ in outdir.glob("f_*.jpg"))
            progress_cb(min(0.99, cnt / expected), cnt, expected)

    _run_ffmpeg(cmd, stop=stop, on_poll=on_poll, poll=0.1)
    frames = sorted(outdir.glob("f_*.jpg"))
    if progress_cb:
        progress_cb(1.0, len(frames), len(frames))
    return frames, 1.0 / max(p.fps, 0.001)


# ---------------------------------------------------------------- images
def dhash(path: Path, hash_size: int = 16) -> int:
    im = Image.open(path)
    im = ImageOps.grayscale(im).resize((hash_size + 1, hash_size), Image.BILINEAR)
    px = list(im.get_flattened_data())
    bits = 0
    pos = 0
    for r in range(hash_size):
        row = px[r * (hash_size + 1):(r + 1) * (hash_size + 1)]
        for x in range(hash_size):
            bits |= (1 if row[x] > row[x + 1] else 0) << pos
            pos += 1
    return bits


def hamming(a: int, b: int) -> int:
    return (a ^ b).bit_count()


def livetext_available() -> bool:
    try:
        from ocrmac.ocrmac import LIVETEXT_AVAILABLE
        return bool(LIVETEXT_AVAILABLE)
    except Exception:
        return False


def gen_variants(im: Image.Image, multi: bool) -> List[Tuple[str, Image.Image, str]]:
    """
    Variants for the vote: (name, image, framework).
    Choices MEASURED on real difficult frames (italic font with halo):
    - raw/vision and enhanced/vision fail on different lines;
    - raw/livetext (Apple's second OCR engine, the "Live Text" one) is
      strong everywhere and, being an INDEPENDENT engine, diversifies the vote;
    - grayscale and downscale were tried and discarded (unstable/worse).
    """
    out = [("raw", im, "vision")]
    if multi:
        enh = ImageEnhance.Contrast(im).enhance(1.5)
        enh = enh.filter(ImageFilter.UnsharpMask(radius=2, percent=120, threshold=3))
        out.append(("enh", enh, "vision"))
        if livetext_available():
            out.append(("lt", im, "livetext"))
        else:
            # fallback for macOS < 13: third vision variant in grayscale
            gray = ImageOps.grayscale(im).convert("RGB")
            gray = ImageEnhance.Contrast(gray).enhance(1.6)
            out.append(("gray", gray, "vision"))
    return out


def thumb_b64(path: Path, width: int = 440) -> str:
    """Base64 JPEG thumbnail for the review report (self-contained, no external files)."""
    try:
        im = Image.open(path).convert("RGB")
        if im.width > width:
            im = im.resize((width, int(im.height * width / im.width)), Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, format="JPEG", quality=62)
        return base64.b64encode(buf.getvalue()).decode("ascii")
    except Exception:
        return ""


# ---------------------------------------------------------------- Apple Vision
_VISION_OK: Optional[bool] = None


def vision_available() -> bool:
    global _VISION_OK
    if _VISION_OK is None:
        try:
            from ocrmac import ocrmac  # noqa: F401
            _VISION_OK = True
        except Exception:
            _VISION_OK = False
    return bool(_VISION_OK)


_VISION_LANGS: Optional[List[str]] = None


def vision_languages() -> List[str]:
    """
    BCP-47 codes that Vision can recognize on this Mac (e.g. "it-IT"),
    cached; [] when Vision is not importable. Used to validate the OCR
    language before a job starts (an unknown language gives an empty SRT
    with no error) and by the sidecar's `hello`.
    """
    global _VISION_LANGS
    if _VISION_LANGS is None:
        try:
            import Vision
            req = Vision.VNRecognizeTextRequest.alloc().init()
            langs, _err = req.supportedRecognitionLanguagesAndReturnError_(None)
            _VISION_LANGS = [str(code) for code in (langs or [])]
        except Exception:
            _VISION_LANGS = []
    return list(_VISION_LANGS)


def warmup(langs: List[str], level: str = "accurate") -> None:
    try:
        from ocrmac import ocrmac
        img = Image.new("RGB", (48, 24), "white")
        ocrmac.OCR(img, recognition_level=level, language_preference=langs).recognize()
        if livetext_available():
            ocrmac.OCR(img, framework="livetext", language_preference=langs).recognize()
    except Exception:
        pass


def ocr_conf(img: Image.Image, langs: List[str], level: str,
             min_conf: float, framework: str = "vision") -> Tuple[str, float]:
    """
    OCR of a single image. Returns (multi-line text, average confidence).
    framework: "vision" (VNRecognizeText) or "livetext" (Live Text engine).

    Both can SPLIT a single visual line into several observations (LiveText
    even into tokens), and the return order is not reliable: sorting by y
    alone can invert the pieces of the same line. So: we group the boxes
    into VISUAL LINES (by vertical overlap) and inside each line we sort
    left to right, joining with spaces.
    """
    from ocrmac import ocrmac
    if framework == "livetext":
        res = ocrmac.OCR(img, framework="livetext",
                         language_preference=langs).recognize()
    else:
        res = ocrmac.OCR(img, recognition_level=level,
                         language_preference=langs).recognize()
    # res: (text, confidence, bbox) with normalized bbox=(x, y, w, h),
    # origin at the bottom left (Vision convention) -> large y = at the top.
    items = [(t.strip(), c, box) for (t, c, box) in res if t.strip() and c >= min_conf]
    if not items:
        return "", 0.0

    lines: List[dict] = []
    # scan top to bottom (decreasing vertical center)
    for t, c, (x, y, w, h) in sorted(items, key=lambda r: -(r[2][1] + r[2][3] / 2)):
        yc = y + h / 2
        for ln in lines:
            # same visual line if the centers are less than ~half a height apart
            if abs(yc - ln["yc"]) < max(h, ln["h"]) * 0.6:
                ln["parts"].append((x, t))
                ln["yc"] = (ln["yc"] + yc) / 2
                ln["h"] = max(ln["h"], h)
                break
        else:
            lines.append({"yc": yc, "h": h, "parts": [(x, t)]})

    text = "\n".join(" ".join(t for _, t in sorted(ln["parts"], key=lambda p: p[0]))
                     for ln in lines).strip()
    conf = sum(c for _, c, _ in items) / len(items)
    return text, conf


def vote_texts(cands: List[Tuple[str, float]]) -> Tuple[str, float, float, List[str]]:
    """
    Confidence-weighted majority vote among alternative readings.
    Returns (winning_text, confidence, agreement_share, discarded_alternatives).
    Empty readings do not vote: any text beats emptiness (Vision does not
    invent text where there is none; if a variant reads, there usually is text).
    """
    groups: Dict[str, dict] = {}
    for text, conf in cands:
        if not text:
            continue
        key = normalize_cmp(text)
        g = groups.setdefault(key, {"w": 0.0, "raw": {}, "confs": []})
        g["w"] += max(conf, 0.05)
        g["raw"][text] = g["raw"].get(text, 0) + 1
        g["confs"].append(conf)
    if not groups:
        return "", 0.0, 1.0, []
    total = sum(g["w"] for g in groups.values())
    key, g = max(groups.items(), key=lambda kv: kv[1]["w"])
    # most frequent raw form of the winning group (ties: the longest)
    raw = max(g["raw"].items(), key=lambda kv: (kv[1], len(kv[0])))[0]
    conf = sum(g["confs"]) / len(g["confs"])
    agree = g["w"] / total if total > 0 else 1.0
    alts = [max(gg["raw"], key=gg["raw"].get) for k, gg in groups.items() if k != key]
    return raw, conf, agree, alts


# ---------------------------------------------------------------- text/filters
_NO_SUB_REGEX = [
    r"non\s+c(?:i\s+)?sono\s+sottotitol",
    r"nessun\s+sottotitol",
    r"no\s+subtitle",
    r"no\s+caption",
    r"there\s+(?:is|are)\s+no\s+subtitle",
]


def normalize_cmp(s: str) -> str:
    s = (s or "").strip().lower()
    s = re.sub(r"[\"“”‘’„«»‹›]", "", s)
    s = re.sub(r"[^\wÀ-ÿ]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def edit_distance(a: str, b: str) -> int:
    a, b = a or "", b or ""
    n, m = len(a), len(b)
    if n == 0 or m == 0:
        return max(n, m)
    dp = list(range(m + 1))
    for i in range(1, n + 1):
        prev = dp[0]
        dp[0] = i
        for j in range(1, m + 1):
            cur = dp[j]
            cost = 0 if a[i - 1] == b[j - 1] else 1
            dp[j] = min(dp[j] + 1, dp[j - 1] + 1, prev + cost)
            prev = cur
    return dp[m]


def texts_similar(a: str, b: str, ratio: float = 0.10) -> bool:
    a1, b1 = normalize_cmp(a), normalize_cmp(b)
    if a1 == b1:
        return True
    if not a1 or not b1:
        return False
    # fade partials: one text is contained in the other
    short, long = (a1, b1) if len(a1) <= len(b1) else (b1, a1)
    if len(short) >= 10 and short in long:
        return True
    L = max(len(a1), len(b1))
    return edit_distance(a1, b1) <= max(2, int(round(L * ratio)))


def looks_like_no_subtitle(text: str, ignore_lines: List[str]) -> bool:
    t = (text or "").strip()
    if not t:
        return True
    tl = t.lower()
    for pat in _NO_SUB_REGEX:
        if re.search(pat, tl):
            return True
    nt = normalize_cmp(t)
    for line in ignore_lines or []:
        nl = normalize_cmp(line)
        if not nl:
            continue
        if texts_similar(t, line):
            return True
        if (len(nl) >= 18 or len(nl.split()) >= 3) and nl in nt:
            return True
    return False


def sanitize(text: str, ignore_lines: List[str]) -> str:
    if not text:
        return ""
    t = re.sub(r"^\s*(text|subtitle|subtitles|caption)\s*:\s*", "", text, flags=re.I).strip()
    if not t or looks_like_no_subtitle(t, ignore_lines):
        return ""
    if not re.search(r"[A-Za-zÀ-ÿ0-9]", t):
        return ""
    return t


# Words "bound" to what follows: breaking the line AFTER one of these is ugly
# (e.g. "intenzione di / mangiare", "I don't have the / slightest idea").
# Penalized when choosing the break point. Lists for the languages actually
# used (it/en); for the OTHER languages only the universal rules are used
# (balancing + punctuation), which remain effective everywhere.
_FUNC_WORDS_IT = frozenset({
    "di", "a", "da", "in", "con", "su", "per", "tra", "fra", "e", "o", "ma",
    "che", "non", "il", "lo", "la", "i", "gli", "le", "un", "uno", "una",
    "del", "dello", "della", "dei", "degli", "delle", "al", "allo", "alla",
    "ai", "agli", "alle", "nel", "nello", "nella", "nei", "negli", "nelle",
    "sul", "sullo", "sulla", "sui", "sugli", "sulle",
    "è", "ho", "ha", "hai", "sono", "sei", "era", "se", "mi", "ti", "si",
    "ci", "vi", "ne", "più", "cui",
})
_FUNC_WORDS_EN = frozenset({
    "a", "an", "the", "of", "to", "in", "on", "at", "by", "for", "with",
    "from", "into", "onto", "and", "or", "but", "nor", "so", "that", "if",
    "as", "than", "is", "are", "was", "were", "be", "been", "being",
    "has", "have", "had", "not", "no", "do", "does", "did",
    "will", "would", "can", "could", "shall", "should", "may", "might",
    "must", "my", "your", "his", "her", "its", "our", "their", "this",
    "these", "those", "some", "any", "very", "don't", "won't", "can't",
    "i'm", "i'll", "he's", "she's", "it's", "we're", "they're", "you're",
})


def _func_words(lang_hint: str) -> frozenset:
    code = resolve_langs(lang_hint)[0].lower()
    if code.startswith("it"):
        return _FUNC_WORDS_IT
    if code.startswith("en"):
        return _FUNC_WORDS_EN
    return frozenset()      # other languages: balancing + punctuation only


def _break_cost(words: List[str], i: int, left: str, func_words: frozenset) -> int:
    """Quality of a break AFTER word i-1 (lower = better)."""
    cost = 0
    if left[-1] in ",;:!?…—":
        cost -= 10                       # natural pause: excellent break point
    if words[i - 1].lower().strip("'\",.;:!?…") in func_words:
        cost += 14                       # don't detach articles/prepositions from what follows
    return cost


def smart_wrap(s: str, width: int, lang_hint: str = "Italian") -> str:
    """
    BALANCED line wrapping (professional subtitling style):
    - <= width: a single line;
    - otherwise 2 lines (then 3) of lengths as SIMILAR as possible,
      breaking only at spaces, preferring punctuation and avoiding
      leaving articles/prepositions at the end of a line (it/en; other
      languages: universal rules only);
    - never break words; greedy fallback for extreme cases.
    """
    s = s.strip()
    if "\n" in s or len(s) <= width or " " not in s:
        return s
    words = s.split()
    fw = _func_words(lang_hint)

    # --- 2 balanced lines
    best2, c2 = None, None
    for i in range(1, len(words)):
        left, right = " ".join(words[:i]), " ".join(words[i:])
        if len(left) > width or len(right) > width:
            continue
        c = abs(len(left) - len(right)) + _break_cost(words, i, left, fw)
        if c2 is None or c < c2:
            c2, best2 = c, (left, right)

    # 2 "good" lines (clean, balanced break) always win
    if best2 and c2 < 14:
        return best2[0] + "\n" + best2[1]

    # --- 3 balanced lines (also as a remedy for an ugly 2-line split,
    #     e.g. when the only possible break falls after an article)
    n = len(words)
    best3, c3 = None, None
    for i in range(1, n - 1):
        l1 = " ".join(words[:i])
        if len(l1) > width:
            break
        for j in range(i + 1, n):
            l2 = " ".join(words[i:j])
            if len(l2) > width:
                break
            l3 = " ".join(words[j:])
            if len(l3) > width:
                continue
            c = (abs(len(l1) - len(l2)) + abs(len(l2) - len(l3)) +
                 _break_cost(words, i, l1, fw) + _break_cost(words, j, l2, fw))
            if c3 is None or c < c3:
                c3, best3 = c, (l1, l2, l3)

    # still prefer 2 lines, unless 3 lines are better
    # (+8 = "cost" of the extra line; ties go to the 3 lines, because
    # here the 2-line split necessarily has an ugly break: c2 >= 14)
    if best2 and (best3 is None or c3 + 8 > c2):
        return best2[0] + "\n" + best2[1]
    if best3:
        return "\n".join(best3)

    # --- greedy fallback (extreme texts): full lines, never broken words
    lines, cur = [], ""
    for w in words:
        cand = (cur + " " + w).strip()
        if len(cand) <= width or not cur:
            cur = cand
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return "\n".join(lines)


def apply_corrections(text: str, corrections: List[Tuple[str, str]]) -> str:
    """'wrong => right' replacements (case-insensitive, longest first)."""
    if not text or not corrections:
        return text
    for wrong, right in corrections:
        text = re.sub(re.escape(wrong), right, text, flags=re.IGNORECASE)
    return text


def postprocess(text: str, wrap: int, ignore_lines: List[str],
                corrections: Optional[List[Tuple[str, str]]] = None,
                lang_hint: str = "Italian") -> str:
    if not text:
        return ""
    text = apply_corrections(text, corrections or [])
    out = text.replace("```", "").replace("\r", "\n").strip()
    lines = [re.sub(r"\s{2,}", " ", ln).strip() for ln in out.split("\n")]
    out = "\n".join(ln for ln in lines if ln)
    if "\n" not in out and len(out) > wrap:
        out = smart_wrap(out, wrap, lang_hint)
    if looks_like_no_subtitle(out, ignore_lines):
        return ""
    return out


# ---------------------------------------------------------------- SRT
def fmt_hms(sec: float) -> str:
    sec = max(0, int(round(sec)))
    h, r = divmod(sec, 3600)
    m, s = divmod(r, 60)
    return f"{h:d}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"


def srt_ts(sec: float) -> str:
    # computed in total milliseconds: avoids the ms=1000 bug with ~.9995+ fractions
    total_ms = max(0, int(round(sec * 1000)))
    ms = total_ms % 1000
    s = (total_ms // 1000) % 60
    m = (total_ms // 60000) % 60
    h = total_ms // 3600000
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def write_srt(segments: List[Tuple[float, float, str]], out_path: str) -> None:
    with open(out_path, "w", encoding="utf-8") as f:
        i = 0
        for s, e, t in segments:
            if not t:
                continue
            i += 1
            f.write(f"{i}\n{srt_ts(s)} --> {srt_ts(e)}\n{t}\n\n")


def parse_srt(path: Path) -> List[Tuple[float, float, str]]:
    content = path.read_text(encoding="utf-8")
    blocks = re.split(r"\n\s*\n", content.strip())
    out = []
    for b in blocks:
        m = re.search(r"(\d+)\s*\n(\d{2}:\d{2}:\d{2},\d{3})\s*-->\s*"
                      r"(\d{2}:\d{2}:\d{2},\d{3})\s*\n(.*)", b, flags=re.S)
        if not m:
            continue

        def to_sec(ts):
            hh, mm, rest = ts.split(":")
            ss, ms = rest.split(",")
            return int(hh) * 3600 + int(mm) * 60 + int(ss) + int(ms) / 1000.0
        out.append((to_sec(m.group(2)), to_sec(m.group(3)), m.group(4).strip()))
    return sorted(out, key=lambda x: x[0])


def merge_segments(segs: List[Tuple[float, float, str]], merge_gap: float,
                   min_duration: float, ignore_lines: List[str],
                   wrap: int, lang_hint: str = "Italian") -> List[Tuple[float, float, str]]:
    """Tuple-based version used by the Sub fix tab (cleanup of existing SRTs)."""
    if not segs:
        return []
    out: List[Tuple[float, float, str]] = []
    cs, ce, ct = segs[0]
    for s, e, t in segs[1:]:
        if ct and t and texts_similar(ct, t) and s - ce <= merge_gap:
            ce = e
            if len(t) > len(ct):
                ct = t
        else:
            if ct and (ce - cs) >= min_duration:
                out.append((cs, ce, postprocess(ct, wrap, ignore_lines,
                                                lang_hint=lang_hint)))
            cs, ce, ct = s, e, t
    if ct and (ce - cs) >= min_duration:
        out.append((cs, ce, postprocess(ct, wrap, ignore_lines, lang_hint=lang_hint)))
    return [(s, e, t) for (s, e, t) in out if t]


# ---------------------------------------------------------------- pipeline
def select_ocr_targets(frames: List[Path], skip_hamming: int,
                       progress_cb: Optional[_StepCallback] = None,
                       stop: Optional[threading.Event] = None,
                       ) -> List[int]:
    """
    Frames to OCR: frame 0 and every frame that differs from the PREVIOUS
    one (dhash) by more than skip_hamming. The others inherit the text
    (forward-fill). progress_cb(ratio, frames_analyzed, frames).
    STOP POINT: checked every 50 frames (dhash of 17k frames takes a while).
    """
    n = len(frames)
    targets: List[int] = []
    prev = None
    for i, fp in enumerate(frames):
        if i % 50 == 0:
            _check_stop(stop)
        try:
            h = dhash(fp)
        except Exception:
            h = None
        if i == 0 or prev is None or h is None or hamming(h, prev) > skip_hamming:
            targets.append(i)
        prev = h
        if progress_cb and (i % 300 == 0):
            progress_cb(i / max(n, 1), i, n)
    return targets


def segments_from_frames(per_text: List[str], per_conf: List[float],
                         per_alts: List[List[str]], dt: float
                         ) -> List[SegInfo]:
    """
    Segments from the per-frame text, with segment voting:
    - empty frame   -> closes the segment;
    - similar text  -> extends and ACCUMULATES the vote (weight = confidence);
    - different text -> closes and opens a new segment.
    The final text is the group with the highest weight among the segment frames.
    """
    segs: List[SegInfo] = []
    cs: Optional[int] = None
    groups: Dict[str, dict] = {}
    rep = ""            # current representative for the similarity comparison
    alts_seen: Dict[str, int] = {}

    def close(end_idx: int):
        nonlocal cs, groups, rep, alts_seen
        if cs is None or not groups:
            cs, groups, rep, alts_seen = None, {}, "", {}
            return
        key, g = max(groups.items(), key=lambda kv: kv[1]["w"])
        total = sum(gg["w"] for gg in groups.values())
        raw = max(g["raw"].items(), key=lambda kv: (kv[1], len(kv[0])))[0]
        conf = sum(g["confs"]) / len(g["confs"])
        agree = g["w"] / total if total > 0 else 1.0
        others = [max(gg["raw"], key=gg["raw"].get) for k, gg in groups.items() if k != key]
        others += [a for a in alts_seen if normalize_cmp(a) != key]
        segs.append(SegInfo(start=cs * dt, end=end_idx * dt, text=raw,
                            conf=conf, agree=agree, nframes=end_idx - cs,
                            alts=sorted(set(others))[:4]))
        cs, groups, rep, alts_seen = None, {}, "", {}

    def add_vote(tx: str, cf: float, al: List[str]):
        nonlocal rep
        key = normalize_cmp(tx)
        g = groups.setdefault(key, {"w": 0.0, "raw": {}, "confs": []})
        g["w"] += max(cf, 0.05)
        g["raw"][tx] = g["raw"].get(tx, 0) + 1
        g["confs"].append(cf)
        for a in al:
            alts_seen[a] = alts_seen.get(a, 0) + 1
        # the representative is the raw text of the currently heaviest group
        bk, bg = max(groups.items(), key=lambda kv: kv[1]["w"])
        rep = max(bg["raw"].items(), key=lambda kv: (kv[1], len(kv[0])))[0]

    for i, tx in enumerate(per_text):
        if not tx:
            close(i)
            continue
        if cs is None:
            cs = i
            add_vote(tx, per_conf[i], per_alts[i])
        elif texts_similar(tx, rep):
            add_vote(tx, per_conf[i], per_alts[i])
        else:
            close(i)
            cs = i
            add_vote(tx, per_conf[i], per_alts[i])
    close(len(per_text))
    return segs


def merge_seginfos(segs: List[SegInfo], merge_gap: float) -> List[SegInfo]:
    """
    Merges adjacent segments with similar text (SLIGHTLY wider threshold:
    this is where fade pieces with some typos get recomposed). The text of
    the segment with more frames wins (more stable).
    """
    if not segs:
        return []
    out: List[SegInfo] = [segs[0]]
    for s in segs[1:]:
        prev = out[-1]
        if (s.start - prev.end) <= merge_gap and texts_similar(prev.text, s.text, ratio=0.18):
            keep, other = (prev, s) if prev.nframes >= s.nframes else (s, prev)
            merged = SegInfo(
                start=prev.start, end=s.end, text=keep.text,
                conf=(prev.conf * prev.nframes + s.conf * s.nframes) /
                     max(1, prev.nframes + s.nframes),
                agree=min(prev.agree, s.agree),
                nframes=prev.nframes + s.nframes, top=prev.top,
                alts=sorted(set(prev.alts + s.alts + [other.text]) - {keep.text})[:4],
                flags=sorted(set(prev.flags + s.flags + [FLAG_MERGED_FADE])),
            )
            out[-1] = merged
        else:
            out.append(s)
    return out


def refine_segment_bounds(video: str, segs: List[SegInfo], dt: float,
                          native_fps: float, crop_expr: str, langs: List[str],
                          p: OcrParams, tmp_root: Path,
                          progress_cb: Optional[_StepCallback] = None,
                          stop: Optional[threading.Event] = None,
                          ) -> int:
    """
    Refines the start/end of every segment at the NATIVE frame rate: extracts
    a ±dt window around the boundary and looks for the first/last frame in
    which the segment text is visible. Precision ~1 native frame (~±20ms).
    Returns the number of boundaries moved. progress_cb(ratio, done, segments).
    STOP POINT: before every row, inside every ffmpeg window (polled) and
    before every OCR of the window.
    """
    moved = 0
    ndt = 1.0 / max(native_fps, 1.0)

    def window_texts(t0: float, t1: float) -> List[Tuple[float, str]]:
        d = Path(tempfile.mkdtemp(prefix="ref_", dir=str(tmp_root)))
        try:
            cmd = [FFMPEG, "-hide_banner", "-nostats", "-y",
                   "-ss", f"{max(0.0, t0):.4f}", "-i", video,
                   "-t", f"{max(0.05, t1 - t0):.4f}",
                   "-vf", crop_expr, "-fps_mode", "passthrough",
                   "-q:v", "2", str(d / "w_%05d.jpg")]
            _run_ffmpeg(cmd, stop=stop, poll=0.05)
            out = []
            for k, fp in enumerate(sorted(d.glob("w_*.jpg"))):
                _check_stop(stop)
                im = Image.open(fp).convert("RGB")
                # for mere presence/absence the raw variant is enough
                txt, _ = ocr_conf(im, langs, p.recognition_level, p.min_confidence)
                out.append((max(0.0, t0) + k * ndt, txt))
            return out
        except Stopped:
            raise          # the generic except below must not swallow it
        except Exception:
            return []
        finally:
            shutil.rmtree(d, ignore_errors=True)

    for n, seg in enumerate(segs):
        _check_stop(stop)
        # START boundary: first native frame with similar text
        win = window_texts(seg.start - dt, seg.start + dt)
        for t, txt in win:
            if txt and texts_similar(txt, seg.text, ratio=0.25):
                if abs(t - seg.start) > ndt / 2:
                    moved += 1
                seg.start = t
                break
        # END boundary: last native frame with similar text
        win = window_texts(seg.end - dt, seg.end + dt)
        last = None
        for t, txt in win:
            if txt and texts_similar(txt, seg.text, ratio=0.25):
                last = t
        if last is not None:
            new_end = last + ndt
            if abs(new_end - seg.end) > ndt / 2:
                moved += 1
            seg.end = new_end
        if progress_cb:
            progress_cb((n + 1) / max(1, len(segs)), n + 1, len(segs))

    # remove small overlaps introduced by the refinement
    segs.sort(key=lambda s: s.start)
    for a, b in zip(segs, segs[1:]):
        if b.start < a.end:
            mid = (b.start + a.end) / 2
            a.end, b.start = mid, mid
    return moved


# ---------------------------------------------------------------- QC report
def _esc(s: str) -> str:
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
             .replace("\n", "<br>"))


# Review-editor template. NOT an f-string: dynamic values enter via
# .replace() on __TOKEN__ tokens (the JS/CSS is full of braces).
# The visible strings (it/en) live in _QC_I18N. BOTH languages travel in
# the report (the "qci18n" JSON block): the __T_*__ tokens of the markup
# only prefill it in the ui_lang of write_qc_html (what shows before the
# script runs); the script then picks the language (window.__subvisionLang
# set by the app, else the browser language) and fills every text from
# the JSON (data-i18n* attributes, T object, flag codes of the rows).
# window.__subvisionSetLang(lang) switches it in place, without a reload.
# Two layouts (C3, report v2): inside the app (the "subvision" message
# handler is there) the page starts with the summary box, the app draws
# the title band above it; in a browser a plain page title comes first.
# In both the header of the summary box (the report bar) sticks to the top
# when the page scrolls, and the legend stays fixed at the bottom.
# <meta name="subvision-report" content="N"> says which template wrote the
# page (REPORT_VERSION): the app upgrades a report without it, or with an
# older N, to the current template (report_upgrade.py) before showing it.
REPORT_VERSION = 2
_QC_TEMPLATE = r"""<!DOCTYPE html>
<html lang="__LANG__"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="subvision-report" content="__REPORT_VERSION__">
<title>__T_TITLE__ __VIDEO__</title>
<script id="appmode">
 // In the SubVision app the title band is native: hide the page title
 // before the first paint (the message handler exists from document start).
 if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.subvision)
   document.documentElement.classList.add('app');
</script>
<style>
 /* Two palettes, dark and light, chosen by the system appearance (the
    app's WKWebView follows the app's theme): the tokens of the native app
    (C3 boards R1/R2), cyan accent in the dark, blue in the light. */
 :root{color-scheme:light dark;
   --bg:#101113; --surface:#16181B; --raised:#1C1F23; --inset:rgba(0,0,0,.25);
   --glass:rgba(255,255,255,.07); --glass-hover:rgba(255,255,255,.11); --glass-line:rgba(255,255,255,.10);
   --line:#26292E; --fg:#E8EAED; --fg2:#9BA1A9; --fg3:#80868E;
   --accent:#2AC9DE; --accent-hover:#4FD5E7; --on-accent:#06252A; --accent-text:#2AC9DE;
   --accent-soft:rgba(42,201,222,.07); --accent-line:rgba(42,201,222,.28);
   --ok:#7FE3AC; --warn-fg:#F5CB78; --warn-bg:#2A2110; --warn-line:rgba(242,184,75,.45);
   --bad-fg:#F59B9B; --bad-bg:rgba(242,109,109,.08); --bad-dot:rgba(242,109,109,.16);
   --bad-line:rgba(242,109,109,.55); --mark-bg:#F2B84B; --mark-fg:#2A1C00}
 @media (prefers-color-scheme: light){
  :root{
   --bg:#F6F7F9; --surface:#FFFFFF; --raised:#EEF0F2; --inset:rgba(0,0,0,.04);
   --glass:rgba(0,0,0,.04); --glass-hover:rgba(0,0,0,.07); --glass-line:rgba(0,0,0,.12);
   --line:#E1E4E8; --fg:#16181B; --fg2:#5C626A; --fg3:#656B73;
   --accent:#0275B6; --accent-hover:#067CC1; --on-accent:#FFFFFF; --accent-text:#206CA1;
   --accent-soft:rgba(39,147,219,.07); --accent-line:rgba(39,147,219,.28);
   --ok:#146C3E; --warn-fg:#7F5300; --warn-bg:#FFF0C4; --warn-line:rgba(245,180,0,.45);
   --bad-fg:#B42323; --bad-bg:rgba(205,55,37,.06); --bad-dot:#FDECEA;
   --bad-line:rgba(217,64,46,.45); --mark-bg:#F2B84B; --mark-fg:#2A1C00}
 }
 *{box-sizing:border-box}
 /* the sticky bar and the fixed legend must not hide a focused field */
 html{scroll-padding-top:64px;scroll-padding-bottom:48px}
 body{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;font-size:13px;
      line-height:1.5;margin:0;background:var(--bg);color:var(--fg);-webkit-font-smoothing:antialiased;
      overflow-x:hidden}
 .mono{font-family:ui-monospace,"SF Mono",Menlo,monospace;font-variant-numeric:tabular-nums}
 .wrap{max-width:1236px;margin:0 auto;padding:16px 28px 72px}
 .ptitle{margin:8px 0 18px;font-size:24px;font-weight:400;letter-spacing:-.01em;line-height:1.25;
         overflow-wrap:anywhere}
 .ptitle b{font-weight:700}
 html.app .ptitle{display:none}
 button{font-family:inherit;cursor:pointer}
 input[type=checkbox]{accent-color:var(--accent);width:14px;height:14px;margin:0;cursor:pointer;flex:none}
 svg.ic{width:12px;height:12px;flex:none;fill:none;stroke:currentColor;stroke-width:1.4;
        stroke-linecap:round;stroke-linejoin:round}
 .btn{display:inline-flex;align-items:center;justify-content:center;gap:5px;border-radius:999px;
      white-space:nowrap;height:24px;padding:0 12px;font-size:12px;font-weight:500;flex:none;
      border:1px solid var(--glass-line);background:var(--glass);color:var(--fg)}
 .btn:hover{background:var(--glass-hover)}
 .btn.pri{background:var(--accent);border-color:var(--accent);color:var(--on-accent);font-weight:600}
 .btn.pri:hover{background:var(--accent-hover);border-color:var(--accent-hover)}
 /* the report bar: header of the summary box, sticky at the top */
 .rhead{position:sticky;top:0;z-index:5}
 .rhead::before{content:"";position:absolute;left:-28px;right:-28px;top:0;bottom:-10px;
                background:var(--bg);z-index:-1;display:none}
 .rhead.stuck::before{display:block}
 .rbar{display:flex;align-items:center;gap:10px;min-height:44px;padding:6px 12px 6px 14px;
       background:var(--raised);border:1px solid var(--line);border-radius:10px 10px 0 0;font-size:12.5px}
 .rhead.stuck .rbar{border-top-color:transparent;border-radius:0 0 10px 10px}
 .rbar .left{display:flex;align-items:center;gap:12px;flex:1 1 auto;min-width:0}
 #counter{white-space:nowrap}
 .rhead.flash #counter{display:none}
 .savedmsg{display:none;align-items:center;gap:6px;color:var(--ok);white-space:nowrap;overflow:hidden;
           text-overflow:ellipsis;min-width:0}
 .rhead.flash .savedmsg{display:inline-flex}
 .savedmsg.err{color:var(--bad-fg)}
 .savedmsg .mono{font-size:12px;overflow:hidden;text-overflow:ellipsis}
 label.opt{display:flex;align-items:center;gap:6px;color:var(--fg2);white-space:nowrap;cursor:pointer}
 .rsum{background:var(--surface);border:1px solid var(--line);border-top:0;border-radius:0 0 10px 10px;
       padding:10px 14px;font-size:12.5px;line-height:1.65}
 .hint{color:var(--fg2);font-size:12px;margin-top:3px}
 h2{display:flex;align-items:center;flex-wrap:wrap;gap:6px 10px;font-size:14px;font-weight:700;
    margin:22px 0 0;padding-bottom:6px;border-bottom:1px solid var(--line)}
 h2 .sub{font-size:12px;font-weight:400;color:var(--fg2)}
 /* one line of the SRT */
 .row{display:grid;grid-template-columns:16px 22px 104px 220px minmax(0,1fr) 92px;gap:12px;
      padding:10px;border-bottom:1px solid var(--line);align-items:start}
 .row.warn{background:var(--warn-bg)} .row.bad{background:var(--bad-bg)}
 .row.added{background:var(--accent-soft)}
 .row.excluded > :not(.cInc){opacity:.5}
 .cInc{padding-top:4px}
 .n{color:var(--fg3);padding-top:3px;font-size:12px}
 .tin{display:block;width:104px;height:22px;font-size:11.5px;color:var(--accent-text);
      border:1px solid var(--glass-line);border-radius:5px;padding:0 6px;background:var(--inset);outline:none}
 .tin + .tin{margin-top:4px}
 .tin:focus{border-color:var(--accent)}
 .tin.bad{border-color:var(--bad-line);color:var(--bad-fg);background:var(--bad-bg)}
 .tin::placeholder{color:var(--fg3);opacity:.6}
 .rdur{font-size:11px;color:var(--fg3);margin-top:3px;padding-left:2px}
 .rdur.bad{color:var(--bad-fg)}
 .thumb{width:220px;height:auto;max-height:80px;object-fit:contain;border-radius:5px;display:block;background:#000}
 .thumb.none{height:40px;display:grid;place-items:center;border:1px dashed var(--glass-line);
             background:transparent;color:var(--fg3);font-size:11px}
 textarea{width:100%;display:block;background:var(--surface);border:1px solid var(--glass-line);border-radius:6px;
          color:var(--fg);font-family:inherit;font-size:13.5px;line-height:1.45;padding:4px 9px;
          resize:none;overflow:hidden;min-height:30px;outline:none}
 textarea:focus{border-color:var(--accent)}
 textarea.edited{border-color:var(--accent);box-shadow:0 0 0 1px var(--accent-line)}
 .alts{display:flex;flex-wrap:wrap;gap:5px;margin-top:6px}
 .altc{font-size:12px;border:1px solid var(--glass-line);background:var(--glass);border-radius:6px;
       padding:1px 7px;line-height:18px;color:var(--fg);cursor:pointer}
 .altc:hover{background:var(--glass-hover)}
 .altc.cur{border-color:var(--accent)}
 .hl{background:var(--mark-bg);color:var(--mark-fg);border-radius:3px;padding:0 2px}
 .subl{display:flex;align-items:center;flex-wrap:wrap;gap:6px 14px;margin-top:6px;font-size:12px;color:var(--fg2)}
 .subl label{display:flex;align-items:center;gap:6px;cursor:pointer}
 .link{display:inline-flex;align-items:center;gap:4px;background:none;border:0;padding:0;
       color:var(--accent-text);font-size:12px}
 .link:disabled{color:var(--fg3);opacity:.7;cursor:default}
 .flag{font-family:ui-monospace,"SF Mono",Menlo,monospace;font-size:10.5px;color:var(--fg3);
       border:1px solid var(--glass-line);border-radius:999px;padding:0 7px;line-height:16px}
 .cf{text-align:right;line-height:1.3;white-space:nowrap}
 .cf b{font-size:13px;font-weight:600}
 .cf .ag{display:block;font-size:11px;color:var(--fg3);margin-top:2px}
 .cf.c-ok b{color:var(--ok)} .cf.c-warn b{color:var(--warn-fg)} .cf.c-bad b{color:var(--bad-fg)}
 .cf.c-added b{color:var(--fg3)}
 /* a long stretch without subtitles */
 .gaprow{display:grid;grid-template-columns:200px 220px minmax(0,1fr);gap:16px;align-items:center;
         padding:10px;border-bottom:1px solid var(--line);font-size:12.5px}
 .gaprow .gt{font-size:12px}
 .gaprow .gd{font-size:12px;color:var(--fg2)}
 .gapact{display:flex;align-items:center;gap:10px}
 .gapact .hint{margin:0}
 .gapact .sp{flex:1}
 .empty{color:var(--fg2);font-size:12px;padding:10px}
 .foot{margin-top:40px;color:var(--fg3);font-size:11.5px;text-align:center}
 .foot a{color:var(--accent-text);text-decoration:none} .foot a:hover{text-decoration:underline}
 /* thin legend, fixed at the bottom */
 .legend{position:fixed;left:0;right:0;bottom:0;height:34px;border-top:1px solid var(--line);
         background:var(--raised);display:flex;align-items:center;gap:18px;padding:0 28px;
         font-size:11.5px;color:var(--fg2);z-index:6;white-space:nowrap;overflow:hidden}
 .legend .lg{display:inline-flex;align-items:center;gap:6px}
 .legend b{color:var(--fg)}
 .sw{display:inline-block;width:12px;height:12px;border-radius:3px;flex:none}
 .sw.warn{background:var(--warn-bg);border:1px solid var(--warn-line)}
 .sw.bad{background:var(--bad-dot);border:1px solid var(--bad-line)}
 .sw.added{background:var(--accent-soft);border:1px solid var(--accent-line)}
 @media (max-width:1000px){
  .row{grid-template-columns:16px 22px 104px 140px minmax(0,1fr) 72px}
  .thumb{width:140px}
  .gaprow{grid-template-columns:180px 140px minmax(0,1fr)}
 }
</style></head><body>
<div class="wrap">
<h1 class="ptitle"><span data-i18n="TITLE">__T_TITLE__</span> <b>__VIDEO__</b></h1>
<div id="rsentinel" style="height:1px;margin-bottom:-1px"></div>
<div class="rhead" id="rhead">
 <div class="rbar">
  <div class="left">
   <span id="counter"></span>
   <span class="savedmsg" id="savedNote" role="status"></span>
   <label class="opt" title="__T_MERGE_TIP__" data-i18n-title="MERGE_TIP">
    <input type="checkbox" id="mergeOnSave" checked> <span data-i18n="MERGE_LABEL">__T_MERGE_LABEL__</span></label>
  </div>
  <button type="button" class="btn" onclick="resetAll()" title="__T_RESET_TIP__" data-i18n-title="RESET_TIP"><svg class="ic" viewBox="0 0 16 16" aria-hidden="true"><path d="M3 8a5 5 0 1 0 1.5-3.6"/><path d="M3 2.5v3h3"/></svg><span data-i18n="RESET">__T_RESET__</span></button>
  <button type="button" class="btn pri" onclick="exportSrt()" data-i18n="SAVE">__T_SAVE__</button>
 </div>
</div>
<div class="rsum"><div id="summary">__SUMMARY__</div>
 <div class="hint" id="hint">__T_HINT__</div>
</div>
<h2><span data-i18n="ROWS_H">__T_ROWS_H__</span> <button type="button" class="btn" onclick="addRow(null)" data-i18n="ADDROW">__T_ADDROW__</button></h2>
<div id="rows"></div>
<h2><span data-i18n="DROPPED_H">__T_DROPPED_H__</span> <span class="sub" data-i18n="DROPPED_SUB">__T_DROPPED_SUB__</span></h2>
<div id="dropped"></div>
<h2><span id="gapsTitle"></span> <span class="sub" data-i18n="GAPS_SUB">__T_GAPS_SUB__</span></h2>
<div id="gaps"></div>
<div class="foot" id="foot">__FOOTER__</div>
</div>
<div class="legend" role="note">
 <span class="lg"><i class="sw warn"></i><span data-i18n="LEG_WARN">__T_LEG_WARN__</span></span>
 <span class="lg"><i class="sw bad"></i><span data-i18n="LEG_BAD">__T_LEG_BAD__</span></span>
 <span class="lg"><i class="sw added"></i><span data-i18n="LEG_ADDED">__T_LEG_ADDED__</span></span>
 <span class="lg"><span class="hl" data-i18n="LEG_WORD">__T_LEG_WORD__</span><span data-i18n="LEG_WORD_TXT">__T_LEG_WORD_TXT__</span></span>
 <span class="lg" data-i18n="LEG_CONF">__T_LEG_CONF__</span>
</div>
<script type="application/json" id="qcdata">__DATA__</script>
<script type="application/json" id="qci18n">__I18N__</script>
<script>
const DATA = JSON.parse(document.getElementById('qcdata').textContent);
// Both languages: {it|en: {html, js, flags, summary, footer}} (see _QC_I18N).
const I18N = JSON.parse(document.getElementById('qci18n').textContent);
// Language at open: window.__subvisionLang ('it' | 'en') when the app set
// it (WKUserScript at document start), otherwise the browser language.
function pickLang(){
  const forced = window.__subvisionLang;
  if (forced === 'it' || forced === 'en') return forced;
  let pref = '';
  try { pref = (navigator.languages && navigator.languages[0]) || navigator.language || ''; } catch(e) {}
  return String(pref).toLowerCase().startsWith('it') ? 'it' : 'en';
}
let LANG = pickLang();
let T = I18N[LANG].js;
// Flag codes of the rows (FLAG_* of the pipeline, plus ADDED_FLAG for the
// lines added by hand): translated when shown, so they follow the language.
const ADDED_FLAG = 'added';
function flagText(code){
  if (code === ADDED_FLAG) return T.addedFlag;
  return (I18N[LANG].flags || {})[code] || code;
}
const LSKEY = 'voc26_rev_' + DATA.srtName;
// Bridge to the SubVision app (WKWebView): the app registers the script
// message handler "subvision" and receives {type:"export", name, srt},
// {type:"state", json} and {type:"confirm", ...}. Absent in Safari/Chrome:
// everything below falls back to the browser (localStorage, save dialog
// or download, confirm()).
const BRIDGE = (window.webkit && window.webkit.messageHandlers &&
                window.webkit.messageHandlers.subvision) || null;
// Initial state: the app injects the saved editor state as
// window.__subvisionState (from <name>.review.json) and it takes
// precedence over localStorage; after "Reset all" the injected state is
// ignored once (sessionStorage marker), until the app re-injects the new one.
let saved = {};
let ignoreInjected = false;
try { ignoreInjected = sessionStorage.getItem(LSKEY + ':reset') === '1';
      if (ignoreInjected) sessionStorage.removeItem(LSKEY + ':reset'); } catch(e) {}
if (!ignoreInjected && window.__subvisionState && typeof window.__subvisionState === 'object') {
  saved = window.__subvisionState;
} else {
  try { saved = JSON.parse(localStorage.getItem(LSKEY) || '{}'); } catch(e) {}
}
let addCounter = 0;
let flashTimer = null;
// Every row on the page by id (OCR rows, dropped ones, rows added by hand).
const ROWS = {};
const ICONS = {
  reset: '<svg class="ic" viewBox="0 0 16 16" aria-hidden="true"><path d="M3 8a5 5 0 1 0 1.5-3.6"/><path d="M3 2.5v3h3"/></svg>',
  remove: '<svg class="ic" viewBox="0 0 16 16" aria-hidden="true"><path d="M4.5 4.5l7 7M11.5 4.5l-7 7"/></svg>',
  check: '<svg class="ic" viewBox="0 0 16 16" aria-hidden="true"><path d="M3.5 8.3l3 3 6-6.6"/></svg>',
};

function esc(s){
  return String(s).replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
}
// Numbers in the language of the page: "2,38 s" / "2.38 s", "98 %" / "98%".
function num(x, d){
  const s = x.toFixed(d);
  return T.decimal === ',' ? s.replace('.', ',') : s;
}
function pct(x){ return T.pct.replace('{n}', Math.round(x * 100)); }
function secs(x, d){ return T.secs.replace('{n}', num(x, d)); }
function gapWarnText(){
  const g = +DATA.gapWarn || 0;
  return num(g, Number.isInteger(g) ? 0 : 1);
}

// Static texts of the page in the current language (markup with data-i18n*,
// title, <html lang>, hint, summary, footer, title of the gaps).
// The in-app hint replaces the browser one when the bridge is present.
function applyStatic(){
  const L = I18N[LANG];
  document.documentElement.lang = LANG;
  document.title = L.html.TITLE + ' ' + DATA.videoName;
  document.querySelectorAll('[data-i18n]').forEach(el => { el.innerHTML = L.html[el.dataset.i18n]; });
  document.querySelectorAll('[data-i18n-title]').forEach(el => { el.title = L.html[el.dataset.i18nTitle]; });
  document.querySelectorAll('[data-i18n-js]').forEach(el => { el.innerHTML = T[el.dataset.i18nJs]; });
  document.getElementById('hint').innerHTML = BRIDGE ? T.hintApp : L.html.HINT;
  document.getElementById('summary').innerHTML = L.summary;
  document.getElementById('foot').innerHTML = L.footer;
  document.getElementById('gapsTitle').textContent = T.gapsTitle.replace('{n}', gapWarnText());
}
// Texts built by makeRow / the gaps: every row and gap keeps a refresher
// that rewrites its labels and tooltips only (inputs, ticks, edits, chosen
// alternatives and added rows are left as they are).
function refreshRows(){
  document.querySelectorAll('.row, .gaprow').forEach(el => { if (el._i18n) el._i18n(); });
}
// Called by the app (evaluateJavaScript) when its language changes while
// the report is open: everything visible switches in place, no reload.
window.__subvisionSetLang = function(lang){
  if (lang !== 'it' && lang !== 'en') return false;
  window.__subvisionLang = lang;
  if (lang !== LANG) {
    LANG = lang; T = I18N[LANG].js;
    applyStatic(); refreshRows(); updateCounter();
  }
  return true;
};

function persistState(){
  const json = JSON.stringify(saved);
  try { localStorage.setItem(LSKEY, json); } catch(e) {}
  if (BRIDGE) { try { BRIDGE.postMessage({type:'state', json: json}); } catch(e) {} }
}

function ts(sec){
  if (sec == null) return '';
  sec = Math.max(0, sec);
  const ms = Math.round(sec*1000);
  const h = Math.floor(ms/3600000), m = Math.floor(ms/60000)%60,
        s = Math.floor(ms/1000)%60, r = ms%1000;
  return String(h).padStart(2,'0')+':'+String(m).padStart(2,'0')+':'+
         String(s).padStart(2,'0')+','+String(r).padStart(3,'0');
}
function parseTs(t){
  const m = (t||'').trim().match(/^(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})$/);
  if(!m) return null;
  return (+m[1])*3600 + (+m[2])*60 + (+m[3]) + (+m[4].padEnd(3,'0'))/1000;
}
// ---- text similarity (mirror of the pipeline's Python logic)
function normCmp(s){
  return (s||'').toLowerCase().replace(/["“”‘’„«»‹›]/g,'')
         .replace(/[^\p{L}\p{N}]+/gu,' ').trim().replace(/\s+/g,' ');
}
function editDist(a,b){
  const n=a.length,m=b.length;
  if(!n||!m) return Math.max(n,m);
  let dp=Array.from({length:m+1},(_,j)=>j);
  for(let i=1;i<=n;i++){
    let prev=dp[0]; dp[0]=i;
    for(let j=1;j<=m;j++){
      const cur=dp[j];
      dp[j]=Math.min(dp[j]+1, dp[j-1]+1, prev+(a[i-1]===b[j-1]?0:1));
      prev=cur;
    }
  }
  return dp[m];
}
function similar(a,b,ratio){
  ratio = ratio || 0.18;
  a=normCmp(a); b=normCmp(b);
  if(a===b) return true;
  if(!a||!b) return false;
  const s=a.length<=b.length?a:b, l=a.length<=b.length?b:a;
  if(s.length>=10 && l.includes(s)) return true;
  const L=Math.max(a.length,b.length);
  return editDist(a,b) <= Math.max(2, Math.round(L*ratio));
}
// ---- word diff (LCS): returns the tokens of b, marking those that differ from a
function wordDiff(a,b){
  const A=(a||'').split(/\s+/).filter(Boolean), B=(b||'').split(/\s+/).filter(Boolean);
  const m=A.length,n=B.length;
  const dp=Array.from({length:m+1},()=>new Array(n+1).fill(0));
  for(let i=m-1;i>=0;i--)for(let j=n-1;j>=0;j--)
    dp[i][j]=(normCmp(A[i])===normCmp(B[j])&&normCmp(B[j]))?dp[i+1][j+1]+1:Math.max(dp[i+1][j],dp[i][j+1]);
  const out=[]; let i=0,j=0;
  while(i<m&&j<n){
    if(normCmp(A[i])===normCmp(B[j])&&normCmp(B[j])){out.push([B[j],false]);i++;j++;}
    else if(dp[i+1][j]>=dp[i][j+1]) i++;
    else {out.push([B[j],true]); j++;}
  }
  while(j<n){out.push([B[j],true]);j++;}
  return out;
}
function state(id){ return saved[id] || {}; }
function setState(id, patch){
  saved[id] = Object.assign({}, saved[id]||{}, patch);
  persistState();
  updateCounter();
}
// The current values of a row: the saved edits over what the OCR gave.
// start/end may be null (a line added with "+ Add line" starts without times).
function rowValues(r){
  const s = state(r.id);
  return {
    text: (s.text !== undefined) ? s.text : r.text,
    start: (s.start !== undefined) ? s.start : r.start,
    end: (s.end !== undefined) ? s.end : r.end,
    included: (s.included !== undefined) ? s.included : !r.dropped,
    top: (s.top !== undefined) ? s.top : !!r.top,
  };
}
function el(tag, cls){
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  return e;
}
function checkbox(){
  const c = document.createElement('input'); c.type = 'checkbox';
  return c;
}

// One line of the SRT (OCR, dropped or added by hand). Returns the element;
// the caller puts it in its place.
function makeRow(r){
  ROWS[r.id] = r;
  const v = rowValues(r);
  const div = el('div', 'row ' + (r.added ? 'added' : (r.cls || '')));
  if(!v.included) div.classList.add('excluded');
  div.dataset.id = r.id;

  const inc = el('div', 'cInc');
  const cb = checkbox(); cb.checked = v.included;
  cb.onchange = () => { setState(r.id, {included: cb.checked});
                        div.classList.toggle('excluded', !cb.checked); };
  inc.appendChild(cb); div.appendChild(inc);

  const numEl = el('div', 'n'); numEl.textContent = r.added ? '+' : String(r.n == null ? '' : r.n);
  div.appendChild(numEl);

  // start, end and the duration under them; invalid times in red
  const ct = el('div', 'cT');
  const ti1 = el('input', 'tin mono'), ti2 = el('input', 'tin mono');
  ti1.value = ts(v.start); ti2.value = ts(v.end);
  ti1.placeholder = ti2.placeholder = '00:00:00,000';
  ti1.spellcheck = ti2.spellcheck = false;
  const dur = el('div', 'rdur mono');
  const checkTimes = () => {
    const a = parseTs(ti1.value), b = parseTs(ti2.value);
    ti1.classList.toggle('bad', a == null);
    ti2.classList.toggle('bad', b == null || (a != null && b <= a));
    if (a != null && b != null) {
      dur.textContent = secs(b - a, 2);
      dur.classList.toggle('bad', b <= a);
    } else {
      const empty = !ti1.value.trim() && !ti2.value.trim();
      dur.textContent = empty ? T.noTimes : T.tsFormat;
      dur.classList.add('bad');
    }
  };
  checkTimes();
  ti1.oninput = checkTimes; ti2.oninput = checkTimes;
  ti1.onchange = () => { setState(r.id, {start: parseTs(ti1.value)}); checkTimes(); };
  ti2.onchange = () => { setState(r.id, {end: parseTs(ti2.value)}); checkTimes(); };
  ct.append(ti1, ti2, dur); div.appendChild(ct);

  // frame: the row's own, the mid-gap one for a row added from a gap, or none
  let thumb;
  if (r.thumb) {
    thumb = el('img', 'thumb'); thumb.src = 'data:image/jpeg;base64,' + r.thumb;
  } else {
    thumb = el('div', 'thumb none');
  }
  div.appendChild(thumb);

  const cx = el('div', 'cTx');
  const ta = document.createElement('textarea'); ta.value = v.text;
  // as tall as its text (lines and wraps); measured again once on the page
  const fit = () => {
    ta.rows = Math.max(1, ta.value.split('\n').length);
    if (ta.isConnected) { ta.style.height = 'auto'; ta.style.height = (ta.scrollHeight + 2) + 'px'; }
  };
  ta._fit = fit;
  fit();
  cx.appendChild(ta);

  // alternative readings, the words that differ from the OCR text highlighted
  const altChips = [];
  if ((r.alts||[]).length) {
    const alts = el('div', 'alts');
    r.alts.forEach(a => {
      const c = el('span', 'altc'); c.dataset.txt = a; altChips.push(c);
      wordDiff((r.text||'').replace(/\n/g,' '), a.replace(/\n/g,' ')).forEach(([w,d],k) => {
        if (k) c.appendChild(document.createTextNode(' '));
        const s = el('span', d ? 'hl' : '');
        s.textContent = w;
        c.appendChild(s);
      });
      c.onclick = () => { ta.value = c.dataset.txt; ta.dispatchEvent(new Event('input')); };
      alts.appendChild(c);
    });
    cx.appendChild(alts);
  }

  // "It's a sign (goes on top)", the flags, Original (or Remove for a row added by hand)
  const subl = el('div', 'subl');
  const lab = el('label');
  const cbTop = checkbox(); cbTop.checked = v.top;
  const labTxt = el('span');
  lab.append(cbTop, labTxt);
  subl.appendChild(lab);
  const act = el('button', 'link'); act.type = 'button';
  const flagEls = [];
  const addFlags = () => (r.flags||[]).forEach(f => {
    const t = el('span', 'flag'); subl.appendChild(t); flagEls.push([t, f]);
  });
  if (r.added) { addFlags(); subl.appendChild(act); }
  else { subl.appendChild(act); addFlags(); }
  cx.appendChild(subl);
  div.appendChild(cx);

  // the box with the text, the alternative in use and Original follow the edits
  const sync = () => {
    ta.classList.toggle('edited', !r.added && ta.value !== r.text);
    altChips.forEach(c => c.classList.toggle('cur', ta.value === c.dataset.txt));
    if (!r.added) act.disabled = (ta.value === r.text && cbTop.checked === !!r.top);
  };
  ta.oninput = () => { setState(r.id, {text: ta.value}); fit(); sync(); };
  cbTop.onchange = () => { setState(r.id, {top: cbTop.checked}); sync(); };
  if (r.added) {
    act.onclick = () => removeRow(r, div);
  } else {
    // back to the row as the OCR gave it: text and "It's a sign"
    act.onclick = () => {
      ta.value = r.text; cbTop.checked = !!r.top;
      setState(r.id, {text: r.text, top: !!r.top});
      fit(); sync();
    };
  }
  sync();

  const cc = el('div', 'cf c-' + (r.added ? 'added' : (r.cls || 'ok')));
  div.appendChild(cc);

  // language switch: labels and tooltips only (see refreshRows)
  div._i18n = () => {
    cb.title = T.includeTip; ti1.title = T.start; ti2.title = T.end; checkTimes();
    if (r.thumb) thumb.alt = T.rowThumbAlt.replace('{n}', r.added ? '+' : r.n);
    else thumb.textContent = T.noFrame;
    altChips.forEach(c => { c.title = T.altTip; });
    labTxt.textContent = T.sign; lab.title = T.signTip;
    flagEls.forEach(([t, f]) => { t.textContent = flagText(f); });
    act.innerHTML = r.added ? ICONS.remove + esc(T.remove) : ICONS.reset + esc(T.orig);
    act.title = r.added ? T.removeTip : T.origTip;
    cc.innerHTML = r.conf != null
      ? '<b>' + pct(r.conf) + '</b><span class="ag">' + esc(T.agree) + ' ' +
        pct(r.agree == null ? 1 : r.agree) + '</span>'
      : '<b>—</b>';
  };
  div._i18n();
  return div;
}

// "Remove" of a row added by hand: gone from the page and from the state.
function removeRow(r, div){
  delete saved[r.id];
  persistState();
  DATA.extraRows = DATA.extraRows.filter(x => x !== r);
  delete ROWS[r.id];
  div.remove();
  updateCounter();
}

function round3(x){ return Math.round(x * 1000) / 1000; }

// A row added by hand. From a gap: under the gap, with the mid-gap frame
// and times 0.5 s after the gap start, 2 s long. From "+ Add line": at the
// end of the rows, no frame, EMPTY times (red until filled). The row stays
// where it is while it is edited; the SRT is sorted by time on save, and on
// the next open the row shows among the others at its time.
function addRow(gap){
  addCounter++;
  const id = 'new' + Date.now() + '_' + addCounter;
  let start = null, end = null;
  const gi = gap ? DATA.gaps.indexOf(gap) : -1;
  if (gap) {
    start = round3(gap.start + Math.min(0.5, (gap.end - gap.start) / 4));
    end = round3(Math.min(gap.end, start + 2));
  }
  const r = {id:id, n:'+', start:start, end:end, text:'', alts:[], flags:[ADDED_FLAG],
             conf:null, added:true, dropped:false, thumb: gap ? gap.thumb : ''};
  DATA.extraRows.push(r);
  const st = {text:'', start:start, end:end, included:true, added:true, top:false};
  if (gi >= 0) st.gap = gi;
  setState(id, st);
  const div = makeRow(r);
  if (gap) {
    // under the gap, after the rows already added there
    let after = gap._el;
    while (after.nextElementSibling && after.nextElementSibling.classList.contains('added'))
      after = after.nextElementSibling;
    after.after(div);
  } else {
    document.getElementById('rows').appendChild(div);
  }
  updateCounter();
  const ta = div.querySelector('textarea');
  ta._fit(); ta.focus();
}

// A restored row added by hand goes before the first row that starts later
// (rows without times go at the end).
function placeByTime(container, div, start){
  if (start != null) {
    for (const other of container.children) {
      const o = ROWS[other.dataset.id];
      if (!o) continue;
      const os = rowValues(o).start;
      if (os != null && os > start) { container.insertBefore(div, other); return; }
    }
  }
  container.appendChild(div);
}

function updateCounter(){
  let inc=0, tot=0;
  document.querySelectorAll('.row').forEach(d => {
    tot++; if(!d.classList.contains('excluded')) inc++;
  });
  document.getElementById('counter').textContent =
    T.counter.replace('{inc}', inc).replace('{tot}', tot);
}

function collectRows(){
  const rows = [];
  const all = DATA.rows.concat(DATA.extraRows);
  for(const r of all){
    const v = rowValues(r);
    if(!v.included) continue;
    const text = (v.text||'').trim();
    if(!text) continue;
    if(v.start==null || v.end==null || v.end<=v.start){
      alert(T.badTimes + ' "'+text.slice(0,40)+'"'); return null;
    }
    rows.push({start:v.start, end:v.end, text:text, top:v.top,
               edited: text !== (r.text||'')});
  }
  rows.sort((a,b)=>a.start-b.start);
  return rows;
}

// merges adjacent rows (same band) with equal/similar text:
// the text edited by hand wins; otherwise the one of the longer row.
function mergeRows(rows, gap){
  gap = gap==null ? 0.6 : gap;
  const out=[]; let merged=0;
  for(const r of rows){
    const p=out[out.length-1];
    if(p && p.top===r.top && (r.start-p.end)<=gap && similar(p.text, r.text)){
      const keep = (r.edited && !p.edited) ? r.text
                 : (p.edited && !r.edited) ? p.text
                 : ((r.end-r.start) > (p.end-p.start) ? r.text : p.text);
      p.text=keep; p.end=Math.max(p.end, r.end); p.edited=p.edited||r.edited;
      merged++;
    } else out.push(Object.assign({}, r));
  }
  return [out, merged];
}

// The SRT, sorted by time and numbered again; a sign gets its position
// tag in the file only (never shown on the page).
function buildSrt(){
  let rows = collectRows();
  if(!rows) return null;
  window._lastMergeInfo = 0;
  if(document.getElementById('mergeOnSave')?.checked){
    const [m, count] = mergeRows(rows);
    rows = m; window._lastMergeInfo = count;
  }
  let out='', i=0;
  for(const r of rows){
    i++;
    const body = (r.top && !r.text.startsWith('{\\an8}')) ? '{\\an8}'+r.text : r.text;
    out += i+'\n'+ts(r.start)+' --> '+ts(r.end)+'\n'+body+'\n\n';
  }
  return out;
}
function stamp(){
  const d = new Date();
  const p = n => String(n).padStart(2,'0');
  return d.getFullYear()+p(d.getMonth()+1)+p(d.getDate())+'-'+p(d.getHours())+p(d.getMinutes());
}
// The outcome of a save, in the report bar in place of the counter for a
// few seconds (green; red for an error). `tip`: the full path and the
// merge note, as the tooltip of the message.
function flash(html, tip, bad){
  const head = document.getElementById('rhead'), n = document.getElementById('savedNote');
  n.innerHTML = (bad ? '' : ICONS.check) + html;
  n.title = tip || '';
  n.classList.toggle('err', !!bad);
  head.classList.add('flash');
  clearTimeout(flashTimer);
  flashTimer = setTimeout(() => { head.classList.remove('flash'); n.title = ''; }, 6000);
}
function savedHtml(key, name){
  return esc(T[key]).replace('{name}', '<span class="mono">' + esc(name) + '</span>');
}
async function exportSrt(){
  const out = buildSrt();
  if(out == null) return;
  const fname = DATA.srtName.replace(/\.srt$/i,'') + '-reviewed-' + stamp() + '.srt';
  const mi = window._lastMergeInfo || 0;
  const mergeNote = mi > 0 ? ' · ' + mi + ' ' + T.mergedDupes : '';
  // 1) SubVision app (WKWebView): the app writes the file next to the original.
  //    With WKScriptMessageHandlerWithReply postMessage returns a promise
  //    ({ok, path, name, bytes}); with the plain handler it returns undefined.
  if (BRIDGE) {
    try {
      const r = await Promise.resolve(BRIDGE.postMessage({type:'export', name: fname, srt: out}));
      // the file name in the bar, the full path (and the merge note) in the tooltip
      flash(savedHtml('savedAs', (r && r.name) || fname), ((r && r.path) || fname) + mergeNote);
    } catch(e) {
      // the app's reply is the reason in words: without the "Error:" of the JS object
      flash(esc(T.srtError + ' ' + ((e && e.message) || e)), '', true);   // no fallback: WKWebView has no useful dialog
    }
    return;
  }
  // 2) Chrome/Edge: "Save" dialog that REMEMBERS the folder (id): from the
  //    second time on it proposes the videos folder. 3) Safari: download.
  if(window.showSaveFilePicker){
    try{
      const h = await showSaveFilePicker({
        suggestedName: fname, id: 'voc26-srt',
        types: [{description:T.srtDesc, accept:{'text/plain':['.srt']}}]
      });
      const w = await h.createWritable();
      await w.write(out); await w.close();
      flash(savedHtml('savedAs', h.name || fname) + esc(mergeNote));
      return;
    }catch(e){
      if(e && e.name === 'AbortError') return;   // cancelled by the user
      // other errors (e.g. API blocked on file://) -> download fallback
    }
  }
  const blob = new Blob([out], {type:'text/plain;charset=utf-8'});
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = fname;
  a.click();
  URL.revokeObjectURL(a.href);
  flash(savedHtml('srtDownloaded', fname) + esc(mergeNote));
}

// "Reset all…" asks first and says what is lost. In the app: the message
// {type:"confirm", title, text, confirm, cancel, destructive} answered with
// {confirmed: true|false} (destructive button + Cancel as the default).
// An app that does not know the message (the promise fails) and a browser
// get confirm() with the title, a blank line and the text.
async function askReset(){
  if (BRIDGE) {
    try {
      const r = await Promise.resolve(BRIDGE.postMessage({type:'confirm', title: T.resetTitle,
        text: T.resetText, confirm: T.resetConfirm, cancel: T.resetCancel, destructive: true}));
      if (r && typeof r.confirmed === 'boolean') return r.confirmed;
    } catch(e) {}
  }
  return confirm(T.resetTitle + '\n\n' + T.resetText);
}
async function resetAll(){
  if(!(await askReset())) return;
  saved = {}; persistState();
  try { localStorage.removeItem(LSKEY); sessionStorage.setItem(LSKEY + ':reset', '1'); } catch(e) {}
  location.reload();
}

// ---- render
applyStatic();
DATA.extraRows = [];
const rowsEl = document.getElementById('rows');
DATA.rows.filter(r=>!r.dropped).forEach(r => rowsEl.appendChild(makeRow(r)));
const dropEl = document.getElementById('dropped');
const droppedRows = DATA.rows.filter(r=>r.dropped);
if(droppedRows.length) droppedRows.forEach(r => dropEl.appendChild(makeRow(r)));
else dropEl.innerHTML = '<div class="empty" data-i18n-js="noneDropped">'+T.noneDropped+'</div>';
const gapsEl = document.getElementById('gaps');
if(DATA.gaps.length){
  DATA.gaps.forEach(g => {
    const d = el('div', 'gaprow'); g._el = d;
    const tc = el('div');
    tc.innerHTML = '<div class="gt mono">' + ts(g.start) + ' → ' + ts(g.end) + '</div><div class="gd"></div>';
    const gd = tc.querySelector('.gd');
    let thumb;
    if (g.thumb) { thumb = el('img', 'thumb'); thumb.src = 'data:image/jpeg;base64,' + g.thumb; }
    else thumb = el('div', 'thumb none');
    const act = el('div', 'gapact');
    const hint = el('span', 'hint');
    const btn = el('button', 'btn'); btn.type = 'button';
    btn.onclick = () => addRow(g);
    act.append(hint, el('span', 'sp'), btn);
    d.append(tc, thumb, act);
    d._i18n = () => {
      gd.textContent = T.gapNoSub.replace('{n}', secs(g.end - g.start, 1));
      hint.textContent = g.edge === 'start' ? T.gapStart : g.edge === 'end' ? T.gapEnd : T.gapHint;
      if (g.thumb) thumb.alt = T.gapThumbAlt; else thumb.textContent = T.noFrame;
      btn.textContent = T.addHere;
    };
    d._i18n();
    gapsEl.appendChild(d);
  });
} else gapsEl.innerHTML = '<div class="empty" data-i18n-js="noneGaps">'+T.noneGaps+'</div>';

// the lines added in previous sessions, among the others at their time
// (still with "+"); the ones from a gap get the gap's frame back
const restored = [];
for(const [id, s] of Object.entries(saved)){
  if(s && s.added && !ROWS[id]){
    const g = (s.gap != null) ? DATA.gaps[s.gap] : null;
    restored.push({id:id, n:'+', start: s.start === undefined ? null : s.start,
                   end: s.end === undefined ? null : s.end, text:s.text||'', alts:[],
                   flags:[ADDED_FLAG], conf:null, added:true, dropped:false,
                   thumb: g ? g.thumb : ''});
  }
}
const startKey = r => { const s = rowValues(r).start; return s == null ? Infinity : s; };
restored.sort((a, b) => startKey(a) - startKey(b));
restored.forEach(r => {
  DATA.extraRows.push(r);
  placeByTime(rowsEl, makeRow(r), rowValues(r).start);
});
updateCounter();
// the text boxes follow their text, also when the page changes width
function fitAll(){ document.querySelectorAll('textarea').forEach(t => { if (t._fit) t._fit(); }); }
fitAll();
let fitTimer = null;
window.addEventListener('resize', () => { clearTimeout(fitTimer); fitTimer = setTimeout(fitAll, 100); });

// the report bar sticks at the top: square top corners and a strip of
// page background under it while the rest of the page passes beneath
function updateStuck(){
  const top = document.getElementById('rsentinel').getBoundingClientRect().top;
  document.getElementById('rhead').classList.toggle('stuck', top < 0);
}
document.addEventListener('scroll', updateStuck, {capture: true, passive: true});
window.addEventListener('resize', updateStuck);
updateStuck();
</script>
</body></html>
"""


def _fmt_seconds(value: float, lang: str) -> str:
    """A threshold in seconds as the report shows it: "6", "3,5" / "3.5"."""
    text = f"{value:.0f}" if float(value).is_integer() else f"{value:.1f}"
    return text.replace(".", ",") if lang == "it" else text


# Review-report strings (text only, zero logic). Both languages go in every
# report; the script picks one at open (see _QC_TEMPLATE).
# "html": __T_*__ tokens / data-i18n keys of the markup; "js": the T object
# used by the scripts; "flags": texts of the segment flag codes (FLAG_*) set
# by the pipeline; "summary": the recap at the top of the report, then
# "stats" (frames, OCR readings, boundaries refined, time) when known.
# No emoji and no {\an8} anywhere in the texts (C3, report v2).
_QC_I18N = {
    "it": {
        "html": {
            "TITLE": "Revisione di",
            "MERGE_TIP": "Al salvataggio: unisce le righe adiacenti con testo uguale o "
                         "molto simile (resa diversa dall’OCR). Se una delle due l’hai "
                         "editata a mano, vince il tuo testo.",
            "MERGE_LABEL": "unisci duplicati",
            "RESET": "Ripristina tutto…",
            "RESET_TIP": "Chiede conferma prima di annullare tutte le modifiche",
            "SAVE": "Salva SRT revisionato",
            "HINT": "Correggi il testo nelle caselle o clicca una lettura alternativa; togli la "
                    "spunta alle righe da escludere. Le modifiche restano in questo browser; "
                    "«Salva SRT revisionato» scarica l’SRT.",
            "ROWS_H": "Righe SRT",
            "ADDROW": "+ Aggiungi riga",
            "DROPPED_H": "Scartate",
            "DROPPED_SUB": "flash brevi o rumore · spunta per rimetterle nell’SRT",
            "GAPS_SUB": "possibili righe saltate",
            "LEG_WARN": "da ricontrollare",
            "LEG_BAD": "molto dubbio o scartato",
            "LEG_ADDED": "aggiunta a mano",
            "LEG_WORD": "parola",
            "LEG_WORD_TXT": "dove la lettura alternativa è diversa",
            "LEG_CONF": "<b>98 %</b> confidenza dell’OCR · accordo = tra le letture dei diversi "
                        "fotogrammi limitrofi analizzati",
        },
        "js": {
            "includeTip": "includi nell’SRT",
            "start": "inizio", "end": "fine",
            "tsFormat": "formato HH:MM:SS,mmm",
            "noTimes": "mancano i tempi",
            "decimal": ",", "pct": "{n} %", "secs": "{n} s",
            "sign": "È un cartello (va in alto)",
            "signTip": "Spuntata, la riga va in alto nell’SRT",
            "altTip": "Usa questa lettura (evidenziate le parole diverse)",
            "orig": "Originale",
            "origTip": "Riporta il testo e la casella «È un cartello» come li ha letti l’OCR",
            "remove": "Togli",
            "removeTip": "Toglie questa riga aggiunta a mano",
            "noFrame": "nessun fotogramma",
            "rowThumbAlt": "Fotogramma della riga {n}",
            "counter": "{inc} righe incluse su {tot}",
            "agree": "accordo",
            "badTimes": "Tempi non validi nella riga:",
            "mergedDupes": "duplicati uniti",
            "srtDesc": "Sottotitoli SubRip",
            "savedAs": "Salvato: {name}",
            "srtDownloaded": "Scaricato in Download: {name}",
            "srtError": "Errore nel salvataggio:",
            "hintApp": "Correggi il testo nelle caselle o clicca una lettura alternativa; togli la "
                       "spunta alle righe da escludere. «Salva SRT revisionato» lo scrive accanto "
                       "all’originale.",
            "resetTitle": "Ripristinare tutto il report?",
            "resetText": "Perderai tutte le modifiche fatte in questo report: testi corretti, "
                         "letture scelte, tempi, spunte, cartelli e righe aggiunte a mano. "
                         "Gli SRT revisionati già salvati non cambiano.",
            "resetConfirm": "Ripristina tutto",
            "resetCancel": "Annulla",
            "noneDropped": "Nessuna.", "noneGaps": "Nessuno.",
            "gapsTitle": "Buchi senza sottotitoli oltre {n} s",
            "gapNoSub": "{n} senza sottotitoli",
            "gapStart": "Inizio del video.",
            "gapEnd": "Fine del video.",
            "gapHint": "Fotogramma a metà del buco: se qui c’era una riga, aggiungila.",
            "gapThumbAlt": "Fotogramma a metà del buco",
            "addHere": "+ Aggiungi una riga qui",
            "addedFlag": "aggiunta a mano",
        },
        "flags": {
            FLAG_TOO_SHORT: "scartata: troppo breve",
            FLAG_NOISE: "scartata: probabile rumore grafico",
            FLAG_MERGED_FADE: "unita da fade/typo",
        },
        "summary": (
            "SRT <b>{srt}</b> · righe <b>{rows}</b> · da ricontrollare <b>{warn}</b> · "
            "scartate (recuperabili) <b>{dropped}</b> · buchi oltre {gap} s <b>{gaps}</b>"
        ),
        "stats": "{frames} fotogrammi · {ocr} letture OCR · {refined} confini raffinati · {elapsed}",
        "footer": "Generato con SubVision v{version} — <a href=\"{url}\">{host}</a>",
    },
    "en": {
        "html": {
            "TITLE": "Review of",
            "MERGE_TIP": "On save: merges adjacent lines with equal or very similar "
                         "text (rendered differently by the OCR). If you edited one "
                         "of the two by hand, your text wins.",
            "MERGE_LABEL": "merge duplicates",
            "RESET": "Reset all…",
            "RESET_TIP": "Asks before undoing all the changes",
            "SAVE": "Save reviewed SRT",
            "HINT": "Fix the text in the boxes or click an alternative reading; untick the lines "
                    "to leave out. Changes stay in this browser; “Save reviewed SRT” downloads the SRT.",
            "ROWS_H": "SRT lines",
            "ADDROW": "+ Add line",
            "DROPPED_H": "Dropped",
            "DROPPED_SUB": "short flashes or noise · tick to put them back in the SRT",
            "GAPS_SUB": "possibly skipped lines",
            "LEG_WARN": "to re-check",
            "LEG_BAD": "very doubtful or dropped",
            "LEG_ADDED": "added by hand",
            "LEG_WORD": "word",
            "LEG_WORD_TXT": "where the alternative reading differs",
            "LEG_CONF": "<b>98%</b> OCR confidence · agreement = among the readings of the "
                        "neighbouring frames analysed",
        },
        "js": {
            "includeTip": "include in the SRT",
            "start": "start", "end": "end",
            "tsFormat": "format HH:MM:SS,mmm",
            "noTimes": "times missing",
            "decimal": ".", "pct": "{n}%", "secs": "{n} s",
            "sign": "It’s a sign (goes on top)",
            "signTip": "Ticked, the line goes on top in the SRT",
            "altTip": "Use this reading (differing words highlighted)",
            "orig": "Original",
            "origTip": "Puts back the text and the “It’s a sign” box as the OCR read them",
            "remove": "Remove",
            "removeTip": "Removes this line added by hand",
            "noFrame": "no frame",
            "rowThumbAlt": "Frame of line {n}",
            "counter": "{inc} lines included out of {tot}",
            "agree": "agreement",
            "badTimes": "Invalid times in line:",
            "mergedDupes": "duplicates merged",
            "srtDesc": "SubRip subtitles",
            "savedAs": "Saved: {name}",
            "srtDownloaded": "Downloaded to Downloads: {name}",
            "srtError": "Could not save:",
            "hintApp": "Fix the text in the boxes or click an alternative reading; untick the lines "
                       "to leave out. “Save reviewed SRT” writes it next to the original.",
            "resetTitle": "Reset the whole report?",
            "resetText": "You will lose all the changes made in this report: corrected texts, "
                         "chosen readings, times, ticks, signs and lines added by hand. "
                         "Reviewed SRTs already saved do not change.",
            "resetConfirm": "Reset all",
            "resetCancel": "Cancel",
            "noneDropped": "None.", "noneGaps": "None.",
            "gapsTitle": "Gaps without subtitles over {n} s",
            "gapNoSub": "{n} without subtitles",
            "gapStart": "Start of the video.",
            "gapEnd": "End of the video.",
            "gapHint": "Frame from the middle of the gap: if a line was missing here, add it.",
            "gapThumbAlt": "Frame from the middle of the gap",
            "addHere": "+ Add a line here",
            "addedFlag": "added by hand",
        },
        "flags": {
            FLAG_TOO_SHORT: "dropped: too short",
            FLAG_NOISE: "dropped: likely graphic noise",
            FLAG_MERGED_FADE: "merged across fade/typo",
        },
        "summary": (
            "SRT <b>{srt}</b> · lines <b>{rows}</b> · to re-check <b>{warn}</b> · "
            "dropped (recoverable) <b>{dropped}</b> · gaps over {gap} s <b>{gaps}</b>"
        ),
        "stats": "{frames} frames · {ocr} OCR readings · {refined} boundaries refined · {elapsed}",
        "footer": "Generated with SubVision v{version} — <a href=\"{url}\">{host}</a>",
    },
}


def write_qc_html(path: Path, video_name: str, srt_name: str,
                  segs: List[SegInfo], dropped: List[SegInfo],
                  gaps: List[Tuple[float, float, str]], stats: RunStats,
                  p: OcrParams, ui_lang: str = "it") -> None:
    """
    INTERACTIVE, self-contained review report (a single offline HTML file):
    - every line's text is editable; alternative readings apply with one
      click; "Original" puts back the text and the sign box of the OCR;
      lines can be included/excluded (dropped ones recoverable);
    - new lines can be added from the top (empty times) or in the "gaps"
      (prefilled times, mid-gap frame); they come back at their time;
    - editable times with the line's duration; "It's a sign" box per line
      ({\\an8} in the SRT only);
    - "Save reviewed SRT" generates the final SRT; changes stay saved in
      the browser (localStorage) across sessions.
    Inside the SubVision app (WKWebView with the "subvision" message
    handler) the SRT, the editor state and the reset question go to the app
    through the bridge and the saved state comes back injected as
    window.__subvisionState; the page then has no title of its own.
    The report carries the texts of BOTH languages and picks one when it
    opens: window.__subvisionLang ("it" | "en", set by the app) or else the
    browser language; window.__subvisionSetLang(lang) switches it live.
    ui_lang ("it" | "en") only sets the initial <html lang> and the texts
    shown before the script runs (kept for signature compatibility).
    """
    def row_cls(s: SegInfo) -> str:
        if s.conf < 0.5 or s.agree < 0.5:
            return "bad"
        if s.conf < p.qc_conf_warn or s.agree < p.qc_agree_warn or s.flags:
            return "warn"
        return ""

    rows = []
    for i, s in enumerate(list(segs) + list(dropped), 1):
        is_dropped = s in dropped
        rows.append({
            "id": f"s{i}", "n": i,
            "start": round(s.start, 3), "end": round(s.end, 3),
            "text": s.text, "top": s.top, "conf": round(s.conf, 3),
            "agree": round(s.agree, 3), "alts": s.alts,
            "flags": list(s.flags),            # codes: translated by the script
            "thumb": s.thumb, "dropped": is_dropped,
            "cls": "bad" if is_dropped else row_cls(s),
        })

    gap_rows = [{"start": round(a, 3), "end": round(b, 3), "thumb": th} for a, b, th in gaps]
    warn_rows = sum(1 for s in segs
                    if s.conf < p.qc_conf_warn or s.agree < p.qc_agree_warn or s.flags)
    stats_values = {"frames": stats.frames, "ocr": stats.ocr_calls,
                    "refined": stats.refined, "elapsed": fmt_hms(stats.elapsed)}
    html = render_qc_html(video_name, srt_name, rows, gap_rows, p.qc_gap_warn,
                          warn_rows, stats_values, ui_lang)
    path.write_text(html, encoding="utf-8")


def gap_edges(rows: List[Dict[str, Any]], gaps: List[Dict[str, Any]]) -> None:
    """
    Sets `edge` on every gap of the report data: "start" for a gap from 0
    (the start of the video), "end" for one with no line after it (none of
    the rows not dropped starts at or after its end), "" otherwise.
    """
    starts = [r["start"] for r in rows if not r.get("dropped") and r.get("start") is not None]
    for g in gaps:
        a, b = g["start"], g["end"]
        if a <= 1e-3:
            g["edge"] = "start"
        elif not any(st >= b - 1e-3 for st in starts):
            g["edge"] = "end"
        else:
            g["edge"] = ""


def render_qc_html(video_name: str, srt_name: str, rows: List[Dict[str, Any]],
                   gaps: List[Dict[str, Any]], gap_warn: float, warn_rows: int,
                   stats: Optional[Dict[str, Any]], ui_lang: str = "it") -> str:
    """
    The review report page (current template, REPORT_VERSION) for the data
    of write_qc_html: `rows` as it builds them (OCR rows, then the dropped
    ones), `gaps` as {start, end, thumb} (their `edge` is set here),
    `gap_warn` the threshold of the gaps in seconds, `warn_rows` the lines
    to re-check of the summary and `stats` {frames, ocr, refined, elapsed}
    for its second half (None: left out, as for an upgraded old report that
    does not say them). Also used by report_upgrade.py.
    """
    import json

    if ui_lang not in _QC_I18N:
        ui_lang = "it"
    tr = _QC_I18N[ui_lang]
    gap_edges(rows, gaps)
    lines = sum(1 for r in rows if not r.get("dropped"))
    data = {
        "srtName": srt_name, "videoName": video_name,
        "rows": rows,
        "gaps": gaps,
        "gapWarn": gap_warn,
    }
    texts = {}
    for lang, ltr in _QC_I18N.items():
        summary = ltr["summary"].format(
            srt=_esc(srt_name), rows=lines, warn=warn_rows,
            dropped=len(rows) - lines, gap=_fmt_seconds(gap_warn, lang),
            gaps=len(gaps))
        if stats:
            summary += " · " + ltr["stats"].format(**stats)
        texts[lang] = {
            "html": ltr["html"], "js": ltr["js"], "flags": ltr["flags"],
            "summary": summary,
            "footer": ltr["footer"].format(version=__version__, url=REPO_URL,
                                           host=REPO_URL.split("://", 1)[-1]),
        }
    payload = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    i18n = json.dumps(texts, ensure_ascii=False).replace("</", "<\\/")
    html = (_QC_TEMPLATE.replace("__LANG__", ui_lang)
            .replace("__REPORT_VERSION__", str(REPORT_VERSION)))
    for key, val in tr["html"].items():
        html = html.replace(f"__T_{key}__", val)
    html = (html
            .replace("__VIDEO__", _esc(video_name))
            .replace("__SUMMARY__", texts[ui_lang]["summary"])
            .replace("__FOOTER__", texts[ui_lang]["footer"]))
    # the two JSON blocks in one pass: their content is never re-scanned
    blocks = {"__DATA__": payload, "__I18N__": i18n}
    return re.sub(r"__(?:DATA|I18N)__", lambda m: blocks[m.group(0)], html)


# ---------------------------------------------------------------- orchestration
def _process_band(video: str, band: str, p: OcrParams, langs: List[str],
                  workdir: Path, stats: RunStats,
                  progress_cb: Optional[ProgressCallback],
                  log_cb: Optional[LogCallback],
                  stop: Optional[threading.Event] = None,
                  ) -> Tuple[List[SegInfo], List[SegInfo], List[Tuple[float, float, str]]]:
    """
    Processes one band ('bottom' or 'top') and returns (segments, dropped, gaps).
    The review-report thumbnails are captured HERE, before the frames are deleted.
    """
    def emit(step: str, ratio: float, count: int, total: int, unit: str) -> None:
        if progress_cb:
            progress_cb(ProgressEvent(step, band, ratio, count, total, unit))

    def stage(name: str, unit: str = "frames") -> _StepCallback:
        # one (step, band) pair per callback, so the caller can dedicate a
        # progress row to every step of every band
        def cb(ratio: float, count: int, total: int) -> None:
            emit(name, ratio, count, total, unit)
        return cb

    def log(code: str, **args: Any) -> None:
        if log_cb:
            log_cb(LogEvent(code, {"band": band, **args}))

    frames, dt = extract_frames(video, workdir / f"frames_{band}", p, band,
                                stage("extract"), stop=stop)
    stats.frames += len(frames)
    log("frames_extracted", n=len(frames), fps=p.fps)
    if not frames:
        return [], [], []

    targets = select_ocr_targets(frames, p.skip_hamming, stage("group"), stop=stop)
    emit("group", 1.0, len(targets), len(frames), "targets")
    log("ocr_targets", targets=len(targets), frames=len(frames))

    # ---- multi-variant OCR in parallel
    nvar = len(gen_variants(Image.new("RGB", (2, 2)), p.multi_variant))
    results: Dict[int, Tuple[str, float, List[str]]] = {}
    done = 0

    def ocr_target(idx: int):
        # STOP POINT: before every task and before every variant (a single
        # Vision call is 0.1-0.3 s and cannot be interrupted)
        _check_stop(stop)
        im = Image.open(frames[idx]).convert("RGB")
        cands = []
        for _, v, fw in gen_variants(im, p.multi_variant):
            _check_stop(stop)
            cands.append(ocr_conf(v, langs, p.recognition_level, p.min_confidence, fw))
        text, conf, agree, alts = vote_texts(cands)
        return idx, (text, conf, alts)

    from concurrent.futures import ThreadPoolExecutor, as_completed
    _check_stop(stop)
    with ThreadPoolExecutor(max_workers=max(1, p.workers)) as ex:
        futs = [ex.submit(ocr_target, i) for i in targets]
        try:
            for fut in as_completed(futs):
                try:
                    idx, res = fut.result()
                    results[idx] = res
                except Stopped:
                    pass           # a stopped task is not an OCR error
                except Exception as e:
                    log("ocr_error", error=str(e))
                done += 1
                stats.ocr_calls += nvar
                if done % 10 == 0 or done == len(targets):
                    emit("ocr", done / len(targets), done, len(targets), "frames")
                # STOP POINT: after every completed task; cancel_futures drops
                # the queued ones, the <= workers in flight finish their current
                # variant and then raise Stopped at their own check
                if stop is not None and stop.is_set():
                    ex.shutdown(wait=False, cancel_futures=True)
                    raise Stopped()
        finally:
            # the `with` exit is shutdown(wait=True) WITHOUT cancel_futures:
            # on an exception it would wait for every queued task (minutes).
            ex.shutdown(wait=False, cancel_futures=True)

    # ---- forward-fill + sanitize
    per_text: List[str] = []
    per_conf: List[float] = []
    per_alts: List[List[str]] = []
    cur: Tuple[str, float, List[str]] = ("", 0.0, [])
    for i in range(len(frames)):
        if i in results:
            cur = results[i]
        t = sanitize(cur[0], p.ignore_lines)
        per_text.append(t)
        per_conf.append(cur[1] if t else 0.0)
        per_alts.append(cur[2] if t else [])

    # ---- segments + merge
    segs = segments_from_frames(per_text, per_conf, per_alts, dt)
    segs = merge_seginfos(segs, p.merge_gap)
    for s in segs:
        s.top = (band == "top")

    # ---- anti-flash + anti-noise: separates (does NOT discard: everything goes in the review report)
    def is_noise(s: SegInfo) -> bool:
        """
        Very short readings with almost no letters (". L", "10)"): they are
        usually graphic elements of the scene, not subtitles. Real very short
        subs ("Si'", "Eh?") have >=2 letters or last longer. When in doubt
        they still end up in the review report with a thumbnail.
        """
        letters = sum(c.isalpha() for c in s.text)
        dur = s.end - s.start
        return (letters == 0 and dur < 0.8) or (letters <= 1 and dur < 0.6)

    kept, dropped = [], []
    for s in segs:
        if (s.end - s.start) < p.min_duration:
            s.flags.append(FLAG_TOO_SHORT)
            dropped.append(s)
        elif is_noise(s):
            s.flags.append(FLAG_NOISE)
            dropped.append(s)
        else:
            kept.append(s)

    # ---- thumbnails (before the frames disappear)
    def snap(seg: SegInfo):
        mid = int(((seg.start + seg.end) / 2) / dt)
        mid = max(0, min(len(frames) - 1, mid))
        seg.thumb = thumb_b64(frames[mid])

    for s in kept + dropped:
        snap(s)

    # ---- long gaps without subs (dialogue band only) with mid-gap thumbnail
    gaps: List[Tuple[float, float, str]] = []
    if band == "bottom":
        anchors = [0.0] + [s.end for s in kept]
        ends = [s.start for s in kept] + [len(frames) * dt]
        for a, b in zip(anchors, ends):
            if b - a >= p.qc_gap_warn:
                mid = int(((a + b) / 2) / dt)
                mid = max(0, min(len(frames) - 1, mid))
                gaps.append((a, b, thumb_b64(frames[mid])))

    # ---- boundary refinement at the native frame rate
    if p.refine_timing and kept:
        _check_stop(stop)
        native = ffprobe_fps(video)
        log("refining", fps=native)
        moved = refine_segment_bounds(video, kept, dt, native, band_crop(p, band),
                                      langs, p, workdir, stage("refine", "segments"),
                                      stop=stop)
        stats.refined += moved
        log("boundaries_moved", n=moved)

    return kept, dropped, gaps


def process_video(video: str, out_path: str, p: OcrParams,
                  progress_cb: Optional[ProgressCallback] = None,
                  log_cb: Optional[LogCallback] = None,
                  tmp_root: Optional[Path] = None,
                  ui_lang: str = "it",
                  stop: Optional[threading.Event] = None,
                  ) -> Tuple[List[Tuple[float, float, str]], RunStats]:
    """
    Full pipeline. progress_cb(ProgressEvent) with step in STEPS and band in
    BANDS; log_cb(LogEvent) with the codes listed on LogEvent. Returns
    (tuple_segments, stats); stats.qc_path holds the path of the review
    report (if generated). ui_lang ("it" | "en") is only the initial
    language of the review report (which carries both and follows the app
    or the browser language when opened). Raises EngineError("vision_unavailable") when
    Apple Vision (ocrmac) cannot be imported, EngineError("probe_failed")
    when ffprobe cannot read the video.
    `stop`: cooperative stop event. When set, the pipeline raises Stopped
    from the next stop point (<= ~1 s), terminates its ffmpeg children,
    writes NO srt/report and removes the workdir (the `finally` below).
    A failing review report does not fail the job: the SRT already written
    stays and the error becomes a LogEvent("report_failed").
    """
    if not vision_available():
        raise EngineError("vision_unavailable", tool="vision")
    _check_stop(stop)
    langs = resolve_langs(p.lang_hint)
    tmp_root = Path(tmp_root or tempfile.gettempdir())
    tmp_root.mkdir(parents=True, exist_ok=True)
    workdir = Path(tempfile.mkdtemp(prefix="voc26_", dir=str(tmp_root)))
    stats = RunStats()
    t0 = time.time()
    try:
        # the first-ever Vision call on a Mac takes ~30 s and cannot be
        # interrupted: the sidecar runs `warmup` at startup, not here
        warmup(langs, p.recognition_level)
        _check_stop(stop)

        all_segs: List[SegInfo] = []
        all_dropped: List[SegInfo] = []
        gaps: List[Tuple[float, float, str]] = []

        bands = ["bottom"] + (["top"] if p.top_band else [])
        for band in bands:
            kept, dropped, g = _process_band(video, band, p, langs, workdir,
                                             stats, progress_cb, log_cb, stop=stop)
            all_segs += kept
            all_dropped += dropped
            gaps += g

        # STOP POINT: last one before anything is written next to the video
        _check_stop(stop)
        all_segs.sort(key=lambda s: (s.start, s.top))

        # text postprocess (incl. corrections) + {\an8} tag for the signs
        final: List[Tuple[float, float, str]] = []
        for s in all_segs:
            txt = postprocess(s.text, p.wrap_width, p.ignore_lines, p.corrections,
                              lang_hint=p.lang_hint)
            if not txt:
                continue
            s.text = txt
            final.append((s.start, s.end, ("{\\an8}" + txt) if s.top else txt))
        stats.segments = len(final)
        stats.dropped = len(all_dropped)
        stats.gaps = [(round(a, 3), round(b, 3)) for a, b, _ in gaps]
        stats.elapsed = time.time() - t0

        write_srt(final, out_path)
        if log_cb:
            log_cb(LogEvent("srt_written", {
                "path": str(out_path), "segments": stats.segments,
                "ocr": stats.ocr_calls, "refined": stats.refined,
                "elapsed": stats.elapsed}))

        if p.qc_report:
            qc = Path(out_path).with_suffix(".review.html")
            try:
                write_qc_html(qc, Path(video).name, Path(out_path).name,
                              [s for s in all_segs if s.text],
                              all_dropped, gaps, stats, p, ui_lang=ui_lang)
            except Exception as e:
                # the SRT is already on disk: a broken report is a log line
                if log_cb:
                    log_cb(LogEvent("report_failed", {"path": str(qc), "error": str(e)}))
            else:
                stats.qc_path = str(qc)
                if log_cb:
                    log_cb(LogEvent("report_written", {"path": str(qc)}))

        return final, stats
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def load_ignore(path: Path) -> List[str]:
    try:
        if not path.exists():
            return []
        return [ln.strip() for ln in path.read_text(encoding="utf-8").splitlines()
                if ln.strip() and not ln.strip().startswith("#")]
    except Exception:
        return []


def load_corrections(path: Path) -> List[Tuple[str, str]]:
    """
    Loads corrections.txt: one rule per line in the format
        wrong => right
    Empty lines and comments (#) are ignored. Longer rules apply first
    (prevents a short rule from "breaking" a more specific one).
    """
    out: List[Tuple[str, str]] = []
    try:
        if not path.exists():
            return []
        for ln in path.read_text(encoding="utf-8").splitlines():
            ln = ln.strip()
            if not ln or ln.startswith("#") or "=>" not in ln:
                continue
            wrong, _, right = ln.partition("=>")
            wrong, right = wrong.strip(), right.strip()
            if wrong:
                out.append((wrong, right))
        out.sort(key=lambda wr: -len(wr[0]))
    except Exception:
        pass
    return out
