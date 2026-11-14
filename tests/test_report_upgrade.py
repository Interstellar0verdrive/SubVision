"""
Old review reports shown with the current template (report_upgrade.py).
The fixtures in fixtures/old-reports are written by the old engines' own
write_qc_html (v1.0.0 and two 2.0 builds before report v2) from synthetic
data: make_fixtures.py there rebuilds them. The copy goes to the state
folder, never next to the original, and keeps the row ids, so the review
state saved for the old report applies to it (checked in headless Chrome
when it is installed: the SRT of the old page and of the copy, with the
same saved state, are the same).
"""

from __future__ import annotations

import json
import os
import shutil
from pathlib import Path

import pytest

from subvision import core, report_upgrade
from subvision.core import EngineError

from test_report import _data_block, _i18n_block, _run_in_chrome, needs_chrome

FIXTURES = Path(__file__).parent / "fixtures" / "old-reports"
OLD = {
    "old-1.0-it.revisione.html": ("1.x", "it", "clip-a.mp4", "clip-a.srt"),
    "old-1.0-en.revisione.html": ("1.x", "en", "clip-b.mp4", "clip-b.srt"),
    "old-2.0-early.revisione.html": ("2.0", "it", "clip-c.mkv", "clip-c_20261113_224348.srt"),
    "old-2.0-bilingual.review.html": ("2.0", "it", "clip-c.mkv", "clip-c_20261113_224348.srt"),
}


@pytest.fixture
def videos(tmp_path: Path) -> Path:
    """A folder with copies of the fixtures (the tests check nothing is written next to them)."""
    d = tmp_path / "videos"
    d.mkdir()
    for name in OLD:
        shutil.copy2(FIXTURES / name, d / name)
    return d


def _listing(folder: Path) -> dict:
    return {p.name: (p.stat().st_size, p.stat().st_mtime_ns) for p in folder.iterdir()}


def _old_data(path: Path) -> dict:
    return report_upgrade.read_data(path.read_text(encoding="utf-8"), path)


def test_fixtures_are_old_reports():
    for name in OLD:
        html = (FIXTURES / name).read_text(encoding="utf-8")
        assert report_upgrade.report_version(html) == 0, name
        assert 'class="legend" role="note"' not in html, name


@pytest.mark.parametrize("name", list(OLD))
def test_upgrade_old_report(tmp_path: Path, videos: Path, name: str):
    source, lang, video, srt = OLD[name]
    original = videos / name
    before = _listing(videos)
    old_bytes = original.read_bytes()
    state = tmp_path / "state"
    res = report_upgrade.upgrade_report(original, state)
    # the copy is in the state folder, with the original's name; nothing changed next to it
    out = Path(res["path"])
    assert res["current"] is False and res["cached"] is False and res["source"] == source
    assert out.parent.parent == state / "tmp" / "reports" and out.name == name
    assert _listing(videos) == before and original.read_bytes() == old_bytes
    html = out.read_text(encoding="utf-8")
    # current template: marker, legend, both languages, the app's language switch
    assert report_upgrade.report_version(html) == core.REPORT_VERSION
    assert '<div class="legend" role="note">' in html and "window.__subvisionSetLang" in html
    assert f'<html lang="{lang}">' in html
    texts = _i18n_block(html)
    assert set(texts) == {"it", "en"}
    # the data: same ids, same order, flags as codes, numbers instead of the scissors
    old = _old_data(original)
    data = _data_block(html)
    assert data["videoName"] == video and data["srtName"] == srt
    assert [r["id"] for r in data["rows"]] == [r["id"] for r in old["rows"]]
    assert [r["text"] for r in data["rows"]] == [r["text"] for r in old["rows"]]
    assert [r["n"] for r in data["rows"]] == [1, 2, 3, 4, 5, 6]
    assert [r["dropped"] for r in data["rows"]] == [False] * 4 + [True] * 2
    assert [r["flags"] for r in data["rows"]] == [[], [core.FLAG_MERGED_FADE], [], [],
                                                 [core.FLAG_TOO_SHORT], [core.FLAG_NOISE]]
    assert [r["top"] for r in data["rows"]] == [False, False, True, False, False, False]
    assert [r["cls"] for r in data["rows"]] == ["", "warn", "", "bad", "bad", "bad"]
    assert data["rows"][1]["alts"] == ["Where are you goinq?", "Wh ere are you going?"]
    assert all(r["thumb"] for r in data["rows"])
    # gaps: the last one has no line after it (end of the video); the threshold is the default
    assert [(g["start"], g["end"], g["edge"]) for g in data["gaps"]] == [(7.0, 20.0, ""), (22.5, 40.0, "end")]
    assert data["gapWarn"] == core.OcrParams().qc_gap_warn
    # the summary in both languages, with the run figures read from the old one
    assert ("righe <b>4</b> · da ricontrollare <b>2</b> · scartate (recuperabili) <b>2</b> · "
            "buchi oltre 6 s <b>2</b> · 480 fotogrammi · 900 letture OCR · 6 confini raffinati · 01:16"
            in texts["it"]["summary"])
    assert ("lines <b>4</b> · to re-check <b>2</b> · dropped (recoverable) <b>2</b> · "
            "gaps over 6 s <b>2</b> · 480 frames · 900 OCR readings · 6 boundaries refined · 01:16"
            in texts["en"]["summary"])


def test_upgrade_is_cached_and_follows_the_file(tmp_path: Path, videos: Path):
    original = videos / "old-1.0-it.revisione.html"
    state = tmp_path / "state"
    first = report_upgrade.upgrade_report(original, state)
    again = report_upgrade.upgrade_report(original, state)
    assert again["cached"] is True and again["path"] == first["path"]
    # the report changed (another date): another copy
    st = original.stat()
    os.utime(original, ns=(st.st_atime_ns, st.st_mtime_ns + 5_000_000_000))
    changed = report_upgrade.upgrade_report(original, state)
    assert changed["cached"] is False and changed["path"] != first["path"]
    # copies not used for a month go at start-up
    old_dir = Path(first["path"]).parent
    os.utime(old_dir, (1, 1))
    assert report_upgrade.clean_old(state) == 1
    assert not old_dir.exists() and Path(changed["path"]).is_file()


def test_current_report_is_left_as_it_is(tmp_path: Path):
    segs = [core.SegInfo(1.0, 2.0, "Ciao", thumb="AAA")]
    path = tmp_path / "v.review.html"
    core.write_qc_html(path, "v.mp4", "v.srt", segs, [], [], core.RunStats(), core.OcrParams())
    res = report_upgrade.upgrade_report(path, tmp_path / "state")
    assert res == {"path": str(path), "current": True}
    assert not (tmp_path / "state" / "tmp" / "reports").exists()


def test_errors(tmp_path: Path):
    with pytest.raises(EngineError) as exc:
        report_upgrade.upgrade_report(tmp_path / "missing.review.html", tmp_path / "state")
    assert exc.value.code == "not_found"
    cases = {
        "page.html": "<html><body>not a report</body></html>",
        "badjson.review.html": '<script type="application/json" id="qcdata">{rows: [</script>',
        "norows.review.html": '<script type="application/json" id="qcdata">{"srtName": "a.srt"}</script>',
    }
    for name, text in cases.items():
        (tmp_path / name).write_text(text, encoding="utf-8")
        with pytest.raises(EngineError) as exc:
            report_upgrade.upgrade_report(tmp_path / name, tmp_path / "state")
        assert exc.value.code == "report_unreadable", name
        assert exc.value.details()["path"] == str(tmp_path / name) and exc.value.details()["detail"]
    (tmp_path / "binary.review.html").write_bytes(b"\xff\xfe\x00qcdata")
    with pytest.raises(EngineError) as exc:
        report_upgrade.upgrade_report(tmp_path / "binary.review.html", tmp_path / "state")
    assert exc.value.code == "report_unreadable"


def test_sparse_old_data(tmp_path: Path):
    """What some old data may lack: names, cls, n, the sign flag (an {\\an8} in the text), the summary."""
    data = {"rows": [
        {"id": "s1", "start": 5.0, "end": 6.0, "text": "{\\an8}CARTELLO", "conf": 0.9, "agree": 0.9},
        {"id": "s2", "start": 6.5, "end": 7.0, "text": "Ciao", "conf": 0.75, "agree": 1.0,
         "alts": ["{\\an8}Ciao!"], "flags": ["dropped: too short"], "n": "✂", "dropped": True},
        {"start": 14.0, "end": 15.0, "text": "Senza id"},
        "not a row",
    ], "gaps": [{"start": 0.0, "end": 5.0}, {"start": 6.0, "end": 10.3, "thumb": "GGG"}, {"start": "x"}]}
    path = tmp_path / "Episode 3.revisione.html"
    path.write_text('<html lang="it"><body><script type="application/json" id="qcdata">'
                    + json.dumps(data) + "</script></body></html>", encoding="utf-8")
    res = report_upgrade.upgrade_report(path, tmp_path / "state")
    html = Path(res["path"]).read_text(encoding="utf-8")
    out = _data_block(html)
    assert out["videoName"] == "Episode 3" and out["srtName"] == "Episode 3.srt"
    assert [r["id"] for r in out["rows"]] == ["s1", "s2", "s3"]
    s1, s2, s3 = out["rows"]
    assert s1["text"] == "CARTELLO" and s1["top"] is True and s1["cls"] == ""
    assert s2["alts"] == ["Ciao!"] and s2["top"] is False and s2["flags"] == [core.FLAG_TOO_SHORT]
    assert s2["cls"] == "bad" and s2["n"] == 2
    assert s3["conf"] is None and s3["cls"] == "" and s3["thumb"] == ""
    # a gap of 4.3 s: that run's threshold was lower than the default 6 s
    assert [g["edge"] for g in out["gaps"]] == ["start", ""] and out["gapWarn"] == 4.0
    summary = _i18n_block(html)["it"]["summary"]
    assert summary.endswith("buchi oltre 4 s <b>2</b>") and "fotogrammi" not in summary
    assert res["source"] == "1.x"


def _state_head(old_html: str, state: dict) -> str:
    """The saved state as every report reads it: localStorage (1.x) and window.__subvisionState (2.0)."""
    srt = json.loads(old_html.split('id="qcdata">', 1)[1].split("</script>", 1)[0])["srtName"]
    js = json.dumps(state)
    return ("<script>try { localStorage.setItem(" + json.dumps("voc26_rev_" + srt) + ", " + json.dumps(js)
            + "); } catch (e) {}\nwindow.__subvisionState = " + js + ";</script>")


SAVED = {
    "s1": {"text": "Hello there, Mira!"},                 # an edit
    "s2": {"included": False},                            # left out
    "s3": {"top": False},                                 # not a sign after all
    "s5": {"included": True, "text": "x-ray"},            # a dropped line put back
    "new1794664414631_1": {"text": "Added by hand", "start": 30.0, "end": 32.0,
                           "included": True, "added": True},
}


@needs_chrome
@pytest.mark.parametrize("name", list(OLD))
def test_saved_state_applies_to_the_copy(tmp_path: Path, videos: Path, name: str):
    """The same `.review.json` gives the same SRT in the old page and in the upgraded copy."""
    original = videos / name
    old_html = original.read_text(encoding="utf-8")
    new_html = Path(report_upgrade.upgrade_report(original, tmp_path / "state")["path"]).read_text(encoding="utf-8")
    probe = "document.getElementById('mergeOnSave').checked = false; return {srt: buildSrt()};"
    head = _state_head(old_html, SAVED)
    for sub in ("old", "new", "page"):
        (tmp_path / sub).mkdir()
    old = _run_in_chrome(tmp_path / "old", old_html, head, probe)
    new = _run_in_chrome(tmp_path / "new", new_html, head, probe)
    assert new["srt"] == old["srt"]
    assert "Hello there, Mira!" in new["srt"] and "Where are you going?" not in new["srt"]
    assert "NORTH GATE" in new["srt"] and "{\\an8}" not in new["srt"]
    assert "x-ray" in new["srt"] and "Added by hand" in new["srt"]
    # and on the page: the edit in its box, the row added by hand among the others at its time
    out = _run_in_chrome(tmp_path / "page", new_html, head, """
      const rows = [...document.querySelectorAll('#rows .row')];
      return {ids: rows.map(r => r.dataset.id), s1: document.querySelector('.row[data-id="s1"] textarea').value,
              legend: getComputedStyle(document.querySelector('.legend')).position};
    """)
    assert out["ids"] == ["s1", "s2", "s3", "s4", "new1794664414631_1"]
    assert out["s1"] == "Hello there, Mira!" and out["legend"] == "fixed"
