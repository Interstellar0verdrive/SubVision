"""
Review report (write_qc_html): the IT/EN texts must stay the ones of 1.0
even though the segment flags are now codes. The fixed segments below are
the same ones used to diff the reports before and after activity 1.2
(byte-identical in both languages).
"""

from __future__ import annotations

from pathlib import Path

from subvision import core
from subvision.core import OcrParams, RunStats, SegInfo


def _fixed_report(tmp_path: Path, lang: str) -> str:
    segs = [
        SegInfo(0.5, 2.0, "Ciao, come stai?", conf=0.95, agree=1.0, nframes=9, thumb="AAA"),
        SegInfo(2.5, 4.0, "Bene, grazie", conf=0.70, agree=0.6, nframes=9, thumb="BBB",
                alts=["Bene grazie", "Bere, grazie"], flags=[core.FLAG_MERGED_FADE]),
        SegInfo(5.0, 6.0, "CARTELLO", conf=0.9, agree=0.9, nframes=6, top=True, thumb="CCC"),
    ]
    dropped = [
        SegInfo(7.0, 7.1, "x", conf=0.4, agree=0.5, nframes=1, thumb="DDD",
                flags=[core.FLAG_TOO_SHORT]),
        SegInfo(8.0, 8.5, ". L", conf=0.4, agree=0.5, nframes=3, thumb="EEE",
                flags=[core.FLAG_NOISE]),
    ]
    gaps = [(10.0, 20.0, "FFF")]
    stats = RunStats(frames=330, ocr_calls=120, segments=3, dropped=2, refined=4, elapsed=12.3)
    out = tmp_path / f"{lang}.revisione.html"
    core.write_qc_html(out, "video.mp4", "video.srt", segs, dropped, gaps, stats,
                       OcrParams(), ui_lang=lang)
    return out.read_text(encoding="utf-8")


def test_report_it_texts(tmp_path: Path):
    html = _fixed_report(tmp_path, "it")
    assert '<html lang="it">' in html
    assert "<title>Revisione — video.mp4</title>" in html
    for text in ('"flags": ["unito da fade/typo"]',
                 '"flags": ["scartato: troppo breve"]',
                 '"flags": ["scartato: probabile rumore grafico"]',
                 "Righe: <b>3</b> · da ricontrollare: <b>1</b> · "
                 "scartate (recuperabili): <b>2</b> · buchi lunghi: <b>1</b>",
                 "Frame: 330 · OCR: 120 · confini raffinati: 4 · tempo: 00:12",
                 "💾 Salva SRT revisionato", "unisci duplicati",
                 '"addedFlag": "aggiunta a mano"',
                 f"Generato con SubVision v{core.__version__}"):
        assert text in html, text
    for code in ("too_short", "noise", "merged_fade"):
        assert f'"{code}"' not in html, code


def test_report_en_texts(tmp_path: Path):
    html = _fixed_report(tmp_path, "en")
    assert '<html lang="en">' in html
    assert "<title>Review — video.mp4</title>" in html
    for text in ('"flags": ["merged across fade/typo"]',
                 '"flags": ["dropped: too short"]',
                 '"flags": ["dropped: likely graphic noise"]',
                 "Lines: <b>3</b> · to re-check: <b>1</b> · "
                 "dropped (recoverable): <b>2</b> · long gaps: <b>1</b>",
                 "Frames: 330 · OCR: 120 · boundaries refined: 4 · time: 00:12",
                 "💾 Save reviewed SRT", "merge duplicates",
                 '"addedFlag": "added by hand"',
                 f"Generated with SubVision v{core.__version__}"):
        assert text in html, text
    for code in ("too_short", "noise", "merged_fade"):
        assert f'"{code}"' not in html, code


def test_qc_i18n_languages_are_aligned():
    it, en = core._QC_I18N["it"], core._QC_I18N["en"]
    assert set(it) == set(en)
    for section in ("html", "js", "flags"):
        assert set(it[section]) == set(en[section]), section
    assert set(it["flags"]) == {core.FLAG_TOO_SHORT, core.FLAG_NOISE, core.FLAG_MERGED_FADE}
    # every token of the template has a text in both languages
    for key in it["html"]:
        assert f"__T_{key}__" in core._QC_TEMPLATE, key
