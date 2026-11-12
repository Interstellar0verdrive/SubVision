"""
Review report (write_qc_html): the IT/EN texts must stay the ones of 1.0
even though the segment flags are now codes. The fixed segments below are
the same ones used to diff the reports before and after activity 1.2
(byte-identical in both languages).
"""

from __future__ import annotations

import re
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


def test_report_app_bridge_and_state(tmp_path: Path):
    """The report talks to the app (WKWebView) and falls back as in 1.0."""
    html = _fixed_report(tmp_path, "it")
    js = html.split("<script>", 1)[1]
    # bridge detection, export through it, state on every change
    assert "window.webkit.messageHandlers.subvision" in js
    assert "BRIDGE.postMessage({type:'export', name: fname, srt: out})" in js
    assert "BRIDGE.postMessage({type:'state', json: json})" in js
    assert "await Promise.resolve(BRIDGE.postMessage(" in js    # reply or no-reply handler
    # fallbacks, in order: bridge, showSaveFilePicker, <a download>
    assert js.index("if (BRIDGE)") < js.index("window.showSaveFilePicker") < js.index("a.download = fname")
    # injected initial state has precedence over localStorage
    assert "window.__subvisionState" in js
    assert js.index("window.__subvisionState && typeof") < js.index("localStorage.getItem(LSKEY)")
    # in-app hint swapped at load, strings present in both languages
    assert "document.getElementById('hint').innerHTML = T.hintApp" in js
    assert '<div class="hint" id="hint">' in html
    for lang, err, hint in (("it", "Errore nel salvataggio:", "accanto al video"),
                            ("en", "Could not save:", "next to the video")):
        h = _fixed_report(tmp_path, lang)
        assert f'"srtError": "{err}"' in h
        assert '"hintApp": "' in h and hint in h
        assert "Chrome/Edge" in h          # the browser hint is unchanged


def test_report_light_and_dark_palettes(tmp_path: Path):
    html = _fixed_report(tmp_path, "it")
    css = html.split("<style>", 1)[1].split("</style>", 1)[0]
    assert "color-scheme:light dark" in css
    assert "@media (prefers-color-scheme: light)" in css
    dark, light = css.split("@media (prefers-color-scheme: light)")
    # every variable of the dark palette has a light value
    names = set(re.findall(r"--([a-z0-9-]+):", dark.split("}")[0]))
    assert names and names == set(re.findall(r"--([a-z0-9-]+):", light.split("}")[0]))
    # the dark palette is the 1.0 one; the light one is readable
    assert "--bg:#14161a" in dark and "--fg:#e8e8e8" in dark
    assert "--bg:#F6F7F9" in light and "--fg:#16181B" in light
    # no hard-coded colour left in the markup (legend dots use classes)
    body = html.split("</style>", 1)[1].split("<script", 1)[0]
    assert 'style="background:#' not in body
    assert '<span class="dot warn"></span>' in body


def test_qc_i18n_languages_are_aligned():
    it, en = core._QC_I18N["it"], core._QC_I18N["en"]
    assert set(it) == set(en)
    for section in ("html", "js", "flags"):
        assert set(it[section]) == set(en[section]), section
    assert set(it["flags"]) == {core.FLAG_TOO_SHORT, core.FLAG_NOISE, core.FLAG_MERGED_FADE}
    # every token of the template has a text in both languages
    for key in it["html"]:
        assert f"__T_{key}__" in core._QC_TEMPLATE, key
