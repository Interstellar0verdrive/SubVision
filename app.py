#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SubVision — GUI (Streamlit)

Extracts hardsubs (burned-in subtitles) from the videos in ./videos and
converts them to .srt using Apple Vision (macOS native OCR). Designed for
MAXIMUM accuracy: multi-variant OCR with voting, timing refinement at the
native frame rate, optional signs band and a review report for guided
manual review.

Start:  ./run.command   (or)  streamlit run app.py
The logic lives in ocr_core.py (testable without the UI).
The interface strings (it/en) live in i18n.py.
"""

import re
import json
import time
import tempfile
import datetime
import subprocess
from pathlib import Path

import streamlit as st
from PIL import Image, ImageDraw

import ocr_core as core
import i18n

# ---------------------------------------------------------------- Config
BASE_DIR = Path(__file__).resolve().parent
VIDEOS_DIR = BASE_DIR / "videos"; VIDEOS_DIR.mkdir(exist_ok=True)
TMP_ROOT = BASE_DIR / "tmp"; TMP_ROOT.mkdir(exist_ok=True)
IGNORE_FILE = BASE_DIR / "ignore.txt"
CORRECTIONS_FILE = BASE_DIR / "correzioni.txt"
PREFS_FILE = BASE_DIR / ".ui_prefs.json"
VIDEO_EXT = {".mp4", ".mkv", ".mov", ".avi", ".m4v", ".webm"}

st.set_page_config(page_title="SubVision", page_icon="🎬", layout="wide")

# Readable (?) tooltips: background distinct from the rest of the page + spaced lists.
st.markdown("""
<style>
div[data-testid="stTooltipContent"]{
  background:#1b2b4d !important;
  border:1px solid #44639f !important;
  border-radius:10px !important;
  box-shadow:0 8px 28px #000d !important;
  max-width:480px !important;
}
div[data-testid="stTooltipContent"] p,
div[data-testid="stTooltipContent"] li{
  color:#eaf1ff !important;
  font-size:13.5px !important;
  line-height:1.55 !important;
}
div[data-testid="stTooltipContent"] ul{
  margin:6px 0 6px 2px !important;
  padding-left:18px !important;
}
div[data-testid="stTooltipContent"] li{ margin-bottom:3px !important; }
</style>
""", unsafe_allow_html=True)

# ---------------------------------------------------------------- State / lock
defaults = {"busy": False, "start_requested": False, "completed_msgs": [],
            "prev_paths": [], "prev_video": None, "prev_idx": 0}
for k, v in defaults.items():
    if k not in st.session_state:
        st.session_state[k] = v
BUSY = bool(st.session_state["busy"])


# ---------------------------------------------------------------- UI language
def load_ui_lang() -> str:
    """Language saved at the last launch (.ui_prefs.json); fallback: English."""
    try:
        lang = json.loads(PREFS_FILE.read_text(encoding="utf-8")).get("lang")
        return lang if lang in i18n.STRINGS else "en"
    except Exception:
        return "en"


def save_ui_lang(lang: str) -> None:
    try:
        PREFS_FILE.write_text(json.dumps({"lang": lang}), encoding="utf-8")
    except Exception:
        pass


_saved_lang = load_ui_lang()
_lang_labels = list(i18n.LANG_OPTIONS)
_lang_codes = list(i18n.LANG_OPTIONS.values())
with st.sidebar:
    _sel = st.selectbox("🌐 Lingua interfaccia / UI language", _lang_labels,
                        index=_lang_codes.index(_saved_lang), disabled=BUSY,
                        help="Lingua dell'interfaccia e del report di revisione — "
                             "indipendente da 'Lingua (hint)', che riguarda l'OCR.\n\n"
                             "Language of the interface and of the review report — "
                             "independent from 'Language (hint)', which affects the OCR.")
UI_LANG = i18n.LANG_OPTIONS[_sel]
if UI_LANG != _saved_lang:
    save_ui_lang(UI_LANG)
L = i18n.STRINGS[UI_LANG]


def list_videos() -> list[Path]:
    return sorted(p for p in VIDEOS_DIR.glob("*") if p.suffix.lower() in VIDEO_EXT)


def preview_frame(video: str, ts: float) -> Path | None:
    d = Path(tempfile.mkdtemp(prefix="prev_", dir=TMP_ROOT))
    out = d / "p.jpg"
    try:
        subprocess.run(["ffmpeg", "-hide_banner", "-y", "-ss", f"{ts:.3f}",
                        "-i", video, "-frames:v", "1", str(out)],
                       check=True, capture_output=True)
        return out if out.exists() else None
    except Exception:
        return None


def crop_overlay(img_path: str, bottom_pct: int, width_pct: int,
                 top_band: bool, top_pct: int, top_w_pct: int) -> Image.Image:
    im = Image.open(img_path).convert("RGB")
    w, h = im.size
    d = ImageDraw.Draw(im, "RGBA")
    # dialogue band (green)
    ch = int(h * max(1, min(100, bottom_pct)) / 100)
    cw = int(w * max(1, min(100, width_pct)) / 100)
    x0 = (w - cw) // 2
    d.rectangle([x0, h - ch, x0 + cw - 1, h - 1], outline=(0, 200, 0, 255), width=3)
    d.rectangle([x0, h - ch, x0 + cw - 1, h - 1], fill=(0, 200, 0, 40))
    # signs band (blue) with its own width
    if top_band:
        th = int(h * max(1, min(100, top_pct)) / 100)
        tw = int(w * max(1, min(100, top_w_pct)) / 100)
        tx0 = (w - tw) // 2
        d.rectangle([tx0, 0, tx0 + tw - 1, th - 1], outline=(60, 150, 255, 255), width=3)
        d.rectangle([tx0, 0, tx0 + tw - 1, th - 1], fill=(60, 150, 255, 35))
    return im


# ---------------------------------------------------------------- Sidebar
st.title(L["app_title"])

if not core.vision_available():
    st.error(L["vision_missing"])

with st.sidebar:
    st.header(L["ocr_options"])
    st.caption(L["ocr_caption"])
    lang_hint = st.text_input(L["lang_hint_label"], "Italian", disabled=BUSY,
                              help=L["lang_hint_help"])
    fps = st.select_slider(L["fps_label"], options=[4, 6, 8, 10, 12], value=12,
                           disabled=BUSY,
                           help=L["fps_help"])
    multi_variant = st.checkbox(L["multi_variant_label"], True, disabled=BUSY,
                                help=L["multi_variant_help"])
    refine_timing = st.checkbox(L["refine_label"], True, disabled=BUSY,
                                help=L["refine_help"])
    min_conf = st.slider(L["min_conf_label"], 0.0, 1.0, 0.30, 0.05, disabled=BUSY,
                         help=L["min_conf_help"])

    st.header(L["band_bottom_header"])
    bottom_pct = st.slider(L["bottom_pct_label"], 5, 80, 28, 1, disabled=BUSY,
                           help=L["bottom_pct_help"])
    width_pct = st.slider(L["width_pct_label"], 50, 100, 96, 1, disabled=BUSY,
                          help=L["width_pct_help"])

    st.header(L["band_top_header"])
    top_band = st.checkbox(L["top_band_label"], True, disabled=BUSY,
                           help=L["top_band_help"])
    top_pct = st.slider(L["top_pct_label"], 5, 50, 22, 1, disabled=BUSY or not top_band,
                        help=L["top_pct_help"])
    top_w_pct = st.slider(L["top_w_pct_label"], 50, 100, 100, 1,
                          disabled=BUSY or not top_band,
                          help=L["top_w_pct_help"])

    st.header(L["segments_header"])
    min_dur = st.number_input(L["min_dur_label"], 0.05, 2.0, 0.20, 0.05, disabled=BUSY,
                              help=L["min_dur_help"])
    merge_gap = st.number_input(L["merge_gap_label"], 0.0, 2.0, 0.6, 0.1,
                                disabled=BUSY,
                                help=L["merge_gap_help"])
    wrap = st.number_input(L["wrap_label"], 28, 64, 42, 2, disabled=BUSY,
                           help=L["wrap_help"])

    with st.expander(L["advanced"]):
        qc_report = st.checkbox(L["qc_report_label"], True, disabled=BUSY,
                                help=L["qc_report_help"])
        qc_gap = st.number_input(L["qc_gap_label"], 2.0, 30.0, 6.0, 1.0,
                                 disabled=BUSY,
                                 help=L["qc_gap_help"])
        skip_ham = st.slider(L["skip_ham_label"], 0, 4, 0, 1, disabled=BUSY,
                             help=L["skip_ham_help"])
        workers = st.slider(L["workers_label"], 1, 8, 4, 1, disabled=BUSY,
                            help=L["workers_help"])
        use_ignore = st.checkbox(L["use_ignore_label"], True, disabled=BUSY,
                                 help=L["use_ignore_help"])
        use_corrections = st.checkbox(L["use_corrections_label"], True, disabled=BUSY,
                                      help=L["use_corrections_help"])
        clean_tmp = st.checkbox(L["clean_tmp_label"], True, disabled=BUSY,
                                help=L["clean_tmp_help"])

ignore_lines = core.load_ignore(IGNORE_FILE) if use_ignore else []
if use_ignore and not IGNORE_FILE.exists():
    st.sidebar.info(L["ignore_missing"])
corrections = core.load_corrections(CORRECTIONS_FILE) if use_corrections else []


def make_params() -> core.OcrParams:
    return core.OcrParams(
        fps=float(fps), lang_hint=lang_hint,
        bottom_keep_pct=int(bottom_pct), keep_w_pct=int(width_pct),
        top_band=bool(top_band), top_keep_pct=int(top_pct),
        top_keep_w_pct=int(top_w_pct),
        min_confidence=float(min_conf), multi_variant=bool(multi_variant),
        skip_hamming=int(skip_ham), refine_timing=bool(refine_timing),
        min_duration=float(min_dur), merge_gap=float(merge_gap),
        wrap_width=int(wrap), workers=int(workers),
        qc_report=bool(qc_report), qc_gap_warn=float(qc_gap),
        ignore_lines=ignore_lines, corrections=corrections,
    )


# ---------------------------------------------------------------- Tabs
tab_run, tab_prev, tab_fix = st.tabs([L["tab_run"], L["tab_prev"], L["tab_fix"]])

# ===== PROCESS =====
with tab_run:
    st.subheader(L["select_videos"])
    videos = list_videos()
    if not videos:
        st.warning(L["no_videos_warn"])
    else:
        sel = {}
        for p in videos:
            sel[p] = st.checkbox(p.name, value=True, key=f"v_{p.name}", disabled=BUSY)
        st.caption(L["outputs_caption"])

        results = st.container()
        for msg, level in st.session_state["completed_msgs"]:
            (results.success if level == "ok" else
             results.warning if level == "warn" else results.error)(msg)

        c1, c2 = st.columns([1.3, 1])
        with c1:
            start_btn = st.button(L["start_btn"], type="primary", disabled=BUSY,
                                  use_container_width=True,
                                  help=L["start_btn_help"])
        with c2:
            if st.button(L["reset_msgs_btn"], disabled=BUSY, use_container_width=True):
                st.session_state["completed_msgs"] = []
                st.rerun()

        # first click: lock the UI and rerun (the widgets get disabled)
        if start_btn and not BUSY:
            st.session_state["busy"] = True
            st.session_state["start_requested"] = True
            st.rerun()

        if st.session_state["start_requested"] and st.session_state["busy"]:
            try:
                chosen = [p for p in videos if sel.get(p)]
                if not chosen:
                    st.warning(L["select_at_least_one"])
                elif not core.vision_available():
                    st.error(L["vision_unavailable"])
                else:
                    params = make_params()

                    # ---- step plan (one row each, visible from the start)
                    bands_plan = [("bottom", L["band_dialogues"])]
                    if params.top_band:
                        bands_plan.append(("top", L["band_signs"]))
                    step_plan = []          # [(key, short label)]
                    for bkey, blabel in bands_plan:
                        step_plan.append((f"extract:{bkey}", f"{L['step_extract']} · {blabel}"))
                        step_plan.append((f"group:{bkey}", f"{L['step_group']} · {blabel}"))
                        nv = 3 if params.multi_variant else 1
                        step_plan.append((f"ocr:{bkey}", f"{L['step_ocr'].format(n=nv)} · {blabel}"))
                        if params.refine_timing:
                            step_plan.append((f"refine:{bkey}", f"{L['step_refine']} · {blabel}"))
                    NSTEP = len(step_plan)
                    order = [k for k, _ in step_plan]
                    # step durations from the previous file -> estimates for the next ones
                    prev_dur = st.session_state.setdefault("step_durations", {})

                    for n, video in enumerate(chosen, 1):
                        st.markdown(L["file_header"].format(n=n, tot=len(chosen),
                                                            name=video.name))

                        # per-file log: created BEFORE the steps, so every step
                        # can write its start/end with duration (mirror of the UI)
                        out = video.with_suffix(".srt")
                        note = ""
                        if out.exists():
                            ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
                            out = out.with_name(f"{out.stem}_{ts}.srt")
                            note = L["srt_existed_note"]
                        logp = out.with_suffix(".log")

                        def logcb(msg, _lp=logp):
                            try:
                                with open(_lp, "a", encoding="utf-8") as f:
                                    f.write(f"[{datetime.datetime.now():%H:%M:%S}] {msg}\n")
                            except Exception:
                                pass

                        logcb(f"video={video.name} fps={params.fps} variants={params.multi_variant} "
                              f"refine={params.refine_timing} top_band={params.top_band} "
                              f"crop={params.bottom_keep_pct}/{params.keep_w_pct} "
                              f"skip={params.skip_hamming}")

                        state = {}
                        for i, (key, label) in enumerate(step_plan, 1):
                            slot = st.empty()
                            est = prev_dur.get(key)
                            wait = (L["waiting"] +
                                    (L["waiting_est"].format(est=core.fmt_hms(est))
                                     if est else ""))
                            slot.markdown(L["step_waiting_row"].format(
                                i=i, n=NSTEP, label=label, wait=wait))
                            state[key] = {"slot": slot, "label": label, "idx": i,
                                          "start": None, "done": False, "last": ""}

                        def _rate_unit(key):
                            # refinement processes SRT lines, the other steps frames
                            return L["unit_rows_s"] if key.startswith("refine") else L["unit_fps"]

                        def finish(key, _state=state, _logcb=logcb):
                            row = _state[key]
                            if row["done"]:
                                return
                            row["done"] = True
                            dur = (time.time() - row["start"]) if row["start"] else 0.0
                            row["dur"] = dur
                            prev_dur[key] = dur
                            rate_s = ""
                            # average only if the step lasted long enough to be meaningful
                            if row.get("count") and dur > 1.0:
                                rate_s = L["rate_avg"].format(rate=row["count"] / dur,
                                                              unit=_rate_unit(key))
                            msg = L["step_done"].format(i=row["idx"], n=NSTEP,
                                                        label=row["label"],
                                                        last=row["last"],
                                                        dur=core.fmt_hms(dur),
                                                        rate=rate_s)
                            row["slot"].success(msg)
                            _logcb(msg)

                        def cb(stagekey, ratio, text, _state=state, _finish=finish,
                               _logcb=logcb):
                            row = _state.get(stagekey)
                            if row is None:
                                return
                            # a new step starts -> the previous ones are done
                            for k in order[:order.index(stagekey)]:
                                _finish(k)
                            if row["start"] is None:
                                row["start"] = time.time()
                                _logcb(L["step_start"].format(i=row["idx"], n=NSTEP,
                                                              label=row["label"]))
                            row["last"] = text
                            m = re.search(r"(\d+)\s*/", text) or re.match(r"(\d+)\b", text)
                            if m:
                                row["count"] = int(m.group(1))
                            el = time.time() - row["start"]
                            eta = (el / ratio - el) if ratio > 0.02 else None
                            eta_s = (L["eta"].format(eta=core.fmt_hms(eta))
                                     if eta is not None and ratio < 0.999 else "")
                            rate_s = ""
                            if row.get("count") and el > 1.0:
                                rate_s = L["rate_live"].format(rate=row["count"] / el,
                                                               unit=_rate_unit(stagekey))
                            if ratio >= 1.0:
                                _finish(stagekey)
                            else:
                                row["slot"].progress(
                                    ratio,
                                    text=L["step_progress"].format(
                                        i=row["idx"], n=NSTEP, label=row["label"],
                                        text=text, elapsed=core.fmt_hms(el),
                                        eta=eta_s, rate=rate_s))
                        try:
                            segs, stats = core.process_video(
                                str(video), str(out), params,
                                progress_cb=cb, log_cb=logcb, tmp_root=TMP_ROOT,
                                ui_lang=UI_LANG)
                        except Exception as e:
                            for key, row in state.items():
                                if not row["done"] and row["start"] is not None:
                                    aborted = L["step_aborted"].format(
                                        i=row["idx"], n=NSTEP, label=row["label"])
                                    row["slot"].error(aborted)
                                    logcb(aborted)
                            logcb(L["log_error"].format(e=e))
                            st.session_state["completed_msgs"].append(
                                (L["msg_error"].format(name=video.name, e=e), "err"))
                            continue

                        for k in order:            # close the remaining steps in green
                            finish(k)

                        # duration summary per step kind (sums the bands)
                        agg = {}
                        for key, row in state.items():
                            kind = row["label"].split(" · ")[0]
                            agg[kind] = agg.get(kind, 0.0) + row.get("dur", 0.0)
                        tempi = " · ".join(f"{k} {core.fmt_hms(v)}" for k, v in agg.items())
                        logcb(L["times_summary"].format(times=tempi))
                        logcb(L["log_result"].format(segments=stats.segments,
                                                     dropped=stats.dropped,
                                                     refined=stats.refined,
                                                     elapsed=core.fmt_hms(stats.elapsed)))

                        qc_note = (L["qc_note"].format(name=Path(stats.qc_path).name)
                                   if stats.qc_path else "")
                        if not segs:
                            st.session_state["completed_msgs"].append(
                                (L["msg_no_subs"].format(name=video.name, out=out.name,
                                                         qc=qc_note),
                                 "warn"))
                        else:
                            st.session_state["completed_msgs"].append(
                                (L["msg_done"].format(name=video.name,
                                                      segments=stats.segments,
                                                      out=out.name, note=note,
                                                      dropped=stats.dropped,
                                                      refined=stats.refined,
                                                      elapsed=core.fmt_hms(stats.elapsed),
                                                      qc=qc_note, times=tempi), "ok"))
                    st.toast(L["batch_done_toast"])
                    if clean_tmp:
                        import shutil
                        for d in TMP_ROOT.glob("*"):
                            try:
                                shutil.rmtree(d, ignore_errors=True) if d.is_dir() else d.unlink()
                            except Exception:
                                pass
            finally:
                st.session_state["busy"] = False
                st.session_state["start_requested"] = False
                st.rerun()

# ===== PREVIEW =====
with tab_prev:
    st.subheader(L["prev_subheader"])
    if BUSY:
        st.info(L["disabled_while_busy"])
    else:
        videos = list_videos()
        if not videos:
            st.info(L["no_videos_info"])
        else:
            name = st.selectbox(L["video_select_label"], [p.name for p in videos],
                                help=L["video_select_help"])
            vid = next(p for p in videos if p.name == name)

            N_PREV = 20            # sample frames to show
            TRIES_PER_ZONE = 3     # attempts per zone to find one with text

            if st.button(L["extract_frames_btn"].format(n=N_PREV),
                         help=L["extract_frames_help"].format(n=N_PREV,
                                                              tries=TRIES_PER_ZONE)):
                dur = core.ffprobe_duration(str(vid))
                if dur <= 0:
                    st.warning(L["invalid_duration"])
                else:
                    import numpy as np
                    from concurrent.futures import ThreadPoolExecutor, as_completed

                    use_vision = core.vision_available()
                    langs = core.resolve_langs(lang_hint)
                    if use_vision:
                        core.warmup(langs, "fast")
                    edges = np.linspace(dur * 0.02, dur * 0.98, N_PREV + 1)
                    pbar = st.progress(0.0, text=L["searching_frames"])

                    def probe_zone(i: int):
                        """Returns (i, path, band) — band: 'bottom' | 'top' | None."""
                        a, b = float(edges[i]), float(edges[i + 1])
                        fallback = None
                        # try the center, then the start and end of the zone
                        for f in (0.5, 0.2, 0.8)[:TRIES_PER_ZONE if use_vision else 1]:
                            fp = preview_frame(str(vid), a + (b - a) * f)
                            if not fp:
                                continue
                            if fallback is None:
                                fallback = fp
                            if not use_vision:
                                return i, str(fp), None
                            try:
                                im = Image.open(fp).convert("RGB")
                                w, h = im.size
                                ch = int(h * bottom_pct / 100)
                                cw = int(w * width_pct / 100)
                                band = im.crop(((w - cw) // 2, h - ch,
                                                (w - cw) // 2 + cw, h))
                                txt, _ = core.ocr_conf(band, langs, "fast", 0.25)
                                if txt.strip():
                                    return i, str(fp), "bottom"
                                # no dialogue: if enabled, try the signs band
                                if top_band:
                                    th = int(h * top_pct / 100)
                                    tw = int(w * top_w_pct / 100)
                                    tband = im.crop(((w - tw) // 2, 0,
                                                     (w - tw) // 2 + tw, th))
                                    txt, _ = core.ocr_conf(tband, langs, "fast", 0.25)
                                    if txt.strip():
                                        return i, str(fp), "top"
                            except Exception:
                                pass
                        return i, (str(fallback) if fallback else None), None

                    frames = [None] * N_PREV
                    done = 0
                    with ThreadPoolExecutor(max_workers=4) as ex:
                        futs = [ex.submit(probe_zone, i) for i in range(N_PREV)]
                        for fut in as_completed(futs):
                            i, fp, band = fut.result()
                            if fp:
                                frames[i] = {"path": fp, "has_text": band is not None,
                                             "band": band}
                            done += 1
                            found = sum(1 for x in frames if x and x["has_text"])
                            pbar.progress(done / N_PREV,
                                          text=L["zone_progress"].format(
                                              done=done, tot=N_PREV, found=found))
                    pbar.empty()
                    st.session_state["prev_paths"] = [f for f in frames if f]
                    st.session_state["prev_video"] = name
                    st.session_state["prev_idx"] = 0

            if (st.session_state.get("prev_paths") and
                    st.session_state.get("prev_video") == name):
                frames = st.session_state["prev_paths"]
                n_text = sum(1 for f in frames if f["has_text"])
                st.caption(L["frames_caption"].format(n=len(frames), with_text=n_text,
                                                      without=len(frames) - n_text))
                c1, c2, c3 = st.columns([1, 6, 1])
                with c1:
                    if st.button("◀"):
                        st.session_state["prev_idx"] = max(0, st.session_state["prev_idx"] - 1)
                with c3:
                    if st.button("▶"):
                        st.session_state["prev_idx"] = min(len(frames) - 1,
                                                           st.session_state["prev_idx"] + 1)
                idx = st.session_state["prev_idx"]
                cur = frames[idx]
                with c2:
                    try:
                        if cur.get("band") == "top":
                            badge = L["badge_top_text"]
                        elif cur["has_text"]:
                            badge = L["badge_bottom_text"]
                        else:
                            badge = L["badge_no_text"]
                        st.image(crop_overlay(cur["path"], bottom_pct, width_pct,
                                              top_band, top_pct, top_w_pct),
                                 caption=L["frame_caption"].format(
                                     i=idx + 1, n=len(frames), badge=badge)
                                 + (L["frame_caption_top"] if top_band else ""),
                                 use_container_width=True)
                    except Exception:
                        st.warning(L["preview_unavailable"])

                if st.button(L["test_ocr_btn"],
                             help=L["test_ocr_help"]):
                    im = Image.open(cur["path"]).convert("RGB")
                    w, h = im.size
                    langs = core.resolve_langs(lang_hint)
                    core.warmup(langs)

                    def test_band(label: str, band_img, is_top: bool):
                        st.markdown(f"##### {label}")
                        t0 = time.time()
                        cands = [core.ocr_conf(v, langs, "accurate", min_conf, fw)
                                 for _, v, fw in core.gen_variants(band_img, multi_variant)]
                        text, conf, agree, alts = core.vote_texts(cands)
                        dt = time.time() - t0
                        st.caption(L["ocr_vote_caption"].format(ms=dt * 1000, n=len(cands)))
                        st.code(text or L["empty_text"], language="text")
                        if text:
                            st.caption(L["conf_agree"].format(conf=conf * 100,
                                                              agree=agree * 100)
                                       + (L["alts_suffix"].format(alts=" | ".join(alts))
                                          if alts else ""))
                        clean = core.postprocess(core.sanitize(text, ignore_lines), wrap,
                                                 ignore_lines, corrections,
                                                 lang_hint=lang_hint)
                        if clean:
                            shown = ("{\\an8}" + clean) if is_top else clean
                            st.text_area(L["final_text_label"], shown,
                                         height=100, key=f"testocr_{label}",
                                         help=L["final_text_help"])
                        else:
                            st.warning(L["no_text_in_band"])

                    ch = int(h * bottom_pct / 100); cw = int(w * width_pct / 100)
                    test_band(L["band_bottom_title"],
                              im.crop(((w - cw) // 2, h - ch, (w - cw) // 2 + cw, h)), False)
                    if top_band:
                        th = int(h * top_pct / 100); tw = int(w * top_w_pct / 100)
                        test_band(L["band_top_title"],
                                  im.crop(((w - tw) // 2, 0, (w - tw) // 2 + tw, th)), True)

# ===== SUB FIX =====
with tab_fix:
    st.subheader(L["fix_subheader"])
    st.caption(L["fix_caption"])
    if BUSY:
        st.info(L["disabled_while_busy"])
    else:
        c1, c2 = st.columns(2)
        with c1:
            fx_merge = st.checkbox(L["fx_merge_label"], True,
                                   help=L["fx_merge_help"])
            fx_ignore = st.checkbox(L["fx_ignore_label"], True,
                                    help=L["fx_ignore_help"])
        with c2:
            fx_flash = st.checkbox(L["fx_flash_label"], True,
                                   help=L["fx_flash_help"])
            fx_min = st.number_input(L["fx_min_label"], 0.1, 2.0, 0.2, 0.1,
                                     help=L["fx_min_help"])

        srts = sorted(VIDEOS_DIR.glob("*.srt"))
        src_mode = st.radio(L["source_label"],
                            [L["source_from_videos"], L["source_upload"]],
                            horizontal=True,
                            help=L["source_help"])
        target = None
        if src_mode == L["source_from_videos"]:
            if srts:
                sn = st.selectbox(L["srt_select_label"], [p.name for p in srts])
                target = next(p for p in srts if p.name == sn)
            else:
                st.info(L["no_srt_info"])
        else:
            up = st.file_uploader(L["upload_srt_label"], type=["srt"])
            if up:
                d = Path(tempfile.mkdtemp(prefix="fix_", dir=TMP_ROOT))
                target = d / (up.name or "in.srt")
                target.write_bytes(up.getbuffer())

        if st.button(L["run_fix_btn"]) and target:
            try:
                segs = core.parse_srt(target)
                ext = core.load_ignore(IGNORE_FILE) if (use_ignore and fx_ignore) else []
                if fx_ignore:
                    segs = [(s, e, t) for s, e, t in segs
                            if not core.looks_like_no_subtitle(t, ext)]
                if fx_merge:
                    segs = core.merge_segments(segs, merge_gap=merge_gap, min_duration=0.0,
                                               ignore_lines=ext, wrap=int(wrap),
                                               lang_hint=lang_hint)
                if fx_flash:
                    segs = [x for x in segs if (x[1] - x[0]) >= float(fx_min)]
                if corrections:
                    segs = [(s, e, core.apply_corrections(t, corrections))
                            for s, e, t in segs]
                if not segs:
                    st.error(L["no_valid_segments"])
                else:
                    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
                    outp = (VIDEOS_DIR if src_mode == L["source_from_videos"]
                            else target.parent) / f"{target.stem}-fixed-{ts}.srt"
                    core.write_srt(segs, str(outp))
                    st.success(L["fix_created"].format(name=outp.name, n=len(segs)))
            except Exception as e:
                st.error(L["generic_error"].format(e=e))
