"""Tests of Sub fix on a small SRT generated here (no file in the repo)."""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from subvision import core, fix

SRT = """1
00:00:01,000 --> 00:00:02,500
Ciao, come stai?

2
00:00:02,700 --> 00:00:04,000
Ciao, come stai?

3
00:00:05,000 --> 00:00:05,050
Flash

4
00:00:06,000 --> 00:00:08,000
Traduzione a cura di Pippo

5
00:00:09,000 --> 00:00:11,000
Il signor Flamilion e' arrivato

6
00:00:12,000 --> 00:00:14,000
Non ci sono sottotitoli
"""


@pytest.fixture
def srt(tmp_path: Path) -> Path:
    p = tmp_path / "episodio.srt"
    p.write_text(SRT, encoding="utf-8")
    return p


def test_fix_all_options(srt: Path) -> None:
    lists = (["Traduzione a cura di"], [("Flamilion", "Hamilton")])
    out, n = fix.fix_srt(srt, merge=True, ignore=True, flash=True, min_dur=0.2, lists=lists)
    assert out.parent == srt.parent
    assert re.fullmatch(r"episodio-fixed-\d{8}_\d{6}\.srt", out.name)
    assert n == 2
    segs = core.parse_srt(out)
    assert len(segs) == 2
    # 1+2 merged (same text, gap 0.2 s < merge_gap), flash and credits dropped,
    # "Non ci sono sottotitoli" dropped by the built-in regex, correction applied
    assert segs[0] == (1.0, 4.0, "Ciao, come stai?")
    assert segs[1][2] == "Il signor Hamilton e' arrivato"


def test_fix_nothing_on(srt: Path) -> None:
    out, n = fix.fix_srt(srt, merge=False, ignore=False, flash=False, lists=([], []))
    assert n == 6
    assert core.parse_srt(out) == core.parse_srt(srt)


def test_fix_single_options(srt: Path) -> None:
    _, n = fix.fix_srt(srt, merge=True, ignore=False, flash=False, lists=([], []))
    # 1+2 merged; merge_segments also runs postprocess, whose built-in
    # "no subtitles" regex drops the last line even with `ignore` off (as in 1.0)
    assert n == 4
    _, n = fix.fix_srt(srt, merge=False, ignore=False, flash=True, min_dur=0.2, lists=([], []))
    assert n == 5                      # only the 50 ms flash dropped
    _, n = fix.fix_srt(srt, merge=False, ignore=True, flash=False, lists=([], []))
    assert n == 5                      # only the "no subtitles" line (regex)
    # the ignore list counts only when `ignore` is on
    _, n = fix.fix_srt(srt, merge=False, ignore=False, flash=False,
                       lists=(["Traduzione a cura di"], []))
    assert n == 6


def test_fix_uses_params(srt: Path) -> None:
    p = core.OcrParams(merge_gap=0.1, wrap_width=42)
    _, n = fix.fix_srt(srt, merge=True, ignore=False, flash=False, params=p, lists=([], []))
    assert n == 5                      # gap 0.2 s > merge_gap 0.1: 1+2 not merged
                                       # (the "no subtitles" line still goes)


def test_fix_no_valid_segments(tmp_path: Path) -> None:
    p = tmp_path / "vuoto.srt"
    p.write_text("1\n00:00:01,000 --> 00:00:01,050\nFlash\n", encoding="utf-8")
    with pytest.raises(core.EngineError) as exc:
        fix.fix_srt(p, flash=True, min_dur=0.2, lists=([], []))
    assert exc.value.code == "no_valid_segments"
    assert list(tmp_path.glob("*-fixed-*")) == []
    with pytest.raises(core.EngineError) as exc:
        fix.fix_srt(tmp_path / "missing.srt")
    assert exc.value.code == "not_found"
