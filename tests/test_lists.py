"""Tests of the state folder paths and of the ignore/corrections lists."""

from __future__ import annotations

from pathlib import Path

import pytest

from subvision import lists, paths


@pytest.fixture
def state(tmp_path: Path, monkeypatch) -> Path:
    """A private state folder, as the app does through SUBVISION_STATO."""
    root = tmp_path / "state"
    monkeypatch.setenv(paths.STATE_ENV, str(root))
    return root


# ---------------------------------------------------------------- paths
def test_state_dir_from_env_or_default(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.delenv(paths.STATE_ENV, raising=False)
    assert paths.state_dir() == Path.home() / "Library" / "Application Support" / "SubVision"
    monkeypatch.setenv(paths.STATE_ENV, str(tmp_path / "dev"))
    assert paths.state_dir() == tmp_path / "dev"
    monkeypatch.setenv(paths.STATE_ENV, "   ")
    assert paths.state_dir() == paths.DEFAULT_STATE


def test_engine_root_has_defaults() -> None:
    root = paths.engine_root()
    assert (root / "src" / "subvision" / "core.py").is_file()
    assert (paths.defaults_dir() / "ignore.txt").is_file()
    assert (paths.defaults_dir() / "corrections.txt").is_file()


def test_state_paths_ensure(state: Path) -> None:
    sp = paths.state_paths()
    assert sp.root == state and not state.exists()
    sp.ensure().ensure()
    for d in (sp.bin, sp.records, sp.tmp, sp.preview):
        assert d.is_dir()
    assert sp.preview == state / "tmp" / "preview"
    assert paths.state_paths(state / "other").root == state / "other"


# ---------------------------------------------------------------- lists
def test_lists_created_from_defaults(state: Path) -> None:
    st = lists.status()
    assert st["ignore"]["path"] == str(state / "ignore.txt")
    assert st["corrections"]["path"] == str(state / "corrections.txt")
    for kind in lists.KINDS:
        p = Path(st[kind]["path"])
        assert p.is_file()
        assert p.read_bytes() == (paths.defaults_dir() / lists.FILE_NAMES[kind]).read_bytes()
    # the defaults only explain the format: nothing active yet
    assert st["ignore"]["count"] == 0 and st["corrections"]["count"] == 0
    assert lists.load() == ([], [])


def test_counts_and_load(state: Path) -> None:
    lists.ensure()
    (state / "ignore.txt").write_text(
        "# comment\nTraduzione a cura di\n\nwww.esempio-fansub.it\n", encoding="utf-8")
    (state / "corrections.txt").write_text(
        "# comment\nFlamilion => Hamilton\nbad line without arrow\n l0ve => love \n",
        encoding="utf-8")
    st = lists.status()
    assert st["ignore"]["count"] == 2 and st["corrections"]["count"] == 2
    ignore, corrections = lists.load()
    assert ignore == ["Traduzione a cura di", "www.esempio-fansub.it"]
    assert corrections == [("Flamilion", "Hamilton"), ("l0ve", "love")]
    assert lists.load(use_ignore=False) == ([], corrections)
    assert lists.load(use_corrections=False) == (ignore, [])
    # the existing files are never overwritten by ensure()
    lists.ensure()
    assert lists.status()["ignore"]["count"] == 2


def test_import_file(state: Path, tmp_path: Path) -> None:
    lists.ensure()
    old = tmp_path / "old-ignore.txt"
    old.write_text("Sottotitoli:\nCredits\n", encoding="utf-8")
    dst = lists.import_file("ignore", old)
    assert dst == state / "ignore.txt"
    assert lists.status()["ignore"]["count"] == 2
    assert lists.load()[0] == ["Sottotitoli:", "Credits"]
    with pytest.raises(FileNotFoundError):
        lists.import_file("corrections", tmp_path / "missing.txt")
    with pytest.raises(ValueError):
        lists.import_file("nope", old)


def test_explicit_state_argument(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.delenv(paths.STATE_ENV, raising=False)
    other = tmp_path / "explicit"
    st = lists.status(other)
    assert Path(st["ignore"]["path"]).parent == other
    assert lists.path_of("corrections", other) == other / "corrections.txt"
