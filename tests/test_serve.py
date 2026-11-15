"""
The sidecar (activity 1.8) through its pipes: `python -m subvision.serve`
with a private state folder (SUBVISION_STATO) and the ffmpeg of the tests
passed through SUBVISION_FFMPEG. One process for the main flow (module
fixture), short-lived ones for EOF and shutdown.
"""

from __future__ import annotations

import json
import os
import queue
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

import pytest

from subvision import core

from conftest import FAST_PROFILE, FAST_PROFILE_LINES, damage_head, damage_tail

PARAMS = {k: v for k, v in FAST_PROFILE.items()}


class Sidecar:
    """A tiny client: requests with ids, replies matched by id, events queued."""

    def __init__(self, state: Path, ffmpeg: str) -> None:
        env = {**os.environ, "SUBVISION_STATO": str(state), "SUBVISION_FFMPEG": ffmpeg}
        self.proc = subprocess.Popen([sys.executable, "-m", "subvision.serve"],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, text=True, env=env, bufsize=1)
        self.replies: dict[int, dict] = {}
        self.events: list[tuple[str, dict]] = []
        self.new_event = threading.Condition()
        self.reply_cv = threading.Condition()
        self.stderr: list[str] = []
        self.next_id = 0
        threading.Thread(target=self._reader, daemon=True).start()
        threading.Thread(target=self._stderr, daemon=True).start()

    def _reader(self) -> None:
        for line in self.proc.stdout:
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            if "event" in obj:
                with self.new_event:
                    self.events.append((obj["event"], obj.get("data") or {}))
                    self.new_event.notify_all()
            else:
                with self.reply_cv:
                    self.replies[obj.get("id")] = obj
                    self.reply_cv.notify_all()

    def _stderr(self) -> None:
        for line in self.proc.stderr:
            self.stderr.append(line.rstrip())

    def send_raw(self, text: str) -> None:
        self.proc.stdin.write(text + "\n")
        self.proc.stdin.flush()

    def call(self, method: str, params: dict | None = None, timeout: float = 30) -> dict:
        self.next_id += 1
        ident = self.next_id
        self.send_raw(json.dumps({"id": ident, "method": method, "params": params or {}}))
        deadline = time.monotonic() + timeout
        with self.reply_cv:
            while ident not in self.replies:
                left = deadline - time.monotonic()
                assert left > 0, f"no reply to {method} within {timeout}s; stderr: {self.stderr[-5:]}"
                self.reply_cv.wait(left)
            reply = self.replies.pop(ident)
        if "error" in reply:
            raise SidecarError(reply["error"])
        return reply["result"]

    def wait_event(self, name: str, timeout: float = 60, since: int = 0) -> tuple[int, dict]:
        """(index, data) of the first event `name` at index >= since."""
        deadline = time.monotonic() + timeout
        with self.new_event:
            while True:
                for i in range(since, len(self.events)):
                    if self.events[i][0] == name:
                        return i, self.events[i][1]
                left = deadline - time.monotonic()
                assert left > 0, f"event {name} not seen within {timeout}s; last: {self.events[-3:]}"
                self.new_event.wait(left)

    def close(self) -> None:
        try:
            self.proc.stdin.close()
        except OSError:
            pass
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()


class SidecarError(Exception):
    def __init__(self, error: dict) -> None:
        super().__init__(f"{error.get('code')}: {error.get('message', '')}")
        self.code = error.get("code")
        self.error = error
        self.data = error.get("data")


def _bad(sidecar: "Sidecar", method: str, params: dict) -> dict:
    """The error object of a call that must be refused as bad_params about one field."""
    with pytest.raises(SidecarError) as exc:
        sidecar.call(method, params)
    err = exc.value.error
    assert err["code"] == "bad_params", err
    assert set(err["data"]) == {"field", "reason"} and err["data"]["reason"], err
    assert err["message"] == f"{err['data']['field']}: {err['data']['reason']}", err
    return err


def _ffmpeg_on(clip_name: str) -> list[str]:
    out = subprocess.run(["pgrep", "-fl", "ffmpeg|ffprobe"], capture_output=True, text=True).stdout
    return [ln for ln in out.splitlines() if clip_name in ln]


# ---------------------------------------------------------------- fixtures
@pytest.fixture(scope="module")
def work(tmp_path_factory, demo_ita, demo_eng, ffmpeg_bin) -> dict:
    if not core.vision_available():
        pytest.skip("Apple Vision (ocrmac) not available")
    root = tmp_path_factory.mktemp("serve")
    clips = []
    for src in (demo_ita, demo_eng):
        dst = root / "videos" / src.name
        dst.parent.mkdir(exist_ok=True)
        shutil.copyfile(src, dst)
        clips.append(dst)
    return {"root": root, "state": root / "state", "clips": clips, "ffmpeg": ffmpeg_bin}


@pytest.fixture(scope="module")
def sidecar(work) -> Sidecar:
    sc = Sidecar(work["state"], work["ffmpeg"])
    sc.wait_event("ready", timeout=30)
    yield sc
    sc.close()


# ---------------------------------------------------------------- tests (in order)
def test_hello(sidecar: Sidecar, work: dict):
    h = sidecar.call("hello")
    assert h["engine"] == "subvision" and h["protocol"] == 1
    assert h["version"] == core.__version__ and h["pid"] == sidecar.proc.pid
    assert h["vision"] is True and isinstance(h["livetext"], bool)
    assert h["languages"] and "it-IT" in h["languages"]
    assert h["ffmpeg"] and h["ffmpeg"]["path"] == work["ffmpeg"] and h["ffmpeg"]["version"]
    assert h["state_folder"] == str(work["state"])
    # the state folder exists with its subfolders and the two lists
    assert (work["state"] / "tmp" / "preview").is_dir()
    assert (work["state"] / "ignore.txt").is_file() and (work["state"] / "corrections.txt").is_file()


def test_non_json_line_is_ignored(sidecar: Sidecar):
    sidecar.send_raw("this is not json")
    sidecar.send_raw("")
    assert sidecar.call("hello")["engine"] == "subvision"
    assert any("not JSON" in ln for ln in sidecar.stderr)


def test_unknown_method_and_bad_request(sidecar: Sidecar):
    with pytest.raises(SidecarError) as exc:
        sidecar.call("nope")
    assert exc.value.code == "unknown_method"
    with pytest.raises(SidecarError) as exc:
        sidecar.call("videos.probe", {"paths": "x"})
    assert exc.value.code == "bad_params"
    assert exc.value.data == {"field": "paths", "reason": "must be a list of strings"}
    assert exc.value.error["message"] == "paths: must be a list of strings"


def test_tools_status_and_lists(sidecar: Sidecar, work: dict):
    st = sidecar.call("tools.status")
    assert set(st["tools"]) == {"ffmpeg", "ffprobe"} and st["active"]["path"] == work["ffmpeg"]
    assert st["custom"] == work["ffmpeg"]
    ls = sidecar.call("lists.status")
    assert set(ls) == {"ignore", "corrections"} and ls["ignore"]["count"] == 0
    extra = work["root"] / "my-ignore.txt"
    extra.write_text("Traduzione a cura di\n", encoding="utf-8")
    ls = sidecar.call("lists.import", {"kind": "ignore", "path": str(extra)})
    assert ls["ignore"]["count"] == 1
    with pytest.raises(SidecarError) as exc:
        sidecar.call("lists.import", {"kind": "ignore", "path": str(work["root"] / "missing.txt")})
    assert exc.value.code == "not_found"
    assert exc.value.error["path"] == str(work["root"] / "missing.txt") and exc.value.error["detail"]
    assert set(exc.value.error) <= {"code", "message", "detail", "tool", "path", "line"}


def test_tools_use(sidecar: Sidecar, work: dict):
    with pytest.raises(SidecarError) as exc:
        sidecar.call("tools.use", {"ffmpeg": str(work["root"] / "not-ffmpeg")})
    assert exc.value.code == "bad_tool"
    assert exc.value.error["tool"] == "ffmpeg" and exc.value.error["path"] == str(work["root"] / "not-ffmpeg")
    assert exc.value.error["detail"]
    res = sidecar.call("tools.use", {"ffmpeg": work["ffmpeg"]})
    assert res["ffmpeg"]["path"] == work["ffmpeg"]
    assert sidecar.call("hello")["ffmpeg"]["path"] == work["ffmpeg"]


def test_videos_probe(sidecar: Sidecar, work: dict):
    bogus = work["root"] / "bogus.mp4"
    bogus.write_bytes(b"nope")
    res = sidecar.call("videos.probe", {"paths": [str(c) for c in work["clips"]] + [str(bogus)]})
    vids = res["videos"]
    assert len(vids) == 3
    for v in vids[:2]:
        assert 50 < v["duration"] < 60 and v["fps"] > 20 and v["width"] > 0 and v["height"] > 0
        assert v["video_codec"] == "h264" and "error" not in v
    assert vids[2]["error"] == "probe_failed" and vids[2]["path"] == str(bogus)
    assert vids[2]["code"] == "probe_failed" and vids[2]["tool"] == "ffprobe" and vids[2]["detail"]


def test_videos_thumbs(sidecar: Sidecar, work: dict):
    """The five frames of the to-do drawer: taken once, then from the cache."""
    clip = work["clips"][0]
    res = sidecar.call("videos.thumbs", {"path": str(clip), "duration": 55.0})
    assert res["path"] == str(clip) and res["cached"] is False and len(res["frames"]) == 5
    assert all(Path(p).is_file() for p in res["frames"])
    assert str(work["state"] / "tmp" / "thumbs") in res["frames"][0]
    again = sidecar.call("videos.thumbs", {"path": str(clip)})
    assert again["cached"] is True and again["frames"] == res["frames"]
    bogus = work["root"] / "bogus-thumbs.mp4"
    bogus.write_bytes(b"nope")
    res = sidecar.call("videos.thumbs", {"path": str(bogus)})
    assert res["frames"] == [None] * 5 and res["error"] == "probe_failed"
    assert _bad(sidecar, "videos.thumbs", {})["data"]["field"] == "path"
    assert _bad(sidecar, "videos.thumbs", {"path": str(clip), "duration": "55"})["data"]["field"] == "duration"


def test_warmup(sidecar: Sidecar):
    res = sidecar.call("warmup", {"languages": ["it-IT", "en-US"]})
    assert res == {"started": True, "languages": ["it-IT"]}
    _, data = sidecar.wait_event("warmup.done", timeout=120)
    assert data["seconds"] >= 0 and data["languages"] == ["it-IT"]


def test_batch_start_and_stop(sidecar: Sidecar, work: dict):
    since = len(sidecar.events)
    res = sidecar.call("batch.start", {"videos": [str(c) for c in work["clips"]],
                                       "params": PARAMS, "lang": "it"})
    assert res == {"started": True}
    i, _ = sidecar.wait_event("batch.step", since=since)
    # during a batch the drawer's frames are not taken (busy), unless they are there already
    fresh = work["root"] / "videos" / "fresh-copy.mp4"
    shutil.copyfile(work["clips"][1], fresh)
    assert sidecar.call("videos.thumbs", {"path": str(fresh)}) == {"path": str(fresh), "busy": True}
    cached = sidecar.call("videos.thumbs", {"path": str(work["clips"][0])})
    assert cached["cached"] is True and len(cached["frames"]) == 5
    assert sidecar.call("batch.stop", {"scope": "all"}) == {"ok": True}
    j, done = sidecar.wait_event("batch.done", since=i, timeout=30)
    assert done["stopped"] >= 1 and done["done"] == 0 and done["skipped"] == 1
    names = [e for e, _ in sidecar.events[since:j + 1]]
    assert "batch.file.stopped" in names and "batch.file.failed" not in names
    time.sleep(0.3)
    assert _ffmpeg_on(work["clips"][0].name) == []
    assert not work["clips"][0].with_suffix(".srt").exists()
    assert not list((work["state"] / "tmp").glob("voc26_*"))
    assert sidecar.call("batch.stop", {"scope": "file"}) == {"ok": False, "reason": "no_batch"}
    # no batch: the same answer with `file`, which is checked first all the same
    assert sidecar.call("batch.stop", {"scope": "file", "file": 0}) == {"ok": False, "reason": "no_batch"}
    assert _bad(sidecar, "batch.stop", {"scope": "file", "file": 1.5})["data"]["field"] == "file"


def test_batch_stop_for_one_file(sidecar: Sidecar, work: dict):
    """F6: `file` names the video the stop is meant for (index or path)."""
    clips = [str(c) for c in work["clips"]]
    since = len(sidecar.events)
    assert sidecar.call("batch.start", {"videos": clips, "params": PARAMS, "lang": "en"}) == {"started": True}
    i, step = sidecar.wait_event("batch.step", since=since)
    assert step["idx"] == 0
    # video 0 is in progress: a stop for another one stops nothing
    assert sidecar.call("batch.stop", {"scope": "file", "file": 1}) == {"ok": False, "reason": "not_running"}
    assert sidecar.call("batch.stop", {"scope": "file", "file": clips[1]}) == {"ok": False, "reason": "not_running"}
    assert sidecar.call("batch.stop", {"scope": "file", "file": 7}) == {"ok": False, "reason": "not_running"}
    # a `file` of the wrong kind is refused, and stops nothing either
    for wrong in (1.5, True, [0], {"idx": 0}):
        err = _bad(sidecar, "batch.stop", {"scope": "file", "file": wrong})
        assert err["data"]["field"] == "file"
    assert _bad(sidecar, "batch.stop", {"scope": "next", "file": 0})["data"]["field"] == "scope"
    assert not any(e == "batch.file.stopped" for e, _ in sidecar.events[since:])
    # the stop for video 0 is taken: it stops, video 1 starts
    assert sidecar.call("batch.stop", {"scope": "file", "file": 0}) == {"ok": True}
    j, stopped = sidecar.wait_event("batch.file.stopped", since=i, timeout=30)
    assert stopped == {"idx": 0}
    k, started = sidecar.wait_event("batch.file.started", since=j)
    assert started["idx"] == 1
    # the same stop again comes late: video 1 is not touched
    assert sidecar.call("batch.stop", {"scope": "file", "file": 0}) == {"ok": False, "reason": "not_running"}
    assert sidecar.call("batch.stop", {"scope": "file", "file": clips[0]}) == {"ok": False, "reason": "not_running"}
    sidecar.wait_event("batch.step", since=k)
    assert not any(e == "batch.file.stopped" for e, _ in sidecar.events[k:])
    # by path
    assert sidecar.call("batch.stop", {"scope": "file", "file": clips[1]}) == {"ok": True}
    m, stopped = sidecar.wait_event("batch.file.stopped", since=k, timeout=30)
    assert stopped == {"idx": 1}
    _, done = sidecar.wait_event("batch.done", since=m, timeout=30)
    assert done["stopped"] == 2 and done["done"] == 0 and done["skipped"] == 0 and done["failed"] == 0
    time.sleep(0.3)
    assert _ffmpeg_on(work["clips"][0].name) == [] and _ffmpeg_on(work["clips"][1].name) == []
    assert not any(c.with_suffix(".srt").exists() for c in work["clips"])
    for c in work["clips"]:
        c.with_suffix(".log").unlink(missing_ok=True)


def test_batch_stop_all_ignores_file(sidecar: Sidecar, work: dict):
    clips = [str(c) for c in work["clips"]]
    since = len(sidecar.events)
    assert sidecar.call("batch.start", {"videos": clips, "params": PARAMS}) == {"started": True}
    i, _ = sidecar.wait_event("batch.step", since=since)
    # `file` names a video that is not in progress and is not even an index: ignored
    assert sidecar.call("batch.stop", {"scope": "all", "file": 1}) == {"ok": True}
    _, done = sidecar.wait_event("batch.done", since=i, timeout=30)
    assert done["stopped"] == 1 and done["skipped"] == 1 and done["done"] == 0
    for c in work["clips"]:
        c.with_suffix(".log").unlink(missing_ok=True)


def test_batch_bad_params(sidecar: Sidecar, work: dict):
    clip = str(work["clips"][0])
    # an OCR parameter the engine refuses: `field` is its key in `params`
    err = _bad(sidecar, "batch.start", {"videos": [clip], "params": {**PARAMS, "lang_hint": "Klingon"}})
    assert err["data"]["field"] == "lang_hint" and "not supported by Vision" in err["data"]["reason"]
    assert err["detail"] == err["message"] and "field=" not in err["detail"]
    err = _bad(sidecar, "batch.start", {"videos": [clip], "params": {**PARAMS, "fps": 0}})
    assert err["data"] == {"field": "fps", "reason": "must be between 0.5 and 60"}
    assert err["message"] == "fps: must be between 0.5 and 60"
    err = _bad(sidecar, "batch.start", {"videos": [clip], "params": {**PARAMS, "top_keep_pct": 101}})
    assert err["data"]["field"] == "top_keep_pct"
    # an unknown key, a value of the wrong kind, params that are not an object
    err = _bad(sidecar, "batch.start", {"videos": [clip], "params": {**PARAMS, "nonsense": 1}})
    assert err["data"] == {"field": "nonsense", "reason": "unknown parameter"}
    err = _bad(sidecar, "batch.start", {"videos": [clip], "params": {**PARAMS, "workers": "many"}})
    assert err["data"]["field"] == "workers" and "many" in err["data"]["reason"]
    err = _bad(sidecar, "batch.start", {"videos": [clip], "params": [1, 2]})
    assert err["data"] == {"field": "params", "reason": "must be an object"}
    # the arguments of the methods
    assert _bad(sidecar, "batch.start", {"videos": []})["data"] == \
        {"field": "videos", "reason": "must not be empty"}
    assert _bad(sidecar, "batch.start", {"videos": "a.mkv"})["data"]["field"] == "videos"
    assert _bad(sidecar, "batch.stop", {"scope": "everything"})["data"] == \
        {"field": "scope", "reason": "must be file or all"}
    assert _bad(sidecar, "preview.frames", {"video": 3})["data"]["field"] == "video"
    assert _bad(sidecar, "preview.frames", {"video": clip, "n": "a lot"})["data"]["field"] == "n"
    assert _bad(sidecar, "preview.frames", {"video": clip, "params": {"fps": "fast"}})["data"]["field"] == "fps"
    assert _bad(sidecar, "srt.fix", {"path": 3})["data"]["field"] == "path"
    assert _bad(sidecar, "srt.fix", {"path": "x.srt", "min_dur": "short"})["data"]["field"] == "min_dur"
    assert _bad(sidecar, "lists.import", {"kind": "nope", "path": "x"})["data"]["field"] == "kind"
    assert _bad(sidecar, "lists.import", {"kind": "ignore"})["data"]["field"] == "path"
    assert _bad(sidecar, "tools.use", {"ffmpeg": 3})["data"]["field"] == "ffmpeg"
    assert _bad(sidecar, "tools.install", {"keys": "ffmpeg"})["data"]["field"] == "keys"
    assert _bad(sidecar, "warmup", {"languages": "it-IT"})["data"]["field"] == "languages"
    # nothing was started by any of them
    assert sidecar.call("batch.stop", {"scope": "all"}) == {"ok": False, "reason": "no_batch"}
    assert sidecar.call("preview.stop") == {"ok": False, "reason": "no_preview"}


def test_batch_full_run(sidecar: Sidecar, work: dict):
    clip = work["clips"][0]
    since = len(sidecar.events)
    assert sidecar.call("batch.start", {"videos": [str(clip)], "params": PARAMS,
                                        "lang": "en"}) == {"started": True}
    _, started = sidecar.wait_event("batch.file.started", since=since)
    assert started["name"] == clip.name and [s["key"] for s in started["steps"]] == ["extract", "group", "ocr"]
    _, fd = sidecar.wait_event("batch.file.done", since=since, timeout=120)
    assert fd["segments"] == FAST_PROFILE_LINES and not fd["empty"]
    _, done = sidecar.wait_event("batch.done", since=since)
    assert done["done"] == 1
    srt = clip.with_suffix(".srt")
    assert srt.exists() and len(core.parse_srt(srt)) == FAST_PROFILE_LINES
    assert Path(fd["report"]).exists() and Path(fd["log"]).exists()
    assert "STEP 1/3 — Frame extraction · dialogue ▶ start" in Path(fd["log"]).read_text(encoding="utf-8")
    work["srt"] = srt


def test_preview_frames_busy_then_done(sidecar: Sidecar, work: dict):
    clip = work["clips"][0]
    since = len(sidecar.events)
    assert sidecar.call("preview.frames", {"video": str(clip), "params": PARAMS,
                                           "n": 20, "tries": 3}) == {"started": True}
    # a second preview job is refused while the first runs (a batch is not: see below)
    assert sidecar.call("preview.frames", {"video": str(clip), "params": PARAMS}) == \
        {"started": False, "reason": "busy"}
    # ...but Sub fix is never subject to busy
    res = sidecar.call("srt.fix", {"path": str(work["srt"]), "params": PARAMS})
    assert res["count"] == FAST_PROFILE_LINES and Path(res["out_path"]).exists()
    assert "-fixed-" in res["out_path"]
    _, done = sidecar.wait_event("preview.done", since=since, timeout=120)
    frames = done["frames"]
    assert len(frames) == 20
    with_text = [f for f in frames if f["has_text"]]
    assert len(with_text) >= 10
    assert all(Path(f["path"]).is_file() for f in frames)
    assert all(f["has_text"] == bool(f["bands"]) and "band" not in f for f in frames)
    assert all(f["bands"] in (["bottom"], ["bottom", "top"], ["top"], []) for f in frames)
    assert str(work["state"] / "tmp" / "preview") in frames[0]["path"]
    progress = [d for e, d in sidecar.events[since:] if e == "preview.progress"]
    assert progress and progress[-1]["done"] == 20
    assert set(progress[-1]) == {"done", "total", "found", "found_top", "zone", "frame"}
    assert {d["zone"] for d in progress} == set(range(20))
    assert all(f["zone"] == i for i, f in enumerate(frames))
    assert progress[-1]["found"] == len(with_text)
    assert progress[-1]["found_top"] == sum("top" in f["bands"] for f in frames)
    work["frame"] = with_text[0]["path"]


def test_preview_test(sidecar: Sidecar, work: dict):
    res = sidecar.call("preview.test", {"frame": work["frame"], "params": PARAMS})
    bottom = res["bands"]["bottom"]
    assert bottom["text"] and not bottom["empty"] and bottom["ms"] >= 0
    assert set(res["bands"]) == {"bottom"}
    with pytest.raises(SidecarError) as exc:
        sidecar.call("preview.test", {"frame": "/nowhere.jpg", "params": PARAMS})
    assert exc.value.code == "not_found"


def test_preview_stop(sidecar: Sidecar, work: dict):
    clip = work["clips"][1]
    since = len(sidecar.events)
    assert sidecar.call("preview.frames", {"video": str(clip), "params": PARAMS}) == {"started": True}
    sidecar.wait_event("preview.progress", since=since, timeout=60)
    assert sidecar.call("preview.stop") == {"ok": True}
    _, stopped = sidecar.wait_event("preview.stopped", since=since, timeout=30)
    assert stopped == {"reason": "user"}
    time.sleep(0.3)
    assert _ffmpeg_on(clip.name) == []
    assert sidecar.call("preview.stop") == {"ok": False, "reason": "no_preview"}
    # resumed on the zones it had not searched: the others are not searched again
    seen = {d["zone"] for e, d in sidecar.events[since:] if e == "preview.progress"}
    left = [z for z in range(20) if z not in seen]
    since = len(sidecar.events)
    assert sidecar.call("preview.frames", {"video": str(clip), "params": PARAMS,
                                           "zones": left}) == {"started": True}
    _, done = sidecar.wait_event("preview.done", since=since, timeout=120)
    assert [f["zone"] for f in done["frames"]] == left
    progress = [d for e, d in sidecar.events[since:] if e == "preview.progress"]
    assert sorted(d["done"] for d in progress) == list(range(21 - len(left), 21))
    assert _bad(sidecar, "preview.frames", {"video": str(clip), "zones": "1,2"})["data"]["field"] == "zones"


def test_batch_start_stops_the_preview(sidecar: Sidecar, work: dict):
    """C3 (board A1): a batch started while the frames are searched stops the search and starts."""
    clip = work["clips"][1]
    since = len(sidecar.events)
    assert sidecar.call("preview.frames", {"video": str(clip), "params": PARAMS}) == {"started": True}
    sidecar.wait_event("preview.progress", since=since, timeout=60)
    assert sidecar.call("batch.start", {"videos": [str(clip)], "params": PARAMS,
                                        "lang": "en"}) == {"started": True}
    names = [e for e, _ in sidecar.events[since:]]
    assert "preview.stopped" in names and "preview.done" not in names
    _, stopped = sidecar.wait_event("preview.stopped", since=since, timeout=5)
    assert stopped == {"reason": "batch"}
    _, done = sidecar.wait_event("batch.done", since=since, timeout=180)
    assert done["done"] == 1
    names = [e for e, _ in sidecar.events[since:]]
    assert names.index("preview.stopped") < names.index("batch.file.started")


def test_srt_fix_errors(sidecar: Sidecar, work: dict):
    empty = work["root"] / "empty.srt"
    empty.write_text("1\n00:00:00,000 --> 00:00:00,050\nx\n", encoding="utf-8")
    with pytest.raises(SidecarError) as exc:
        sidecar.call("srt.fix", {"path": str(empty), "flash": True, "min_dur": 0.2})
    assert exc.value.code == "no_valid_segments"
    with pytest.raises(SidecarError) as exc:
        sidecar.call("srt.fix", {"path": str(work["root"] / "missing.srt")})
    assert exc.value.code == "not_found"
    assert exc.value.error["path"] == str(work["root"] / "missing.srt")
    garbage = work["root"] / "garbage.srt"
    garbage.write_text("\n\nthis is not an srt\nat all\n", encoding="utf-8")
    with pytest.raises(SidecarError) as exc:
        sidecar.call("srt.fix", {"path": str(garbage)})
    assert exc.value.code == "bad_srt"
    assert exc.value.error["path"] == str(garbage) and exc.value.error["line"] == 3
    assert "-->" in exc.value.error["detail"]
    binary = work["root"] / "binary.srt"
    binary.write_bytes(b"\xff\xfe\x00garbage")
    with pytest.raises(SidecarError) as exc:
        sidecar.call("srt.fix", {"path": str(binary)})
    assert exc.value.code == "bad_srt" and exc.value.error["line"] == 1


def test_report_upgrade(sidecar: Sidecar, work: dict):
    """An old report: a copy with the current template in the state folder; errors with their code."""
    folder = work["root"] / "old-report"
    folder.mkdir()
    old = folder / "old-1.0-it.revisione.html"
    shutil.copy2(Path(__file__).parent / "fixtures" / "old-reports" / old.name, old)
    res = sidecar.call("report.upgrade", {"path": str(old)})
    assert res["current"] is False and res["cached"] is False and res["source"] == "1.x"
    copy = Path(res["path"])
    assert copy.is_file() and str(work["state"] / "tmp" / "reports") in str(copy)
    assert f'<meta name="subvision-report" content="{core.REPORT_VERSION}">' in copy.read_text(encoding="utf-8")
    assert sorted(p.name for p in folder.iterdir()) == [old.name]
    assert sidecar.call("report.upgrade", {"path": str(old)}) == {**res, "cached": True}
    assert sidecar.call("report.upgrade", {"path": str(copy)}) == {"path": str(copy), "current": True}
    with pytest.raises(SidecarError) as exc:
        sidecar.call("report.upgrade", {"path": str(folder / "missing.review.html")})
    assert exc.value.code == "not_found"
    junk = folder / "junk.review.html"
    junk.write_text("<html>no data</html>", encoding="utf-8")
    with pytest.raises(SidecarError) as exc:
        sidecar.call("report.upgrade", {"path": str(junk)})
    assert exc.value.code == "report_unreadable" and exc.value.error["path"] == str(junk)
    assert _bad(sidecar, "report.upgrade", {})["data"]["field"] == "path"


def test_batch_failed_file_carries_the_details(sidecar: Sidecar, work: dict):
    bogus = work["root"] / "broken.mp4"
    bogus.write_bytes(b"not a video")
    since = len(sidecar.events)
    assert sidecar.call("batch.start", {"videos": [str(bogus)], "params": PARAMS}) == {"started": True}
    _, failed = sidecar.wait_event("batch.file.failed", since=since, timeout=60)
    assert failed["code"] == "probe_failed" and failed["message"] == "probe_failed"
    assert failed["tool"] == "ffprobe" and failed["path"] == str(bogus) and failed["detail"]
    assert failed["at_step"] == "extract:bottom" and failed["error"].startswith("probe_failed")
    # F6: the log of the file and the short text of its row (the first line of the detail)
    assert failed["log"] == str(bogus.with_suffix(".log")) and Path(failed["log"]).is_file()
    assert failed["text"] == failed["detail"].splitlines()[0]
    assert "Invalid data found when processing input" in failed["detail"]
    _, done = sidecar.wait_event("batch.done", since=since)
    assert done["failed"] == 1


def test_damaged_videos(sidecar: Sidecar, work: dict):
    """
    The two recipes of conftest on the real sidecar: (a) a video the probe
    refuses, (b) one the probe accepts and ffmpeg gives up on halfway.
    """
    folder = work["root"] / "damaged"
    folder.mkdir()
    no_index = damage_head(work["clips"][0], folder / "no-index.mp4")
    damaged = damage_tail(work["clips"][0], folder / "damaged.mp4")
    vids = sidecar.call("videos.probe", {"paths": [str(no_index), str(damaged)]})["videos"]
    assert vids[0]["code"] == "probe_failed" and vids[0]["tool"] == "ffprobe"
    assert "moov atom not found" in vids[0]["detail"]
    assert "error" not in vids[1] and "code" not in vids[1]
    assert 50 < vids[1]["duration"] < 60 and vids[1]["width"] == 1280 and vids[1]["height"] == 544

    since = len(sidecar.events)
    assert sidecar.call("batch.start", {"videos": [str(no_index), str(damaged)],
                                        "params": PARAMS, "lang": "it"}) == {"started": True}
    _, done = sidecar.wait_event("batch.done", since=since, timeout=60)
    assert done["failed"] == 2 and done["done"] == 0 and done["stopped"] == 0
    failed = [d for e, d in sidecar.events[since:] if e == "batch.file.failed"]
    assert [f["idx"] for f in failed] == [0, 1]
    a, b = failed
    assert a["code"] == "probe_failed" and a["text"] == "moov atom not found" and a["tool"] == "ffprobe"
    assert b["code"] == "unknown" and b["message"] == "unknown" and b["tool"] == "ffmpeg"
    assert b["at_step"] == "extract:bottom" and b["path"] == str(damaged)
    # the batch is in Italian: so is the engine's own sentence (11.3.4); the parts are there for the app
    assert b["text"].startswith("ffmpeg è uscito con il codice ") and "Decode error rate" in b["text"]
    assert b["program"] == "ffmpeg" and b["status"] != 0 and "Decode error rate" in b["reason"]
    assert b["detail"].startswith("CalledProcessError: ") and "Conversion failed!" in b["detail"]
    assert b["error"] == f"unknown ({b['text']})"
    for f, video in ((a, no_index), (b, damaged)):
        assert set(f) <= {"idx", "at_step", "log", "code", "message", "error", "text",
                          "detail", "tool", "path", "line", "program", "status", "reason"}
        assert f["log"] == str(video.with_suffix(".log"))
        assert f"ERRORE: {f['error']}" in Path(f["log"]).read_text(encoding="utf-8")
        assert not video.with_suffix(".srt").exists()
        # the prefix of the alert is the app's, not the engine's
        assert not f["text"].startswith(("Qualcosa", "Something", "ERRORE", "unknown"))
    time.sleep(0.3)
    assert _ffmpeg_on(damaged.name) == []
    assert not list((work["state"] / "tmp").glob("voc26_*"))


def test_preview_failed_carries_the_details(sidecar: Sidecar, work: dict):
    bogus = work["root"] / "broken.mp4"
    bogus.write_bytes(b"not a video")
    since = len(sidecar.events)
    assert sidecar.call("preview.frames", {"video": str(bogus), "params": PARAMS}) == {"started": True}
    _, failed = sidecar.wait_event("preview.failed", since=since, timeout=60)
    assert failed["error"] == "invalid_duration" and failed["code"] == "invalid_duration"
    assert failed["tool"] == "ffprobe" and failed["path"] == str(bogus)


def test_tools_install_with_no_keys(sidecar: Sidecar):
    since = len(sidecar.events)
    res = sidecar.call("tools.install", {"keys": []})
    assert res == {"started": True, "keys": []}
    i, done = sidecar.wait_event("tools.done", since=since, timeout=10)
    assert done["ok"] is True and set(done["status"]["tools"]) == {"ffmpeg", "ffprobe"}
    assert not any(e == "tools.progress" for e, _ in sidecar.events[since:i])
    # and the slot is free again at once
    assert sidecar.call("tools.install", {"keys": []})["started"] is True


def test_shutdown_during_a_batch(work: dict):
    sc = Sidecar(work["state"], work["ffmpeg"])
    sc.wait_event("ready", timeout=30)
    clip = work["clips"][1]
    assert sc.call("batch.start", {"videos": [str(clip)], "params": PARAMS}) == {"started": True}
    sc.wait_event("batch.step", timeout=60)
    t0 = time.monotonic()
    assert sc.call("shutdown") == {"bye": True}
    sc.proc.wait(timeout=5)
    assert sc.proc.returncode == 0 and time.monotonic() - t0 < 5
    time.sleep(0.3)
    assert _ffmpeg_on(clip.name) == []
    assert not list((work["state"] / "tmp").glob("voc26_*"))


def test_eof_closes_the_process(work: dict):
    sc = Sidecar(work["state"], work["ffmpeg"])
    sc.wait_event("ready", timeout=30)
    assert sc.call("hello")["engine"] == "subvision"
    t0 = time.monotonic()
    sc.proc.stdin.close()
    sc.proc.wait(timeout=2)
    assert sc.proc.returncode == 0 and time.monotonic() - t0 < 2
