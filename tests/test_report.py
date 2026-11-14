"""
Review report (write_qc_html): the IT/EN texts must stay the ones of 1.0
even though the segment flags are now codes. The fixed segments below are
the same ones used to diff the reports before and after activity 1.2.
Since C2 (item 72) every report carries BOTH languages and picks one when
it opens (window.__subvisionLang, else the browser language); ui_lang only
prefills the markup.
Since C3 (report v2) the page has the look of the R1/R2 boards: report bar
as the sticky header of the summary box, legend fixed at the bottom, sign
box instead of the {\an8} tag, "Original" / "Remove" per row, manual rows
back at their time on reopen. The behaviours run in headless Chrome when
it is installed.
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


IT_TEXTS = ('"merged_fade": "unita da fade/typo"',
            '"too_short": "scartata: troppo breve"',
            '"noise": "scartata: probabile rumore grafico"',
            "righe <b>3</b> · da ricontrollare <b>1</b> · "
            "scartate (recuperabili) <b>2</b> · buchi oltre 6 s <b>1</b>",
            "330 fotogrammi · 120 letture OCR · 4 confini raffinati · 00:12",
            "Salva SRT revisionato", "unisci duplicati",
            '"addedFlag": "aggiunta a mano"',
            f"Generato con SubVision v{core.__version__}")
EN_TEXTS = ('"merged_fade": "merged across fade/typo"',
            '"too_short": "dropped: too short"',
            '"noise": "dropped: likely graphic noise"',
            "lines <b>3</b> · to re-check <b>1</b> · "
            "dropped (recoverable) <b>2</b> · gaps over 6 s <b>1</b>",
            "330 frames · 120 OCR readings · 4 boundaries refined · 00:12",
            "Save reviewed SRT", "merge duplicates",
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
        assert '<html lang="it">' in html and "<title>Revisione di video.mp4</title>" in html
    else:
        assert '<html lang="en">' in html and "<title>Review of video.mp4</title>" in html
    # ...but the texts of both languages are in every report ("</" is
    # written "<\\/" inside the JSON blocks)
    flat = html.replace("<\\/", "</")
    for text in IT_TEXTS + EN_TEXTS:
        assert text in flat, text
    i18n = _i18n_block(html)
    assert set(i18n) == {"it", "en"}
    for code in ("too_short", "noise", "merged_fade"):
        assert code in i18n["it"]["flags"] and code in i18n["en"]["flags"]
    assert i18n["it"]["html"]["TITLE"] == "Revisione di" and i18n["en"]["html"]["TITLE"] == "Review of"
    assert "righe <b>3</b>" in i18n["it"]["summary"] and "lines <b>3</b>" in i18n["en"]["summary"]
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
                  "getElementById('gapsTitle').textContent = T.gapsTitle"):
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
    for lang, err, hint in (("it", "Errore nel salvataggio:", "accanto all’originale"),
                            ("en", "Could not save:", "next to the original")):
        h = _fixed_report(tmp_path, lang)
        assert f'"srtError": "{err}"' in h
        assert '"hintApp": "' in h and hint in h
    # the browser hint says where the changes stay
    assert "Le modifiche restano in questo browser" in _fixed_report(tmp_path, "it")
    assert "Changes stay in this browser" in _fixed_report(tmp_path, "en")


def test_report_save_message_in_the_bar(tmp_path: Path):
    """
    After a save the report bar shows "Salvato: <file>" (green) in place of
    the counter for a few seconds (board R2); through the app the file name
    comes from the bridge's reply and the full path goes in the tooltip.
    """
    for lang, saved in (("it", "Salvato: {name}"), ("en", "Saved: {name}")):
        html = _fixed_report(tmp_path, lang)
        js = html.split("<script>", 1)[1]
        css = html.split("<style>", 1)[1].split("</style>", 1)[0]
        assert f'"savedAs": "{saved}"' in html
        assert '<span class="savedmsg" id="savedNote" role="status"></span>' in html
        assert ".rhead.flash #counter{display:none}" in css
        assert ".rhead.flash .savedmsg{display:inline-flex}" in css
        assert "color:var(--ok)" in re.search(r"\.savedmsg\{([^}]*)\}", css).group(1)
        bridge = js[js.index("if (BRIDGE) {"):js.index("window.showSaveFilePicker")]
        assert "flash(savedHtml('savedAs', (r && r.name) || fname), ((r && r.path) || fname) + mergeNote);" in bridge
        assert "flash(esc(T.srtError + ' ' + e), '', true);" in bridge
        browser = js[js.index("window.showSaveFilePicker"):js.index("async function askReset()")]
        assert "flash(savedHtml('savedAs', h.name || fname) + esc(mergeNote));" in browser
        assert "flash(savedHtml('srtDownloaded', fname) + esc(mergeNote));" in browser


def test_report_layout_app_and_browser(tmp_path: Path):
    """
    In the app the page starts with the summary box (the title band is
    native); in a browser a plain title comes first. The report bar is the
    sticky header of the summary box, the column is 1180 px at most, the
    legend is fixed at the bottom. No emoji anywhere in the texts.
    """
    html = _fixed_report(tmp_path, "it")
    head = html.split("<style>", 1)[0]
    css = html.split("<style>", 1)[1].split("</style>", 1)[0]
    body = html.split("</style>", 1)[1].split('<script type="application/json"', 1)[0]
    # app mode decided before the first paint, from the message handler
    assert '<script id="appmode">' in head and "messageHandlers.subvision" in head
    assert "classList.add('app')" in head
    assert "html.app .ptitle{display:none}" in css
    assert '<h1 class="ptitle"><span data-i18n="TITLE">Revisione di</span> <b>video.mp4</b></h1>' in body
    # no back button, Finder or browser buttons in the page
    for gone in ("Finder", "Apri nel browser", "‹", "Torna"):
        assert gone not in body, gone
    # sticky bar: header of the summary box, as wide as the column
    assert ".rhead{position:sticky;top:0;z-index:5}" in css
    assert ".wrap{max-width:1236px;margin:0 auto;padding:16px 28px 72px}" in css   # 1180 + 2 × 28
    bar = body[body.index('<div class="rhead" id="rhead">'):body.index('<div class="rsum">')]
    for piece in ('id="counter"', 'id="mergeOnSave"', 'onclick="resetAll()"', "Ripristina tutto…",
                  'class="btn pri" onclick="exportSrt()"', "Salva SRT revisionato"):
        assert piece in bar, piece
    # legend fixed at the bottom, with the exact texts
    assert ".legend{position:fixed;left:0;right:0;bottom:0;height:34px" in css
    legend = body[body.index('<div class="legend"'):]
    for text in ("da ricontrollare", "molto dubbio o scartato", "aggiunta a mano",
                 '<span class="hl" data-i18n="LEG_WORD">parola</span>',
                 "dove la lettura alternativa è diversa",
                 "<b>98 %</b> confidenza dell’OCR · accordo = tra le letture dei diversi "
                 "fotogrammi limitrofi analizzati"):
        assert text in legend, text
    en = core._QC_I18N["en"]["html"]["LEG_CONF"]
    assert en.startswith("<b>98%</b> OCR confidence · agreement = ")
    # no emoji left in the strings of either language
    emoji = re.compile("[\U0001F300-\U0001FAFF☀-➿⭐⭕]")
    for lang in ("it", "en"):
        for section in ("html", "js", "flags"):
            for key, val in core._QC_I18N[lang][section].items():
                assert not emoji.search(val), (lang, key, val)
    # section titles
    it = core._QC_I18N["it"]
    assert it["html"]["DROPPED_H"] == "Scartate"
    assert it["html"]["DROPPED_SUB"] == "flash brevi o rumore · spunta per rimetterle nell’SRT"
    assert it["js"]["gapsTitle"] == "Buchi senza sottotitoli oltre {n} s"
    assert it["html"]["GAPS_SUB"] == "possibili righe saltate"
    assert it["js"]["addHere"] == "+ Aggiungi una riga qui"
    assert it["html"]["ADDROW"] == "+ Aggiungi riga"


def test_report_no_an8_in_the_interface():
    """{\\an8} is written in the SRT only: never in a text of the page."""
    for lang in ("it", "en"):
        for section in ("html", "js", "flags"):
            for key, val in core._QC_I18N[lang][section].items():
                assert "an8" not in val, (lang, key)
    markup = core._QC_TEMPLATE.split("<script>", 1)[0]
    assert "an8" not in markup.split("<style>", 1)[1].split("</style>", 1)[1]
    assert core._QC_I18N["it"]["js"]["sign"] == "È un cartello (va in alto)"


def test_report_reset_question_texts():
    it, en = core._QC_I18N["it"]["js"], core._QC_I18N["en"]["js"]
    assert it["resetTitle"] == "Ripristinare tutto il report?"
    assert it["resetText"] == ("Perderai tutte le modifiche fatte in questo report: testi corretti, "
                               "letture scelte, tempi, spunte, cartelli e righe aggiunte a mano. "
                               "Gli SRT revisionati già salvati non cambiano.")
    assert (it["resetConfirm"], it["resetCancel"]) == ("Ripristina tutto", "Annulla")
    assert en["resetTitle"] and en["resetText"] and (en["resetConfirm"], en["resetCancel"]) == ("Reset all", "Cancel")
    js = core._QC_TEMPLATE.split("<script>", 1)[1]
    ask = js[js.index("async function askReset(){"):js.index("async function resetAll(){")]
    # the app gets title, text and buttons; anything else: confirm() with title, blank line, text
    assert ("BRIDGE.postMessage({type:'confirm', title: T.resetTitle,\n"
            "        text: T.resetText, confirm: T.resetConfirm, cancel: T.resetCancel, destructive: true})") in ask
    assert "if (r && typeof r.confirmed === 'boolean') return r.confirmed;" in ask
    assert "return confirm(T.resetTitle + '\\n\\n' + T.resetText);" in ask
    assert "if(!(await askReset())) return;" in js


def test_report_light_and_dark_palettes(tmp_path: Path):
    html = _fixed_report(tmp_path, "it")
    css = html.split("<style>", 1)[1].split("</style>", 1)[0]
    assert "color-scheme:light dark" in css
    assert "@media (prefers-color-scheme: light)" in css
    dark, light = css.split("@media (prefers-color-scheme: light)")
    # every variable of the dark palette has a light value
    names = set(re.findall(r"--([a-z0-9-]+):", dark.split("}")[0]))
    assert names and names == set(re.findall(r"--([a-z0-9-]+):", light.split("}")[0]))
    # the app's tokens: cyan accent in the dark, blue in the light
    assert "--bg:#101113" in dark and "--fg:#E8EAED" in dark and "--accent:#2AC9DE" in dark
    assert "--bg:#F6F7F9" in light and "--fg:#16181B" in light and "--accent:#0275B6" in light
    # no hard-coded colour left in the markup (legend swatches use classes)
    body = html.split("</style>", 1)[1].split("<script", 1)[0]
    assert 'style="background:#' not in body
    assert '<i class="sw warn"></i>' in body


def test_qc_i18n_languages_are_aligned():
    it, en = core._QC_I18N["it"], core._QC_I18N["en"]
    assert set(it) == set(en)
    for section in ("html", "js", "flags"):
        assert set(it[section]) == set(en[section]), section
    assert set(it["flags"]) == {core.FLAG_TOO_SHORT, core.FLAG_NOISE, core.FLAG_MERGED_FADE}
    # every token of the template has a text in both languages, and the
    # markup tells the script where it goes (or the script sets it itself)
    by_script = {"HINT"}
    for key in it["html"]:
        assert f"__T_{key}__" in core._QC_TEMPLATE, key
        assert (f'data-i18n="{key}"' in core._QC_TEMPLATE
                or f'data-i18n-title="{key}"' in core._QC_TEMPLATE
                or key in by_script), key


def test_report_rows_data(tmp_path: Path):
    """Dropped rows keep their number; gaps say whether they are at the start or the end."""
    data = _data_block(_fixed_report(tmp_path, "it"))
    assert [r["n"] for r in data["rows"]] == [1, 2, 3, 4, 5]
    assert data["gapWarn"] == OcrParams().qc_gap_warn
    assert [g["edge"] for g in data["gaps"]] == ["end"]          # 10-20 s, nothing after it
    segs = [SegInfo(4.0, 5.0, "a", conf=1, agree=1, nframes=3)]
    out = tmp_path / "edges.review.html"
    core.write_qc_html(out, "v.mp4", "v.srt", segs, [], [(0.0, 4.0, ""), (5.0, 9.0, "")],
                       RunStats(), OcrParams(), ui_lang="it")
    assert [g["edge"] for g in _data_block(out.read_text())["gaps"]] == ["start", "end"]
    segs.append(SegInfo(12.0, 13.0, "b", conf=1, agree=1, nframes=3))
    core.write_qc_html(out, "v.mp4", "v.srt", segs, [], [(5.0, 12.0, "")],
                       RunStats(), OcrParams(), ui_lang="it")
    assert [g["edge"] for g in _data_block(out.read_text())["gaps"]] == [""]
