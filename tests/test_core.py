"""
Engine tests: pure helpers (fast) and one real run on the ita demo clip
(~10 s from the second run; the first Vision call per user can take ~30 s).
"""

from __future__ import annotations

from pathlib import Path

import pytest

from subvision import core
from subvision.core import OcrParams

from conftest import FAST_PROFILE, FAST_PROFILE_LINES


# ---------------------------------------------------------------- pure helpers
def test_srt_ts_rounding():
    assert core.srt_ts(0) == "00:00:00,000"
    assert core.srt_ts(1.9995) == "00:00:02,000"          # no ms=1000 bug
    assert core.srt_ts(3661.25) == "01:01:01,250"
    assert core.srt_ts(-2) == "00:00:00,000"


def test_fmt_hms():
    assert core.fmt_hms(5) == "00:05"
    assert core.fmt_hms(65.4) == "01:05"
    assert core.fmt_hms(3600) == "1:00:00"


def test_smart_wrap_balanced_and_function_words():
    assert core.smart_wrap("corto", 42) == "corto"
    # two lines: the slightly less balanced split wins because it does not
    # leave the preposition "di" at the end of the first line
    s = "Ho l'intenzione di mangiare la pizza"
    out = core.smart_wrap(s, 20, "Italian")
    assert out == "Ho l'intenzione\ndi mangiare la pizza"
    # a comma is a preferred break point
    assert core.smart_wrap("Vieni qui, subito adesso", 15) == "Vieni qui,\nsubito adesso"
    # never breaks words; already multi-line text is left alone
    assert core.smart_wrap("a\nb", 1) == "a\nb"
    long_word = "x" * 50
    assert core.smart_wrap(long_word + " y", 10) == long_word + "\ny"


def test_parse_and_write_srt_roundtrip(tmp_path: Path):
    segs = [(0.5, 2.0, "Ciao"), (2.5, 4.0, "Riga uno\nriga due"), (5.0, 6.0, "")]
    out = tmp_path / "x.srt"
    core.write_srt(segs, str(out))
    parsed = core.parse_srt(out)
    assert parsed == [(0.5, 2.0, "Ciao"), (2.5, 4.0, "Riga uno\nriga due")]
    text = out.read_text(encoding="utf-8")
    assert text.startswith("1\n00:00:00,500 --> 00:00:02,000\nCiao\n\n2\n")


def test_merge_segments_joins_similar_and_drops_short():
    segs = [(0.0, 1.0, "Ciao mondo"), (1.2, 2.0, "Ciao mondo!"),
            (2.1, 2.15, "Flash"), (3.0, 4.0, "Altro testo")]
    out = core.merge_segments(segs, merge_gap=0.6, min_duration=0.2,
                              ignore_lines=[], wrap=42)
    assert out == [(0.0, 2.0, "Ciao mondo!"), (3.0, 4.0, "Altro testo")]
    # ignore list removes a line entirely
    out = core.merge_segments([(0.0, 1.0, "Traduzione a cura di X")], 0.6, 0.2,
                              ["Traduzione a cura di"], 42)
    assert out == []


def test_vote_texts_weighted_majority():
    text, conf, agree, alts = core.vote_texts([("Ciao", 0.9), ("Ciao", 0.8), ("Ciaa", 0.95)])
    assert text == "Ciao"
    assert alts == ["Ciaa"]
    assert 0.5 < agree < 1.0
    assert core.vote_texts([("", 0.0)]) == ("", 0.0, 1.0, [])


def test_postprocess_corrections_and_ignore():
    assert core.postprocess("Flamilion arriva", 42, [], [("Flamilion", "Hamilton")]) == "Hamilton arriva"
    assert core.postprocess("no subtitles", 42, []) == ""
    assert core.postprocess("", 42, []) == ""


def test_load_lists(tmp_path: Path):
    ign = tmp_path / "ignore.txt"
    ign.write_text("# comment\n\nTraduzione a cura di\n", encoding="utf-8")
    assert core.load_ignore(ign) == ["Traduzione a cura di"]
    cor = tmp_path / "correzioni.txt"
    cor.write_text("# c\nab => cd\nlonger rule => x\nbad line\n", encoding="utf-8")
    assert core.load_corrections(cor) == [("longer rule", "x"), ("ab", "cd")]
    assert core.load_ignore(tmp_path / "missing.txt") == []


def test_band_crop_expressions():
    p = OcrParams(bottom_keep_pct=28, keep_w_pct=96, top_keep_pct=22, top_keep_w_pct=100)
    assert core.band_crop(p, "bottom") == "crop=iw*96/100:ih*28/100:(iw-iw*96/100)/2:ih-ih*28/100"
    assert core.band_crop(p, "top") == "crop=iw:ih*22/100:0:0"


# ---------------------------------------------------------------- real run
def test_process_video_fast_profile(demo_ita_copy: Path, ffmpeg_bin: str, tmp_path: Path):
    if not core.vision_available():
        pytest.skip("Apple Vision (ocrmac) not available")
    out = demo_ita_copy.with_suffix(".srt")
    p = OcrParams(**FAST_PROFILE)
    segs, stats = core.process_video(str(demo_ita_copy), str(out), p,
                                     tmp_root=tmp_path / "tmp")
    assert out.exists()
    parsed = core.parse_srt(out)
    assert len(parsed) == FAST_PROFILE_LINES, [t for _, _, t in parsed]
    assert len(segs) == FAST_PROFILE_LINES
    assert stats.segments == FAST_PROFILE_LINES
    assert stats.frames > 0 and stats.ocr_calls > 0
    report = demo_ita_copy.with_suffix(".revisione.html")
    assert report.exists() and stats.qc_path == str(report)
    # the workdir is removed after the run
    assert not list((tmp_path / "tmp").glob("voc26_*"))
