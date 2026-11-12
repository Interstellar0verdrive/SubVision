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

from conftest import FAST_PROFILE, FAST_PROFILE_LINES

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
            raise SidecarError(reply["error"]["code"], reply["error"].get("message", ""))
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
    def __init__(self, code: str, message: str) -> None:
        super().__init__(f"{code}: {message}")
        self.code = code


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
    assert (work["state"] / "ignore.txt").is_file() and (work["state"] / "correzioni.txt").is_file()


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


def test_tools_use(sidecar: Sidecar, work: dict):
    with pytest.raises(SidecarError) as exc:
        sidecar.call("tools.use", {"ffmpeg": str(work["root"] / "not-ffmpeg")})
    assert exc.value.code == "bad_tool"
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
        assert "error" not in v
    assert vids[2]["error"] == "probe_failed" and vids[2]["path"] == str(bogus)


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


def test_batch_bad_params(sidecar: Sidecar, work: dict):
    with pytest.raises(SidecarError) as exc:
        sidecar.call("batch.start", {"videos": [str(work["clips"][0])],
                                     "params": {**PARAMS, "lang_hint": "Klingon"}})
    assert exc.value.code == "bad_params"
    with pytest.raises(SidecarError) as exc:
        sidecar.call("batch.start", {"videos": [str(work["clips"][0])],
                                     "params": {**PARAMS, "nonsense": 1}})
    assert exc.value.code == "bad_params"
    with pytest.raises(SidecarError) as exc:
        sidecar.call("batch.start", {"videos": []})
    assert exc.value.code == "bad_params"


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
    # a second long job is refused while the first runs
    assert sidecar.call("batch.start", {"videos": [str(clip)], "params": PARAMS}) == \
        {"started": False, "reason": "busy"}
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
    assert str(work["state"] / "tmp" / "preview") in frames[0]["path"]
    progress = [d for e, d in sidecar.events[since:] if e == "preview.progress"]
    assert progress and progress[-1]["done"] == 20
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
    sidecar.wait_event("preview.stopped", since=since, timeout=30)
    time.sleep(0.3)
    assert _ffmpeg_on(clip.name) == []
    assert sidecar.call("preview.stop") == {"ok": False, "reason": "no_preview"}


def test_srt_fix_errors(sidecar: Sidecar, work: dict):
    empty = work["root"] / "empty.srt"
    empty.write_text("1\n00:00:00,000 --> 00:00:00,050\nx\n", encoding="utf-8")
    with pytest.raises(SidecarError) as exc:
        sidecar.call("srt.fix", {"path": str(empty), "flash": True, "min_dur": 0.2})
    assert exc.value.code == "no_valid_segments"
    with pytest.raises(SidecarError) as exc:
        sidecar.call("srt.fix", {"path": str(work["root"] / "missing.srt")})
    assert exc.value.code == "not_found"


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
