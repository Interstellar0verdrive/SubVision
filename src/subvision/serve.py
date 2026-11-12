"""
The engine as a sidecar of the native app: `subvision serve`, JSON lines
on stdin/stdout.

The SwiftUI app starts this process once and talks to it for the life of
the window. Every line is a JSON object:

    request   {"id": 7, "method": "hello", "params": {}}
    reply     {"id": 7, "result": {...}}
              {"id": 7, "error": {"code": "unknown_method", "message": "..."}}
    event     {"event": "batch.step", "data": {...}}

Replies may come back in a different order than the requests (each one
runs in its own thread): the `id` is what counts. Events have no id.
Lines that are not JSON are ignored (logged on stderr). `shutdown` and
EOF on stdin close the process.

The channel is a DEDICATED descriptor: at startup stdout is duplicated for
the protocol and the real stdout (fd 1) is redirected to stderr, so a
forgotten `print` or the output of a child process ends up in the log and
cannot break a protocol line. The launcher/app sends stderr to
`<state>/records/engine.log`.

Adapted from `serve.py` of AnimeUp 2.1 (the channel, the request loop,
the method table; MIT-licensed pieces by the same author). What differs:
the long jobs (batch, preview) run INSIDE this process, one at a time,
with a cooperative stop (plan, D7); the methods are the ones of the
SubVision protocol (plan, table 1.4).

Tools: ffmpeg/ffprobe are resolved once (`tools.ffmpeg_path(state,
custom)` -> `core.set_tools`) at startup, after `tools.install` and on
`tools.use {ffmpeg}` ("Use my own ffmpeg", D11). The custom path can also
come from the `SUBVISION_FFMPEG` environment variable (tests, CLI).
"""

from __future__ import annotations

import dataclasses
import json
import os
import platform
import shutil
import signal
import subprocess
import sys
import threading
import time
import traceback
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, TextIO

from subvision import __version__, batch, core, fix, lists, preview, tools
from subvision.core import EngineError, OcrParams, Stopped
from subvision.paths import StatePaths, state_paths

PROTOCOL = 1
FFMPEG_ENV = "SUBVISION_FFMPEG"


class MethodError(Exception):
    """An error for the caller, with a stable code."""

    def __init__(self, code: str, message: str = "") -> None:
        super().__init__(message or code)
        self.code = code


# ---------------------------------------------------------------------------
#  State of the process
# ---------------------------------------------------------------------------

_state: Optional[StatePaths] = None
_custom_ffmpeg: Optional[str] = None
_tools_lock = threading.Lock()          # tools.install / tools.use
_warmup_lock = threading.Lock()

# One long job at a time (batch or preview): `_job` holds its kind, its stop
# control and its thread; `_job_lock` guards the slot.
_job_lock = threading.Lock()
_job: Optional[Dict[str, Any]] = None


def _paths() -> StatePaths:
    global _state
    if _state is None:
        _state = state_paths().ensure()
    return _state


def _configure_tools(custom: Optional[str]) -> Optional[Dict[str, Any]]:
    """
    Resolves ffmpeg/ffprobe (custom path first, then <state>/bin) and
    configures the engine. Returns {path, version} of the active ffmpeg, or
    None when there is none (the engine keeps the previous configuration).
    """
    root = _paths().root
    ffmpeg = tools.ffmpeg_path(root, custom)
    ffprobe = tools.ffprobe_path(root, custom)
    if not ffmpeg or not ffprobe:
        return None
    core.set_tools(ffmpeg, ffprobe)
    return {"path": ffmpeg, "version": tools.tool_version(ffmpeg)}


def _active_ffmpeg() -> Optional[Dict[str, Any]]:
    path = core.FFMPEG
    if not path or not Path(path).is_file():
        return None
    return {"path": path, "version": tools.tool_version(path)}


# ---------------------------------------------------------------------------
#  Parameters
# ---------------------------------------------------------------------------

_PARAM_FIELDS = {f.name: f for f in dataclasses.fields(OcrParams)
                 if f.name not in ("ignore_lines", "corrections")}


def _params_from(raw: Any) -> OcrParams:
    """OcrParams from the `params` object of a request (unknown keys -> bad_params)."""
    if raw is None:
        return OcrParams()
    if not isinstance(raw, dict):
        raise MethodError("bad_params", "params must be an object")
    values: Dict[str, Any] = {}
    for key, value in raw.items():
        f = _PARAM_FIELDS.get(key)
        if f is None:
            raise MethodError("bad_params", f"unknown parameter: {key}")
        try:
            if f.type in ("float", float):
                values[key] = float(value)
            elif f.type in ("int", int):
                values[key] = int(value)
            elif f.type in ("bool", bool):
                values[key] = bool(value)
            else:
                values[key] = str(value)
        except (TypeError, ValueError) as e:
            raise MethodError("bad_params", f"{key}: {e}") from e
    return OcrParams(**values)


def _lists_for(params: dict) -> lists.Lists:
    return lists.load(bool(params.get("use_ignore", True)),
                      bool(params.get("use_corrections", True)), _paths().root)


def _with_lists(p: OcrParams, pair: lists.Lists) -> OcrParams:
    ignore, corrections = pair
    return dataclasses.replace(p, ignore_lines=list(ignore), corrections=list(corrections))


def _strings(params: dict, key: str) -> List[str]:
    value = params.get(key)
    if not isinstance(value, list) or not all(isinstance(v, str) for v in value):
        raise MethodError("bad_params", f"{key} must be a list of strings")
    return value


def _engine_error(e: EngineError) -> MethodError:
    extra = ", ".join(f"{k}={v}" for k, v in e.args_.items())
    return MethodError(e.code, f"{e.code}" + (f" ({extra})" if extra else ""))


# ---------------------------------------------------------------------------
#  The methods
# ---------------------------------------------------------------------------

def _hello(_params: dict) -> dict:
    return {
        "engine": "subvision",
        "version": __version__,
        "protocol": PROTOCOL,
        "pid": os.getpid(),
        "python": platform.python_version(),
        "vision": core.vision_available(),
        "livetext": core.livetext_available(),
        "ffmpeg": _active_ffmpeg(),
        "languages": core.vision_languages(),
        "state_folder": str(_paths().root),
    }


# --- tools -----------------------------------------------------------------

def _tools_status(_params: dict) -> dict:
    return {"tools": tools.status(_paths().root), "active": _active_ffmpeg(),
            "custom": _custom_ffmpeg}


def _tools_install(params: dict) -> dict:
    """Starts in a thread and replies at once: `tools.progress`, then `tools.done`."""
    keys = params.get("keys")
    if keys is not None and not (isinstance(keys, list) and all(isinstance(k, str) for k in keys)):
        raise MethodError("bad_params", "keys must be a list of strings")
    if not _tools_lock.acquire(blocking=False):
        return {"started": False, "reason": "already_running"}
    todo = [k for k in (keys if keys is not None else tools.missing(_paths().root))
            if k in tools.TOOLS]

    def progress(key: str, state: str, done: int, total: int, error: Optional[str] = None) -> None:
        data = {"key": key, "state": state, "bytes": done, "total": total}
        if error:
            data["error"] = error
        _emit("tools.progress", data)

    def work() -> None:
        try:
            ok = tools.install(todo, _paths().root, progress)
            _configure_tools(_custom_ffmpeg)
            _emit("tools.done", {"ok": ok, "status": _tools_status({})})
        except Exception:  # noqa: BLE001 - the engine must not die
            traceback.print_exc(file=sys.stderr)
            _emit("tools.done", {"ok": False, "status": _tools_status({})})
        finally:
            _tools_lock.release()

    threading.Thread(target=work, daemon=True, name="tools-install").start()
    return {"started": True, "keys": todo}


def _tools_use(params: dict) -> dict:
    """`{ffmpeg: path|null}`: "Use my own ffmpeg" (D11); null goes back to <state>/bin."""
    global _custom_ffmpeg
    custom = params.get("ffmpeg")
    if custom is not None and not isinstance(custom, str):
        raise MethodError("bad_params", "ffmpeg must be a path or null")
    if custom and not tools.tool_version(custom):
        raise MethodError("bad_tool", f"{custom} does not answer -version")
    _custom_ffmpeg = custom or None
    return {"ffmpeg": _configure_tools(_custom_ffmpeg), "custom": _custom_ffmpeg}


# --- warmup ----------------------------------------------------------------

def _warmup(params: dict) -> dict:
    """
    First Vision call (~30 s once per user, S5): in a thread, for the FIRST
    language given only (one is enough to pay the cost). Not interruptible.
    """
    languages = params.get("languages") or ["it-IT"]
    if not isinstance(languages, list) or not all(isinstance(x, str) for x in languages):
        raise MethodError("bad_params", "languages must be a list of strings")
    if not _warmup_lock.acquire(blocking=False):
        return {"started": False, "reason": "already_running"}
    langs = core.resolve_langs(languages[0])

    def work() -> None:
        t0 = time.monotonic()
        try:
            core.warmup(langs, "accurate")
        finally:
            _warmup_lock.release()
            _emit("warmup.done", {"seconds": round(time.monotonic() - t0, 2),
                                  "languages": langs})

    threading.Thread(target=work, daemon=True, name="warmup").start()
    return {"started": True, "languages": langs}


# --- lists -----------------------------------------------------------------

def _lists_status(_params: dict) -> dict:
    return lists.status(_paths().root)


def _lists_import(params: dict) -> dict:
    kind, path = params.get("kind"), params.get("path")
    if kind not in lists.KINDS or not isinstance(path, str):
        raise MethodError("bad_params", "lists.import wants {kind: ignore|corrections, path}")
    try:
        lists.import_file(kind, path, _paths().root)
    except FileNotFoundError as e:
        raise MethodError("not_found", str(e)) from e
    return lists.status(_paths().root)


# --- videos ----------------------------------------------------------------

def _probe(path: str) -> Dict[str, Any]:
    """duration, fps, width, height of one video through ffprobe (json output)."""
    cmd = [core.FFPROBE, "-v", "error", "-select_streams", "v:0",
           "-show_entries", "stream=width,height,avg_frame_rate,r_frame_rate:format=duration",
           "-of", "json", path]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=60,
                             check=True, stdin=subprocess.DEVNULL).stdout
        info = json.loads(out)
        stream = (info.get("streams") or [{}])[0]
        duration = float((info.get("format") or {}).get("duration") or 0)
        fps = 0.0
        for key in ("avg_frame_rate", "r_frame_rate"):
            val = str(stream.get(key) or "")
            if "/" in val:
                n, d = val.split("/")
                fps = float(n) / (float(d) or 1.0)
            elif val:
                fps = float(val)
            if fps > 0.1:
                break
        if duration <= 0 or not stream:
            raise ValueError("no video stream or duration")
        return {"path": path, "duration": round(duration, 3), "fps": round(fps, 3),
                "width": int(stream.get("width") or 0), "height": int(stream.get("height") or 0)}
    except (OSError, subprocess.SubprocessError, ValueError, KeyError) as e:
        return {"path": path, "error": "probe_failed", "message": str(e)}


def _videos_probe(params: dict) -> dict:
    return {"videos": [_probe(p) for p in _strings(params, "paths")]}


# --- long jobs (one at a time) ---------------------------------------------

def _start_job(kind: str, stop: Any, target: Callable[[], None]) -> bool:
    """Takes the job slot and starts `target` in a thread; False when busy."""
    global _job
    with _job_lock:
        if _job is not None and _job["thread"].is_alive():
            return False

        def run() -> None:
            global _job
            try:
                target()
            finally:
                with _job_lock:
                    _job = None

        th = threading.Thread(target=run, daemon=True, name=f"job-{kind}")
        _job = {"kind": kind, "stop": stop, "thread": th}
        th.start()
        return True


def _current_job(kind: Optional[str] = None) -> Optional[Dict[str, Any]]:
    with _job_lock:
        if _job is None or not _job["thread"].is_alive():
            return None
        if kind and _job["kind"] != kind:
            return None
        return _job


def _batch_start(params: dict) -> dict:
    videos = _strings(params, "videos")
    if not videos:
        raise MethodError("bad_params", "videos must not be empty")
    p = _params_from(params.get("params"))
    try:
        batch.validate_params(p)
    except EngineError as e:
        raise _engine_error(e) from e
    lang = params.get("lang") if params.get("lang") in ("it", "en") else "en"
    pair = _lists_for(params)
    control = batch.BatchControl()

    def work() -> None:
        try:
            batch.run_batch(videos, p, {"ignore": pair[0], "corrections": pair[1]}, lang,
                            _emit, control, tmp_root=_paths().tmp)
        except Exception as e:  # noqa: BLE001 - never leave the app without batch.done
            traceback.print_exc(file=sys.stderr)
            _emit("batch.done", {"done": 0, "failed": 0, "stopped": 0,
                                 "skipped": len(videos), "elapsed": 0.0,
                                 "error": f"{type(e).__name__}: {e}"})

    if not _start_job("batch", control, work):
        return {"started": False, "reason": "busy"}
    return {"started": True}


def _batch_stop(params: dict) -> dict:
    scope = params.get("scope", "file")
    if scope not in ("file", "all"):
        raise MethodError("bad_params", "scope must be file or all")
    job = _current_job("batch")
    if job is None:
        return {"ok": False, "reason": "no_batch"}
    job["stop"].stop(scope)
    return {"ok": True}


def _preview_frames(params: dict) -> dict:
    video = params.get("video")
    if not isinstance(video, str) or not video:
        raise MethodError("bad_params", "video must be a path")
    p = _params_from(params.get("params"))
    n = int(params.get("n", 20))
    tries = int(params.get("tries", 3))
    stop = threading.Event()

    def work() -> None:
        try:
            frames = preview.find_frames(video, p, n=n, tries=tries, emit=_emit,
                                         stop=stop, state=_paths().root)
            _emit("preview.done", {"frames": frames})
        except Stopped:
            _emit("preview.stopped", {})
        except EngineError as e:
            _emit("preview.failed", {"error": e.code, "message": str(_engine_error(e))})
        except Exception as e:  # noqa: BLE001
            traceback.print_exc(file=sys.stderr)
            _emit("preview.failed", {"error": "internal", "message": f"{type(e).__name__}: {e}"})

    if not _start_job("preview", stop, work):
        return {"started": False, "reason": "busy"}
    return {"started": True}


def _preview_stop(_params: dict) -> dict:
    job = _current_job("preview")
    if job is None:
        return {"ok": False, "reason": "no_preview"}
    job["stop"].set()
    return {"ok": True}


def _preview_test(params: dict) -> dict:
    frame = params.get("frame")
    if not isinstance(frame, str) or not Path(frame).is_file():
        raise MethodError("not_found", "frame must be the path of an existing image")
    p = _params_from(params.get("params"))
    try:
        return preview.test_frame(frame, p, lists=_lists_for(params))
    except EngineError as e:
        raise _engine_error(e) from e


def _srt_fix(params: dict) -> dict:
    """Synchronous and never `busy`: Sub fix must work during a batch."""
    path = params.get("path")
    if not isinstance(path, str):
        raise MethodError("bad_params", "path must be the path of an .srt")
    p = _params_from(params.get("params"))
    try:
        out, count = fix.fix_srt(path, merge=bool(params.get("merge", True)),
                                 ignore=bool(params.get("ignore", True)),
                                 flash=bool(params.get("flash", True)),
                                 min_dur=float(params.get("min_dur", 0.2)),
                                 params=p, lists=_lists_for(params))
    except EngineError as e:
        raise _engine_error(e) from e
    return {"out_path": str(out), "count": count}


METHODS: Dict[str, Callable[[dict], dict]] = {
    "hello": _hello,
    "tools.status": _tools_status,
    "tools.install": _tools_install,
    "tools.use": _tools_use,
    "warmup": _warmup,
    "lists.status": _lists_status,
    "lists.import": _lists_import,
    "videos.probe": _videos_probe,
    "batch.start": _batch_start,
    "batch.stop": _batch_stop,
    "preview.frames": _preview_frames,
    "preview.stop": _preview_stop,
    "preview.test": _preview_test,
    "srt.fix": _srt_fix,
}


# ---------------------------------------------------------------------------
#  The channel
# ---------------------------------------------------------------------------

_out: Optional[TextIO] = None
_write_lock = threading.Lock()


def _write(obj: dict) -> None:
    line = json.dumps(obj, ensure_ascii=False, separators=(",", ":"), default=str)
    with _write_lock:
        if _out is None:
            return
        _out.write(line + "\n")
        _out.flush()


def _emit(event: str, data: dict) -> None:
    _write({"event": event, "data": data})


def handle(request: object) -> Optional[dict]:
    """The reply to a decoded request (None: no reply)."""
    if not isinstance(request, dict):
        return {"id": None, "error": {"code": "bad_request",
                                      "message": "a request is a JSON object"}}
    ident = request.get("id")
    method = request.get("method")
    params = request.get("params") or {}
    if not isinstance(method, str) or not isinstance(params, dict):
        return {"id": ident, "error": {"code": "bad_request",
                                       "message": "needs a method and object params"}}
    fn = METHODS.get(method)
    if fn is None:
        return {"id": ident, "error": {"code": "unknown_method",
                                       "message": f"unknown method: {method}"}}
    try:
        return {"id": ident, "result": fn(params)}
    except MethodError as e:
        return {"id": ident, "error": {"code": e.code, "message": str(e)}}
    except Exception as e:  # noqa: BLE001 - the engine must not die
        traceback.print_exc(file=sys.stderr)
        return {"id": ident, "error": {"code": "internal",
                                       "message": f"{type(e).__name__}: {e}"}}


def _clean_orphans() -> None:
    """Work folders of a previous crashed run and old previews."""
    paths = _paths()
    for d in paths.tmp.glob("voc26_*"):
        shutil.rmtree(d, ignore_errors=True)
    try:
        preview.clean_old(paths.root)
    except Exception:  # noqa: BLE001
        pass


def _stop_everything(grace: float = 2.0) -> None:
    """Stops the long job in progress and waits for it a little."""
    job = _current_job()
    if job is None:
        return
    stop = job["stop"]
    if isinstance(stop, batch.BatchControl):
        stop.stop("all")
    else:
        stop.set()
    job["thread"].join(timeout=grace)


def main() -> int:
    """The loop: one line read, one job in the pool; exits on EOF or shutdown."""
    global _out
    _out = os.fdopen(os.dup(1), "w", encoding="utf-8", buffering=1)
    os.dup2(2, 1)
    sys.stdout = sys.stderr
    # no inherited signal mask (the app may have one) and no SIGINT: the stop
    # of the jobs is cooperative, a Ctrl-C in a terminal must not kill a batch
    signal.pthread_sigmask(signal.SIG_SETMASK, [])
    signal.signal(signal.SIGINT, signal.SIG_IGN)

    paths = _paths()
    _clean_orphans()
    global _custom_ffmpeg
    _custom_ffmpeg = os.environ.get(FFMPEG_ENV) or None
    _configure_tools(_custom_ffmpeg)
    lists.ensure(paths.root)

    _emit("ready", {"version": __version__, "protocol": PROTOCOL, "pid": os.getpid()})
    print(f"subvision serve {__version__}: ready (pid {os.getpid()}, state {paths.root})",
          file=sys.stderr)

    def work(request: dict) -> None:
        reply = handle(request)
        if reply is not None:
            _write(reply)

    with ThreadPoolExecutor(max_workers=4, thread_name_prefix="serve") as pool:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                request = json.loads(line)
            except ValueError:
                print(f"serve: ignored a line that is not JSON: {line[:80]!r}", file=sys.stderr)
                continue
            if isinstance(request, dict) and request.get("method") == "shutdown":
                _write({"id": request.get("id"), "result": {"bye": True}})
                break
            pool.submit(work, request)
        # EOF or shutdown: stop the job, do not wait for a warmup in progress
        _stop_everything()
        pool.shutdown(wait=False, cancel_futures=True)
    with _write_lock:
        try:
            _out.flush()
        except OSError:
            pass
    # a Vision warmup cannot be interrupted and a pool thread may still be
    # busy: leave now, the children are already terminated by the stop
    os._exit(0)


if __name__ == "__main__":
    sys.exit(main())
