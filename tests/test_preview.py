"""
Tests of the preview module on the demo clips (frames and OCR test).

The tests on the frames of the user's video (C2, items 77 and 78) read the
folder named by the SUBVISION_USER_FRAMES environment variable and are
skipped when it is unset or the files are missing: those frames are
private and never go in the repo.
"""

from __future__ import annotations

import os
import subprocess
import threading
import time
from pathlib import Path

import pytest
from PIL import Image

from subvision import core, preview
from subvision.core import OcrParams

from conftest import FAST_PROFILE


def _ffmpeg_processes(needle: str) -> list[str]:
    out = subprocess.run(["ps", "-axo", "command"], capture_output=True, text=True).stdout
    return [ln for ln in out.splitlines() if "ffmpeg" in ln and needle in ln]


@pytest.fixture
def params() -> OcrParams:
    return OcrParams(**FAST_PROFILE)


@pytest.fixture
def vision() -> None:
    if not core.vision_available():
        pytest.skip("Apple Vision (ocrmac) not available")


# ---------------------------------------------------------------- folders
def test_preview_dir_depends_on_path_and_mtime(tmp_path: Path) -> None:
    v = tmp_path / "a.mp4"
    v.write_bytes(b"x" * 10)
    d1 = preview.preview_dir(v, tmp_path)
    assert d1.parent == tmp_path / "tmp" / "preview" and len(d1.name) == 16
    assert preview.preview_dir(v, tmp_path) == d1
    os.utime(v, (1_000_000, 1_000_000))
    assert preview.preview_dir(v, tmp_path) != d1


def test_clean_old_removes_week_old_folders(tmp_path: Path) -> None:
    root = tmp_path / "tmp" / "preview"
    old, fresh = root / "old", root / "fresh"
    old.mkdir(parents=True)
    fresh.mkdir()
    (old / "000.jpg").write_bytes(b"")
    past = time.time() - 8 * 86400
    os.utime(old, (past, past))
    assert preview.clean_old(tmp_path) == 1
    assert not old.exists() and fresh.exists()
    assert preview.clean_old(tmp_path) == 0
    assert preview.clean_old(tmp_path / "nowhere") == 0


# ---------------------------------------------------------------- quick "is there text?"
def test_looks_like_text() -> None:
    # what the quick OCR invents on the frames of the demo clips without
    # subtitles (confidence 0.5, like a real line): never "text"; digits and
    # punctuation are texture too (C2: two real LETTERS are needed)
    for junk in ("", " ", "r", "i", "I", "a", "*", "(", "-{", "?", "...", "- !", "\n",
                 "42", "4", "1 2", "3.", "+ &"):
        assert not preview.looks_like_text(junk), junk
    # real lines, short ones included
    for text in ("Un drago.", "So...", "Eh?", "No", "OK", "Sei sciocca\na viaggiare sola,",
                 "Grazie.", "A dragon.", "Sì.", "Да"):
        assert preview.looks_like_text(text), text
    # one ideograph, kana or hangul is a whole line
    for text in ("え", "嗯", "是", "네", "あ！"):
        assert preview.looks_like_text(text), text
    assert preview.QUICK_MIN_LETTERS == 2 and preview.QUICK_MIN_CONF == 0.3
    assert preview.CONFIRM_LEVEL == "accurate"


@pytest.mark.parametrize("clip_name, lang", [("ita", "Italian"), ("eng", "English")])
def test_find_frames_has_no_false_positive_on_the_demo(clip_name: str, lang: str, demo_ita: Path,
                                                       demo_eng: Path, tmp_path: Path,
                                                       ffmpeg_bin: str, vision) -> None:
    """
    F6: zone 4 of both demo clips (12-14 s) has no subtitle at any of the
    three timestamps tried, but the quick OCR reads "r" / "i" (confidence
    0.5) in the picture at 13.77 s: it used to count as a frame with text.
    Zone 15 (41-43 s) has no subtitle either. Every other zone that had
    text before still has it (no false negative): 18 of 20 on the ita clip.
    """
    clip = demo_ita if clip_name == "ita" else demo_eng
    p = OcrParams(**{**FAST_PROFILE, "lang_hint": lang})
    frames = preview.find_frames(clip, p, n=20, tries=3, state=tmp_path)
    assert len(frames) == 20
    flags = [f["has_text"] for f in frames]
    assert not flags[4] and frames[4]["bands"] == [], frames[4]
    assert 12.0 < frames[4]["ts"] < 14.0            # the fallback: the first timestamp tried
    assert not flags[15]
    without = [i for i, has in enumerate(flags) if not has]
    if clip_name == "ita":
        assert without == [4, 15], without
    else:
        # zone 8 of the eng clip ("So...", small and short): the quick OCR sees
        # nothing at all there, before and after this change
        assert set(without) <= {4, 8, 15}, without


# ---------------------------------------------------------------- frames + OCR test
def test_find_frames_and_test_frame(demo_ita: Path, params: OcrParams, tmp_path: Path,
                                    ffmpeg_bin: str, vision) -> None:
    events: list[dict] = []
    t0 = time.time()
    frames = preview.find_frames(demo_ita, params, n=20, tries=3,
                                 emit=lambda name, data: events.append((name, data)),
                                 state=tmp_path)
    elapsed = time.time() - t0
    assert len(frames) == 20
    with_text = [f for f in frames if f["has_text"]]
    assert len(with_text) >= 10, f"only {len(with_text)} frames with text in {elapsed:.1f}s"
    outdir = preview.preview_dir(demo_ita, tmp_path)
    assert [Path(f["path"]).name for f in frames] == [f"{i:03d}.jpg" for i in range(20)]
    assert sorted(p.name for p in outdir.iterdir()) == [f"{i:03d}.jpg" for i in range(20)]
    for f in frames:
        assert Path(f["path"]).is_file() and Path(f["path"]).parent == outdir
        assert f["width"] > 0 and f["height"] > 0
        assert f["bands"] in (["bottom"], [])        # no signs band in the fast profile
        assert f["has_text"] == bool(f["bands"])
        assert "band" not in f                         # the 1.x single field is gone
    ts = [f["ts"] for f in frames]
    assert ts == sorted(ts) and 0 < ts[0] < ts[-1] < 60
    # whole frames: the demo clip is landscape, the band would be much flatter
    assert frames[0]["width"] > frames[0]["height"]
    # progress: one event per zone, done growing to 20, found never above done
    assert [n for n, _ in events] == ["preview.progress"] * 20
    dones = [d["done"] for _, d in events]
    assert dones == list(range(1, 21))
    assert all(d["found"] <= d["done"] and d["total"] == 20 for _, d in events)
    assert events[-1][1]["found"] == len(with_text)
    assert all(d["found_top"] == 0 for _, d in events)

    # OCR test on a frame with text: raw and final text, time, no top band
    res = preview.test_frame(with_text[0]["path"], params, lists=([], []))
    bottom = res["bands"]["bottom"]
    assert set(res["bands"]) == {"bottom"}
    assert bottom["text"].strip() and bottom["final"].strip() and not bottom["empty"]
    assert 0 < bottom["conf"] <= 1 and 0 < bottom["agree"] <= 1
    assert bottom["ms"] > 0 and bottom["variants"] == 1
    # with the signs band and the variants on: the top band appears, {\an8} only with text
    p2 = OcrParams(**{**FAST_PROFILE, "top_band": True, "multi_variant": True})
    res2 = preview.test_frame(with_text[0]["path"], p2, lists=([], []))
    assert set(res2["bands"]) == {"bottom", "top"}
    assert res2["bands"]["bottom"]["variants"] == 3
    top = res2["bands"]["top"]
    assert top["empty"] == (not top["final"])
    if top["final"]:
        assert top["final"].startswith("{\\an8}")
    # a correction and the ignore list reach `final`
    word = bottom["final"].split()[0].strip(".,!?")
    res3 = preview.test_frame(with_text[0]["path"], params, lists=([], [(word, "XYZ")]))
    assert "XYZ" in res3["bands"]["bottom"]["final"]
    res4 = preview.test_frame(with_text[0]["path"], params, lists=([bottom["text"]], []))
    assert res4["bands"]["bottom"]["empty"] and res4["bands"]["bottom"]["text"] == bottom["text"]


def test_find_frames_signs_band_on_the_demo(demo_ita: Path, tmp_path: Path,
                                           ffmpeg_bin: str, vision) -> None:
    """
    C2 (item 78): with the signs band on, both bands are checked on every
    frame. The demo clips have no signs, but the quick OCR reads "Ji?" and
    "li?" in the top of the picture at 34 s and 37 s: the accurate
    confirmation (item 77) keeps them out, and the dialogue count is the
    same as with the band off.
    """
    events: list[dict] = []
    p = OcrParams(**{**FAST_PROFILE, "top_band": True})
    frames = preview.find_frames(demo_ita, p, n=20, tries=3, state=tmp_path,
                                 emit=lambda name, data: events.append(data))
    assert len(frames) == 20
    assert all(f["bands"] in (["bottom"], []) for f in frames), [f["bands"] for f in frames]
    assert [i for i, f in enumerate(frames) if not f["has_text"]] == [4, 15]
    assert events[-1] == {"done": 20, "total": 20, "found": 18, "found_top": 0}


def test_zone_choice_prefers_both_bands(demo_ita: Path, tmp_path: Path, ffmpeg_bin: str,
                                        vision, monkeypatch) -> None:
    """
    The choice of a zone's frame, with scripted readings (one worker, so the
    zones and their timestamps are probed in order): text in both bands
    wins; otherwise the first with text, dialogue before signs only; the
    accurate confirmation runs only where it can change the choice.
    """
    monkeypatch.setattr(preview, "OCR_WORKERS", 1)
    quick_script: list[list[str]] = []
    confirm_script: list[bool] = []
    confirm_calls: list[str] = []

    def fake_quick(image, params, langs):
        return quick_script.pop(0)

    def fake_confirm(image, params, langs, band):
        confirm_calls.append(band)
        return confirm_script.pop(0)

    monkeypatch.setattr(preview, "quick_bands", fake_quick)
    monkeypatch.setattr(preview, "confirm_band", fake_confirm)
    p = OcrParams(**{**FAST_PROFILE, "top_band": True})
    # zone 0: dialogue at 0.5 (confirmed), dialogue at 0.2 (no confirmation
    #         needed), both at 0.8 (confirmed) -> the 0.8 frame, both bands
    # zone 1: signs at 0.5 (confirmed), dialogue at 0.2 (NOT confirmed),
    #         nothing at 0.8 -> the 0.5 frame, signs only
    quick_script[:] = [["bottom"], ["bottom"], ["bottom", "top"],
                       ["top"], ["bottom"], []]
    confirm_script[:] = [True, True, True,
                         True, False]
    events: list[dict] = []
    frames = preview.find_frames(demo_ita, p, n=2, tries=3, state=tmp_path,
                                 emit=lambda name, data: events.append(data))
    assert not quick_script and not confirm_script
    assert confirm_calls == ["bottom", "bottom", "top", "top", "bottom"]
    z0, z1 = frames
    assert z0["bands"] == ["bottom", "top"] and z0["has_text"]
    assert z1["bands"] == ["top"] and z1["has_text"]
    dur = core.ffprobe_duration(str(demo_ita))
    lo, hi = dur * 0.02, dur * 0.98
    step = (hi - lo) / 2
    assert z0["ts"] == pytest.approx(lo + step * 0.8, abs=0.002)
    assert z1["ts"] == pytest.approx(lo + step + step * 0.5, abs=0.002)
    assert events[-1] == {"done": 2, "total": 2, "found": 2, "found_top": 2}

    # signs band off: only the dialogue band, the first confirmed one wins
    # (the third timestamp is never probed); nothing confirmed -> fallback
    confirm_calls.clear()
    p_off = OcrParams(**{**FAST_PROFILE, "top_band": False})
    quick_script[:] = [["bottom"], ["bottom"],
                       ["bottom"], [], []]
    confirm_script[:] = [False, True,
                         False]
    frames = preview.find_frames(demo_ita, p_off, n=2, tries=3, state=tmp_path)
    assert not quick_script and not confirm_script
    assert [f["bands"] for f in frames] == [["bottom"], []]
    assert frames[0]["ts"] == pytest.approx(lo + step * 0.2, abs=0.002)
    assert frames[1]["ts"] == pytest.approx(lo + step + step * 0.5, abs=0.002)   # first grabbed
    assert not frames[1]["has_text"]


# ---------------------------------------------------------------- the user's frames (C2)
USER_FRAMES_ENV = "SUBVISION_USER_FRAMES"


def _user_frame(name: str) -> Image.Image:
    folder = os.environ.get(USER_FRAMES_ENV, "").strip()
    if not folder:
        pytest.skip(f"{USER_FRAMES_ENV} not set")
    path = Path(folder).expanduser() / name
    if not path.is_file():
        pytest.skip(f"missing {path}")
    return Image.open(path).convert("RGB")


@pytest.mark.parametrize("lang_hint", ["Italian", "it-IT"])
def test_user_frame_busy_scene_has_no_text(lang_hint: str, vision) -> None:
    """
    _test-1.mkv, frame 6 of 20 (17.77 s): a busy anime scene, no text. The
    quick OCR reads "I'ii" (confidence 0.3) in the dialogue band; the
    accurate confirmation reads nothing, so no band has text.
    """
    im = _user_frame("test1-no-text.jpg")
    p = OcrParams(lang_hint=lang_hint)                 # defaults: signs band on
    assert p.top_band
    assert preview.probe_bands(im, p, core.resolve_langs(p.lang_hint)) == []


@pytest.mark.parametrize("lang_hint", ["Italian", "it-IT"])
def test_user_frame_sign_and_dialogue(lang_hint: str, vision) -> None:
    """
    _test-1.mkv, frame 9 of 20 (26.78 s): "Nota: Borscht = minestra a base
    di barbabietola" at the top and "Borscht?" at the bottom: both bands
    with the signs band on, the dialogue only with it off.
    """
    im = _user_frame("test1-sign-and-dialogue.jpg")
    p = OcrParams(lang_hint=lang_hint)
    langs = core.resolve_langs(p.lang_hint)
    assert preview.probe_bands(im, p, langs) == ["bottom", "top"]
    p_off = OcrParams(lang_hint=lang_hint, top_band=False)
    assert preview.probe_bands(im, p_off, langs) == ["bottom"]


def test_find_frames_invalid_video(tmp_path: Path, params: OcrParams, ffmpeg_bin: str) -> None:
    bad = tmp_path / "bad.mp4"
    bad.write_bytes(b"not a video")
    with pytest.raises(core.EngineError) as exc:
        preview.find_frames(bad, params, n=4, state=tmp_path)
    assert exc.value.code == "invalid_duration"


def test_stop_midway_leaves_no_ffmpeg(demo_ita_copy: Path, params: OcrParams,
                                      tmp_path: Path, ffmpeg_bin: str, vision) -> None:
    stop = threading.Event()
    events: list[dict] = []

    def emit(name: str, data: dict) -> None:
        events.append(data)
        stop.set()                 # stop at the first completed zone

    t0 = time.time()
    with pytest.raises(preview.Stopped):
        preview.find_frames(demo_ita_copy, params, n=20, tries=3, emit=emit,
                            stop=stop, state=tmp_path)
    after = time.time() - t0
    assert events and events[0]["done"] == 1
    assert len(events) < 20
    assert _ffmpeg_processes(demo_ita_copy.name) == []
    time.sleep(0.5)
    assert _ffmpeg_processes(demo_ita_copy.name) == []
    assert after < 15, f"stop took {after:.1f}s"
    # no half-made files (NNN_k.jpg) are left behind
    outdir = preview.preview_dir(demo_ita_copy, tmp_path)
    assert all("_" not in p.name for p in outdir.iterdir())


def test_stop_during_ffmpeg(demo_ita_copy: Path, tmp_path: Path, ffmpeg_bin: str) -> None:
    """_run_ffmpeg terminates the child when the event is set while it runs."""
    stop = threading.Event()
    out = tmp_path / "slow.mp4"
    # a full re-encode of the clip takes a few seconds: enough to stop it
    cmd = ["ffmpeg", "-hide_banner", "-nostats", "-y", "-i", str(demo_ita_copy),
           "-vf", "scale=iw*2:ih*2", "-c:v", "libx264", "-preset", "veryslow", str(out)]
    threading.Timer(0.5, stop.set).start()
    t0 = time.time()
    with pytest.raises(preview.Stopped):
        preview._run_ffmpeg(cmd, stop, poll=0.05)
    assert time.time() - t0 < 5
    assert _ffmpeg_processes(demo_ita_copy.name) == []
