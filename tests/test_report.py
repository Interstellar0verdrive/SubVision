"""
Review report (write_qc_html): the IT/EN texts must stay the ones of 1.0
even though the segment flags are now codes. The fixed segments below are
the same ones used to diff the reports before and after activity 1.2.
Since C2 (item 72) every report carries BOTH languages and picks one when
it opens (window.__subvisionLang, else the browser language); ui_lang only
prefills the markup.
"""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

import pytest

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
    out = tmp_path / f"{lang}.review.html"
    core.write_qc_html(out, "video.mp4", "video.srt", segs, dropped, gaps, stats,
                       OcrParams(), ui_lang=lang)
    return out.read_text(encoding="utf-8")


IT_TEXTS = ('"merged_fade": "unito da fade/typo"',
            '"too_short": "scartato: troppo breve"',
            '"noise": "scartato: probabile rumore grafico"',
            "Righe: <b>3</b> · da ricontrollare: <b>1</b> · "
            "scartate (recuperabili): <b>2</b> · buchi lunghi: <b>1</b>",
            "Frame: 330 · OCR: 120 · confini raffinati: 4 · tempo: 00:12",
            "💾 Salva SRT revisionato", "unisci duplicati",
            '"addedFlag": "aggiunta a mano"',
            f"Generato con SubVision v{core.__version__}")
EN_TEXTS = ('"merged_fade": "merged across fade/typo"',
            '"too_short": "dropped: too short"',
            '"noise": "dropped: likely graphic noise"',
            "Lines: <b>3</b> · to re-check: <b>1</b> · "
            "dropped (recoverable): <b>2</b> · long gaps: <b>1</b>",
            "Frames: 330 · OCR: 120 · boundaries refined: 4 · time: 00:12",
            "💾 Save reviewed SRT", "merge duplicates",
            '"addedFlag": "added by hand"',
            f"Generated with SubVision v{core.__version__}")


def _i18n_block(html: str) -> dict:
    raw = html.split('<script type="application/json" id="qci18n">', 1)[1].split("</script>", 1)[0]
    return json.loads(raw)


def _data_block(html: str) -> dict:
    raw = html.split('<script type="application/json" id="qcdata">', 1)[1].split("</script>", 1)[0]
    return json.loads(raw)


@pytest.mark.parametrize("lang", ["it", "en"])
def test_report_carries_both_languages(tmp_path: Path, lang: str):
    html = _fixed_report(tmp_path, lang)
    # ui_lang only prefills the markup (what shows before the script runs)
    if lang == "it":
        assert '<html lang="it">' in html and "<title>Revisione — video.mp4</title>" in html
    else:
        assert '<html lang="en">' in html and "<title>Review — video.mp4</title>" in html
    # ...but the texts of both languages are in every report ("</" is
    # written "<\\/" inside the JSON blocks)
    flat = html.replace("<\\/", "</")
    for text in IT_TEXTS + EN_TEXTS:
        assert text in flat, text
    i18n = _i18n_block(html)
    assert set(i18n) == {"it", "en"}
    for code in ("too_short", "noise", "merged_fade"):
        assert code in i18n["it"]["flags"] and code in i18n["en"]["flags"]
    assert i18n["it"]["html"]["TITLE"] == "Revisione" and i18n["en"]["html"]["TITLE"] == "Review"
    assert "Righe: <b>3</b>" in i18n["it"]["summary"] and "Lines: <b>3</b>" in i18n["en"]["summary"]
    assert "Generato con" in i18n["it"]["footer"] and "Generated with" in i18n["en"]["footer"]
    # the rows carry the flag CODES: the script translates them when shown
    flags = [r["flags"] for r in _data_block(html)["rows"]]
    assert flags == [[], ["merged_fade"], [], ["too_short"], ["noise"]]
    # a closing tag inside the JSON never ends the <script> block early
    raw = html.split('id="qci18n">', 1)[1].split("</script>", 1)[0]
    assert "</" not in raw


def test_report_unknown_ui_lang_falls_back_to_italian(tmp_path: Path):
    html = _fixed_report(tmp_path, "fr")
    assert '<html lang="it">' in html
    assert set(_i18n_block(html)) == {"it", "en"}


def test_report_language_api(tmp_path: Path):
    """
    The language is picked at open: window.__subvisionLang ('it' | 'en', set
    by the app) first, then the browser language; window.__subvisionSetLang
    switches every visible text in place (no reload).
    """
    js = _fixed_report(tmp_path, "it").split("<script>", 1)[1]
    assert "window.__subvisionLang" in js
    assert "if (forced === 'it' || forced === 'en') return forced;" in js
    assert "navigator.languages" in js and "navigator.language" in js
    assert "window.__subvisionSetLang = function(lang){" in js
    setlang = js[js.index("window.__subvisionSetLang = function(lang){"):]
    setlang = setlang[:setlang.index("\n};") + 4]
    assert "location.reload" not in setlang
    for call in ("applyStatic();", "refreshRows();", "updateCounter();"):
        assert call in setlang, call
    # static texts: html lang, title, data-i18n markup, hint, summary, footer
    static = js[js.index("function applyStatic(){"):js.index("function refreshRows(){")]
    for piece in ("document.documentElement.lang = LANG", "document.title =",
                  "[data-i18n]", "[data-i18n-title]", "[data-i18n-js]",
                  "document.getElementById('hint').innerHTML = BRIDGE ? T.hintApp : L.html.HINT",
                  "getElementById('summary').innerHTML = L.summary",
                  "getElementById('foot').innerHTML = L.footer",
                  "n.dataset.wide = L.html.SRT_SAVED"):
        assert piece in static, piece
    # rows and gaps keep a refresher for their labels (edits are not touched)
    assert js.count("._i18n = () => {") == 2
    assert "flagText(f)" in js and "flags:[ADDED_FLAG]" in js and "flags:[T.addedFlag]" not in js


JSC = Path("/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc")


@pytest.mark.skipif(not JSC.exists(), reason="JavaScriptCore shell not available")
def test_report_language_choice_runs(tmp_path: Path):
    """pickLang() of the real report, run in JavaScriptCore."""
    js = _fixed_report(tmp_path, "it").split("<script>", 1)[1].split("</script>", 1)[0]
    fn = js[js.index("function pickLang(){"):]
    fn = fn[:fn.index("\n}\n") + 3]
    cases = [
        ("'en'", "['it-IT']", "'it-IT'", "en"),     # the app decides
        ("'it'", "['en-US']", "'en-US'", "it"),
        ("'de'", "['it-IT','en']", "'it-IT'", "it"),  # not it/en: browser language
        ("undefined", "['it']", "'it'", "it"),
        ("undefined", "['en-GB','it']", "'en-GB'", "en"),
        ("undefined", "['de-DE']", "'de-DE'", "en"),
        ("undefined", "[]", "'it-CH'", "it"),       # navigator.language fallback
        ("undefined", "undefined", "undefined", "en"),
    ]
    for forced, langs, lang, expected in cases:
        src = (f"var window = {{__subvisionLang: {forced}}};\n"
               f"var navigator = {{languages: {langs}, language: {lang}}};\n"
               f"{fn}\nprint(pickLang());\n")
        script = tmp_path / "pick.js"
        script.write_text(src, encoding="utf-8")
        out = subprocess.run([str(JSC), str(script)], capture_output=True, text=True, timeout=30)
        assert out.returncode == 0, out.stderr
        assert out.stdout.strip() == expected, (forced, langs, lang, out.stdout)


@pytest.mark.skipif(not JSC.exists(), reason="JavaScriptCore shell not available")
def test_report_script_syntax(tmp_path: Path):
    js = _fixed_report(tmp_path, "en").split("<script>", 1)[1].split("</script>", 1)[0]
    script = tmp_path / "report.js"
    script.write_text(js, encoding="utf-8")
    out = subprocess.run([str(JSC), "-e", f"checkSyntax({json.dumps(str(script))})"],
                         capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr + out.stdout


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
    # in-app hint swapped at load (and on a language switch), both languages
    assert "document.getElementById('hint').innerHTML = BRIDGE ? T.hintApp : L.html.HINT" in js
    assert '<div class="hint" id="hint">' in html
    for lang, err, hint in (("it", "Errore nel salvataggio:", "accanto al video"),
                            ("en", "Could not save:", "next to the video")):
        h = _fixed_report(tmp_path, lang)
        assert f'"srtError": "{err}"' in h
        assert '"hintApp": "' in h and hint in h
        assert "Chrome/Edge" in h          # the browser hint is unchanged


def test_report_export_note_does_not_push_the_top_bar(tmp_path: Path):
    """
    F6 (report 2.0): after an export through the app the note is the short
    "SRT saved" only, with the path as its tooltip, and the note always
    keeps the width of that message, so the title and the buttons of the
    top bar stay where they are. In a browser the message is the 1.0 one.
    """
    for lang, short, resting in (("it", "SRT salvato ✓", "salvato ✓"),
                                 ("en", "SRT saved ✓", "saved ✓")):
        html = _fixed_report(tmp_path, lang)
        js = html.split("<script>", 1)[1]
        css = html.split("<style>", 1)[1].split("</style>", 1)[0]
        assert f'"srtSaved": "{short}"' in html
        # the note reserves the width of the short export message (invisible sizer)
        assert f'<span class="saved" id="savedNote" data-wide="{short}">{resting}</span>' in html
        assert ".saved::after{content:attr(data-wide);height:0;visibility:hidden}" in css
        saved = re.search(r"\.saved\{([^}]*)\}", css).group(1)
        assert "display:inline-grid" in saved and "flex:none" in saved and "white-space:nowrap" in saved
        # through the bridge: short message, path (and merge note) in the tooltip
        bridge = js[js.index("if (BRIDGE) {"):js.index("window.showSaveFilePicker")]
        assert "flash(T.srtSaved, ((r && r.path) || fname) + mergeNote);" in bridge
        assert "T.srtSaved + ' ('" not in bridge
        assert "flash(T.srtError + ' ' + e);" in bridge
        # flash: the tooltip lives as long as the message, then both go back
        flash = js[js.index("function flash(msg, tip){"):js.index("async function exportSrt()")]
        assert "n.title = tip || '';" in flash and "n.title='';" in flash
        assert "n.textContent=T.saved;" in flash
        # anything longer than the short message (file name, error) wraps as before
        assert "n.classList.toggle('long', msg !== T.srtSaved);" in flash
        assert "n.classList.remove('long');" in flash
        assert ".saved.long{flex:0 1 auto;white-space:normal}" in css
        # in a browser nothing changes: the file name stays in the message
        browser = js[js.index("window.showSaveFilePicker"):js.index("function resetAll()")]
        assert "flash(T.srtSaved + ' (' + fname + ')' + mergeNote);" in browser
        assert "flash(T.srtDownloaded + ' (' + fname + ')' + mergeNote);" in browser
        # the look of the note is the 1.0 one
        assert "color:var(--ok);font-size:13px;margin-left:6px;opacity:0;transition:opacity .3s" in saved


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
    # every token of the template has a text in both languages, and the
    # markup tells the script where it goes (or the script sets it itself)
    by_script = {"SAVED", "SRT_SAVED", "HINT"}
    for key in it["html"]:
        assert f"__T_{key}__" in core._QC_TEMPLATE, key
        assert (f'data-i18n="{key}"' in core._QC_TEMPLATE
                or f'data-i18n-title="{key}"' in core._QC_TEMPLATE
                or key in by_script), key
