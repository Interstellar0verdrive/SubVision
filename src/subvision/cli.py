"""
Command-line interface of the engine (`subvision`, plan D9): the same
engine the app uses, without the app. A test bench more than a product:
one page in the README is all the documentation it gets.

    subvision extract <video...> [options]   hardsubs -> SRT + review report + log
    subvision fix <srt> [options]            Sub fix of an existing SRT
    subvision preview <video> [--n 20]       sample frames and whether they have text
    subvision serve                          the sidecar of the app (JSON lines)
    subvision --version

Progress goes to stderr, one line per step; results (the files written)
to stdout. Texts in English. ffmpeg/ffprobe: `--ffmpeg PATH`, then
`$SUBVISION_FFMPEG`, then the ones downloaded by the app in the state
folder, then the PATH.
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
import threading
from pathlib import Path
from typing import Any, Dict, List, Optional

from subvision import __version__, batch, core, fix, lists, preview, tools
from subvision.core import OcrParams
from subvision.paths import state_paths

DEFAULTS = OcrParams()


# ---------------------------------------------------------------- arguments
def _add_band_options(ap: argparse.ArgumentParser) -> None:
    ap.add_argument("--lang", default=DEFAULTS.lang_hint,
                    help=f"OCR language (name or BCP-47 code; default {DEFAULTS.lang_hint})")
    ap.add_argument("--bottom-pct", type=int, default=DEFAULTS.bottom_keep_pct,
                    help="height of the dialogue band, %% from the bottom")
    ap.add_argument("--bottom-width", type=int, default=DEFAULTS.keep_w_pct,
                    help="centred width of the dialogue band, %%")
    group = ap.add_mutually_exclusive_group()
    group.add_argument("--top", dest="top_band", action="store_true", default=DEFAULTS.top_band,
                       help="read the signs band too (default)")
    group.add_argument("--no-top", dest="top_band", action="store_false",
                       help="skip the signs band")
    ap.add_argument("--top-pct", type=int, default=DEFAULTS.top_keep_pct,
                    help="height of the signs band, %% from the top")
    ap.add_argument("--top-width", type=int, default=DEFAULTS.top_keep_w_pct,
                    help="centred width of the signs band, %%")


def _add_ocr_options(ap: argparse.ArgumentParser) -> None:
    ap.add_argument("--fps", type=float, default=DEFAULTS.fps, help="frames per second analysed")
    ap.add_argument("--skip-hamming", type=int, default=DEFAULTS.skip_hamming,
                    help="skip near-identical frames (0 = OCR every frame)")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--multi", dest="multi_variant", action="store_true",
                   default=DEFAULTS.multi_variant, help="3 OCR variants with voting (default)")
    g.add_argument("--no-multi", dest="multi_variant", action="store_false",
                   help="a single OCR reading per frame")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--refine", dest="refine_timing", action="store_true",
                   default=DEFAULTS.refine_timing, help="refine the timings at the native fps (default)")
    g.add_argument("--no-refine", dest="refine_timing", action="store_false")
    ap.add_argument("--min-conf", type=float, default=DEFAULTS.min_confidence,
                    help="minimum OCR confidence")
    ap.add_argument("--min-duration", type=float, default=DEFAULTS.min_duration,
                    help="segments shorter than this are dropped (seconds)")
    ap.add_argument("--merge-gap", type=float, default=DEFAULTS.merge_gap,
                    help="merge similar segments closer than this (seconds)")
    ap.add_argument("--wrap", type=int, default=DEFAULTS.wrap_width, help="line wrap width")
    ap.add_argument("--workers", type=int, default=DEFAULTS.workers, help="OCR threads")
    ap.add_argument("--gap-warn", type=float, default=DEFAULTS.qc_gap_warn,
                    help="gaps without subtitles longer than this go in the report")
    ap.add_argument("--no-report", dest="qc_report", action="store_false",
                    default=DEFAULTS.qc_report, help="do not write the review report")


def _add_lists_options(ap: argparse.ArgumentParser) -> None:
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--ignore", dest="use_ignore", action="store_true", default=True,
                   help="use the ignore list of the state folder (default)")
    g.add_argument("--no-ignore", dest="use_ignore", action="store_false")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--corrections", dest="use_corrections", action="store_true", default=True,
                   help="use the corrections list of the state folder (default)")
    g.add_argument("--no-corrections", dest="use_corrections", action="store_false")


def _add_tools_option(ap: argparse.ArgumentParser) -> None:
    ap.add_argument("--ffmpeg", default=None, help="ffmpeg to use (ffprobe is looked for next to it)")


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="subvision",
                                 description="SubVision engine: hardsubs to SRT with Apple Vision.")
    ap.add_argument("--version", "-V", action="version", version=f"subvision {__version__}")
    sub = ap.add_subparsers(dest="command")

    ex = sub.add_parser("extract", help="extract the hardsubs of one or more videos")
    ex.add_argument("videos", nargs="+", help="video files")
    _add_ocr_options(ex)
    _add_band_options(ex)
    _add_lists_options(ex)
    _add_tools_option(ex)
    ex.add_argument("--log-lang", choices=("en", "it"), default="en",
                    help="language of the per-file log and initial language of the "
                         "review report (which carries both)")

    fx = sub.add_parser("fix", help="clean up an existing SRT (Sub fix)")
    fx.add_argument("srt", help="the .srt file")
    fx.add_argument("--no-merge", dest="merge", action="store_false", default=True,
                    help="do not merge nearby similar lines")
    fx.add_argument("--no-ignore", dest="ignore", action="store_false", default=True,
                    help="do not drop the lines of the ignore list")
    fx.add_argument("--no-flash", dest="flash", action="store_false", default=True,
                    help="keep the flashes shorter than --min-dur")
    fx.add_argument("--min-dur", type=float, default=0.2, help="flash threshold (seconds)")
    fx.add_argument("--merge-gap", type=float, default=DEFAULTS.merge_gap)
    fx.add_argument("--wrap", type=int, default=DEFAULTS.wrap_width)
    fx.add_argument("--lang", default=DEFAULTS.lang_hint, help="language for the line wrapping")
    fx.add_argument("--no-corrections", dest="use_corrections", action="store_false", default=True)

    pv = sub.add_parser("preview", help="sample frames of a video and say which have text")
    pv.add_argument("video")
    pv.add_argument("--n", type=int, default=20, help="frames to sample")
    pv.add_argument("--tries", type=int, default=3, help="timestamps tried per zone")
    _add_band_options(pv)
    _add_tools_option(pv)

    sub.add_parser("serve", help="run the sidecar of the app (JSON lines on stdin/stdout)")
    return ap


# ---------------------------------------------------------------- helpers
def _params_from(args: argparse.Namespace) -> OcrParams:
    p = OcrParams(lang_hint=args.lang,
                  bottom_keep_pct=args.bottom_pct, keep_w_pct=args.bottom_width,
                  top_band=args.top_band, top_keep_pct=args.top_pct,
                  top_keep_w_pct=args.top_width)
    for attr, name in (("fps", "fps"), ("skip_hamming", "skip_hamming"),
                       ("multi_variant", "multi_variant"), ("refine_timing", "refine_timing"),
                       ("min_confidence", "min_conf"), ("min_duration", "min_duration"),
                       ("merge_gap", "merge_gap"), ("wrap_width", "wrap"),
                       ("workers", "workers"), ("qc_gap_warn", "gap_warn"),
                       ("qc_report", "qc_report")):
        if hasattr(args, name):
            setattr(p, attr, getattr(args, name))
    return p


def _setup_tools(custom: Optional[str]) -> bool:
    """Configures ffmpeg/ffprobe: --ffmpeg, $SUBVISION_FFMPEG, the state folder, the PATH."""
    state = state_paths().root
    custom = custom or os.environ.get("SUBVISION_FFMPEG") or None
    ffmpeg = tools.ffmpeg_path(state, custom) or shutil.which("ffmpeg")
    ffprobe = tools.ffprobe_path(state, custom) or shutil.which("ffprobe")
    if not ffmpeg or not ffprobe:
        print("error: ffmpeg/ffprobe not found (pass --ffmpeg, set SUBVISION_FFMPEG, "
              "or run the app once to download them)", file=sys.stderr)
        return False
    core.set_tools(ffmpeg, ffprobe)
    return True


def _hms(sec: float) -> str:
    return core.fmt_hms(sec)


# ---------------------------------------------------------------- commands
def cmd_extract(args: argparse.Namespace) -> int:
    if not _setup_tools(args.ffmpeg):
        return 2
    videos = [Path(v) for v in args.videos]
    missing = [v for v in videos if not v.is_file()]
    if missing:
        print("error: not found: " + ", ".join(str(m) for m in missing), file=sys.stderr)
        return 2
    p = _params_from(args)
    state = state_paths().ensure()
    ignore, corrections = lists.load(args.use_ignore, args.use_corrections, state.root)
    lang = args.log_lang
    failed = {"n": 0}
    last_step: Dict[str, Optional[str]] = {"id": None}

    def emit(event: str, data: Dict[str, Any]) -> None:
        if event == "batch.file.started":
            print(f"[{data['idx'] + 1}/{data['total']}] {data['name']} -> {Path(data['srt']).name}",
                  file=sys.stderr)
            last_step["id"] = None
        elif event == "batch.step":
            sid = f"{data['step']}:{data['band']}"
            if sid != last_step["id"]:
                last_step["id"] = sid
                print(f"    {data['step']} · {data['band']} ...", file=sys.stderr)
            if data["ratio"] >= 1.0:
                print(f"    {data['step']} · {data['band']}: {data['count']}/{data['total']} "
                      f"{data['unit']} in {_hms(data['elapsed'])}", file=sys.stderr)
        elif event == "batch.file.done":
            note = " (no subtitles found)" if data["empty"] else ""
            print(f"    done: {data['segments']} lines, {data['dropped']} dropped, "
                  f"{data['refined']} boundaries refined, {_hms(data['elapsed'])}{note}",
                  file=sys.stderr)
            print(data["srt"])
            if data.get("report"):
                print(data["report"])
        elif event == "batch.file.failed":
            failed["n"] += 1
            print(f"    FAILED at {data['at_step']}: {data['error']}", file=sys.stderr)
        elif event == "batch.file.stopped":
            print("    stopped", file=sys.stderr)
        elif event == "batch.done":
            print(f"batch: {data['done']} done, {data['failed']} failed, "
                  f"{data['stopped']} stopped, {_hms(data['elapsed'])}", file=sys.stderr)

    control = batch.BatchControl()
    try:
        batch.run_batch(videos, p, {"ignore": ignore, "corrections": corrections}, lang,
                        emit, control, tmp_root=state.tmp, ui_lang=lang)
    except core.EngineError as e:
        print(f"error: {e.describe()}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        control.stop("all")
        print("interrupted", file=sys.stderr)
        return 130
    return 1 if failed["n"] else 0


def cmd_fix(args: argparse.Namespace) -> int:
    state = state_paths().ensure()
    pair = lists.load(True, args.use_corrections, state.root)
    p = OcrParams(merge_gap=args.merge_gap, wrap_width=args.wrap, lang_hint=args.lang)
    try:
        out, count = fix.fix_srt(args.srt, merge=args.merge, ignore=args.ignore,
                                 flash=args.flash, min_dur=args.min_dur, params=p, lists=pair)
    except core.EngineError as e:
        print(f"error: {e.describe()}", file=sys.stderr)
        return 2
    print(f"{count} lines -> {out.name}", file=sys.stderr)
    print(out)
    return 0


def cmd_preview(args: argparse.Namespace) -> int:
    if not _setup_tools(args.ffmpeg):
        return 2
    if not Path(args.video).is_file():
        print(f"error: not found: {args.video}", file=sys.stderr)
        return 2
    p = _params_from(args)
    state = state_paths().ensure()

    def emit(event: str, data: Dict[str, Any]) -> None:
        if event == "preview.progress":
            print(f"\r    {data['done']}/{data['total']} frames, {data['found']} with text",
                  end="", file=sys.stderr, flush=True)

    try:
        frames = preview.find_frames(args.video, p, n=args.n, tries=args.tries, emit=emit,
                                     stop=threading.Event(), state=state.root)
    except core.EngineError as e:
        print(f"\nerror: {e.describe()}", file=sys.stderr)
        return 2
    print(file=sys.stderr)
    for f in frames:
        flag = f["band"] or "-"
        print(f"{f['ts']:8.3f}s  {flag:6s}  {f['path']}")
    print(f"{sum(1 for f in frames if f['has_text'])}/{len(frames)} frames with text",
          file=sys.stderr)
    return 0


def cmd_serve(_args: argparse.Namespace) -> int:
    from subvision import serve
    return serve.main()


def main(argv: Optional[List[str]] = None) -> int:
    ap = build_parser()
    args = ap.parse_args(argv)
    if args.command is None:
        ap.print_help(sys.stderr)
        return 2
    return {"extract": cmd_extract, "fix": cmd_fix, "preview": cmd_preview,
            "serve": cmd_serve}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
