"""
Review reports written before the current template, shown with it.

A report is one offline HTML file next to the video (core.write_qc_html).
The ones written by 1.0 (`ocr_core.py`) and by the 2.0 builds before the
report v2 of C3 keep their old page: old layout, no fixed legend, Italian
even when the app is in English. The current template marks its pages with
`<meta name="subvision-report" content="N">` (core.REPORT_VERSION); a page
without it, or with an older N, is an old report.

`upgrade_report(path)` reads the data the old page carries (the
`<script type="application/json" id="qcdata">` block: srtName, videoName,
rows, gaps; the same keys in every old version) and writes a copy rendered
with the current template into `<state>/tmp/reports/<key>/<same name>`,
`key` being a hash of the report's path, size and modification time and
of the current template (a changed report, or a new template, gets a new
copy). The original is never written, nor anything next to it.

What the old data lacks or says differently, and what the copy gets:
- flags: 1.0 and the first 2.0 builds wrote them as translated text
  ("scartato: troppo breve", "dropped: too short"...); they go back to the
  codes (FLAG_*), which the page translates in both languages;
- `n` of a dropped row was "✂": it is the row's number, as today;
- a text (or reading) starting with `{\\an8}`: the tag goes, the row is a
  sign (`top`);
- `cls` (yellow / red): kept; computed with the default thresholds when
  absent;
- the gaps' `edge` (start / end of the video) is computed from the rows,
  as write_qc_html does;
- `gapWarn` (the threshold in the gaps' title): the default one (6 s),
  or lower when the report lists a shorter gap (the threshold of that run
  was lower: its whole seconds, at least 1);
- the summary's run figures (frames, OCR readings, boundaries refined,
  time) are read from the old summary when it has them, else left out.

The rows keep the ids of the old report ("s1", "s2"...: the order of the
old data is kept), so the review state saved by the app next to the
report (`<name>.review.json`, keyed by row id) applies to the copy as it
did to the original.

Copies not used for CACHE_MAX_AGE are removed by `clean_old` (sidecar
start-up). The sidecar's method is `report.upgrade {path}` (serve.py).
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import re
import shutil
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from subvision import __version__, core
from subvision.core import EngineError
from subvision.paths import state_paths

CACHE_MAX_AGE = 30 * 86400      # seconds: copies not used for this long are removed

_VERSION_RE = re.compile(r'<meta\s+name="subvision-report"\s+content="(\d+)"', re.I)
_DATA_RE = re.compile(r'<script type="application/json" id="qcdata">(.*?)</script>', re.S)
_LANG_RE = re.compile(r'<html\s+lang="([a-zA-Z-]+)"')
_AN8_RE = re.compile(r"^\s*\{\\an8\}")
# "Frame: 1500 · OCR: 2892 · confini raffinati: 19 · tempo: 01:16" (1.0 and
# the 2.0 builds before report v2; English: Frames, boundaries refined, time)
_STATS_RE = re.compile(r"Frames?:\s*(\d+)\s*·\s*OCR:\s*(\d+)\s*·\s*"
                       r"(?:confini raffinati|boundaries refined):\s*(\d+)\s*·\s*"
                       r"(?:tempo|time):\s*(\d+(?::\d{2}){1,2})")

# The flag texts of the old reports (1.0 and the first 2.0 builds wrote the
# translated text in the data), and today's texts, back to their codes.
_FLAG_TEXTS = {
    "scartato: troppo breve": core.FLAG_TOO_SHORT,
    "scartato: probabile rumore grafico": core.FLAG_NOISE,
    "unito da fade/typo": core.FLAG_MERGED_FADE,
    "dropped: too short": core.FLAG_TOO_SHORT,
    "dropped: likely graphic noise": core.FLAG_NOISE,
    "merged across fade/typo": core.FLAG_MERGED_FADE,
}
for _tr in core._QC_I18N.values():
    for _code, _text in _tr["flags"].items():
        _FLAG_TEXTS.setdefault(_text, _code)


def reports_root(state: Optional[Path | str] = None) -> Path:
    """`<state>/tmp/reports`: the upgraded copies."""
    return state_paths(state).tmp / "reports"


def report_version(html: str) -> int:
    """The template version a report page declares; 0 for a page without the marker."""
    m = _VERSION_RE.search(html)
    return int(m.group(1)) if m else 0


def _template_digest() -> str:
    """Changes with the template, its texts and the engine version: a new one makes new copies."""
    blob = core._QC_TEMPLATE + json.dumps(core._QC_I18N, sort_keys=True) + __version__
    return hashlib.sha1(blob.encode("utf-8")).hexdigest()[:12]


def cache_path(report: Path | str, state: Optional[Path | str] = None) -> Path:
    """Where the upgraded copy of `report` goes (path + size + mtime + template)."""
    r = Path(report)
    st = r.stat()
    key = f"{r.resolve()}|{st.st_size}|{st.st_mtime_ns}|{core.REPORT_VERSION}|{_template_digest()}"
    digest = hashlib.sha1(key.encode("utf-8")).hexdigest()[:16]
    return reports_root(state) / digest / r.name


def _unreadable(path: Path, detail: str) -> EngineError:
    return EngineError("report_unreadable", path=str(path), detail=detail)


def read_data(html: str, path: Path) -> Dict[str, Any]:
    """The report's own data (the qcdata block); report_unreadable when it cannot be used."""
    m = _DATA_RE.search(html)
    if not m:
        raise _unreadable(path, "no qcdata block: not a SubVision review report")
    try:
        data = json.loads(m.group(1))
    except ValueError as e:
        raise _unreadable(path, f"qcdata is not valid JSON: {e}") from e
    if not isinstance(data, dict) or not isinstance(data.get("rows"), list):
        raise _unreadable(path, "qcdata has no rows")
    return data


def _number(value: Any) -> Optional[float]:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        return None
    return float(value)


def _strip_an8(text: str) -> tuple[str, bool]:
    """The text without a leading {\\an8}, and whether it had one."""
    if _AN8_RE.match(text):
        return _AN8_RE.sub("", text, count=1), True
    return text, False


def _row_cls(conf: Optional[float], agree: Optional[float], flags: List[str], dropped: bool) -> str:
    """The row's colour with the default thresholds (as write_qc_html computes it)."""
    if dropped:
        return "bad"
    p = core.OcrParams()
    c = 1.0 if conf is None else conf
    a = 1.0 if agree is None else agree
    if c < 0.5 or a < 0.5:
        return "bad"
    if c < p.qc_conf_warn or a < p.qc_agree_warn or flags:
        return "warn"
    return ""


def upgrade_rows(raw_rows: List[Any]) -> List[Dict[str, Any]]:
    """The rows of an old report in the shape of today's (ids and order kept)."""
    rows = []
    for i, r in enumerate(raw_rows, 1):
        if not isinstance(r, dict):
            continue
        text, an8 = _strip_an8(str(r.get("text") or ""))
        alts = []
        for alt in r.get("alts") or []:
            if isinstance(alt, str):
                alts.append(_strip_an8(alt)[0])     # a reading's tag says nothing of the row
        flags = [_FLAG_TEXTS.get(f, f) for f in r.get("flags") or [] if isinstance(f, str)]
        dropped = bool(r.get("dropped"))
        conf, agree = _number(r.get("conf")), _number(r.get("agree"))
        start, end = _number(r.get("start")), _number(r.get("end"))
        cls = r.get("cls")
        if cls not in ("", "warn", "bad"):
            cls = _row_cls(conf, agree, flags, dropped)
        rows.append({
            "id": str(r.get("id") or f"s{i}"), "n": i,
            "start": None if start is None else round(start, 3),
            "end": None if end is None else round(end, 3),
            "text": text, "top": bool(r.get("top")) or an8,
            "conf": None if conf is None else round(conf, 3),
            "agree": None if agree is None else round(agree, 3),
            "alts": alts, "flags": flags,
            "thumb": r.get("thumb") if isinstance(r.get("thumb"), str) else "",
            "dropped": dropped, "cls": cls,
        })
    return rows


def upgrade_gaps(raw_gaps: Any) -> List[Dict[str, Any]]:
    gaps = []
    for g in raw_gaps if isinstance(raw_gaps, list) else []:
        if not isinstance(g, dict):
            continue
        a, b = _number(g.get("start")), _number(g.get("end"))
        if a is None or b is None or b < a:
            continue
        gaps.append({"start": round(a, 3), "end": round(b, 3),
                     "thumb": g.get("thumb") if isinstance(g.get("thumb"), str) else ""})
    return gaps


def gap_threshold(data: Dict[str, Any], gaps: List[Dict[str, Any]]) -> float:
    """The threshold of the gaps' title: the report's, else the default, else lower (see the module)."""
    known = _number(data.get("gapWarn"))
    if known is not None and known > 0:
        return known
    default = core.OcrParams().qc_gap_warn
    if gaps:
        shortest = min(g["end"] - g["start"] for g in gaps)
        if shortest < default:
            return float(max(1, math.floor(shortest)))
    return default


def run_stats(html: str) -> Optional[Dict[str, Any]]:
    """Frames, OCR readings, boundaries refined and time from the old summary (None if absent)."""
    m = _STATS_RE.search(_DATA_RE.sub("", html))
    if not m:
        return None
    return {"frames": int(m.group(1)), "ocr": int(m.group(2)),
            "refined": int(m.group(3)), "elapsed": m.group(4)}


def _names(data: Dict[str, Any], path: Path) -> tuple[str, str]:
    """videoName and srtName of the data, else from the report's file name."""
    stem = path.name
    for suffix in (".revisione.html", ".review.html", ".html"):
        if stem.lower().endswith(suffix):
            stem = stem[: -len(suffix)]
            break
    video = data.get("videoName") if isinstance(data.get("videoName"), str) else ""
    srt = data.get("srtName") if isinstance(data.get("srtName"), str) else ""
    return video or stem, srt or stem + ".srt"


def render_upgraded(html: str, path: Path) -> str:
    """The page of the old report `html` (read from `path`) with the current template."""
    data = read_data(html, path)
    rows = upgrade_rows(data["rows"])
    gaps = upgrade_gaps(data.get("gaps"))
    video, srt = _names(data, path)
    warn = sum(1 for r in rows if not r["dropped"] and r["cls"] in ("warn", "bad"))
    m = _LANG_RE.search(html)
    lang = m.group(1).split("-")[0].lower() if m else "it"
    return core.render_qc_html(video, srt, rows, gaps, gap_threshold(data, gaps), warn,
                               run_stats(html), lang if lang in ("it", "en") else "it")


def upgrade_report(report: Path | str, state: Optional[Path | str] = None) -> Dict[str, Any]:
    """
    The page to show for `report`:
    `{path, current: true}` when it already has the current template (its own path);
    otherwise `{path, current: false, cached, source}`, `path` being the
    upgraded copy (`cached`: it was there already) and `source` "1.x" (a
    report without the app bridge) or "2.0" (a 2.0 build before report v2).
    Errors: `not_found` (no such file), `report_unreadable` (not a review
    report, or its data cannot be read: `detail` says why).
    """
    path = Path(report)
    if not path.is_file():
        raise EngineError("not_found", path=str(path))
    try:
        html = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as e:
        raise _unreadable(path, f"{type(e).__name__}: {e}") from e
    if report_version(html) >= core.REPORT_VERSION:
        return {"path": str(path), "current": True}
    source = "2.0" if "messageHandlers.subvision" in html else "1.x"
    target = cache_path(path, state)
    if target.is_file():
        os.utime(target.parent)       # in use: clean_old keeps it
        return {"path": str(target), "current": False, "cached": True, "source": source}
    page = render_upgraded(html, path)
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(target.name + ".part")
    tmp.write_text(page, encoding="utf-8")
    os.replace(tmp, target)
    return {"path": str(target), "current": False, "cached": False, "source": source}


def clean_old(state: Optional[Path | str] = None, max_age: float = CACHE_MAX_AGE) -> int:
    """Removes the copies not used for `max_age` seconds; returns how many."""
    root = reports_root(state)
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
