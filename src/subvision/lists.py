"""
The two user lists of the engine, kept in the state folder:

  ignore.txt       lines to discard when they come out of the OCR
                   (fansub credits, watermarks, ...), one per line;
  corrections.txt  "wrong => right" replacements applied at the end.

Both are created on first use by copying `defaults/ignore.txt` and
`defaults/corrections.txt` of the engine (comments that explain the
format). The user edits them from Settings; "Import..." replaces one of
them with a file of the 1.x installation (whose corrections list was
called `correzioni.txt`: it is imported like any other text file).
"""

from __future__ import annotations

import shutil
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from subvision import core
from subvision.paths import defaults_dir, state_dir

KINDS = ("ignore", "corrections")
FILE_NAMES = {"ignore": "ignore.txt", "corrections": "corrections.txt"}

Lists = Tuple[List[str], List[Tuple[str, str]]]   # (ignore_lines, corrections)


def path_of(kind: str, state: Optional[Path | str] = None) -> Path:
    """`<state>/ignore.txt` or `<state>/corrections.txt`."""
    if kind not in FILE_NAMES:
        raise ValueError(f"unknown list kind: {kind!r}")
    root = Path(state) if state is not None else state_dir()
    return root / FILE_NAMES[kind]


def ensure(state: Optional[Path | str] = None) -> Dict[str, Path]:
    """
    Creates the missing lists from the engine defaults (the state folder
    too, if needed). Existing files are never touched. Returns the paths.
    """
    out: Dict[str, Path] = {}
    for kind in KINDS:
        dst = path_of(kind, state)
        if not dst.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            src = defaults_dir() / FILE_NAMES[kind]
            if src.is_file():
                shutil.copyfile(src, dst)
            else:
                dst.write_text("", encoding="utf-8")
        out[kind] = dst
    return out


def count(kind: str, state: Optional[Path | str] = None) -> int:
    """Active entries of a list (comments and empty lines excluded)."""
    path = path_of(kind, state)
    if kind == "ignore":
        return len(core.load_ignore(path))
    return len(core.load_corrections(path))


def status(state: Optional[Path | str] = None) -> Dict[str, Dict[str, object]]:
    """{ignore: {path, count}, corrections: {path, count}} (the `lists.status` reply)."""
    paths = ensure(state)
    return {kind: {"path": str(paths[kind]), "count": count(kind, state)} for kind in KINDS}


def load(use_ignore: bool = True, use_corrections: bool = True,
         state: Optional[Path | str] = None) -> Lists:
    """
    (ignore_lines, corrections) for OcrParams / fix_srt / test_frame; an
    empty list when the corresponding switch is off.
    """
    paths = ensure(state)
    ignore = core.load_ignore(paths["ignore"]) if use_ignore else []
    corrections = core.load_corrections(paths["corrections"]) if use_corrections else []
    return ignore, corrections


def import_file(kind: str, src: Path | str, state: Optional[Path | str] = None) -> Path:
    """
    "Import...": replaces the list `kind` with a copy of `src` (a text file,
    e.g. the ignore.txt of a 1.x installation). Returns the state path.
    """
    src = Path(src)
    if not src.is_file():
        raise FileNotFoundError(str(src))
    dst = path_of(kind, state)
    dst.parent.mkdir(parents=True, exist_ok=True)
    text = src.read_text(encoding="utf-8", errors="replace")
    dst.write_text(text, encoding="utf-8")
    return dst
