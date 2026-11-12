# SPDX-License-Identifier: MIT
"""A stand-in for `subvision serve` with a tools window to drive, for the
SVShell tests and the ShellDemo app. Same copy in Examples/ShellDemo/.

Speaks the JSON-lines protocol: `{"id", "method", "params"}` in,
`{"id", "result"}` or `{"id", "error"}` out, `{"event", "data"}` pushed.
Methods: hello, tools.status, tools.install, echo, shutdown, quit.

`tools.status` says ffmpeg is missing until `tools.install` has run; the
install emits `tools.progress` for every key asked (bytes growing in a few
steps, then done), then `warmup` (a task of unknown length), then `tools.done`.
`FAKE_TOOLS_FAIL=<key>` makes that key fail once, with a checksum error, so
Try Again can be tested. `FAKE_TOOLS_STEP` is the seconds between steps (0.05).
"""

import json
import os
import sys
import threading
import time

LOCK = threading.Lock()
STATE = {"verified": False, "failed_once": set()}


def log(text):
    sys.stderr.write(f"fake_engine[{os.getpid()}]: {text}\n")
    sys.stderr.flush()


def write(obj):
    with LOCK:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()


def status():
    return {"tools": [
        {"key": "ffmpeg", "name": "FFmpeg", "verified": STATE["verified"], "version": "7.1" if STATE["verified"] else None},
    ], "all_verified": STATE["verified"]}


def install(keys):
    step = float(os.environ.get("FAKE_TOOLS_STEP", "0.05"))
    fail = os.environ.get("FAKE_TOOLS_FAIL")
    ok = True
    for key in keys:
        total = 38_000_000 if key == "ffmpeg" else 10_000_000
        write({"event": "tools.progress", "data": {"key": key, "state": "running", "bytes": 0, "total": total}})
        for i in range(1, 5):
            time.sleep(step)
            if fail == key and key not in STATE["failed_once"] and i == 2:
                STATE["failed_once"].add(key)
                write({"event": "tools.progress", "data": {"key": key, "state": "failed", "bytes": total // 4,
                                                           "total": total, "error": "checksum mismatch (fake)"}})
                ok = False
                break
            write({"event": "tools.progress", "data": {"key": key, "state": "running", "bytes": total * i // 4, "total": total}})
        else:
            write({"event": "tools.progress", "data": {"key": key, "state": "done", "bytes": total, "total": total}})
    if ok:
        STATE["verified"] = True
        write({"event": "tools.progress", "data": {"key": "warmup", "state": "running"}})
        time.sleep(step * 2)
        write({"event": "tools.progress", "data": {"key": "warmup", "state": "done"}})
    write({"event": "tools.done", "data": {"ok": ok, "status": status()}})


def main():
    if sys.argv[1:] != ["serve"]:
        sys.exit(2)
    if os.environ.get("FAKE_TOOLS_VERIFIED") == "1":
        STATE["verified"] = True
    log("serve: started")
    write({"event": "ready", "data": {"pid": os.getpid()}})
    for line in sys.stdin:
        try:
            request = json.loads(line)
        except ValueError:
            continue
        rid = request.get("id")
        method = request.get("method")
        params = request.get("params") or {}
        log(f"got {method} #{rid}")
        if method == "shutdown":
            write({"id": rid, "result": {"bye": True}})
            break
        if method == "hello":
            write({"id": rid, "result": {
                "engine": "fake", "version": "0.0.1", "protocol": 1, "pid": os.getpid(),
                "python": sys.version.split()[0], "vision": True, "livetext": False,
                "ffmpeg": {"path": "/fake/ffmpeg", "version": "7.1"} if STATE["verified"] else None,
                "languages": ["it-IT", "en-US"],
                "state_folder": os.environ.get("SUBVISION_STATO", "")}})
        elif method == "tools.status":
            write({"id": rid, "result": status()})
        elif method == "tools.install":
            keys = params.get("keys")
            if keys is None:
                keys = ["ffmpeg"]
            write({"id": rid, "result": {"started": True, "keys": keys}})
            threading.Thread(target=install, args=(keys,), daemon=True).start()
        elif method == "echo":
            write({"id": rid, "result": params})
        elif method == "quit":
            os._exit(0)
        else:
            write({"id": rid, "error": {"code": "unknown_method", "message": str(method)}})
    log("serve: stdin closed, exiting")


if __name__ == "__main__":
    main()
