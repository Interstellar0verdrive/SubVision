"""
The five frames of the to-do drawer (thumbs.py): on the demo clips, on tiny
generated videos (an anamorphic one, a very short one) and on files ffmpeg
cannot read; the cache and its key.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import time
from pathlib import Path

import pytest
from PIL import Image

from subvision import thumbs

from conftest import damage_tail


def _make_video(ffmpeg: str, out: Path, seconds: float, size: str = "320x240",
                sar: str | None = None) -> Path:
    vf = f"testsrc2=size={size}:rate=25,format=yuv420p"
    if sar:
        vf += f",setsar={sar}"
    subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi",
                    "-i", vf, "-t", str(seconds), "-c:v", "libx264", "-preset", "ultrafast",
                    str(out)], check=True, stdin=subprocess.DEVNULL)
    return out


def test_five_frames_of_a_demo_clip(ffmpeg_bin: str, demo_ita_copy: Path, tmp_path: Path) -> None:
    state = tmp_path / "state"
    res = thumbs.video_frames(demo_ita_copy, state)
    assert res["cached"] is False and len(res["frames"]) == 5
    assert all(res["frames"]), res
    for p in res["frames"]:
        assert Path(p).parent == thumbs.thumbs_dir(demo_ita_copy, state)
        with Image.open(p) as im:
            # 1280x544: 320 wide, the height of the aspect ratio, even
            assert im.size == (320, 136)
    # different frames along the video (the positions are 10/30/50/70/90 %)
    sizes = {Path(p).stat().st_size for p in res["frames"]}
    assert len(sizes) > 1
    assert res["seconds"] < 10
    # the second time: the cache, at once, the same files
    again = thumbs.video_frames(demo_ita_copy, state)
    assert again["cached"] is True and again["frames"] == res["frames"] and again["seconds"] < 0.5


def test_duration_from_the_caller_spares_ffprobe(ffmpeg_bin: str, demo_ita_copy: Path,
                                                 tmp_path: Path) -> None:
    res = thumbs.video_frames(demo_ita_copy, tmp_path, duration=55.0, ffprobe="/nowhere/ffprobe")
    assert all(res["frames"]) and "error" not in res


def test_a_changed_file_gets_new_frames(ffmpeg_bin: str, tmp_path: Path) -> None:
    v = _make_video(ffmpeg_bin, tmp_path / "v.mp4", 2)
    first = thumbs.thumbs_dir(v, tmp_path)
    assert all(thumbs.video_frames(v, tmp_path)["frames"])
    _make_video(ffmpeg_bin, v, 3)
    os.utime(v, (time.time() + 5, time.time() + 5))
    assert thumbs.thumbs_dir(v, tmp_path) != first
    res = thumbs.video_frames(v, tmp_path)
    assert res["cached"] is False and all(res["frames"])
    assert Path(res["frames"][0]).parent == thumbs.thumbs_dir(v, tmp_path)


def test_anamorphic_and_short_videos(ffmpeg_bin: str, tmp_path: Path) -> None:
    # 720x576 with 16:15 pixels shows as 768x576 (4:3): 320x240
    v = _make_video(ffmpeg_bin, tmp_path / "pal.mp4", 1, size="720x576", sar="16/15")
    res = thumbs.video_frames(v, tmp_path)
    assert all(res["frames"])
    with Image.open(res["frames"][2]) as im:
        assert im.size == (320, 240)
    # a video of half a second still gives its frames
    short = _make_video(ffmpeg_bin, tmp_path / "short.mp4", 0.5)
    assert all(thumbs.video_frames(short, tmp_path)["frames"])


def test_unreadable_videos_fail_quietly(ffmpeg_bin: str, demo_ita: Path, tmp_path: Path) -> None:
    bogus = tmp_path / "bogus.mp4"
    bogus.write_bytes(b"nope")
    res = thumbs.video_frames(bogus, tmp_path)
    assert res["frames"] == [None] * 5 and res["error"] == "probe_failed"
    missing = thumbs.video_frames(tmp_path / "missing.mp4", tmp_path)
    assert missing["frames"] == [None] * 5
    # the probe accepts it (55 s), the frames after the first megabyte are zeros:
    # the frames that cannot be decoded are None, the call does not raise
    damaged = damage_tail(demo_ita, tmp_path / "damaged.mp4")
    res = thumbs.video_frames(damaged, tmp_path, duration=55.0)
    assert len(res["frames"]) == 5 and None in res["frames"]
    # no half-written file is left behind
    assert not list(thumbs.thumbs_root(tmp_path).rglob("*.part.jpg"))


def test_a_frame_that_times_out_is_none(ffmpeg_bin: str, demo_ita_copy: Path, tmp_path: Path) -> None:
    res = thumbs.video_frames(demo_ita_copy, tmp_path, timeout=0.0001)
    assert res["frames"] == [None] * 5 and "error" not in res
    # a later call takes them (nothing of the failed one was cached)
    assert all(thumbs.video_frames(demo_ita_copy, tmp_path)["frames"])


def test_clean_old_removes_unused_folders(ffmpeg_bin: str, demo_ita_copy: Path, tmp_path: Path) -> None:
    root = thumbs.thumbs_root(tmp_path)
    old = root / "old"
    old.mkdir(parents=True)
    past = time.time() - 31 * 86400
    os.utime(old, (past, past))
    res = thumbs.video_frames(demo_ita_copy, tmp_path)
    assert not old.exists()
    used = thumbs.thumbs_dir(demo_ita_copy, tmp_path)
    os.utime(used, (past, past))
    # a cache hit keeps the folder alive
    assert thumbs.video_frames(demo_ita_copy, tmp_path)["cached"] is True
    assert thumbs.clean_old(tmp_path) == 0 and used.is_dir()
    shutil.rmtree(used)
    assert res["frames"]
