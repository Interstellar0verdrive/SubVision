"""
Rebuilds the old-format review reports of this folder with the old engines'
own write_qc_html and small synthetic data (no frame of a real video: the
thumbnails are 16x6 plain JPEGs):

  old-1.0-it.revisione.html, old-1.0-en.revisione.html   v1.0.0 (ocr_core.py)
  old-2.0-early.revisione.html     2.0 at bdc2e8f (13/11: app bridge, Italian only)
  old-2.0-bilingual.review.html    2.0 just before report v2 (ff4d755~1: both languages)

    uv run python tests/fixtures/old-reports/make_fixtures.py

Needs the git history (the tag and the commits above) and Pillow.
"""

from __future__ import annotations

import base64
import importlib
import io
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def git_show(ref: str, path: str) -> str:
    return subprocess.run(["git", "-C", str(ROOT), "show", f"{ref}:{path}"],
                          check=True, capture_output=True, text=True).stdout


def thumb(color: tuple) -> str:
    im = Image.new("RGB", (16, 6), color)
    b = io.BytesIO()
    im.save(b, "JPEG", quality=60)
    return base64.b64encode(b.getvalue()).decode()


def build(mod, lang: str, name: str, video: str, srt: str) -> None:
    # The flags as that pipeline put them in SegInfo.flags (text in 1.0, codes later):
    # the keys of the English table are what the pipeline wrote.
    flags = list(mod._QC_I18N["en"]["flags"].keys())
    fade = next(f for f in flags if "fade" in f)
    short = next(f for f in flags if "short" in f or "breve" in f)
    noise = next(f for f in flags if "noise" in f or "rumore" in f)
    Seg = mod.SegInfo
    segs = [
        Seg(1.0, 3.0, "Hello there, Mira.", conf=0.97, agree=1.0, nframes=20, thumb=thumb((40, 60, 90))),
        Seg(3.5, 5.0, "Where are you going?", conf=0.72, agree=0.6, nframes=14, thumb=thumb((50, 50, 50)),
            alts=["Where are you goinq?", "Wh ere are you going?"], flags=[fade]),
        Seg(5.0, 7.0, "NORTH GATE", conf=0.9, agree=0.9, nframes=12, top=True, thumb=thumb((90, 30, 30))),
        Seg(20.0, 22.5, "To the river,\nbefore the night.", conf=0.45, agree=0.4, nframes=18,
            thumb=thumb((20, 80, 20))),
    ]
    dropped = [
        Seg(8.0, 8.1, "x", conf=0.4, agree=0.5, nframes=1, thumb=thumb((10, 10, 10)), flags=[short]),
        Seg(9.0, 9.4, ". L", conf=0.4, agree=0.5, nframes=3, thumb=thumb((30, 30, 30)), flags=[noise]),
    ]
    gaps = [(7.0, 20.0, thumb((60, 60, 0))), (22.5, 40.0, thumb((0, 60, 60)))]
    stats = mod.RunStats(frames=480, ocr_calls=900, segments=4, dropped=2, refined=6, elapsed=75.8)
    mod.write_qc_html(HERE / name, video, srt, segs, dropped, gaps, stats, mod.OcrParams(), ui_lang=lang)
    print("wrote", name, (HERE / name).stat().st_size, "bytes")


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        (tmp / "v10").mkdir()
        (tmp / "v10" / "ocr_core.py").write_text(git_show("v1.0.0", "ocr_core.py"))
        sys.path.insert(0, str(tmp / "v10"))
        v10 = importlib.import_module("ocr_core")
        build(v10, "it", "old-1.0-it.revisione.html", "clip-a.mp4", "clip-a.srt")
        build(v10, "en", "old-1.0-en.revisione.html", "clip-b.mp4", "clip-b.srt")
        sys.path.pop(0)
        for ref, name in (("bdc2e8f", "old-2.0-early.revisione.html"),
                          ("ff4d755~1", "old-2.0-bilingual.review.html")):
            pkg = tmp / ref.replace("~", "_") / "subvision"
            pkg.mkdir(parents=True)
            for f in ("__init__.py", "core.py"):
                (pkg / f).write_text(git_show(ref, f"src/subvision/{f}"))
            for m in [k for k in sys.modules if k == "subvision" or k.startswith("subvision.")]:
                del sys.modules[m]
            sys.path.insert(0, str(pkg.parent))
            core = importlib.import_module("subvision.core")
            build(core, "it", name, "clip-c.mkv", "clip-c_20261113_224348.srt")
            sys.path.pop(0)


if __name__ == "__main__":
    main()
