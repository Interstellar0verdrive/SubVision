"""
Folders of the SubVision engine.

State folder: `$SUBVISION_STATO` when set (the Debug build of the app
passes `~/Library/Application Support/SubVision-dev`), otherwise
`~/Library/Application Support/SubVision`. Inside it: `bin/` (uv, ffmpeg,
ffprobe), `records/` (engine log), `tmp/` (work folders of the batch) and
`tmp/preview/` (whole frames of the preview), plus `ignore.txt` and
`correzioni.txt` (see lists.py).

Engine root: the folder that holds `src/` and `defaults/`. In the repo it
is the checkout; in the app bundle `copy_engine.sh` copies `defaults/`
next to `src/`, so the same relative path works in both places.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

STATE_ENV = "SUBVISION_STATO"
DEFAULT_STATE = Path.home() / "Library" / "Application Support" / "SubVision"


def state_dir() -> Path:
    """The state folder (not created here: see StatePaths.ensure)."""
    env = os.environ.get(STATE_ENV, "").strip()
    return Path(env).expanduser() if env else DEFAULT_STATE


def engine_root() -> Path:
    """The folder that contains `src/subvision` and `defaults/`."""
    return Path(__file__).resolve().parents[2]


def defaults_dir() -> Path:
    return engine_root() / "defaults"


@dataclass(frozen=True)
class StatePaths:
    root: Path

    @property
    def bin(self) -> Path:
        return self.root / "bin"

    @property
    def records(self) -> Path:
        return self.root / "records"

    @property
    def tmp(self) -> Path:
        return self.root / "tmp"

    @property
    def preview(self) -> Path:
        return self.tmp / "preview"

    def ensure(self) -> "StatePaths":
        """Creates the folder and its subfolders (idempotent)."""
        for d in (self.root, self.bin, self.records, self.tmp, self.preview):
            d.mkdir(parents=True, exist_ok=True)
        return self


def state_paths(root: Optional[Path | str] = None) -> StatePaths:
    """The state folders, rooted at `root` or at state_dir()."""
    return StatePaths(Path(root) if root is not None else state_dir())
