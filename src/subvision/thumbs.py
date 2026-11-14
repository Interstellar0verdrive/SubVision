"""
Five frames of a video, taken as soon as it enters the list: the to-do
drawer of the app shows them until the Preview has found its own 20.

`video_frames` takes one frame at 10, 30, 50, 70 and 90 % of the duration,
about THUMB_WIDTH pixels wide (the display aspect ratio, square pixels), as
JPEGs in `<state>/tmp/thumbs/<hash of path+mtime+size>/N.jpg`: the key is
the one of the Preview's folders (`preview.preview_dir`), so a file that
changed gets new frames. A folder that already holds the five frames is
the answer at once (its date is touched, so it lives while the video is in
the list); folders not used for THUMBS_MAX_AGE are removed by `clean_old`.

One ffmpeg per frame, one after the other (the cheapest on the machine, and
a frame that fails does not take the others with it): fast seek (`-ss`
before `-i`), one frame, scaled by ffmpeg. Measured with the bundled ffmpeg
9: 0.3–0.45 s for the five on the 55 s 1280x544 H.264 demo clips, about
0.9 s on a 2 h 1920x1040 HEVC film. Each ffmpeg has FRAME_TIMEOUT seconds;
a frame that fails or times out is None, the others stay.

The sidecar's `videos.thumbs` runs this synchronously in its pool, outside
the slot of the long jobs (batch, preview): it does not take the slot and
nothing waits for it. During a batch it answers `busy` unless the frames
are already there (see serve.py); the app asks again when the batch ends.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from subvision import core
from subvision.paths import state_paths
from subvision.preview import _duration, preview_dir

THUMB_FRACTIONS = (0.1, 0.3, 0.5, 0.7, 0.9)
THUMB_WIDTH = 320                # pixels; the height follows the display aspect ratio
FRAME_TIMEOUT = 20.0             # seconds one ffmpeg may take
THUMBS_MAX_AGE = 30 * 86400      # seconds: folders not used for this long are removed


def thumbs_root(state: Optional[Path | str] = None) -> Path:
    return state_paths(state).tmp / "thumbs"


def thumbs_dir(video: Path | str, state: Optional[Path | str] = None) -> Path:
    """`<state>/tmp/thumbs/<hash>` for this video (path + mtime + size, as the Preview's)."""
    return thumbs_root(state) / preview_dir(video, state).name


def clean_old(state: Optional[Path | str] = None, max_age: float = THUMBS_MAX_AGE) -> int:
    """Removes the folders not used for `max_age` seconds; returns how many."""
    root = thumbs_root(state)
    if not root.is_dir():
        return 0
    now = time.time()
    removed = 0
    for d in root.iterdir():
        try:
            if d.is_dir() and now - d.stat().st_mtime > max_age:
                shutil.rmtree(d, ignore_errors=True)
                removed += 1
        except OSError:
            continue
    return removed


def _grab(ffmpeg: str, video: str, ts: float, out: Path, timeout: float) -> bool:
    """One frame at `ts`, scaled; written to a temporary name and moved into place."""
    part = out.with_name(out.stem + ".part.jpg")
    vf = f"scale={THUMB_WIDTH}:trunc({THUMB_WIDTH}/dar/2)*2,setsar=1"
    cmd = [ffmpeg, "-hide_banner", "-nostats", "-loglevel", "error", "-y",
           "-ss", f"{ts:.3f}", "-i", video, "-map", "0:v:0", "-an", "-sn", "-dn",
           "-frames:v", "1", "-vf", vf, "-q:v", "4", str(part)]
    try:
        subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.PIPE, timeout=timeout, check=True)
        if part.is_file() and part.stat().st_size > 0:
            os.replace(part, out)
            return True
    except (OSError, subprocess.SubprocessError):
        pass
    part.unlink(missing_ok=True)
    return False


def cached_frames(video: Path | str, state: Optional[Path | str] = None) -> Optional[List[str]]:
    """The five frames when they are all there already, else None."""
    d = thumbs_dir(video, state)
    paths = [d / f"{i}.jpg" for i in range(len(THUMB_FRACTIONS))]
    if all(p.is_file() for p in paths):
        try:
            os.utime(d)
        except OSError:
            pass
        return [str(p) for p in paths]
    return None


def video_frames(video: Path | str, state: Optional[Path | str] = None,
                 duration: Optional[float] = None, ffmpeg: Optional[str] = None,
                 ffprobe: Optional[str] = None, timeout: float = FRAME_TIMEOUT) -> Dict[str, Any]:
    """
    `{frames, cached, seconds}`: `frames` lists the five JPEGs in order (None
    for a frame that could not be taken), `cached` says they were all there
    already, `seconds` is the time taken. `duration` (from `videos.probe`)
    spares an ffprobe. When the duration cannot be read every frame is None
    and `error` is "probe_failed". Never raises for a bad video.
    """
    t0 = time.monotonic()
    video = str(video)
    cached = cached_frames(video, state)
    if cached is not None:
        return {"frames": cached, "cached": True, "seconds": round(time.monotonic() - t0, 3)}
    ffmpeg = ffmpeg or core.FFMPEG
    ffprobe = ffprobe or core.FFPROBE
    clean_old(state)
    n = len(THUMB_FRACTIONS)
    if not duration or duration <= 0:
        try:
            duration = _duration(ffprobe, video)
        except Exception:  # noqa: BLE001 - a bad video gives empty boxes, not an error
            duration = 0.0
    if not duration or duration <= 0:
        return {"frames": [None] * n, "cached": False, "error": "probe_failed",
                "seconds": round(time.monotonic() - t0, 3)}
    d = thumbs_dir(video, state)
    d.mkdir(parents=True, exist_ok=True)
    frames: List[Optional[str]] = []
    for i, f in enumerate(THUMB_FRACTIONS):
        out = d / f"{i}.jpg"
        if out.is_file() or _grab(ffmpeg, video, duration * f, out, timeout):
            frames.append(str(out))
        else:
            frames.append(None)
    return {"frames": frames, "cached": False, "seconds": round(time.monotonic() - t0, 3)}
