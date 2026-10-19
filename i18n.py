#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SubVision — stringhe dell'interfaccia (italiano / inglese).

Solo testo: nessuna logica. app.py sceglie la lingua con il selettore in
cima alla sidebar e legge le stringhe da STRINGS[lang]; le stringhe del
report di revisione vivono invece in ocr_core._QC_I18N (il report viene
generato nella lingua UI passata a process_video/write_qc_html).
"""

# etichetta del selettore -> codice lingua
LANG_OPTIONS = {"Italiano": "it", "English": "en"}

STRINGS = {
    # ================================================================ ITALIANO
    "it": {
        # --- generale
        "app_title": "🎬 SubVision — Hardsub → SRT (Apple Vision)",
        "vision_missing": "Apple Vision non disponibile. Installa il wrapper:  "
                          "`pip install ocrmac`  (richiede macOS 10.15+).",
        "ui_lang_label": "🌐 Lingua interfaccia / UI language",
        "ui_lang_help": "La lingua dell'interfaccia e del report di revisione. "
                        "Indipendente da 'Lingua (hint)', che riguarda l'OCR.",

        # --- sidebar: Opzioni OCR
        "ocr_options": "Opzioni OCR",
        "ocr_caption": "Default = massima accuratezza (puntata da 20-24 min ≈ 1.5-2 ore). "
                       "Ogni opzione ha un (?) con la spiegazione.",
        "lang_hint_label": "Lingua (hint)",
        "lang_hint_help": "La lingua dei sottotitoli incisi: aiuta l'OCR a scegliere "
                          "il dizionario giusto (accenti, apostrofi).\n\n"
                          "Valori: Italian, English, Japanese, Spanish, French, "
                          "German…\n\n"
                          "⚠️ Sbagliarla peggiora molto gli accenti (è, à, ì).",
        "fps_label": "FPS analisi",
        "fps_help": "Quanti fotogrammi al secondo vengono analizzati.\n"
                    "- **12** = massima accuratezza: becca anche sub brevissimi "
                    "e confini precisi *(default)*\n"
                    "- **8-10** = ottimo compromesso\n"
                    "- **4-6** = veloce, rischia di perdere flash molto brevi\n\n"
                    "Il tempo di elaborazione cresce in proporzione. Con *Raffina "
                    "i tempi* attivo, i confini vengono comunque portati al frame "
                    "nativo del video.",
        "multi_variant_label": "OCR multi-variante con voto",
        "multi_variant_help": "Ogni frame viene letto in 3 versioni (originale / "
                              "contrasto+sharpen / scala di grigi) e vince il testo con "
                              "più voti pesati per confidenza.\n\n"
                              "Misurato: corregge i typo del passaggio singolo "
                              "(es. 'saff' → 'sai?'). Costa ~3x in tempo OCR.\n"
                              "Disattiva solo se hai fretta e i sub sono molto puliti.",
        "refine_label": "Raffina i tempi al frame nativo",
        "refine_help": "Dopo l'analisi, inizio e fine di OGNI riga vengono "
                       "ricalcolati al framerate reale del video (es. 23.976): "
                       "precisione ~±20ms invece di ~±40-120ms.\n\n"
                       "Costo: pochi minuti in più a puntata. Disattiva solo "
                       "se i tempi 'a occhio' ti bastano.",
        "min_conf_label": "Confidenza minima",
        "min_conf_help": "L'OCR assegna a ogni riga letta una confidenza 0-1; sotto "
                         "questa soglia il testo viene ignorato.\n"
                         "- **0.30** = default: filtra il rumore mantenendo il recall\n"
                         "- **più basso** (0.15-0.25) = recupera testo su font "
                         "difficili, ma più rumore (che comunque finisce nel report di revisione)\n"
                         "- **più alto** (0.5+) = solo testo sicuro: rischi di "
                         "perdere sub",

        # --- sidebar: banda dialoghi
        "band_bottom_header": "Banda dialoghi (in basso)",
        "bottom_pct_label": "Altezza dal basso (%)",
        "bottom_pct_help": "Quanta parte INFERIORE del fotogramma viene analizzata per i "
                           "dialoghi. Deve contenere i sottotitoli anche quando vanno su "
                           "2 righe.\n"
                           "- **25-30%** = tipico per gli anime *(default 28)*\n"
                           "- **troppo basso** = tagli la prima riga dei sub doppi\n"
                           "- **troppo alto** = includi più scena → più rumore e più "
                           "lento\n\n"
                           "Usa la scheda Anteprima (riquadro VERDE) per verificare.",
        "width_pct_label": "Larghezza centrale (%)",
        "width_pct_help": "Quanta larghezza (centrata) viene analizzata per i dialoghi.\n"
                          "- **96%** = default: esclude solo gli angoli estremi\n"
                          "- **100%** = tutto: usalo se i sub arrivano fino ai bordi\n"
                          "- **più stretto** (85-92%) = meno rumore da loghi/watermark, "
                          "ma rischi di tagliare righe lunghe",

        # --- sidebar: banda cartelli
        "band_top_header": "Banda cartelli (in alto)",
        "top_band_label": "OCR anche la parte alta ({\\an8})",
        "top_band_help": "Seconda passata sulla parte ALTA del frame: cattura cartelli, "
                         "insegne e note del traduttore che i fansub mettono in alto. "
                         "Le righe entrano nell'SRT con tag {\\an8} (posizione alta).\n\n"
                         "ON di default (massima completezza). Disattiva per le serie "
                         "senza cartelli: dimezzi il tempo di elaborazione.",
        "top_pct_label": "Altezza dall'alto (%)",
        "top_pct_help": "Quanta parte SUPERIORE del frame viene analizzata per i "
                        "cartelli. 20-25% basta quasi sempre (default 22).\n\n"
                        "Riquadro AZZURRO nella scheda Anteprima.",
        "top_w_pct_label": "Larghezza centrale cartelli (%)",
        "top_w_pct_help": "Quanta larghezza (centrata) viene analizzata nella banda "
                          "cartelli — separata da quella dei dialoghi.\n"
                          "- **100%** = default: i cartelli possono stare ovunque\n"
                          "- **più stretto** (85-95%) = esclude i watermark/loghi del "
                          "fansub negli angoli in alto, se generano righe spurie",

        # --- sidebar: segmenti
        "segments_header": "Segmenti",
        "min_dur_label": "Durata minima riga (s)",
        "min_dur_help": "Righe più brevi di così vengono scartate come 'flash' "
                        "(letture spurie di 1-2 frame).\n\n"
                        "⚠️ NON si perdono: restano nel report di revisione con thumbnail e "
                        "spunta per recuperarle. 0.20s = default; abbassa a 0.10 "
                        "se la serie ha davvero sub fulminei.",
        "merge_gap_label": "Gap max per unire righe simili (s)",
        "merge_gap_help": "Se due righe hanno testo uguale/simile e sono separate da "
                          "un buco più corto di così, vengono FUSE in una sola "
                          "(tipico: micro-interruzioni durante dissolvenze o "
                          "cambi scena con lo stesso sub).\n"
                          "- **0.6s** = default\n"
                          "- **più alto** = unisce di più (rischio: fonde due "
                          "battute uguali volutamente separate)",
        "wrap_label": "Larghezza per andare a capo",
        "wrap_help": "Sotto questa soglia la riga resta una. Sopra, viene spezzata "
                     "in 2 (o 3) righe BILANCIATE: lunghezze simili (80 caratteri → "
                     "~40+40, non 72+8), taglio preferito dopo la punteggiatura, "
                     "mai dopo articoli/preposizioni (regola attiva per Italian ed "
                     "English; altre lingue: solo bilanciamento+punteggiatura), "
                     "mai parole spezzate.\n\n"
                     "**36-44** = valori tipici per i player. **42** = default.",

        # --- sidebar: avanzate
        "advanced": "Avanzate",
        "qc_report_label": "Genera report di revisione (.revisione.html)",
        "qc_report_help": "Crea l'EDITOR di revisione accanto all'SRT: thumbnail e "
                          "confidenza per riga, righe dubbie evidenziate, testo "
                          "editabile, letture alternative con un click, righe "
                          "aggiungibili nei buchi, export dell'SRT revisionato.\n"
                          "Praticamente gratis: tienilo sempre attivo.",
        "qc_gap_label": "Revisione: segnala buchi senza sub > (s)",
        "qc_gap_help": "Nel report di revisione, gli intervalli senza sottotitoli più "
                       "lunghi di così vengono elencati come possibili righe "
                       "SALTATE (con thumbnail a metà intervallo).\n"
                       "- **6s** = default\n"
                       "- **3-4s** = controllo più fitto (più voci da "
                       "scorrere)",
        "skip_ham_label": "Skip Hamming",
        "skip_ham_help": "Ottimizzazione: salta l'OCR dei frame quasi identici al "
                         "precedente (ereditano il testo).\n"
                         "- **0** = OCR di OGNI frame, nessuna assunzione "
                         "*(max accuratezza, default)*\n"
                         "- **1** = ~20-30% più veloce; misurato: tempi identici\n"
                         "- **≥2** = più veloce ma confini meno affidabili "
                         "(il raffinamento li recupera in parte)",
        "workers_label": "Thread OCR",
        "workers_help": "Chiamate OCR in parallelo. NON cambia l'accuratezza: il "
                        "Neural Engine è il collo di bottiglia (~18 frame/s totali). "
                        "4 = default; alzarlo dà benefici minimi.",
        "use_ignore_label": "Usa ignore.txt",
        "use_ignore_help": "Scarta le frasi elencate in ignore.txt (una per riga, "
                           "# per i commenti): utile per watermark ricorrenti del "
                           "fansub, loghi, scritte fisse.",
        "use_corrections_label": "Usa correzioni.txt",
        "use_corrections_help": "Applica le sostituzioni automatiche di "
                                "correzioni.txt (formato: `sbagliato => giusto`, "
                                "una per riga, case-insensitive).\n\n"
                                "Perfetto per i typo RICORRENTI che l'OCR non "
                                "risolverà mai, tipo i nomi propri su font "
                                "difficili: `Flamilion => Hamilton` sistema "
                                "tutte le puntate della serie in un colpo.",
        "clean_tmp_label": "Svuota /tmp a fine processo",
        "clean_tmp_help": "Elimina i frame temporanei a fine batch. Disattiva solo "
                          "per debug (occhio: i frame occupano GB).",
        "ignore_missing": "ignore.txt non trovato: uso solo i filtri interni.",

        # --- tab
        "tab_run": "Elabora",
        "tab_prev": "Anteprima",
        "tab_fix": "Sub fix",

        # --- Elabora
        "select_videos": "Seleziona i video",
        "no_videos_warn": "Nessun video in ./videos. Aggiungi file (.mkv, .mp4, .mov, …) e ricarica.",
        "outputs_caption": "L'SRT (e il report .revisione.html) vengono salvati accanto al video. "
                           "Se l'SRT esiste, viene aggiunto un timestamp.",
        "start_btn": "▶ Avvia OCR",
        "start_btn_help": "Elabora i video selezionati con le opzioni della "
                          "sidebar. Per ogni video crea: .srt, report .revisione.html "
                          "e .log accanto al file.",
        "reset_msgs_btn": "Reset messaggi",
        "select_at_least_one": "Seleziona almeno un video.",
        "vision_unavailable": "Apple Vision non disponibile.",
        "band_dialogues": "dialoghi",
        "band_signs": "cartelli",
        "step_extract": "Estrazione fotogrammi",
        "step_group": "Analisi ridondanza",
        "step_ocr": "OCR x{n} letture",
        "step_refine": "Raffinamento tempi",
        "file_header": "#### 🎞️ File {n}/{tot} — {name}",
        "srt_existed_note": " (l'SRT esisteva già)",
        "waiting": "in attesa",
        "waiting_est": " · stima ~{est} (dal file precedente)",
        "step_waiting_row": "⬜ **STEP {i}/{n}** — {label} — *{wait}*",
        "unit_rows_s": "righe/s",
        "unit_fps": "fps",
        "rate_avg": " — media {rate:.1f} {unit}",
        "step_done": "STEP {i}/{n} — {label} ✅ {last} — concluso in {dur}{rate}",
        "step_start": "STEP {i}/{n} — {label} ▶ inizio",
        "step_aborted": "STEP {i}/{n} — {label} ❌ interrotto",
        "eta": " — ETA {eta}",
        "rate_live": " — {rate:.1f} {unit}",
        "step_progress": "STEP {i}/{n} — {label}: {text} — trascorso {elapsed}{eta}{rate}",
        "log_error": "ERRORE: {e}",
        "msg_error": "{name}: errore — {e}",
        "times_summary": "⏱ {times}",
        "log_result": "RISULTATO: {segments} righe, {dropped} scartate "
                      "(nel report di revisione), {refined} confini raffinati, "
                      "totale {elapsed}",
        "qc_note": " · report di revisione: **{name}**",
        "msg_no_subs": "{name}: nessun sottotitolo trovato → {out}{qc}",
        "msg_done": "{name}: {segments} righe → **{out}**{note}"
                    " · {dropped} scartate (nel report di revisione) · "
                    "{refined} confini raffinati · "
                    "totale {elapsed}{qc}\n\n"
                    "⏱ {times}",
        "batch_done_toast": "Batch completato ✅",

        # --- Anteprima
        "prev_subheader": "Anteprima ritaglio + test OCR",
        "disabled_while_busy": "Disabilitata durante l'elaborazione.",
        "no_videos_info": "Nessun video in ./videos.",
        "video_select_label": "Video",
        "video_select_help": "Il video su cui verificare le bande di ritaglio e "
                             "provare l'OCR su singoli frame.",
        "extract_frames_btn": "Estrai {n} frame di esempio (cerca quelli col testo)",
        "extract_frames_help": "Divide il video in {n} zone temporali e in ognuna cerca "
                               "un fotogramma che CONTENGA testo nella banda dialoghi "
                               "(fino a {tries} tentativi per zona, OCR veloce). "
                               "Se in una zona non c'è testo, mostra comunque un frame "
                               "etichettato 'senza testo'.\n\n"
                               "Sui frame vengono disegnate le bande: VERDE = dialoghi, "
                               "AZZURRO = cartelli. Regola gli slider finché i sub cadono "
                               "dentro. Richiede ~15-40s.",
        "invalid_duration": "Durata non valida.",
        "searching_frames": "Cerco frame col testo…",
        "zone_progress": "Zona {done}/{tot} — {found} frame col testo",
        "frames_caption": "{n} frame — {with_text} con testo rilevato, "
                          "{without} senza (zone mute del video).",
        "badge_top_text": "✅ testo rilevato (cartello in alto)",
        "badge_bottom_text": "✅ testo rilevato (dialoghi)",
        "badge_no_text": "◽ zona senza testo",
        "frame_caption": "Frame {i}/{n} — {badge} — verde = dialoghi",
        "frame_caption_top": ", azzurro = cartelli",
        "preview_unavailable": "Anteprima non disponibile.",
        "test_ocr_btn": "🔍 Test OCR su questo frame",
        "test_ocr_help": "Esegue l'OCR con voto sulla banda dialoghi e, se attiva, "
                         "anche sulla banda cartelli: due risultati separati.",
        "band_bottom_title": "🟩 Banda dialoghi",
        "band_top_title": "🟦 Banda cartelli ({\\an8})",
        "ocr_vote_caption": "OCR con voto ({ms:.0f} ms, {n} varianti):",
        "empty_text": "<VUOTO>",
        "conf_agree": "Confidenza {conf:.0f}% · accordo {agree:.0f}%",
        "alts_suffix": " · alternative: {alts}",
        "final_text_label": "Testo finale (dopo pulizia e a-capo)",
        "final_text_help": "Com'è l'OCR grezzo dopo sanificazione, filtri, "
                           "correzioni e a-capo: è ciò che finirebbe "
                           "nell'SRT.",
        "no_text_in_band": "Nessun testo rilevato in questa banda.",

        # --- Sub fix
        "fix_subheader": "Correggi un file .srt esistente (senza rifare l'OCR)",
        "fix_caption": "Gli SRT prodotti da **Elabora** sono già puliti: questa scheda NON serve per "
                       "quelli. Serve per gli SRT che vengono da fuori: i vecchi SRT fatti con Ollama, "
                       "file scaricati/modificati a mano, o per applicare retroattivamente le nuove "
                       "regole di correzioni.txt a puntate già elaborate — in secondi, senza "
                       "rielaborare il video.",
        "fx_merge_label": "Unisci righe duplicate/simili",
        "fx_merge_help": "Righe consecutive con testo identico o molto simile "
                         "vengono fuse in un unico intervallo (usa il 'Gap max' "
                         "impostato nella sidebar).",
        "fx_ignore_label": "Rimuovi righe senza sottotitoli",
        "fx_ignore_help": "Elimina righe generiche tipo 'Non ci sono "
                          "sottotitoli…' (retaggio dei vecchi SRT fatti con "
                          "Ollama) e le frasi di ignore.txt.",
        "fx_flash_label": "Rimuovi flash troppo brevi",
        "fx_flash_help": "Elimina le righe con durata inferiore alla soglia "
                         "qui sotto: di norma sono letture spurie.",
        "fx_min_label": "Durata minima (s)",
        "fx_min_help": "Soglia per il filtro 'flash': righe più brevi di "
                       "così vengono rimosse (se il filtro è attivo).",
        "source_label": "Sorgente",
        "source_from_videos": "Da ./videos",
        "source_upload": "Carica file",
        "source_help": "Scegli un .srt già presente in ./videos oppure caricane "
                       "uno da un'altra cartella.",
        "srt_select_label": ".srt",
        "no_srt_info": "Nessun .srt in ./videos.",
        "upload_srt_label": "Carica .srt",
        "run_fix_btn": "Esegui Sub fix",
        "no_valid_segments": "Nessun segmento valido dopo la pulizia.",
        "fix_created": "Creato: {name} ({n} righe)",
        "generic_error": "Errore: {e}",

        # --- footer / aggiornamenti
        "footer": "SubVision v{version} — [⭐ GitHub]({url})",
        "update_available": "🆕 Nuova versione **{tag}** disponibile — "
                            "[vai alle release]({url})",
    },

    # ================================================================ ENGLISH
    "en": {
        # --- general
        "app_title": "🎬 SubVision — Hardsub → SRT (Apple Vision)",
        "vision_missing": "Apple Vision not available. Install the wrapper:  "
                          "`pip install ocrmac`  (requires macOS 10.15+).",
        "ui_lang_label": "🌐 Lingua interfaccia / UI language",
        "ui_lang_help": "Language of the interface and of the review report. "
                        "Independent from 'Language (hint)', which affects the OCR.",

        # --- sidebar: OCR options
        "ocr_options": "OCR options",
        "ocr_caption": "Defaults = maximum accuracy (a 20-24 min episode ≈ 1.5-2 hours). "
                       "Every option has a (?) with its explanation.",
        "lang_hint_label": "Language (hint)",
        "lang_hint_help": "The language of the burned-in subtitles: it helps the OCR pick "
                          "the right dictionary (accents, apostrophes).\n\n"
                          "Values: Italian, English, Japanese, Spanish, French, "
                          "German…\n\n"
                          "⚠️ Getting it wrong noticeably hurts accented characters (è, à, ì).",
        "fps_label": "Analysis FPS",
        "fps_help": "How many frames per second are analyzed.\n"
                    "- **12** = maximum accuracy: catches even very short subs "
                    "and precise boundaries *(default)*\n"
                    "- **8-10** = great compromise\n"
                    "- **4-6** = fast, may miss very short flashes\n\n"
                    "Processing time grows proportionally. With *Refine timing* "
                    "enabled, boundaries are snapped to the video's native frame "
                    "rate anyway.",
        "multi_variant_label": "Multi-variant OCR with voting",
        "multi_variant_help": "Each frame is read in 3 versions (original / "
                              "contrast+sharpen / grayscale) and the text with the "
                              "most confidence-weighted votes wins.\n\n"
                              "Measured: it fixes single-pass typos "
                              "(e.g. 'saff' → 'sai?'). Costs ~3x in OCR time.\n"
                              "Disable only if you are in a hurry and the subs are very clean.",
        "refine_label": "Refine timing to the native frame rate",
        "refine_help": "After the analysis, the start and end of EVERY line are "
                       "recomputed at the video's real frame rate (e.g. 23.976): "
                       "precision ~±20ms instead of ~±40-120ms.\n\n"
                       "Cost: a few extra minutes per episode. Disable only "
                       "if rough timing is good enough for you.",
        "min_conf_label": "Minimum confidence",
        "min_conf_help": "The OCR assigns each detected line a 0-1 confidence; below "
                         "this threshold the text is ignored.\n"
                         "- **0.30** = default: filters noise while keeping recall\n"
                         "- **lower** (0.15-0.25) = recovers text on difficult "
                         "fonts, but more noise (which still ends up in the review report)\n"
                         "- **higher** (0.5+) = only confident text: you may "
                         "lose subs",

        # --- sidebar: dialogue band
        "band_bottom_header": "Dialogue band (bottom)",
        "bottom_pct_label": "Height from the bottom (%)",
        "bottom_pct_help": "How much of the LOWER part of the frame is analyzed for "
                           "dialogue. It must contain the subtitles even when they span "
                           "2 lines.\n"
                           "- **25-30%** = typical for anime *(default 28)*\n"
                           "- **too low** = you cut off the first line of two-line subs\n"
                           "- **too high** = you include more of the scene → more noise and "
                           "slower\n\n"
                           "Use the Preview tab (GREEN box) to verify.",
        "width_pct_label": "Center width (%)",
        "width_pct_help": "How much (centered) width is analyzed for dialogue.\n"
                          "- **96%** = default: excludes only the extreme corners\n"
                          "- **100%** = everything: use it if subs reach the edges\n"
                          "- **narrower** (85-92%) = less noise from logos/watermarks, "
                          "but you may cut long lines",

        # --- sidebar: signs band
        "band_top_header": "Signs band (top)",
        "top_band_label": "OCR the top area too ({\\an8})",
        "top_band_help": "Second pass on the TOP part of the frame: it captures signs, "
                         "banners and translator notes that fansubs place at the top. "
                         "Lines enter the SRT with the {\\an8} tag (top position).\n\n"
                         "ON by default (maximum completeness). Disable for series "
                         "without signs: you halve the processing time.",
        "top_pct_label": "Height from the top (%)",
        "top_pct_help": "How much of the UPPER part of the frame is analyzed for "
                        "signs. 20-25% is almost always enough (default 22).\n\n"
                        "BLUE box in the Preview tab.",
        "top_w_pct_label": "Signs center width (%)",
        "top_w_pct_help": "How much (centered) width is analyzed in the signs "
                          "band — separate from the dialogue one.\n"
                          "- **100%** = default: signs can be anywhere\n"
                          "- **narrower** (85-95%) = excludes fansub watermarks/logos "
                          "in the top corners, if they generate spurious lines",

        # --- sidebar: segments
        "segments_header": "Segments",
        "min_dur_label": "Minimum line duration (s)",
        "min_dur_help": "Lines shorter than this are discarded as 'flashes' "
                        "(spurious 1-2 frame readings).\n\n"
                        "⚠️ They are NOT lost: they stay in the review report with a thumbnail and "
                        "a checkbox to recover them. 0.20s = default; lower to 0.10 "
                        "if the series really has lightning-fast subs.",
        "merge_gap_label": "Max gap to merge similar lines (s)",
        "merge_gap_help": "If two lines have equal/similar text and are separated by "
                          "a gap shorter than this, they are MERGED into one "
                          "(typical: micro-interruptions during fades or "
                          "scene cuts with the same sub).\n"
                          "- **0.6s** = default\n"
                          "- **higher** = merges more (risk: it fuses two "
                          "identical lines that were intentionally separate)",
        "wrap_label": "Line-wrap width",
        "wrap_help": "Below this threshold the line stays single. Above it, it is split "
                     "into 2 (or 3) BALANCED lines: similar lengths (80 characters → "
                     "~40+40, not 72+8), preferred break after punctuation, "
                     "never after articles/prepositions (rule active for Italian and "
                     "English; other languages: balancing+punctuation only), "
                     "never broken words.\n\n"
                     "**36-44** = typical values for players. **42** = default.",

        # --- sidebar: advanced
        "advanced": "Advanced",
        "qc_report_label": "Generate review report (.revisione.html)",
        "qc_report_help": "Creates the review EDITOR next to the SRT: thumbnail and "
                          "confidence per line, doubtful lines highlighted, editable "
                          "text, alternative readings applied with one click, lines "
                          "addable in the gaps, export of the reviewed SRT.\n"
                          "Practically free: keep it always on.",
        "qc_gap_label": "Review: flag gaps without subs > (s)",
        "qc_gap_help": "In the review report, intervals without subtitles longer "
                       "than this are listed as possibly SKIPPED lines "
                       "(with a thumbnail at mid-interval).\n"
                       "- **6s** = default\n"
                       "- **3-4s** = tighter check (more entries to "
                       "scroll)",
        "skip_ham_label": "Hamming skip",
        "skip_ham_help": "Optimization: skips the OCR of frames nearly identical to the "
                         "previous one (they inherit the text).\n"
                         "- **0** = OCR of EVERY frame, no assumptions "
                         "*(max accuracy, default)*\n"
                         "- **1** = ~20-30% faster; measured: identical timing\n"
                         "- **≥2** = faster but less reliable boundaries "
                         "(refinement partially recovers them)",
        "workers_label": "OCR threads",
        "workers_help": "Parallel OCR calls. It does NOT change accuracy: the "
                        "Neural Engine is the bottleneck (~18 frames/s total). "
                        "4 = default; raising it gives minimal benefits.",
        "use_ignore_label": "Use ignore.txt",
        "use_ignore_help": "Discards the phrases listed in ignore.txt (one per line, "
                           "# for comments): useful for recurring fansub "
                           "watermarks, logos, fixed text.",
        "use_corrections_label": "Use correzioni.txt",
        "use_corrections_help": "Applies the automatic replacements from "
                                "correzioni.txt (format: `wrong => right`, "
                                "one per line, case-insensitive).\n\n"
                                "Perfect for the RECURRING typos the OCR will "
                                "never fix, like proper nouns on difficult "
                                "fonts: `Flamilion => Hamilton` fixes "
                                "every episode of the series in one go.",
        "clean_tmp_label": "Empty /tmp when done",
        "clean_tmp_help": "Deletes the temporary frames at the end of the batch. Disable only "
                          "for debugging (careful: frames take up GBs).",
        "ignore_missing": "ignore.txt not found: using only the internal filters.",

        # --- tabs
        "tab_run": "Process",
        "tab_prev": "Preview",
        "tab_fix": "Sub fix",

        # --- Process
        "select_videos": "Select the videos",
        "no_videos_warn": "No videos in ./videos. Add files (.mkv, .mp4, .mov, …) and reload.",
        "outputs_caption": "The SRT (and the .revisione.html report) are saved next to the video. "
                           "If the SRT exists, a timestamp is appended.",
        "start_btn": "▶ Start OCR",
        "start_btn_help": "Processes the selected videos with the sidebar "
                          "options. For each video it creates: .srt, .revisione.html report "
                          "and .log next to the file.",
        "reset_msgs_btn": "Clear messages",
        "select_at_least_one": "Select at least one video.",
        "vision_unavailable": "Apple Vision not available.",
        "band_dialogues": "dialogue",
        "band_signs": "signs",
        "step_extract": "Frame extraction",
        "step_group": "Redundancy analysis",
        "step_ocr": "OCR x{n} readings",
        "step_refine": "Timing refinement",
        "file_header": "#### 🎞️ File {n}/{tot} — {name}",
        "srt_existed_note": " (the SRT already existed)",
        "waiting": "waiting",
        "waiting_est": " · estimate ~{est} (from the previous file)",
        "step_waiting_row": "⬜ **STEP {i}/{n}** — {label} — *{wait}*",
        "unit_rows_s": "lines/s",
        "unit_fps": "fps",
        "rate_avg": " — average {rate:.1f} {unit}",
        "step_done": "STEP {i}/{n} — {label} ✅ {last} — finished in {dur}{rate}",
        "step_start": "STEP {i}/{n} — {label} ▶ start",
        "step_aborted": "STEP {i}/{n} — {label} ❌ aborted",
        "eta": " — ETA {eta}",
        "rate_live": " — {rate:.1f} {unit}",
        "step_progress": "STEP {i}/{n} — {label}: {text} — elapsed {elapsed}{eta}{rate}",
        "log_error": "ERROR: {e}",
        "msg_error": "{name}: error — {e}",
        "times_summary": "⏱ {times}",
        "log_result": "RESULT: {segments} lines, {dropped} dropped "
                      "(in the review report), {refined} boundaries refined, "
                      "total {elapsed}",
        "qc_note": " · review report: **{name}**",
        "msg_no_subs": "{name}: no subtitles found → {out}{qc}",
        "msg_done": "{name}: {segments} lines → **{out}**{note}"
                    " · {dropped} dropped (in the review report) · "
                    "{refined} boundaries refined · "
                    "total {elapsed}{qc}\n\n"
                    "⏱ {times}",
        "batch_done_toast": "Batch completed ✅",

        # --- Preview
        "prev_subheader": "Crop preview + OCR test",
        "disabled_while_busy": "Disabled while processing.",
        "no_videos_info": "No videos in ./videos.",
        "video_select_label": "Video",
        "video_select_help": "The video on which to verify the crop bands and "
                             "try the OCR on single frames.",
        "extract_frames_btn": "Extract {n} sample frames (looks for the ones with text)",
        "extract_frames_help": "Splits the video into {n} time zones and in each one looks for "
                               "a frame that CONTAINS text in the dialogue band "
                               "(up to {tries} attempts per zone, fast OCR). "
                               "If a zone has no text, it still shows a frame "
                               "labeled 'no text'.\n\n"
                               "The bands are drawn on the frames: GREEN = dialogue, "
                               "BLUE = signs. Adjust the sliders until the subs fall "
                               "inside. Takes ~15-40s.",
        "invalid_duration": "Invalid duration.",
        "searching_frames": "Looking for frames with text…",
        "zone_progress": "Zone {done}/{tot} — {found} frames with text",
        "frames_caption": "{n} frames — {with_text} with detected text, "
                          "{without} without (silent zones of the video).",
        "badge_top_text": "✅ text detected (sign at the top)",
        "badge_bottom_text": "✅ text detected (dialogue)",
        "badge_no_text": "◽ zone without text",
        "frame_caption": "Frame {i}/{n} — {badge} — green = dialogue",
        "frame_caption_top": ", blue = signs",
        "preview_unavailable": "Preview not available.",
        "test_ocr_btn": "🔍 Test OCR on this frame",
        "test_ocr_help": "Runs the voting OCR on the dialogue band and, if enabled, "
                         "also on the signs band: two separate results.",
        "band_bottom_title": "🟩 Dialogue band",
        "band_top_title": "🟦 Signs band ({\\an8})",
        "ocr_vote_caption": "Voting OCR ({ms:.0f} ms, {n} variants):",
        "empty_text": "<EMPTY>",
        "conf_agree": "Confidence {conf:.0f}% · agreement {agree:.0f}%",
        "alts_suffix": " · alternatives: {alts}",
        "final_text_label": "Final text (after cleanup and line-wrap)",
        "final_text_help": "The raw OCR after sanitization, filters, "
                           "corrections and line-wrap: this is what would end up "
                           "in the SRT.",
        "no_text_in_band": "No text detected in this band.",

        # --- Sub fix
        "fix_subheader": "Fix an existing .srt file (without redoing the OCR)",
        "fix_caption": "The SRTs produced by **Process** are already clean: this tab is NOT for "
                       "them. It is for SRTs coming from outside: old SRTs made with Ollama, "
                       "files downloaded/edited by hand, or to retroactively apply new "
                       "correzioni.txt rules to episodes already processed — in seconds, without "
                       "reprocessing the video.",
        "fx_merge_label": "Merge duplicate/similar lines",
        "fx_merge_help": "Consecutive lines with identical or very similar text "
                         "are merged into a single interval (uses the 'Max gap' "
                         "set in the sidebar).",
        "fx_ignore_label": "Remove no-subtitle lines",
        "fx_ignore_help": "Deletes generic lines like 'There are no "
                          "subtitles…' (legacy of the old Ollama-made SRTs) "
                          "and the phrases from ignore.txt.",
        "fx_flash_label": "Remove too-short flashes",
        "fx_flash_help": "Deletes lines with a duration below the threshold "
                         "here below: they are usually spurious readings.",
        "fx_min_label": "Minimum duration (s)",
        "fx_min_help": "Threshold for the 'flash' filter: lines shorter than "
                       "this are removed (if the filter is enabled).",
        "source_label": "Source",
        "source_from_videos": "From ./videos",
        "source_upload": "Upload file",
        "source_help": "Pick an .srt already present in ./videos or upload "
                       "one from another folder.",
        "srt_select_label": ".srt",
        "no_srt_info": "No .srt in ./videos.",
        "upload_srt_label": "Upload .srt",
        "run_fix_btn": "Run Sub fix",
        "no_valid_segments": "No valid segments after cleanup.",
        "fix_created": "Created: {name} ({n} lines)",
        "generic_error": "Error: {e}",

        # --- footer / updates
        "footer": "SubVision v{version} — [⭐ GitHub]({url})",
        "update_available": "🆕 New version **{tag}** available — "
                            "[go to releases]({url})",
    },
}
