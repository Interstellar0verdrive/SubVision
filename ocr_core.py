#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SubVision — core pipeline (no UI).

Estrae hardsub (sottotitoli incisi nel video) e li converte in .srt usando
Apple Vision (framework OCR nativo di macOS, via il wrapper `ocrmac`).

Filosofia: MASSIMA ACCURATEZZA, la velocita' non e' una priorita'.
L'obiettivo e' minimizzare il rework manuale (sottotitoli saltati, tempi
imprecisi, typo), quindi:

1. OCR MULTI-VARIANTE con voto: ogni frame viene OCR-ato in piu' versioni
   (raw, contrasto+sharpen, grayscale) e il testo si decide a maggioranza
   pesata per confidenza. Nessuna variante vince sempre da sola (misurato).
2. VOTO DI SEGMENTO: il testo finale di un sottotitolo e' quello che ha
   raccolto piu' peso su tutti i frame del segmento (non "il piu' lungo").
3. RAFFINAMENTO TIMING: i confini inizio/fine vengono ricalcolati al
   framerate NATIVO del video (precisione ~1 frame, ~±20ms).
4. BANDA SUPERIORE opzionale per i cartelli/insegne tradotti ({\\an8}).
5. REPORT DI REVISIONE (.revisione.html): ogni riga porta con se'
   confidenza, accordo tra varianti e thumbnail; le righe dubbie, i flash
   scartati e i buchi lunghi finiscono in un report/editor HTML per una
   revisione manuale guidata.

Questo modulo non importa streamlit: puo' essere testato/eseguito headless.
"""

from __future__ import annotations

import io
import os
import re
import time
import base64
import shutil
import hashlib
import tempfile
import subprocess
import datetime
from pathlib import Path
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional, Tuple

from PIL import Image, ImageOps, ImageEnhance, ImageFilter

# ocrmac e' importato "lazy" dentro le funzioni OCR cosi' il modulo si carica
# anche dove Apple Vision non e' disponibile (utile per i test sugli SRT).

# ---------------------------------------------------------------- Lingue
LANG_MAP = {
    "italian": "it-IT", "italiano": "it-IT",
    "english": "en-US", "inglese": "en-US",
    "spanish": "es-ES", "spagnolo": "es-ES",
    "french": "fr-FR", "francese": "fr-FR",
    "german": "de-DE", "tedesco": "de-DE",
    "portuguese": "pt-BR", "portoghese": "pt-BR",
    "japanese": "ja-JP", "giapponese": "ja-JP",
    "korean": "ko-KR", "coreano": "ko-KR",
    "chinese": "zh-Hans", "cinese": "zh-Hans",
}


def resolve_langs(lang_hint: str) -> List[str]:
    key = (lang_hint or "").strip().lower()
    if not key:
        return ["it-IT"]
    if key in LANG_MAP:
        return [LANG_MAP[key]]
    return [lang_hint.strip()]


# ---------------------------------------------------------------- Parametri
@dataclass
class OcrParams:
    """
    Default = MASSIMA ACCURATEZZA (fps alto, nessuno skip, 3 varianti, banda
    cartelli attiva, raffinamento tempi). Con questi valori una puntata da
    20-24 min richiede ~1.5-2 ore. Per un profilo veloce (~10-15 min):
    fps=6, skip_hamming=1, multi_variant=False, top_band=False.
    """
    fps: float = 12.0                  # frame/sec analizzati (12 = max precisione
                                       # nel rilevare sub brevissimi e confini)
    lang_hint: str = "Italian"
    # banda inferiore (dialoghi)
    bottom_keep_pct: int = 28          # altezza tenuta dal basso (%)
    keep_w_pct: int = 96               # larghezza centrata tenuta (%)
    # banda superiore (cartelli / insegne / note del traduttore)
    top_band: bool = True              # ON di default: cattura i cartelli {\an8}
    top_keep_pct: int = 22             # altezza tenuta dall'alto (%)
    top_keep_w_pct: int = 100          # larghezza centrata banda cartelli (%)
                                       # (riduci per escludere watermark negli angoli)
    # OCR
    recognition_level: str = "accurate"
    min_confidence: float = 0.30
    multi_variant: bool = True         # OCR in 3 varianti + voto (consigliato)
    # skip frame ridondanti (dhash vs frame precedente):
    # 0 = OCR di OGNI frame, nessuna assunzione (max accuratezza, default);
    # 1 = salta i quasi-identici (~20-30% piu' veloce, tempi identici misurati);
    # >=2 = piu' veloce ma i confini base si spostano (il raffinamento recupera).
    skip_hamming: int = 0
    # timing
    refine_timing: bool = True         # raffina inizio/fine al framerate nativo
    # segmenti
    min_duration: float = 0.20         # sotto questa durata -> scartato (ma nel report di revisione)
    merge_gap: float = 0.6             # unisci segmenti vicini con testo simile
    wrap_width: int = 42
    workers: int = 4
    # QC
    qc_report: bool = True
    qc_gap_warn: float = 6.0           # buchi senza sub piu' lunghi di X sec nel report di revisione
    qc_conf_warn: float = 0.80         # sotto questa confidenza -> riga "gialla"
    qc_agree_warn: float = 0.70        # sotto questo accordo varianti -> "gialla"
    ignore_lines: List[str] = field(default_factory=list)
    # correzioni automatiche "sbagliato => giusto" (da correzioni.txt):
    # per i typo RICORRENTI che l'OCR non risolvera' mai (es. nomi propri su
    # font impossibili: "Flamilion => Hamilton"). Applicate a fine pipeline.
    corrections: List[Tuple[str, str]] = field(default_factory=list)


@dataclass
class SegInfo:
    start: float
    end: float
    text: str
    conf: float = 1.0                  # confidenza media pesata del testo vincente
    agree: float = 1.0                 # quota di voti del testo vincente (0-1)
    nframes: int = 0                   # frame che compongono il segmento
    top: bool = False                  # True = banda superiore (cartello)
    thumb: str = ""                    # thumbnail JPEG base64 (per il report di revisione)
    alts: List[str] = field(default_factory=list)   # letture alternative scartate
    flags: List[str] = field(default_factory=list)  # note QC


@dataclass
class RunStats:
    frames: int = 0
    ocr_calls: int = 0
    segments: int = 0
    dropped: int = 0
    refined: int = 0
    elapsed: float = 0.0
    qc_path: str = ""


# ---------------------------------------------------------------- ffmpeg
def _run(cmd: list) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, capture_output=True, text=True)


def ffprobe_duration(video: str) -> float:
    try:
        out = _run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                    "-of", "default=nw=1:nk=1", video]).stdout
        return float((out or "0").strip())
    except Exception:
        return 0.0


def ffprobe_fps(video: str) -> float:
    """Framerate nativo del video (per il raffinamento dei confini)."""
    for entry in ("avg_frame_rate", "r_frame_rate"):
        try:
            val = _run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                        "-show_entries", f"stream={entry}",
                        "-of", "default=nk=1:nw=1", video]).stdout.strip()
            if "/" in val:
                n, d = val.split("/")
                fps = float(n) / (float(d) or 1.0)
            else:
                fps = float(val)
            if fps > 0.1:
                return fps
        except Exception:
            continue
    return 24.0


def band_crop(p: OcrParams, band: str) -> str:
    """Espressione crop ffmpeg per la banda richiesta ('bottom' | 'top')."""
    if band == "top":
        vb = max(1, min(100, int(p.top_keep_pct)))
        kw = max(1, min(100, int(p.top_keep_w_pct)))
        crop_w = "iw" if kw >= 100 else f"iw*{kw}/100"
        crop_x = "0" if kw >= 100 else f"(iw-iw*{kw}/100)/2"
        return f"crop={crop_w}:ih*{vb}/100:{crop_x}:0"
    vb = max(1, min(100, int(p.bottom_keep_pct)))
    kw = max(1, min(100, int(p.keep_w_pct)))
    crop_w = "iw" if kw >= 100 else f"iw*{kw}/100"
    crop_x = "0" if kw >= 100 else f"(iw-iw*{kw}/100)/2"
    return f"crop={crop_w}:ih*{vb}/100:{crop_x}:ih-ih*{vb}/100"


def extract_frames(video: str, outdir: Path, p: OcrParams, band: str,
                   progress_cb: Optional[Callable[[float, str], None]] = None
                   ) -> Tuple[List[Path], float]:
    """
    Estrae i frame della banda richiesta, SENZA filtri di enhancement:
    l'immagine raw legge meglio (misurato); le varianti si generano in PIL
    al momento dell'OCR, cosi' possono votare.
    """
    outdir.mkdir(parents=True, exist_ok=True)
    vf = f"fps={p.fps},{band_crop(p, band)}"
    pattern = str(outdir / "f_%08d.jpg")
    cmd = ["ffmpeg", "-hide_banner", "-y", "-i", video, "-vf", vf,
           "-fps_mode", "passthrough", "-q:v", "2", pattern]
    duration = ffprobe_duration(video)
    expected = max(1, int(duration * p.fps)) if duration else 0
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    while proc.poll() is None:
        time.sleep(0.3)
        cnt = sum(1 for _ in outdir.glob("f_*.jpg"))
        if progress_cb and expected:
            progress_cb(min(0.99, cnt / expected), f"{cnt}/~{expected} frame")
    _, err = proc.communicate()
    if proc.returncode != 0:
        raise subprocess.CalledProcessError(proc.returncode, cmd, stderr=err)
    frames = sorted(outdir.glob("f_*.jpg"))
    if progress_cb:
        progress_cb(1.0, f"{len(frames)} frame estratti")
    return frames, 1.0 / max(p.fps, 0.001)


# ---------------------------------------------------------------- immagini
def dhash(path: Path, hash_size: int = 16) -> int:
    im = Image.open(path)
    im = ImageOps.grayscale(im).resize((hash_size + 1, hash_size), Image.BILINEAR)
    px = list(im.getdata())
    bits = 0
    pos = 0
    for r in range(hash_size):
        row = px[r * (hash_size + 1):(r + 1) * (hash_size + 1)]
        for x in range(hash_size):
            bits |= (1 if row[x] > row[x + 1] else 0) << pos
            pos += 1
    return bits


def hamming(a: int, b: int) -> int:
    return (a ^ b).bit_count()


def livetext_available() -> bool:
    try:
        from ocrmac.ocrmac import LIVETEXT_AVAILABLE
        return bool(LIVETEXT_AVAILABLE)
    except Exception:
        return False


def gen_variants(im: Image.Image, multi: bool) -> List[Tuple[str, Image.Image, str]]:
    """
    Varianti per il voto: (nome, immagine, framework).
    Scelte MISURATE su frame difficili reali (font corsivo con alone):
    - raw/vision ed enhanced/vision sbagliano su righe diverse;
    - raw/livetext (il secondo motore OCR di Apple, quello di "Testo attivo")
      e' forte ovunque ed essendo un motore INDIPENDENTE diversifica il voto;
    - grayscale e downscale sono stati provati e scartati (instabili/peggiori).
    """
    out = [("raw", im, "vision")]
    if multi:
        enh = ImageEnhance.Contrast(im).enhance(1.5)
        enh = enh.filter(ImageFilter.UnsharpMask(radius=2, percent=120, threshold=3))
        out.append(("enh", enh, "vision"))
        if livetext_available():
            out.append(("lt", im, "livetext"))
        else:
            # fallback per macOS < 13: terza variante vision in grayscale
            gray = ImageOps.grayscale(im).convert("RGB")
            gray = ImageEnhance.Contrast(gray).enhance(1.6)
            out.append(("gray", gray, "vision"))
    return out


def thumb_b64(path: Path, width: int = 440) -> str:
    """Thumbnail JPEG base64 per il report di revisione (autonomo, niente file esterni)."""
    try:
        im = Image.open(path).convert("RGB")
        if im.width > width:
            im = im.resize((width, int(im.height * width / im.width)), Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, format="JPEG", quality=62)
        return base64.b64encode(buf.getvalue()).decode("ascii")
    except Exception:
        return ""


# ---------------------------------------------------------------- Apple Vision
_VISION_OK: Optional[bool] = None


def vision_available() -> bool:
    global _VISION_OK
    if _VISION_OK is None:
        try:
            from ocrmac import ocrmac  # noqa: F401
            _VISION_OK = True
        except Exception:
            _VISION_OK = False
    return bool(_VISION_OK)


def warmup(langs: List[str], level: str = "accurate") -> None:
    try:
        from ocrmac import ocrmac
        img = Image.new("RGB", (48, 24), "white")
        ocrmac.OCR(img, recognition_level=level, language_preference=langs).recognize()
        if livetext_available():
            ocrmac.OCR(img, framework="livetext", language_preference=langs).recognize()
    except Exception:
        pass


def ocr_conf(img: Image.Image, langs: List[str], level: str,
             min_conf: float, framework: str = "vision") -> Tuple[str, float]:
    """
    OCR di una singola immagine. Ritorna (testo multi-riga, confidenza media).
    framework: "vision" (VNRecognizeText) o "livetext" (motore di Testo attivo).

    Entrambi possono SPEZZARE una singola riga visiva in piu' osservazioni
    (LiveText addirittura in token), e l'ordine di ritorno non e' affidabile:
    ordinare solo per y puo' invertire i pezzi della stessa riga. Quindi:
    raggruppiamo i box in RIGHE VISIVE (per sovrapposizione verticale) e
    dentro ogni riga ordiniamo da sinistra a destra, unendo con spazi.
    """
    from ocrmac import ocrmac
    if framework == "livetext":
        res = ocrmac.OCR(img, framework="livetext",
                         language_preference=langs).recognize()
    else:
        res = ocrmac.OCR(img, recognition_level=level,
                         language_preference=langs).recognize()
    # res: (text, confidence, bbox) con bbox=(x, y, w, h) normalizzato,
    # origine in basso a sinistra (convenzione Vision) -> y grande = in alto.
    items = [(t.strip(), c, box) for (t, c, box) in res if t.strip() and c >= min_conf]
    if not items:
        return "", 0.0

    lines: List[dict] = []
    # scorri dall'alto verso il basso (centro verticale decrescente)
    for t, c, (x, y, w, h) in sorted(items, key=lambda r: -(r[2][1] + r[2][3] / 2)):
        yc = y + h / 2
        for ln in lines:
            # stessa riga visiva se i centri distano meno di ~mezza altezza
            if abs(yc - ln["yc"]) < max(h, ln["h"]) * 0.6:
                ln["parts"].append((x, t))
                ln["yc"] = (ln["yc"] + yc) / 2
                ln["h"] = max(ln["h"], h)
                break
        else:
            lines.append({"yc": yc, "h": h, "parts": [(x, t)]})

    text = "\n".join(" ".join(t for _, t in sorted(ln["parts"], key=lambda p: p[0]))
                     for ln in lines).strip()
    conf = sum(c for _, c, _ in items) / len(items)
    return text, conf


def vote_texts(cands: List[Tuple[str, float]]) -> Tuple[str, float, float, List[str]]:
    """
    Voto a maggioranza pesata per confidenza tra letture alternative.
    Ritorna (testo_vincente, confidenza, quota_accordo, alternative_scartate).
    Le letture vuote non votano: qualunque testo batte il vuoto (Vision non
    inventa testo dove non c'e'; se una variante legge, di norma c'e' testo).
    """
    groups: Dict[str, dict] = {}
    for text, conf in cands:
        if not text:
            continue
        key = normalize_cmp(text)
        g = groups.setdefault(key, {"w": 0.0, "raw": {}, "confs": []})
        g["w"] += max(conf, 0.05)
        g["raw"][text] = g["raw"].get(text, 0) + 1
        g["confs"].append(conf)
    if not groups:
        return "", 0.0, 1.0, []
    total = sum(g["w"] for g in groups.values())
    key, g = max(groups.items(), key=lambda kv: kv[1]["w"])
    # forma raw piu' frequente del gruppo vincente (a parita': la piu' lunga)
    raw = max(g["raw"].items(), key=lambda kv: (kv[1], len(kv[0])))[0]
    conf = sum(g["confs"]) / len(g["confs"])
    agree = g["w"] / total if total > 0 else 1.0
    alts = [max(gg["raw"], key=gg["raw"].get) for k, gg in groups.items() if k != key]
    return raw, conf, agree, alts


# ---------------------------------------------------------------- testo/filtri
_NO_SUB_REGEX = [
    r"non\s+c(?:i\s+)?sono\s+sottotitol",
    r"nessun\s+sottotitol",
    r"no\s+subtitle",
    r"no\s+caption",
    r"there\s+(?:is|are)\s+no\s+subtitle",
]


def normalize_cmp(s: str) -> str:
    s = (s or "").strip().lower()
    s = re.sub(r"[\"“”‘’„«»‹›]", "", s)
    s = re.sub(r"[^\wÀ-ÿ]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def edit_distance(a: str, b: str) -> int:
    a, b = a or "", b or ""
    n, m = len(a), len(b)
    if n == 0 or m == 0:
        return max(n, m)
    dp = list(range(m + 1))
    for i in range(1, n + 1):
        prev = dp[0]
        dp[0] = i
        for j in range(1, m + 1):
            cur = dp[j]
            cost = 0 if a[i - 1] == b[j - 1] else 1
            dp[j] = min(dp[j] + 1, dp[j - 1] + 1, prev + cost)
            prev = cur
    return dp[m]


def texts_similar(a: str, b: str, ratio: float = 0.10) -> bool:
    a1, b1 = normalize_cmp(a), normalize_cmp(b)
    if a1 == b1:
        return True
    if not a1 or not b1:
        return False
    # parziali di dissolvenza: un testo e' contenuto nell'altro
    short, long = (a1, b1) if len(a1) <= len(b1) else (b1, a1)
    if len(short) >= 10 and short in long:
        return True
    L = max(len(a1), len(b1))
    return edit_distance(a1, b1) <= max(2, int(round(L * ratio)))


def looks_like_no_subtitle(text: str, ignore_lines: List[str]) -> bool:
    t = (text or "").strip()
    if not t:
        return True
    tl = t.lower()
    for pat in _NO_SUB_REGEX:
        if re.search(pat, tl):
            return True
    nt = normalize_cmp(t)
    for line in ignore_lines or []:
        nl = normalize_cmp(line)
        if not nl:
            continue
        if texts_similar(t, line):
            return True
        if (len(nl) >= 18 or len(nl.split()) >= 3) and nl in nt:
            return True
    return False


def sanitize(text: str, ignore_lines: List[str]) -> str:
    if not text:
        return ""
    t = re.sub(r"^\s*(text|subtitle|subtitles|caption)\s*:\s*", "", text, flags=re.I).strip()
    if not t or looks_like_no_subtitle(t, ignore_lines):
        return ""
    if not re.search(r"[A-Za-zÀ-ÿ0-9]", t):
        return ""
    return t


# Parole "legate" al seguito: spezzare la riga DOPO una di queste e' brutto
# (es. "intenzione di / mangiare", "I don't have the / slightest idea").
# Penalizzate nella scelta del punto di taglio. Liste per le lingue usate
# davvero (it/en); per le ALTRE lingue si usano solo le regole universali
# (bilanciamento + punteggiatura), che restano efficaci ovunque.
_FUNC_WORDS_IT = frozenset({
    "di", "a", "da", "in", "con", "su", "per", "tra", "fra", "e", "o", "ma",
    "che", "non", "il", "lo", "la", "i", "gli", "le", "un", "uno", "una",
    "del", "dello", "della", "dei", "degli", "delle", "al", "allo", "alla",
    "ai", "agli", "alle", "nel", "nello", "nella", "nei", "negli", "nelle",
    "sul", "sullo", "sulla", "sui", "sugli", "sulle",
    "è", "ho", "ha", "hai", "sono", "sei", "era", "se", "mi", "ti", "si",
    "ci", "vi", "ne", "più", "cui",
})
_FUNC_WORDS_EN = frozenset({
    "a", "an", "the", "of", "to", "in", "on", "at", "by", "for", "with",
    "from", "into", "onto", "and", "or", "but", "nor", "so", "that", "if",
    "as", "than", "is", "are", "was", "were", "be", "been", "being",
    "has", "have", "had", "not", "no", "do", "does", "did",
    "will", "would", "can", "could", "shall", "should", "may", "might",
    "must", "my", "your", "his", "her", "its", "our", "their", "this",
    "these", "those", "some", "any", "very", "don't", "won't", "can't",
    "i'm", "i'll", "he's", "she's", "it's", "we're", "they're", "you're",
})


def _func_words(lang_hint: str) -> frozenset:
    code = resolve_langs(lang_hint)[0].lower()
    if code.startswith("it"):
        return _FUNC_WORDS_IT
    if code.startswith("en"):
        return _FUNC_WORDS_EN
    return frozenset()      # altre lingue: solo bilanciamento + punteggiatura


def _break_cost(words: List[str], i: int, left: str, func_words: frozenset) -> int:
    """Qualita' di un taglio DOPO la parola i-1 (piu' basso = meglio)."""
    cost = 0
    if left[-1] in ",;:!?…—":
        cost -= 10                       # pausa naturale: ottimo punto di taglio
    if words[i - 1].lower().strip("'\",.;:!?…") in func_words:
        cost += 14                       # non staccare articoli/preposizioni dal seguito
    return cost


def smart_wrap(s: str, width: int, lang_hint: str = "Italian") -> str:
    """
    A capo BILANCIATO (stile sottotitolaggio professionale):
    - <= width: una riga sola;
    - altrimenti 2 righe (poi 3) di lunghezza il piu' possibile SIMILE,
      spezzando solo agli spazi, preferendo la punteggiatura ed evitando
      di lasciare articoli/preposizioni a fine riga (it/en; altre lingue:
      solo regole universali);
    - mai spezzare le parole; fallback greedy per i casi estremi.
    """
    s = s.strip()
    if "\n" in s or len(s) <= width or " " not in s:
        return s
    words = s.split()
    fw = _func_words(lang_hint)

    # --- 2 righe bilanciate
    best2, c2 = None, None
    for i in range(1, len(words)):
        left, right = " ".join(words[:i]), " ".join(words[i:])
        if len(left) > width or len(right) > width:
            continue
        c = abs(len(left) - len(right)) + _break_cost(words, i, left, fw)
        if c2 is None or c < c2:
            c2, best2 = c, (left, right)

    # 2 righe "buone" (taglio pulito e bilanciato) vincono sempre
    if best2 and c2 < 14:
        return best2[0] + "\n" + best2[1]

    # --- 3 righe bilanciate (anche come rimedio a un 2-righe brutto,
    #     es. quando l'unico taglio possibile cade dopo un articolo)
    n = len(words)
    best3, c3 = None, None
    for i in range(1, n - 1):
        l1 = " ".join(words[:i])
        if len(l1) > width:
            break
        for j in range(i + 1, n):
            l2 = " ".join(words[i:j])
            if len(l2) > width:
                break
            l3 = " ".join(words[j:])
            if len(l3) > width:
                continue
            c = (abs(len(l1) - len(l2)) + abs(len(l2) - len(l3)) +
                 _break_cost(words, i, l1, fw) + _break_cost(words, j, l2, fw))
            if c3 is None or c < c3:
                c3, best3 = c, (l1, l2, l3)

    # preferisci comunque 2 righe, a meno che 3 righe non siano migliori
    # (+8 = "costo" della riga in piu'; a parita' vincono le 3 righe,
    # perche' qui il 2-righe ha per forza un taglio brutto: c2 >= 14)
    if best2 and (best3 is None or c3 + 8 > c2):
        return best2[0] + "\n" + best2[1]
    if best3:
        return "\n".join(best3)

    # --- fallback greedy (testi estremi): righe piene, mai parole spezzate
    lines, cur = [], ""
    for w in words:
        cand = (cur + " " + w).strip()
        if len(cand) <= width or not cur:
            cur = cand
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return "\n".join(lines)


def apply_corrections(text: str, corrections: List[Tuple[str, str]]) -> str:
    """Sostituzioni 'sbagliato => giusto' (case-insensitive, le piu' lunghe prima)."""
    if not text or not corrections:
        return text
    for wrong, right in corrections:
        text = re.sub(re.escape(wrong), right, text, flags=re.IGNORECASE)
    return text


def postprocess(text: str, wrap: int, ignore_lines: List[str],
                corrections: Optional[List[Tuple[str, str]]] = None,
                lang_hint: str = "Italian") -> str:
    if not text:
        return ""
    text = apply_corrections(text, corrections or [])
    out = text.replace("```", "").replace("\r", "\n").strip()
    lines = [re.sub(r"\s{2,}", " ", ln).strip() for ln in out.split("\n")]
    out = "\n".join(ln for ln in lines if ln)
    if "\n" not in out and len(out) > wrap:
        out = smart_wrap(out, wrap, lang_hint)
    if looks_like_no_subtitle(out, ignore_lines):
        return ""
    return out


# ---------------------------------------------------------------- SRT
def fmt_hms(sec: float) -> str:
    sec = max(0, int(round(sec)))
    h, r = divmod(sec, 3600)
    m, s = divmod(r, 60)
    return f"{h:d}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"


def srt_ts(sec: float) -> str:
    # calcolo in millisecondi totali: evita il bug ms=1000 con frazioni ~.9995+
    total_ms = max(0, int(round(sec * 1000)))
    ms = total_ms % 1000
    s = (total_ms // 1000) % 60
    m = (total_ms // 60000) % 60
    h = total_ms // 3600000
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def write_srt(segments: List[Tuple[float, float, str]], out_path: str) -> None:
    with open(out_path, "w", encoding="utf-8") as f:
        i = 0
        for s, e, t in segments:
            if not t:
                continue
            i += 1
            f.write(f"{i}\n{srt_ts(s)} --> {srt_ts(e)}\n{t}\n\n")


def parse_srt(path: Path) -> List[Tuple[float, float, str]]:
    content = path.read_text(encoding="utf-8")
    blocks = re.split(r"\n\s*\n", content.strip())
    out = []
    for b in blocks:
        m = re.search(r"(\d+)\s*\n(\d{2}:\d{2}:\d{2},\d{3})\s*-->\s*"
                      r"(\d{2}:\d{2}:\d{2},\d{3})\s*\n(.*)", b, flags=re.S)
        if not m:
            continue

        def to_sec(ts):
            hh, mm, rest = ts.split(":")
            ss, ms = rest.split(",")
            return int(hh) * 3600 + int(mm) * 60 + int(ss) + int(ms) / 1000.0
        out.append((to_sec(m.group(2)), to_sec(m.group(3)), m.group(4).strip()))
    return sorted(out, key=lambda x: x[0])


def merge_segments(segs: List[Tuple[float, float, str]], merge_gap: float,
                   min_duration: float, ignore_lines: List[str],
                   wrap: int, lang_hint: str = "Italian") -> List[Tuple[float, float, str]]:
    """Versione su tuple usata dalla scheda Sub fix (pulizia SRT esistenti)."""
    if not segs:
        return []
    out: List[Tuple[float, float, str]] = []
    cs, ce, ct = segs[0]
    for s, e, t in segs[1:]:
        if ct and t and texts_similar(ct, t) and s - ce <= merge_gap:
            ce = e
            if len(t) > len(ct):
                ct = t
        else:
            if ct and (ce - cs) >= min_duration:
                out.append((cs, ce, postprocess(ct, wrap, ignore_lines,
                                                lang_hint=lang_hint)))
            cs, ce, ct = s, e, t
    if ct and (ce - cs) >= min_duration:
        out.append((cs, ce, postprocess(ct, wrap, ignore_lines, lang_hint=lang_hint)))
    return [(s, e, t) for (s, e, t) in out if t]


# ---------------------------------------------------------------- pipeline
def select_ocr_targets(frames: List[Path], skip_hamming: int,
                       progress_cb: Optional[Callable[[float, str], None]] = None
                       ) -> List[int]:
    """
    Frame da OCR-are: il frame 0 e ogni frame che differisce dal PRECEDENTE
    (dhash) piu' di skip_hamming. Gli altri ereditano il testo (forward-fill).
    """
    n = len(frames)
    targets: List[int] = []
    prev = None
    for i, fp in enumerate(frames):
        try:
            h = dhash(fp)
        except Exception:
            h = None
        if i == 0 or prev is None or h is None or hamming(h, prev) > skip_hamming:
            targets.append(i)
        prev = h
        if progress_cb and (i % 300 == 0):
            progress_cb(i / max(n, 1), f"Analisi frame {i}/{n}")
    return targets


def segments_from_frames(per_text: List[str], per_conf: List[float],
                         per_alts: List[List[str]], dt: float
                         ) -> List[SegInfo]:
    """
    Segmenti dal testo per-frame, con voto di segmento:
    - frame vuoto  -> chiude il segmento;
    - testo simile -> estende e ACCUMULA il voto (peso = confidenza);
    - testo diverso -> chiude e apre un nuovo segmento.
    Il testo finale e' il gruppo col peso maggiore tra i frame del segmento.
    """
    segs: List[SegInfo] = []
    cs: Optional[int] = None
    groups: Dict[str, dict] = {}
    rep = ""            # rappresentante corrente per il confronto di similarita'
    alts_seen: Dict[str, int] = {}

    def close(end_idx: int):
        nonlocal cs, groups, rep, alts_seen
        if cs is None or not groups:
            cs, groups, rep, alts_seen = None, {}, "", {}
            return
        key, g = max(groups.items(), key=lambda kv: kv[1]["w"])
        total = sum(gg["w"] for gg in groups.values())
        raw = max(g["raw"].items(), key=lambda kv: (kv[1], len(kv[0])))[0]
        conf = sum(g["confs"]) / len(g["confs"])
        agree = g["w"] / total if total > 0 else 1.0
        others = [max(gg["raw"], key=gg["raw"].get) for k, gg in groups.items() if k != key]
        others += [a for a in alts_seen if normalize_cmp(a) != key]
        segs.append(SegInfo(start=cs * dt, end=end_idx * dt, text=raw,
                            conf=conf, agree=agree, nframes=end_idx - cs,
                            alts=sorted(set(others))[:4]))
        cs, groups, rep, alts_seen = None, {}, "", {}

    def add_vote(tx: str, cf: float, al: List[str]):
        nonlocal rep
        key = normalize_cmp(tx)
        g = groups.setdefault(key, {"w": 0.0, "raw": {}, "confs": []})
        g["w"] += max(cf, 0.05)
        g["raw"][tx] = g["raw"].get(tx, 0) + 1
        g["confs"].append(cf)
        for a in al:
            alts_seen[a] = alts_seen.get(a, 0) + 1
        # il rappresentante e' il raw del gruppo attualmente piu' pesante
        bk, bg = max(groups.items(), key=lambda kv: kv[1]["w"])
        rep = max(bg["raw"].items(), key=lambda kv: (kv[1], len(kv[0])))[0]

    for i, tx in enumerate(per_text):
        if not tx:
            close(i)
            continue
        if cs is None:
            cs = i
            add_vote(tx, per_conf[i], per_alts[i])
        elif texts_similar(tx, rep):
            add_vote(tx, per_conf[i], per_alts[i])
        else:
            close(i)
            cs = i
            add_vote(tx, per_conf[i], per_alts[i])
    close(len(per_text))
    return segs


def merge_seginfos(segs: List[SegInfo], merge_gap: float) -> List[SegInfo]:
    """
    Unisce segmenti adiacenti con testo simile (soglia LEGGERMENTE piu' larga:
    qui si ricompongono i pezzi di fade con qualche typo). Vince il testo del
    segmento con piu' frame (piu' stabile).
    """
    if not segs:
        return []
    out: List[SegInfo] = [segs[0]]
    for s in segs[1:]:
        prev = out[-1]
        if (s.start - prev.end) <= merge_gap and texts_similar(prev.text, s.text, ratio=0.18):
            keep, other = (prev, s) if prev.nframes >= s.nframes else (s, prev)
            merged = SegInfo(
                start=prev.start, end=s.end, text=keep.text,
                conf=(prev.conf * prev.nframes + s.conf * s.nframes) /
                     max(1, prev.nframes + s.nframes),
                agree=min(prev.agree, s.agree),
                nframes=prev.nframes + s.nframes, top=prev.top,
                alts=sorted(set(prev.alts + s.alts + [other.text]) - {keep.text})[:4],
                flags=sorted(set(prev.flags + s.flags + ["unito da fade/typo"])),
            )
            out[-1] = merged
        else:
            out.append(s)
    return out


def refine_segment_bounds(video: str, segs: List[SegInfo], dt: float,
                          native_fps: float, crop_expr: str, langs: List[str],
                          p: OcrParams, tmp_root: Path,
                          progress_cb: Optional[Callable[[float, str], None]] = None,
                          ) -> int:
    """
    Raffina inizio/fine di ogni segmento al framerate NATIVO: estrae una
    finestra ±dt attorno al confine e cerca il primo/ultimo frame in cui il
    testo del segmento e' visibile. Precisione ~1 frame nativo (~±20ms).
    Ritorna il numero di confini spostati.
    """
    moved = 0
    ndt = 1.0 / max(native_fps, 1.0)

    def window_texts(t0: float, t1: float) -> List[Tuple[float, str]]:
        d = Path(tempfile.mkdtemp(prefix="ref_", dir=str(tmp_root)))
        try:
            cmd = ["ffmpeg", "-hide_banner", "-y",
                   "-ss", f"{max(0.0, t0):.4f}", "-i", video,
                   "-t", f"{max(0.05, t1 - t0):.4f}",
                   "-vf", crop_expr, "-fps_mode", "passthrough",
                   "-q:v", "2", str(d / "w_%05d.jpg")]
            subprocess.run(cmd, check=True, capture_output=True)
            out = []
            for k, fp in enumerate(sorted(d.glob("w_*.jpg"))):
                im = Image.open(fp).convert("RGB")
                # per la sola presenza/assenza basta la variante raw
                txt, _ = ocr_conf(im, langs, p.recognition_level, p.min_confidence)
                out.append((max(0.0, t0) + k * ndt, txt))
            return out
        except Exception:
            return []
        finally:
            shutil.rmtree(d, ignore_errors=True)

    for n, seg in enumerate(segs):
        # confine di INIZIO: primo frame nativo con testo simile
        win = window_texts(seg.start - dt, seg.start + dt)
        for t, txt in win:
            if txt and texts_similar(txt, seg.text, ratio=0.25):
                if abs(t - seg.start) > ndt / 2:
                    moved += 1
                seg.start = t
                break
        # confine di FINE: ultimo frame nativo con testo simile
        win = window_texts(seg.end - dt, seg.end + dt)
        last = None
        for t, txt in win:
            if txt and texts_similar(txt, seg.text, ratio=0.25):
                last = t
        if last is not None:
            new_end = last + ndt
            if abs(new_end - seg.end) > ndt / 2:
                moved += 1
            seg.end = new_end
        if progress_cb:
            progress_cb((n + 1) / max(1, len(segs)),
                        f"{n + 1}/{len(segs)} righe")

    # elimina piccole sovrapposizioni introdotte dal raffinamento
    segs.sort(key=lambda s: s.start)
    for a, b in zip(segs, segs[1:]):
        if b.start < a.end:
            mid = (b.start + a.end) / 2
            a.end, b.start = mid, mid
    return moved


# ---------------------------------------------------------------- QC report
def _esc(s: str) -> str:
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
             .replace("\n", "<br>"))


# Template dell'editor di revisione. NON e' una f-string: i valori dinamici entrano via
# .replace() sui token __TOKEN__ (il JS/CSS e' pieno di graffe).
# Le stringhe visibili (it/en) vivono in _QC_I18N: entrano anch'esse via token
# (__T_*__ nell'HTML, oggetto T=__JSTR__ nel JS).
_QC_TEMPLATE = r"""<!DOCTYPE html>
<html lang="__LANG__"><head><meta charset="utf-8">
<title>__T_TITLE__ — __VIDEO__</title>
<style>
 :root{color-scheme:dark}
 body{font-family:-apple-system,Helvetica,Arial,sans-serif;margin:0;background:#14161a;color:#e8e8e8}
 .wrap{max-width:1100px;margin:0 auto;padding:18px 22px 80px}
 h1{font-size:20px} h2{font-size:16px;margin-top:36px;border-bottom:1px solid #333;padding-bottom:6px}
 .sum{background:#1d2026;border:1px solid #333;border-radius:10px;padding:12px 16px;line-height:1.7;font-size:14px}
 .topbar{position:sticky;top:0;z-index:10;background:#14161acc;backdrop-filter:blur(8px);
        border-bottom:1px solid #333;padding:10px 22px;display:flex;gap:12px;align-items:center}
 .topbar b{font-size:15px}
 button{background:#2a6df4;color:#fff;border:0;border-radius:8px;padding:8px 16px;
        font-size:14px;cursor:pointer}
 button:hover{filter:brightness(1.15)}
 button.sec{background:#3a3d45} button.mini{padding:2px 10px;font-size:12px;border-radius:6px}
 .row{display:flex;gap:12px;border-bottom:1px solid #2a2d33;padding:10px 4px;align-items:flex-start}
 .row.warn{background:#241f0e} .row.bad{background:#2b1616} .row.excluded{opacity:.45}
 .row.added{background:#12281a}
 .cInc{padding-top:4px}
 .cT{width:120px;flex:none;font-size:12px;color:#9ecbff}
 .cT input{width:112px;background:#1d2026;border:1px solid #3a3d45;border-radius:5px;
          color:#9ecbff;font-size:12px;padding:3px 5px;margin-bottom:3px;font-family:ui-monospace,monospace}
 .cImg{flex:none} .cImg img{max-width:400px;border-radius:6px;display:block}
 .cTx{flex:1;min-width:220px}
 textarea{width:100%;box-sizing:border-box;background:#1d2026;border:1px solid #3a3d45;
         border-radius:6px;color:#e8e8e8;font-size:15px;line-height:1.45;padding:6px 8px;
         resize:vertical;min-height:38px;font-family:inherit}
 textarea.edited{border-color:#2a6df4}
 .cC{width:78px;flex:none;text-align:right;font-size:13px;white-space:nowrap}
 .dur{color:#777;font-size:11px}
 .tag{display:inline-block;background:#444;border-radius:4px;font-size:11px;
      padding:1px 7px;margin:4px 4px 0 0;color:#ddd}
 .tag.top{background:#2a6df4;color:#fff;font-weight:700;cursor:pointer;
          border:1px solid #7db1ff;box-shadow:0 0 8px #2a6df499}
 .tag.top.off{background:#26282e;color:#777;font-weight:400;
          border:1px dashed #555;box-shadow:none}
 .chip{display:inline-block;background:#26313f;border:1px solid #3d5470;border-radius:6px;
       font-size:13px;padding:2px 9px;margin:5px 5px 0 0;color:#bcd6f5;cursor:pointer}
 .chip:hover{background:#31435a}
 .chip.orig{border-style:dashed}
 .hl{background:#f7d154;color:#1a1a1a;border-radius:3px;padding:0 3px;font-weight:600}
 label.opt{color:#bbb;font-size:13px;display:flex;align-items:center;gap:5px;cursor:pointer}
 .hint{color:#888;font-size:12px;margin-top:4px}
 .n{color:#888;width:26px;flex:none;padding-top:6px;font-size:13px}
 .gap{border:1px dashed #665c20;border-radius:8px;margin:10px 0;padding:10px;display:flex;gap:12px}
 .legend span{margin-right:16px;font-size:13px}
 .dot{display:inline-block;width:10px;height:10px;border-radius:3px;margin-right:5px}
 .saved{color:#7fd07f;font-size:13px;margin-left:6px;opacity:0;transition:opacity .3s}
</style></head><body>
<div class="topbar">
 <b>🎬 __T_TITLE__ — __VIDEO__</b>
 <span style="flex:1"></span>
 <span id="counter" style="color:#aaa;font-size:13px"></span>
 <label class="opt" title="__T_MERGE_TIP__">
   <input type="checkbox" id="mergeOnSave" checked> __T_MERGE_LABEL__</label>
 <button class="sec" onclick="resetAll()">__T_RESET__</button>
 <button onclick="exportSrt()">__T_SAVE__</button>
 <span class="saved" id="savedNote">__T_SAVED__</span>
</div>
<div class="wrap">
<div class="sum">__SUMMARY__
 <div class="legend" style="margin-top:6px">
  <span><span class="dot" style="background:#241f0e;border:1px solid #665c20"></span>__T_LEG_WARN__</span>
  <span><span class="dot" style="background:#2b1616;border:1px solid #663333"></span>__T_LEG_BAD__</span>
  <span><span class="dot" style="background:#12281a;border:1px solid #2f6b45"></span>__T_LEG_ADDED__</span>
 </div>
 <div class="hint">__T_HINT__</div>
</div>
<h2>__T_ROWS_H__ <button class="mini sec" onclick="addRow(null)">__T_ADDROW__</button></h2>
<div id="rows"></div>
<h2>__T_DROPPED_H__</h2>
<div id="dropped"></div>
<h2>__T_GAPS_H__</h2>
<div id="gaps"></div>
</div>
<script type="application/json" id="qcdata">__DATA__</script>
<script>
const DATA = JSON.parse(document.getElementById('qcdata').textContent);
const T = __JSTR__;
const LSKEY = 'voc26_rev_' + DATA.srtName;
let saved = {};
try { saved = JSON.parse(localStorage.getItem(LSKEY) || '{}'); } catch(e) {}
let addCounter = 0;

function ts(sec){
  sec = Math.max(0, sec);
  const ms = Math.round(sec*1000);
  const h = Math.floor(ms/3600000), m = Math.floor(ms/60000)%60,
        s = Math.floor(ms/1000)%60, r = ms%1000;
  return String(h).padStart(2,'0')+':'+String(m).padStart(2,'0')+':'+
         String(s).padStart(2,'0')+','+String(r).padStart(3,'0');
}
function parseTs(t){
  const m = (t||'').trim().match(/^(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})$/);
  if(!m) return null;
  return (+m[1])*3600 + (+m[2])*60 + (+m[3]) + (+m[4].padEnd(3,'0'))/1000;
}
// ---- similarita' testi (replica della logica Python della pipeline)
function normCmp(s){
  return (s||'').toLowerCase().replace(/["“”‘’„«»‹›]/g,'')
         .replace(/[^\p{L}\p{N}]+/gu,' ').trim().replace(/\s+/g,' ');
}
function editDist(a,b){
  const n=a.length,m=b.length;
  if(!n||!m) return Math.max(n,m);
  let dp=Array.from({length:m+1},(_,j)=>j);
  for(let i=1;i<=n;i++){
    let prev=dp[0]; dp[0]=i;
    for(let j=1;j<=m;j++){
      const cur=dp[j];
      dp[j]=Math.min(dp[j]+1, dp[j-1]+1, prev+(a[i-1]===b[j-1]?0:1));
      prev=cur;
    }
  }
  return dp[m];
}
function similar(a,b,ratio){
  ratio = ratio || 0.18;
  a=normCmp(a); b=normCmp(b);
  if(a===b) return true;
  if(!a||!b) return false;
  const s=a.length<=b.length?a:b, l=a.length<=b.length?b:a;
  if(s.length>=10 && l.includes(s)) return true;
  const L=Math.max(a.length,b.length);
  return editDist(a,b) <= Math.max(2, Math.round(L*ratio));
}
// ---- diff a parole (LCS): ritorna i token di b marcando quelli diversi da a
function wordDiff(a,b){
  const A=(a||'').split(/\s+/).filter(Boolean), B=(b||'').split(/\s+/).filter(Boolean);
  const m=A.length,n=B.length;
  const dp=Array.from({length:m+1},()=>new Array(n+1).fill(0));
  for(let i=m-1;i>=0;i--)for(let j=n-1;j>=0;j--)
    dp[i][j]=(normCmp(A[i])===normCmp(B[j])&&normCmp(B[j]))?dp[i+1][j+1]+1:Math.max(dp[i+1][j],dp[i][j+1]);
  const out=[]; let i=0,j=0;
  while(i<m&&j<n){
    if(normCmp(A[i])===normCmp(B[j])&&normCmp(B[j])){out.push([B[j],false]);i++;j++;}
    else if(dp[i+1][j]>=dp[i][j+1]) i++;
    else {out.push([B[j],true]); j++;}
  }
  while(j<n){out.push([B[j],true]);j++;}
  return out;
}
function state(id){ return saved[id] || {}; }
function setState(id, patch){
  saved[id] = Object.assign({}, saved[id]||{}, patch);
  localStorage.setItem(LSKEY, JSON.stringify(saved));
  const n = document.getElementById('savedNote');
  n.style.opacity = 1; setTimeout(()=>n.style.opacity=0, 900);
  updateCounter();
}
function rowValues(r){
  const s = state(r.id);
  return {
    text: (s.text !== undefined) ? s.text : r.text,
    start: (s.start !== undefined) ? s.start : r.start,
    end: (s.end !== undefined) ? s.end : r.end,
    included: (s.included !== undefined) ? s.included : !r.dropped,
    top: (s.top !== undefined) ? s.top : !!r.top,
  };
}

function makeRow(r, container){
  const v = rowValues(r);
  const div = document.createElement('div');
  div.className = 'row ' + (r.added ? 'added' : r.cls || '');
  if(!v.included) div.classList.add('excluded');
  div.dataset.id = r.id;

  const inc = document.createElement('div'); inc.className='cInc';
  const cb = document.createElement('input'); cb.type='checkbox'; cb.checked=v.included;
  cb.title=T.includeTip;
  cb.onchange = () => { setState(r.id,{included:cb.checked});
                        div.classList.toggle('excluded', !cb.checked); };
  inc.appendChild(cb); div.appendChild(inc);

  const num = document.createElement('div'); num.className='n'; num.textContent=r.n||''; div.appendChild(num);

  const ct = document.createElement('div'); ct.className='cT';
  const ti1 = document.createElement('input'); ti1.value = ts(v.start); ti1.title=T.start;
  const ti2 = document.createElement('input'); ti2.value = ts(v.end); ti2.title=T.end;
  const dur = document.createElement('div'); dur.className='dur';
  const updDur = () => {
    const a=parseTs(ti1.value), b=parseTs(ti2.value);
    dur.textContent = (a!=null && b!=null) ? (b-a).toFixed(2)+'s' : T.tsFormat;
  };
  updDur();
  ti1.onchange = () => { const t=parseTs(ti1.value); if(t!=null) setState(r.id,{start:t}); updDur(); };
  ti2.onchange = () => { const t=parseTs(ti2.value); if(t!=null) setState(r.id,{end:t}); updDur(); };
  ct.append(ti1, ti2, dur); div.appendChild(ct);

  if(r.thumb){
    const ci = document.createElement('div'); ci.className='cImg';
    const img = document.createElement('img'); img.src='data:image/jpeg;base64,'+r.thumb;
    ci.appendChild(img); div.appendChild(ci);
  }

  const cx = document.createElement('div'); cx.className='cTx';
  const ta = document.createElement('textarea'); ta.value = v.text;
  ta.rows = Math.max(1, v.text.split('\n').length);
  if(v.text !== r.text) ta.classList.add('edited');
  ta.oninput = () => { setState(r.id,{text:ta.value});
                       ta.classList.toggle('edited', ta.value !== r.text); };
  cx.appendChild(ta);

  const tags = document.createElement('div');
  const an8 = document.createElement('span');
  const an8Label = on => on ? T.signOn : T.signOff;
  an8.className = 'tag top' + (v.top?'':' off');
  an8.textContent = an8Label(v.top);
  an8.title=T.signTip;
  an8.onclick = () => { const nv=!(state(r.id).top!==undefined?state(r.id).top:!!r.top);
                        setState(r.id,{top:nv}); an8.classList.toggle('off',!nv);
                        an8.textContent = an8Label(nv); };
  tags.appendChild(an8);
  (r.flags||[]).forEach(f => { const t=document.createElement('span');
                               t.className='tag'; t.textContent=f; tags.appendChild(t); });
  cx.appendChild(tags);

  if((r.alts||[]).length || r.text){
    const alt = document.createElement('div');
    (r.alts||[]).forEach(a => {
      const c = document.createElement('span'); c.className='chip'; c.dataset.txt=a;
      c.title=T.altTip;
      // evidenzia le parole che differiscono dal testo originale della riga
      wordDiff((r.text||'').replace(/\n/g,' '), a.replace(/\n/g,' ')).forEach(([w,d],k)=>{
        if(k) c.appendChild(document.createTextNode(' '));
        const s=document.createElement('span');
        if(d) s.className='hl';
        s.textContent=w;
        c.appendChild(s);
      });
      c.onclick = () => { ta.value=c.dataset.txt; ta.dispatchEvent(new Event('input')); };
      alt.appendChild(c);
    });
    if(r.text){
      const o = document.createElement('span'); o.className='chip orig'; o.textContent=T.orig;
      o.onclick = () => { ta.value=r.text; ta.dispatchEvent(new Event('input')); };
      alt.appendChild(o);
    }
    cx.appendChild(alt);
  }
  div.appendChild(cx);

  const cc = document.createElement('div'); cc.className='cC';
  cc.innerHTML = r.conf!=null ? Math.round(r.conf*100)+'%<div class="dur">'+T.agree+' '+
                 Math.round((r.agree||1)*100)+'%</div>' : '—';
  div.appendChild(cc);

  container.appendChild(div);
  return div;
}

function addRow(gap){
  addCounter++;
  const id = 'new'+Date.now()+'_'+addCounter;
  const base = gap ? {start: gap.start+0.5, end: Math.min(gap.end-0.5, gap.start+2.5)}
                   : {start: 0, end: 2};
  const r = {id:id, n:'+', start:base.start, end:base.end, text:'', alts:[],
             flags:[T.addedFlag], conf:null, added:true, dropped:false,
             thumb: gap ? gap.thumb : ''};
  DATA.extraRows.push(r);
  setState(id, {text:'', start:base.start, end:base.end, included:true, added:true});
  const div = makeRow(r, document.createElement('div'));   // creato staccato...
  if(gap) gap._el.after(div);                              // ...poi spostato dove serve
  else document.getElementById('rows').appendChild(div);
  div.querySelector('textarea').focus();
}

function updateCounter(){
  let inc=0, tot=0;
  document.querySelectorAll('.row').forEach(d => {
    tot++; if(!d.classList.contains('excluded')) inc++;
  });
  document.getElementById('counter').textContent =
    T.counter.replace('{inc}', inc).replace('{tot}', tot);
}

function collectRows(){
  const rows = [];
  const all = DATA.rows.concat(DATA.extraRows);
  for(const r of all){
    const v = rowValues(r);
    if(!v.included) continue;
    const text = (v.text||'').trim();
    if(!text) continue;
    if(v.start==null || v.end==null || v.end<=v.start){
      alert(T.badTimes + ' "'+text.slice(0,40)+'"'); return null;
    }
    rows.push({start:v.start, end:v.end, text:text, top:v.top,
               edited: text !== (r.text||'')});
  }
  rows.sort((a,b)=>a.start-b.start);
  return rows;
}

// unisce righe adiacenti (stessa banda) con testo uguale/simile:
// vince il testo editato a mano; a parita', quello della riga piu' lunga.
function mergeRows(rows, gap){
  gap = gap==null ? 0.6 : gap;
  const out=[]; let merged=0;
  for(const r of rows){
    const p=out[out.length-1];
    if(p && p.top===r.top && (r.start-p.end)<=gap && similar(p.text, r.text)){
      const keep = (r.edited && !p.edited) ? r.text
                 : (p.edited && !r.edited) ? p.text
                 : ((r.end-r.start) > (p.end-p.start) ? r.text : p.text);
      p.text=keep; p.end=Math.max(p.end, r.end); p.edited=p.edited||r.edited;
      merged++;
    } else out.push(Object.assign({}, r));
  }
  return [out, merged];
}

function buildSrt(){
  let rows = collectRows();
  if(!rows) return null;
  window._lastMergeInfo = 0;
  if(document.getElementById('mergeOnSave')?.checked){
    const [m, count] = mergeRows(rows);
    rows = m; window._lastMergeInfo = count;
  }
  let out='', i=0;
  for(const r of rows){
    i++;
    const body = (r.top && !r.text.startsWith('{\\an8}')) ? '{\\an8}'+r.text : r.text;
    out += i+'\n'+ts(r.start)+' --> '+ts(r.end)+'\n'+body+'\n\n';
  }
  return out;
}
function stamp(){
  const d = new Date();
  const p = n => String(n).padStart(2,'0');
  return d.getFullYear()+p(d.getMonth()+1)+p(d.getDate())+'-'+p(d.getHours())+p(d.getMinutes());
}
function flash(msg){
  const n = document.getElementById('savedNote');
  n.textContent = msg; n.style.opacity = 1;
  setTimeout(()=>{ n.style.opacity=0; n.textContent=T.saved; }, 2500);
}
async function exportSrt(){
  const out = buildSrt();
  if(out == null) return;
  const fname = DATA.srtName.replace(/\.srt$/i,'') + '-revisionato-' + stamp() + '.srt';
  const mi = window._lastMergeInfo || 0;
  const mergeNote = mi > 0 ? ' · ' + mi + ' ' + T.mergedDupes : '';
  // Chrome/Edge: dialogo "Salva" che RICORDA la cartella (id) -> dalla seconda
  // volta propone direttamente la cartella dei video. Safari: fallback Download.
  if(window.showSaveFilePicker){
    try{
      const h = await showSaveFilePicker({
        suggestedName: fname, id: 'voc26-srt',
        types: [{description:T.srtDesc, accept:{'text/plain':['.srt']}}]
      });
      const w = await h.createWritable();
      await w.write(out); await w.close();
      flash(T.srtSaved + ' (' + fname + ')' + mergeNote);
      return;
    }catch(e){
      if(e && e.name === 'AbortError') return;   // annullato dall'utente
      // altri errori (es. API bloccata su file://) -> fallback download
    }
  }
  const blob = new Blob([out], {type:'text/plain;charset=utf-8'});
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = fname;
  a.click();
  URL.revokeObjectURL(a.href);
  flash(T.srtDownloaded + ' (' + fname + ')' + mergeNote);
}

function resetAll(){
  if(!confirm(T.confirmReset)) return;
  localStorage.removeItem(LSKEY); location.reload();
}

// ---- render
DATA.extraRows = [];
const rowsEl = document.getElementById('rows');
DATA.rows.filter(r=>!r.dropped).forEach(r => makeRow(r, rowsEl));
const dropEl = document.getElementById('dropped');
const droppedRows = DATA.rows.filter(r=>r.dropped);
if(droppedRows.length) droppedRows.forEach(r => makeRow(r, dropEl));
else dropEl.innerHTML = '<div class="hint">'+T.noneDropped+'</div>';
const gapsEl = document.getElementById('gaps');
if(DATA.gaps.length){
  DATA.gaps.forEach((g,gi) => {
    const d = document.createElement('div'); d.className='gap'; g._el = d;
    const img = g.thumb ? '<img src="data:image/jpeg;base64,'+g.thumb+
                '" style="max-width:400px;border-radius:6px">' : '';
    d.innerHTML = '<div class="cT">'+ts(g.start)+'<br>→ '+ts(g.end)+
                  '<div class="dur">'+(g.end-g.start).toFixed(1)+T.gapNoSub+'</div></div>'+
                  '<div>'+img+'</div><div style="flex:1"><div class="hint">'+
                  T.gapHint+'</div></div>';
    const btn = document.createElement('button'); btn.className='mini'; btn.textContent=T.addHere;
    btn.onclick = () => addRow(g);
    d.lastElementChild.appendChild(btn);
    gapsEl.appendChild(d);
  });
} else gapsEl.innerHTML = '<div class="hint">'+T.noneGaps+'</div>';

// ripristina righe aggiunte in sessioni precedenti
for(const [id, s] of Object.entries(saved)){
  if(s.added && !DATA.rows.find(r=>r.id===id) && !DATA.extraRows.find(r=>r.id===id)){
    const r = {id:id, n:'+', start:s.start||0, end:s.end||2, text:s.text||'', alts:[],
               flags:[T.addedFlag], conf:null, added:true, dropped:false, thumb:''};
    DATA.extraRows.push(r);
    makeRow(r, rowsEl);
  }
}
updateCounter();
</script>
</body></html>
"""


# Stringhe del report di revisione (solo testo, zero logica).
# "html": token __T_*__ del markup; "js": oggetto T usato dagli script;
# "flags": traduzione delle note QC generate dalla pipeline (in italiano);
# "summary": riepilogo in testa al report.
_QC_I18N = {
    "it": {
        "html": {
            "TITLE": "Revisione",
            "MERGE_TIP": "Al salvataggio: unisce le righe adiacenti con testo uguale o "
                         "molto simile (resa diversa dall'OCR). Se una delle due l'hai "
                         "editata a mano, vince il tuo testo.",
            "MERGE_LABEL": "unisci duplicati",
            "RESET": "↺ Ripristina tutto",
            "SAVE": "💾 Salva SRT revisionato",
            "SAVED": "salvato ✓",
            "LEG_WARN": "da ricontrollare",
            "LEG_BAD": "molto dubbio / scartato",
            "LEG_ADDED": "riga aggiunta a mano",
            "HINT": "Modifica il testo nelle caselle, clicca una <b>lettura alternativa</b> per usarla,\n"
                    " spunta/de-spunta le righe da includere. Le modifiche restano salvate in questo browser.<br>\n"
                    " <b>💾 Salva SRT revisionato</b> crea <code>nome-revisionato-data.srt</code>: con <b>Chrome/Edge</b> si apre\n"
                    " il dialogo Salva che <b>ricorda la cartella</b> (scegli la cartella dei video la prima volta);\n"
                    " con <b>Safari</b> il file va in Download.",
            "ROWS_H": "Righe SRT",
            "ADDROW": "➕ aggiungi riga",
            "DROPPED_H": "⚠️ Scartate (flash brevi / rumore) — spunta ✔ per recuperarle nell'SRT",
            "GAPS_H": "🕳️ Intervalli lunghi senza sottotitoli — possibili righe saltate",
        },
        "js": {
            "includeTip": "includi nell'SRT",
            "start": "inizio", "end": "fine",
            "tsFormat": "⚠️ formato: HH:MM:SS,mmm",
            "signOn": "✓ CARTELLO ↑ {\\an8}", "signOff": "cartello ↑ {\\an8}",
            "signTip": "clicca per attivare/disattivare la posizione in alto",
            "altTip": "usa questa lettura (in giallo le parole che differiscono)",
            "orig": "↺ originale",
            "counter": "{inc} righe incluse su {tot}",
            "agree": "accordo",
            "badTimes": "Tempi non validi nella riga:",
            "saved": "salvato ✓",
            "mergedDupes": "duplicati uniti",
            "srtDesc": "Sottotitoli SubRip",
            "srtSaved": "SRT salvato ✓",
            "srtDownloaded": "SRT scaricato in Download",
            "confirmReset": "Annullare tutte le modifiche fatte in questo report?",
            "noneDropped": "Nessuna.", "noneGaps": "Nessuno.",
            "gapNoSub": "s senza sub",
            "gapHint": "Thumbnail a metà intervallo. Se qui mancava una riga, aggiungila:",
            "addHere": "➕ aggiungi riga qui",
            "addedFlag": "aggiunta a mano",
        },
        "flags": {},    # le note QC nascono già in italiano
        "summary": (
            "SRT: <b>{srt}</b><br>"
            "Righe: <b>{rows}</b> · da ricontrollare: <b>{warn}</b> · "
            "scartate (recuperabili): <b>{dropped}</b> · "
            "buchi lunghi: <b>{gaps}</b><br>"
            "Frame: {frames} · OCR: {ocr} · "
            "confini raffinati: {refined} · tempo: {elapsed}"
        ),
    },
    "en": {
        "html": {
            "TITLE": "Review",
            "MERGE_TIP": "On save: merges adjacent lines with equal or very similar "
                         "text (rendered differently by the OCR). If you edited one "
                         "of the two by hand, your text wins.",
            "MERGE_LABEL": "merge duplicates",
            "RESET": "↺ Reset all",
            "SAVE": "💾 Save reviewed SRT",
            "SAVED": "saved ✓",
            "LEG_WARN": "to re-check",
            "LEG_BAD": "very doubtful / dropped",
            "LEG_ADDED": "line added by hand",
            "HINT": "Edit the text in the boxes, click an <b>alternative reading</b> to use it,\n"
                    " check/uncheck the lines to include. Changes stay saved in this browser.<br>\n"
                    " <b>💾 Save reviewed SRT</b> creates <code>name-revisionato-date.srt</code>: with <b>Chrome/Edge</b> the\n"
                    " Save dialog opens and <b>remembers the folder</b> (pick the videos folder the first time);\n"
                    " with <b>Safari</b> the file goes to Downloads.",
            "ROWS_H": "SRT lines",
            "ADDROW": "➕ add line",
            "DROPPED_H": "⚠️ Dropped (short flashes / noise) — tick ✔ to recover them into the SRT",
            "GAPS_H": "🕳️ Long intervals without subtitles — possibly skipped lines",
        },
        "js": {
            "includeTip": "include in the SRT",
            "start": "start", "end": "end",
            "tsFormat": "⚠️ format: HH:MM:SS,mmm",
            "signOn": "✓ SIGN ↑ {\\an8}", "signOff": "sign ↑ {\\an8}",
            "signTip": "click to toggle the top position",
            "altTip": "use this reading (differing words in yellow)",
            "orig": "↺ original",
            "counter": "{inc} lines included out of {tot}",
            "agree": "agreement",
            "badTimes": "Invalid times in line:",
            "saved": "saved ✓",
            "mergedDupes": "duplicates merged",
            "srtDesc": "SubRip subtitles",
            "srtSaved": "SRT saved ✓",
            "srtDownloaded": "SRT downloaded to Downloads",
            "confirmReset": "Undo all the changes made in this report?",
            "noneDropped": "None.", "noneGaps": "None.",
            "gapNoSub": "s without subs",
            "gapHint": "Thumbnail at mid-interval. If a line was missing here, add it:",
            "addHere": "➕ add line here",
            "addedFlag": "added by hand",
        },
        "flags": {
            "scartato: troppo breve": "dropped: too short",
            "scartato: probabile rumore grafico": "dropped: likely graphic noise",
            "unito da fade/typo": "merged across fade/typo",
        },
        "summary": (
            "SRT: <b>{srt}</b><br>"
            "Lines: <b>{rows}</b> · to re-check: <b>{warn}</b> · "
            "dropped (recoverable): <b>{dropped}</b> · "
            "long gaps: <b>{gaps}</b><br>"
            "Frames: {frames} · OCR: {ocr} · "
            "boundaries refined: {refined} · time: {elapsed}"
        ),
    },
}


def write_qc_html(path: Path, video_name: str, srt_name: str,
                  segs: List[SegInfo], dropped: List[SegInfo],
                  gaps: List[Tuple[float, float, str]], stats: RunStats,
                  p: OcrParams, ui_lang: str = "it") -> None:
    """
    Report di revisione INTERATTIVO e autonomo (un solo file HTML, offline):
    - testo di ogni riga editabile; le letture alternative si applicano con
      un click; righe includibili/escludibili (anche recuperare le scartate);
    - righe nuove aggiungibili nei "buchi" (tempi precompilati);
    - tempi editabili; tag {\\an8} attivabile per riga;
    - "Salva SRT revisionato" genera l'SRT finale; le modifiche restano
      salvate nel browser (localStorage) tra una sessione e l'altra.
    ui_lang ("it" | "en") sceglie la lingua dei testi del report.
    """
    import json

    tr = _QC_I18N.get(ui_lang) or _QC_I18N["it"]
    flag_tr = tr["flags"]

    def row_cls(s: SegInfo) -> str:
        if s.conf < 0.5 or s.agree < 0.5:
            return "bad"
        if s.conf < p.qc_conf_warn or s.agree < p.qc_agree_warn or s.flags:
            return "warn"
        return ""

    rows = []
    for i, s in enumerate(list(segs) + list(dropped), 1):
        is_dropped = s in dropped
        rows.append({
            "id": f"s{i}", "n": i if not is_dropped else "✂",
            "start": round(s.start, 3), "end": round(s.end, 3),
            "text": s.text, "top": s.top, "conf": round(s.conf, 3),
            "agree": round(s.agree, 3), "alts": s.alts,
            "flags": [flag_tr.get(f, f) for f in s.flags],
            "thumb": s.thumb, "dropped": is_dropped,
            "cls": "bad" if is_dropped else row_cls(s),
        })
    data = {
        "srtName": srt_name, "videoName": video_name,
        "rows": rows,
        "gaps": [{"start": round(a, 3), "end": round(b, 3), "thumb": th}
                 for a, b, th in gaps],
    }
    warn_rows = sum(1 for s in segs
                    if s.conf < p.qc_conf_warn or s.agree < p.qc_agree_warn or s.flags)
    summary = tr["summary"].format(
        srt=_esc(srt_name), rows=len(segs), warn=warn_rows,
        dropped=len(dropped), gaps=len(gaps), frames=stats.frames,
        ocr=stats.ocr_calls, refined=stats.refined,
        elapsed=fmt_hms(stats.elapsed))
    payload = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    jstr = json.dumps(tr["js"], ensure_ascii=False).replace("</", "<\\/")
    html = _QC_TEMPLATE.replace("__LANG__", ui_lang).replace("__JSTR__", jstr)
    for key, val in tr["html"].items():
        html = html.replace(f"__T_{key}__", val)
    html = (html
            .replace("__VIDEO__", _esc(video_name))
            .replace("__SUMMARY__", summary)
            .replace("__DATA__", payload))
    path.write_text(html, encoding="utf-8")


# ---------------------------------------------------------------- orchestrazione
def _process_band(video: str, band: str, p: OcrParams, langs: List[str],
                  workdir: Path, stats: RunStats,
                  progress_cb, log_cb) -> Tuple[List[SegInfo], List[SegInfo], List[Tuple[float, float, str]]]:
    """
    Elabora una banda ('bottom' o 'top') e ritorna (segmenti, scartati, gaps).
    I thumbnail report di revisione vengono catturati QUI, prima che i frame vengano cancellati.
    """
    def stage(name):
        # chiave "stage:banda" (es. "ocr:bottom") cosi' la GUI puo' dedicare
        # una riga di avanzamento a ogni step di ogni banda.
        def cb(ratio, text):
            if progress_cb:
                progress_cb(f"{name}:{band}", ratio, text)
        return cb

    def log(msg):
        if log_cb:
            log_cb(f"[{band}] {msg}")

    frames, dt = extract_frames(video, workdir / f"frames_{band}", p, band, stage("extract"))
    stats.frames += len(frames)
    log(f"{len(frames)} frame @ {p.fps}fps")
    if not frames:
        return [], [], []

    targets = select_ocr_targets(frames, p.skip_hamming, stage("group"))
    stage("group")(1.0, f"{len(targets)}/{len(frames)} frame da leggere")
    log(f"{len(targets)}/{len(frames)} frame da OCR-are")

    # ---- OCR multi-variante in parallelo
    nvar = len(gen_variants(Image.new("RGB", (2, 2)), p.multi_variant))
    results: Dict[int, Tuple[str, float, List[str]]] = {}
    done = 0

    def ocr_target(idx: int):
        im = Image.open(frames[idx]).convert("RGB")
        cands = [ocr_conf(v, langs, p.recognition_level, p.min_confidence, fw)
                 for _, v, fw in gen_variants(im, p.multi_variant)]
        text, conf, agree, alts = vote_texts(cands)
        return idx, (text, conf, alts)

    from concurrent.futures import ThreadPoolExecutor, as_completed
    with ThreadPoolExecutor(max_workers=max(1, p.workers)) as ex:
        futs = [ex.submit(ocr_target, i) for i in targets]
        for fut in as_completed(futs):
            try:
                idx, res = fut.result()
                results[idx] = res
            except Exception as e:
                log(f"OCR errore su un frame: {e}")
            done += 1
            stats.ocr_calls += nvar
            if progress_cb and (done % 10 == 0 or done == len(targets)):
                progress_cb(f"ocr:{band}", done / len(targets),
                            f"{done}/{len(targets)} frame")

    # ---- forward-fill + sanitize
    per_text: List[str] = []
    per_conf: List[float] = []
    per_alts: List[List[str]] = []
    cur: Tuple[str, float, List[str]] = ("", 0.0, [])
    for i in range(len(frames)):
        if i in results:
            cur = results[i]
        t = sanitize(cur[0], p.ignore_lines)
        per_text.append(t)
        per_conf.append(cur[1] if t else 0.0)
        per_alts.append(cur[2] if t else [])

    # ---- segmenti + merge
    segs = segments_from_frames(per_text, per_conf, per_alts, dt)
    segs = merge_seginfos(segs, p.merge_gap)
    for s in segs:
        s.top = (band == "top")

    # ---- anti-flash + anti-rumore: separa (NON butta: tutto finisce nel report di revisione)
    def is_noise(s: SegInfo) -> bool:
        """
        Letture brevissime quasi senza lettere (". L", "10)"): di norma sono
        elementi grafici della scena, non sottotitoli. I sub veri cortissimi
        ("Si'", "Eh?") hanno >=2 lettere o durano di piu'. In caso di dubbio
        finiscono comunque nel report di revisione con thumbnail.
        """
        letters = sum(c.isalpha() for c in s.text)
        dur = s.end - s.start
        return (letters == 0 and dur < 0.8) or (letters <= 1 and dur < 0.6)

    kept, dropped = [], []
    for s in segs:
        if (s.end - s.start) < p.min_duration:
            s.flags.append("scartato: troppo breve")
            dropped.append(s)
        elif is_noise(s):
            s.flags.append("scartato: probabile rumore grafico")
            dropped.append(s)
        else:
            kept.append(s)

    # ---- thumbnails (prima che i frame spariscano)
    def snap(seg: SegInfo):
        mid = int(((seg.start + seg.end) / 2) / dt)
        mid = max(0, min(len(frames) - 1, mid))
        seg.thumb = thumb_b64(frames[mid])

    for s in kept + dropped:
        snap(s)

    # ---- gap lunghi senza sub (solo banda dialoghi) con thumbnail a meta'
    gaps: List[Tuple[float, float, str]] = []
    if band == "bottom":
        anchors = [0.0] + [s.end for s in kept]
        ends = [s.start for s in kept] + [len(frames) * dt]
        for a, b in zip(anchors, ends):
            if b - a >= p.qc_gap_warn:
                mid = int(((a + b) / 2) / dt)
                mid = max(0, min(len(frames) - 1, mid))
                gaps.append((a, b, thumb_b64(frames[mid])))

    # ---- raffinamento confini al framerate nativo
    if p.refine_timing and kept:
        native = ffprobe_fps(video)
        log(f"raffinamento confini a {native:.3f} fps nativi…")
        moved = refine_segment_bounds(video, kept, dt, native, band_crop(p, band),
                                      langs, p, workdir, stage("refine"))
        stats.refined += moved
        log(f"{moved} confini spostati")

    return kept, dropped, gaps


def process_video(video: str, out_path: str, p: OcrParams,
                  progress_cb: Optional[Callable[[str, float, str], None]] = None,
                  log_cb: Optional[Callable[[str], None]] = None,
                  tmp_root: Optional[Path] = None,
                  ui_lang: str = "it"
                  ) -> Tuple[List[Tuple[float, float, str]], RunStats]:
    """
    Pipeline completa. progress_cb(stage, ratio, text) con stage in
    {"extract","group","ocr","refine"}. Ritorna (segmenti_tuple, stats);
    stats.qc_path contiene il percorso del report di revisione (se generato).
    ui_lang ("it" | "en") e' solo la lingua dei testi del report di revisione.
    """
    if not vision_available():
        raise RuntimeError("Apple Vision non disponibile (pip install ocrmac). "
                           "Serve macOS 10.15+.")
    langs = resolve_langs(p.lang_hint)
    tmp_root = Path(tmp_root or tempfile.gettempdir())
    tmp_root.mkdir(parents=True, exist_ok=True)
    workdir = Path(tempfile.mkdtemp(prefix="voc26_", dir=str(tmp_root)))
    stats = RunStats()
    t0 = time.time()
    try:
        warmup(langs, p.recognition_level)

        all_segs: List[SegInfo] = []
        all_dropped: List[SegInfo] = []
        gaps: List[Tuple[float, float, str]] = []

        bands = ["bottom"] + (["top"] if p.top_band else [])
        for band in bands:
            kept, dropped, g = _process_band(video, band, p, langs, workdir,
                                             stats, progress_cb, log_cb)
            all_segs += kept
            all_dropped += dropped
            gaps += g

        all_segs.sort(key=lambda s: (s.start, s.top))

        # postprocess del testo (incl. correzioni) + tag {\an8} per i cartelli
        final: List[Tuple[float, float, str]] = []
        for s in all_segs:
            txt = postprocess(s.text, p.wrap_width, p.ignore_lines, p.corrections,
                              lang_hint=p.lang_hint)
            if not txt:
                continue
            s.text = txt
            final.append((s.start, s.end, ("{\\an8}" + txt) if s.top else txt))
        stats.segments = len(final)
        stats.dropped = len(all_dropped)
        stats.elapsed = time.time() - t0

        write_srt(final, out_path)
        if log_cb:
            log_cb(f"SRT scritto: {out_path} ({stats.segments} righe, "
                   f"{stats.ocr_calls} OCR, {stats.refined} confini raffinati, "
                   f"{stats.elapsed:.1f}s)")

        if p.qc_report:
            qc = Path(out_path).with_suffix(".revisione.html")
            write_qc_html(qc, Path(video).name, Path(out_path).name,
                          [s for s in all_segs if s.text],
                          all_dropped, gaps, stats, p, ui_lang=ui_lang)
            stats.qc_path = str(qc)
            if log_cb:
                log_cb(f"Report di revisione: {qc}")

        return final, stats
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def load_ignore(path: Path) -> List[str]:
    try:
        if not path.exists():
            return []
        return [ln.strip() for ln in path.read_text(encoding="utf-8").splitlines()
                if ln.strip() and not ln.strip().startswith("#")]
    except Exception:
        return []


def load_corrections(path: Path) -> List[Tuple[str, str]]:
    """
    Carica correzioni.txt: una regola per riga nel formato
        sbagliato => giusto
    Righe vuote e commenti (#) ignorati. Le regole piu' lunghe si applicano
    per prime (evita che una regola corta "rompa" una piu' specifica).
    """
    out: List[Tuple[str, str]] = []
    try:
        if not path.exists():
            return []
        for ln in path.read_text(encoding="utf-8").splitlines():
            ln = ln.strip()
            if not ln or ln.startswith("#") or "=>" not in ln:
                continue
            wrong, _, right = ln.partition("=>")
            wrong, right = wrong.strip(), right.strip()
            if wrong:
                out.append((wrong, right))
        out.sort(key=lambda wr: -len(wr[0]))
    except Exception:
        pass
    return out
