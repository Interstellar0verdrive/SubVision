#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SubVision — lightweight check for a newer release on GitHub.

At most one request every 24h (timestamp + last result cached in
.ui_prefs.json), short timeout, and every error is swallowed: offline or
any failure means "no update", never a slower or broken startup.
No streamlit here, so it can be tested headless.
"""

import json
import re
import time
import urllib.error
import urllib.request
from pathlib import Path

RELEASES_API = "https://api.github.com/repos/Interstellar0verdrive/SubVision/releases/latest"
RELEASES_PAGE = "https://github.com/Interstellar0verdrive/SubVision/releases/latest"
CHECK_EVERY = 24 * 3600     # seconds between two network checks
TIMEOUT = 2.5               # seconds


def parse_version(v: str) -> tuple:
    """'v1.2.3' / '1.2' -> (1, 2, 3) / (1, 2, 0); () if unparsable."""
    m = re.match(r"\s*v?(\d+)(?:\.(\d+))?(?:\.(\d+))?", str(v or ""))
    return tuple(int(x or 0) for x in m.groups()) if m else ()


def is_newer(tag: str, current: str) -> bool:
    new, cur = parse_version(tag), parse_version(current)
    return bool(new and cur and new > cur)


def fetch_latest_tag(url: str = RELEASES_API, timeout: float = TIMEOUT) -> str | None:
    """tag_name of the latest release (raises on network/HTTP errors)."""
    req = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github+json", "User-Agent": "SubVision"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r).get("tag_name")


def check_for_update(prefs_path: Path, current: str, url: str = RELEASES_API,
                     timeout: float = TIMEOUT, now: float | None = None) -> str | None:
    """Newer release tag (e.g. 'v1.1.0') or None. Never raises."""
    try:
        now = time.time() if now is None else now
        try:
            prefs = json.loads(Path(prefs_path).read_text(encoding="utf-8"))
            if not isinstance(prefs, dict):
                prefs = {}
        except Exception:
            prefs = {}
        cache = prefs.get("update_check")
        cache = cache if isinstance(cache, dict) else {}
        latest = cache.get("latest")
        try:
            fresh = 0 <= now - float(cache.get("ts", 0)) < CHECK_EVERY
        except Exception:
            fresh = False
        if not fresh:
            try:
                latest = fetch_latest_tag(url, timeout)
            except urllib.error.HTTPError as e:
                if e.code == 404:       # no release published yet
                    latest = None
            except Exception:
                pass                    # offline / timeout: keep the last result
            # failed attempts are recorded too: no retry (and no timeout) until tomorrow
            prefs["update_check"] = {"ts": now, "latest": latest}
            try:
                Path(prefs_path).write_text(json.dumps(prefs), encoding="utf-8")
            except Exception:
                pass
        return latest if latest and is_newer(latest, current) else None
    except Exception:
        return None
