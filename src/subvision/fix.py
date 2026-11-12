"""
Sub fix: cleanup of an existing SRT (the "Sub fix" page of the app).

Same logic as the Sub fix tab of SubVision 1.0 (app.py): parse, drop the
lines that match the ignore list, merge nearby segments with similar text,
drop the flashes shorter than `min_dur`, apply the corrections, write
`<stem>-fixed-<YYYYMMDD_HHMMSS>.srt` next to the source.
"""

from __future__ import annotations

import datetime
from pathlib import Path
from typing import Optional, Tuple

from subvision import core
from subvision.lists import Lists


def fix_srt(path: Path | str, merge: bool = True, ignore: bool = True,
            flash: bool = True, min_dur: float = 0.2,
            params: Optional[core.OcrParams] = None,
            lists: Optional[Lists] = None) -> Tuple[Path, int]:
    """
    Returns (output path, number of segments written). `params` gives
    merge_gap, wrap_width and lang_hint (defaults of OcrParams when None);
    `lists` is the (ignore_lines, corrections) pair of lists.load(): the
    ignore lines are used only when `ignore` is on, the corrections
    whenever they are given. Raises EngineError("no_valid_segments") when
    nothing is left (no file is written), EngineError("not_found") when
    the source does not exist.
    """
    src = Path(path)
    if not src.is_file():
        raise core.EngineError("not_found", path=str(src))
    p = params or core.OcrParams()
    ignore_lines, corrections = lists or ([], [])

    segs = core.parse_srt(src)
    ext = list(ignore_lines) if ignore else []
    if ignore:
        segs = [(s, e, t) for s, e, t in segs if not core.looks_like_no_subtitle(t, ext)]
    if merge:
        segs = core.merge_segments(segs, merge_gap=p.merge_gap, min_duration=0.0,
                                   ignore_lines=ext, wrap=int(p.wrap_width),
                                   lang_hint=p.lang_hint)
    if flash:
        segs = [x for x in segs if (x[1] - x[0]) >= float(min_dur)]
    if corrections:
        segs = [(s, e, core.apply_corrections(t, corrections)) for s, e, t in segs]
    segs = [x for x in segs if x[2]]
    if not segs:
        raise core.EngineError("no_valid_segments", path=str(src))

    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    out = src.parent / f"{src.stem}-fixed-{stamp}.srt"
    core.write_srt(segs, str(out))
    return out, len(segs)
