# SPDX-License-Identifier: MIT
"""A stand-in for `subvision serve`, for the SVEngine tests.

Speaks the JSON-lines protocol: `{"id", "method", "params"}` in,
`{"id", "result"}` or `{"id", "error"}` out, `{"event", "data"}` pushed.
Methods: hello, echo, sleep (answers from a thread, so replies can overtake
each other), events, noise, signals, crash, quit, shutdown.
"""

import json
import os
import signal
import sys
import threading
import time

LOCK = threading.Lock()


def log(text):
    """stderr goes to the engine log, like the real engine's."""
    sys.stderr.write(f"fake_engine[{os.getpid()}]: {text}\n")
    sys.stderr.flush()


def write(obj):
    with LOCK:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()
    log(f"wrote {obj}")


def main():
    if sys.argv[1:] != ["serve"]:
        sys.exit(2)
    log("serve: started")
    write({"event": "ready", "data": {"pid": os.getpid()}})
    for line in sys.stdin:
        try:
            request = json.loads(line)
        except ValueError:
            continue
        rid = request.get("id")
        method = request.get("method")
        log(f"got {method} #{rid}")
        params = request.get("params") or {}
        if method == "shutdown":
            write({"id": rid, "result": {"bye": True}})
            break
        if method == "hello":
            write({"id": rid, "result": {
                "engine": "fake", "version": "0.0.1", "protocol": 1, "pid": os.getpid(),
                "python": sys.version.split()[0], "vision": True, "livetext": False,
                "ffmpeg": None, "languages": ["it-IT", "en-US"],
                "state_folder": os.environ.get("SUBVISION_STATO", ""),
                "code_folder": os.environ.get("SUBVISION_CODE", ""),
                "cwd": os.getcwd()}})
        elif method == "echo":
            write({"id": rid, "result": params})
        elif method == "sleep":
            seconds = float(params.get("seconds", 1))

            def later(rid=rid, seconds=seconds):  # bound now, not when the thread runs
                time.sleep(seconds)
                write({"id": rid, "result": {"slept": seconds}})

            threading.Thread(target=later, daemon=True).start()
        elif method == "events":
            n = int(params.get("n", 1))
            for i in range(n):
                write({"event": "tick", "data": {"i": i}})
            write({"id": rid, "result": {"sent": n}})
        elif method == "noise":
            with LOCK:
                print("not json, must be ignored", flush=True)
                print("", flush=True)
            write({"id": rid, "result": {"ok": True}})
        elif method == "signals":
            blocked = sorted(int(s) for s in signal.pthread_sigmask(signal.SIG_BLOCK, []))
            write({"id": rid, "result": {"blocked": blocked}})
        elif method == "crash":
            os._exit(3)
        elif method == "quit":
            os._exit(0)
        else:
            write({"id": rid, "error": {"code": "unknown_method", "message": str(method)}})
    log("serve: stdin closed, exiting")


if __name__ == "__main__":
    main()
