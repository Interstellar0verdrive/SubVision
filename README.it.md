# 🎬 SubVision — Hardsub → SRT (Apple Vision)

[🇬🇧 English](README.md) | 🇮🇹 Italiano

**Estrae i sottotitoli HARD-SUB (incisi nel video) e li converte in `.srt`
usando Apple Vision, il motore OCR nativo di macOS — veloce, offline, niente
allucinazioni.**

Progettato per la **massima accuratezza**: i default privilegiano sempre la
qualità sulla velocità. L'obiettivo è ridurre al minimo il rework manuale.

Perché Apple Vision invece di un LLM/VLM:

- **NON allucina**: legge i glifi presenti; se non c'è testo, restituisce vuoto.
- **~50-100x più veloce di un VLM**: gira su Neural Engine (~18 frame/s).
- **Deterministico, 100% offline.**

L'interfaccia è disponibile in **italiano e inglese** (selettore in cima alla
sidebar; la scelta viene ricordata tra un avvio e l'altro). Anche il report di
revisione viene generato nella lingua scelta.

| Schermata principale | Anteprima con le bande |
| --- | --- |
| ![Schermata principale](demo/screenshots/app_main_it.png) | ![Anteprima](demo/screenshots/app_preview_en.png) |

## 🧪 Demo (Sintel)

La cartella [`demo/`](demo) contiene un clip di 55 secondi di dialoghi da
[Sintel](https://durian.blender.org), l'open movie della Blender Foundation
(CC-BY 3.0, **© copyright Blender Foundation | durian.blender.org**), con i
sottotitoli impressi in italiano e in inglese, più ciò che SubVision ne ha
estratto (`.srt` e report `.revisione.html`).

**Accuratezza misurata sulla demo** (profilo veloce: `fps=6`,
`skip_hamming=1`, senza raffinamento tempi né banda cartelli — ~20s di
elaborazione per clip su Mac Apple Silicon):

- clip italiano: **12 righe su 12 trovate**, testo **identico carattere per
  carattere** all'SRT ufficiale di Sintel;
- clip inglese: **12 righe su 12**, testo identico all'SRT ufficiale;
- tempi entro ~±0.1s dai sub ufficiali già col profilo veloce (il profilo
  default raffina i confini al framerate nativo, ~±20ms).

## 🚀 Avvio

1. Metti i video in `./videos` (`.mkv .mp4 .mov .avi .m4v .webm`)
2. Doppio clic su `run.command`
   (la prima volta: clic destro → Apri; se serve `chmod +x run.command`)

Il launcher installa le dipendenze SOLO la prima volta o quando
`requirements.txt` cambia: gli avvii successivi sono immediati (~1s).

**Requisiti:** macOS 10.15+, ffmpeg (`brew install ffmpeg`), Python 3.10+.

Ogni opzione della GUI ha un'icona **(?)** con la spiegazione contestuale:
passa il mouse sopra per leggerla. Questo README ripete e approfondisce.

## ⏱️ Quanto ci mette (puntata da 20-24 min)

| Profilo | Impostazioni | Tempo |
| --- | --- | --- |
| **Default (massima accuratezza)** | fps 12 · skip 0 · 3 varianti · cartelli ON · raffinamento ON | ≈ 1.5-2 ore |
| Bilanciato | fps 8-10 · skip 1 · 3 varianti · cartelli solo se servono | ≈ 30-45 min |
| Veloce (bozza) | fps 6 · skip 1 · multi-variante OFF · cartelli OFF · raffinamento OFF | ≈ 5-15 min |

## ✨ Le 5 armi per l'accuratezza

1. **OCR multi-variante con voto** *(default: ON)* — ogni frame viene letto
   3 volte: Vision raw, Vision con contrasto, e **LiveText** (il secondo
   motore OCR di Apple, quello di "Testo attivo": un motore indipendente che
   sbaglia in modo diverso). Vince il testo con più voti pesati per
   confidenza. Set scelto misurando su frame difficili reali (font corsivo
   con alone).
2. **Voto di segmento** — il testo finale di una riga è quello che ha vinto
   su TUTTI i frame in cui era visibile (decine di letture), non una lettura
   singola.
3. **Raffinamento tempi** *(default: ON)* — i confini inizio/fine vengono
   ricalcolati al framerate NATIVO del video: precisione ~1 frame (~±20ms)
   invece di ±40-120ms.
4. **Banda cartelli** *(default: ON)* — seconda passata sulla parte alta del
   frame per cartelli/insegne/note del traduttore. Finiscono nell'SRT con tag
   `{\an8}` (posizione alta). Disattivala per le serie senza cartelli:
   dimezzi il tempo.
5. **Report di revisione interattivo** (`.revisione.html` accanto all'SRT —
   *default: ON*) — non solo la mappa per la revisione: è un **editor**.
   Aprilo nel browser e:
   - ogni riga ha thumbnail, confidenza, accordo tra varianti;
   - il testo è **editabile** direttamente (es. "e" → "è");
   - le **letture alternative** si applicano con un click (chip azzurre), con
     le parole che differiscono **evidenziate in giallo**;
   - le righe si includono/escludono con la spunta — puoi anche **recuperare**
     i flash scartati e le letture di rumore;
   - nei "buchi lunghi" puoi **aggiungere** una riga con tempi precompilati;
   - tempi editabili e tag `{\an8}` attivabile per riga (badge blu acceso
     "✓ CARTELLO" quando attivo);
   - **💾 Salva SRT revisionato** crea `nome-revisionato-AAAAMMGG-HHMM.srt`:
     con Chrome/Edge si apre il dialogo Salva che **ricorda la cartella**
     (scegli la cartella dei video la prima volta); con Safari il file va in
     Download;
   - al salvataggio, se "unisci duplicati" è attivo (default), le righe
     adiacenti con testo uguale/simile vengono **fuse** — vince il testo che
     hai editato a mano, altrimenti quello della riga più lunga;
   - le modifiche restano salvate nel browser: puoi chiudere e riprendere.
     "Ripristina tutto" azzera.

## ⚙️ Guida alle opzioni (sidebar)

### Opzioni OCR

- **Lingua (hint)** — default: `Italian`. La lingua dei sub incisi: guida il
  dizionario dell'OCR (accenti, apostrofi). Sbagliarla peggiora molto è/à/ì.
  Valori: Italian, English, Japanese, Spanish, French, German, …
- **FPS analisi** — default: `12` (max). Fotogrammi analizzati al secondo.
  Più alto = becca sub più brevi e confini più precisi, tempo proporzionale.
  8-10 ottimo compromesso; 4-6 veloce ma può perdere flash brevissimi.
- **OCR multi-variante con voto** — default: ON. 3 letture per frame + voto.
  Corregge i typo della lettura singola. Costa ~3x. OFF solo per bozze.
- **Raffina i tempi** — default: ON. Ricalcola inizio/fine al framerate reale
  (es. 23.976): precisione ~±20ms. Costa pochi minuti a puntata.
- **Confidenza minima** — default: `0.30`. Sotto questa soglia una lettura
  viene ignorata. Più bassa (0.15-0.25) = più recall su font difficili, più
  rumore; più alta (0.5+) = solo testo sicuro, rischi di perdere sub.

### Banda dialoghi (in basso)

- **Altezza dal basso (%)** — default: `28`. Deve contenere i sub anche su
  2 righe. 25-30% tipico per gli anime. Verifica con Anteprima (riquadro
  VERDE).
- **Larghezza centrale (%)** — default: `96`. 100% se i sub arrivano ai
  bordi; più stretto (85-92%) = meno rumore da loghi.

### Banda cartelli (in alto)

- **OCR anche la parte alta** — default: ON. Cattura cartelli/note del
  traduttore in alto → tag `{\an8}` nell'SRT. OFF per serie senza cartelli
  (dimezza il tempo).
- **Altezza dall'alto (%)** — default: `22`. Riquadro AZZURRO in Anteprima.
- **Larghezza centrale cartelli** — default: `100`, separata da quella dei
  dialoghi. Restringi (85-95%) se un watermark in un angolo alto genera
  righe spurie.

### Segmenti

- **Durata minima riga (s)** — default: `0.20`. Righe più brevi = "flash"
  scartati. NON si perdono: restano nel report di revisione con thumbnail e
  spunta per recuperarle. 0.10 per serie con sub fulminei.
- **Gap max per unire (s)** — default: `0.6`. Righe con testo simile separate
  da un buco più corto vengono fuse (micro-interruzioni nelle dissolvenze).
- **Larghezza per andare a capo** — default: `42`. Sopra la soglia la riga
  viene spezzata in 2 (o 3) righe **bilanciate** (stile sottotitolaggio
  professionale): lunghezze simili, taglio preferito dopo la punteggiatura,
  mai dopo articoli/preposizioni (liste dedicate per Italian ed English),
  mai parole spezzate.

### Avanzate

- **Genera report di revisione** — default: ON. Praticamente gratis.
- **Revisione: segnala buchi > (s)** — default: `6`. Gli intervalli senza sub
  più lunghi finiscono nel report come possibili righe saltate.
- **Skip Hamming** — default: `0` (max accuratezza). Salta l'OCR dei frame
  quasi identici al precedente. 1 = ~20-30% più veloce (misurato: tempi
  identici); ≥2 = più veloce, confini base meno affidabili.
- **Thread OCR** — default: `4`. Parallelismo; non cambia l'accuratezza (il
  Neural Engine resta il collo di bottiglia, ~18 frame/s totali).
- **Usa ignore.txt** — default: ON. Scarta le frasi in `ignore.txt` (una per
  riga, `#` = commento): watermark del fansub, loghi, scritte fisse.
- **Usa correzioni.txt** — default: ON. Applica le sostituzioni di
  `correzioni.txt` (formato: `sbagliato => giusto`, case-insensitive).
  L'arma per i typo RICORRENTI che l'OCR non risolverà mai — i nomi propri su
  font impossibili: `Flamilion => Hamilton` sistema tutte le puntate della
  serie. Vale per pipeline, Test OCR e Sub fix.
- **Svuota /tmp** — default: ON. Pulisce i frame temporanei a fine batch.

## 🖥️ Le 3 schede

- **Elabora** — batch OCR dei video selezionati → `.srt` + `.revisione.html`
  + `.log` accanto al video. Avanzamento a STEP: per ogni file vedi l'elenco
  completo degli step già dall'inizio; lo step attivo mostra barra, conteggio,
  tempo trascorso, ETA e velocità live; quelli conclusi diventano righe verdi
  con statistiche; quelli in attesa mostrano una stima basata sul file
  precedente. Il `.log` registra tutto in modo speculare.
- **Anteprima** — 20 frame campione CHE CONTENGONO TESTO: il video viene
  diviso in 20 zone e in ognuna si cercano frame con sottotitoli (fino a 3
  tentativi per zona, OCR veloce). Bande disegnate sopra (verde = dialoghi,
  azzurro = cartelli). "Test OCR" esegue il voto su entrambe le bande: usala
  per tarare bande e lingua PRIMA di lanciare una puntata intera.
- **Sub fix** — pulizia di un `.srt` esistente SENZA rifare l'OCR. Per gli
  SRT esterni (vecchi file fatti con altri strumenti, file scaricati) o per
  applicare retroattivamente nuove regole di `correzioni.txt` a puntate già
  elaborate, in pochi secondi.

## 🧭 Flusso consigliato (per serie nuova)

1. Metti la puntata 1 in `./videos`
2. **Anteprima** → estrai i 20 frame → tara le bande (verde/azzurro)
3. **Test OCR** su un frame con sottotitolo → verifica lingua e lettura
4. **Elabora** (default massimi) → aspetta
5. Apri il `.revisione.html` → sistemi le righe evidenziate → 💾 Salva SRT
   revisionato
6. Per le puntate successive della stessa serie: stesse impostazioni, lancia
   in batch anche più file insieme.

## 🧠 Pipeline (come funziona sotto)

1. ffmpeg estrae i frame della banda (RAW: niente filtri fissi — misurato che
   l'enhancement fisso peggiorava l'OCR; le varianti votano al punto 3).
2. dhash: (opzionale, skip>0) salta i frame quasi identici al precedente.
3. Apple Vision legge ogni frame target in 3 varianti → voto pesato.
4. Forward-fill + sanificazione (junk, ignore.txt, anti-rumore grafico).
5. Segmenti dal testo per-frame con voto di segmento; merge dei fade.
6. Raffinamento confini al framerate nativo (finestra ±1/fps per lato).
7. Scrittura `.srt` (+ `{\an8}` per i cartelli) e report `.revisione.html`.

## 📁 File

| File | Ruolo |
| --- | --- |
| `app.py` | GUI Streamlit |
| `ocr_core.py` | logica pura, senza UI (testabile headless) |
| `i18n.py` | stringhe dell'interfaccia (it/en) |
| `requirements.txt` | streamlit, pillow, numpy, ocrmac |
| `run.command` | launcher macOS |
| `ignore.txt` | frasi da ignorare |
| `correzioni.txt` | sostituzioni automatiche `sbagliato => giusto` |
| `videos/` | metti qui i video; qui compaiono `.srt` / `.revisione.html` / `.log` |
| `demo/` | clip demo Sintel (CC-BY) con SRT estratti e report |

## 🧪 Uso headless (senza GUI)

```bash
source .venv/bin/activate
python3 -c "import ocr_core as C; \
  C.process_video('videos/ep.mkv', 'videos/ep.srt', C.OcrParams(lang_hint='Italian'))"
```

`OcrParams()` senza argomenti = default di massima accuratezza. Profilo
veloce: `OcrParams(fps=6, skip_hamming=1, multi_variant=False,
top_band=False, refine_timing=False)`. Il parametro `ui_lang` di
`process_video` ("it"/"en") sceglie la lingua del report di revisione.

## 📝 Note

- Qualche typo di accento può restare (Sì→Si): è OCR reale, non inventa mai
  frasi. Il report di revisione mostra le letture alternative: spesso quella
  giusta è lì.
- Il primo OCR di ogni sessione impiega qualche secondo (init Neural Engine).

### Cronologia

- **v3.0 (ott 2026)** — il progetto diventa **SubVision** (prima si chiamava
  *video-OCR-2026*) e diventa open source: interfaccia bilingue it/en con
  selettore (la scelta viene ricordata), report di revisione nella lingua
  scelta, demo Sintel (CC-BY) con benchmark di accuratezza.
- **v2.9 (lug 2026)** — velocità negli step di Elabora (fps live e media a
  fine step); il "report QC" diventa *report di revisione*
  (`.revisione.html`); a-capo bilanciato in 2-3 righe con taglio dopo
  punteggiatura e mai dopo articoli/preposizioni.
- **v2.8** — editor di revisione: diff in giallo nelle letture alternative;
  "unisci duplicati" al salvataggio; `.log` per file con gli step.
- **v2.7** — avanzamento a step con ETA per fase; Sub fix chiarita.
- **v2.6** — terza variante OCR = LiveText (motore indipendente);
  `correzioni.txt`; Test OCR su entrambe le bande.
- **v2.5** — fix ordine parole nelle letture spezzate; larghezze bande
  separate; launcher senza reinstallazione pip.
- **v2.4** — Anteprima intelligente (20 frame col testo); tooltip leggibili.
- **v2.3** — salvataggio SRT accanto all'originale (cartella ricordata).
- **v2.2** — default massima accuratezza + hint completi.
- **v2.1** — report di revisione interattivo. **v2** — multi-variante+voto,
  raffinamento tempi, banda cartelli. **v1** — prima versione Apple Vision.

## Licenza

[MIT](LICENSE) © 2026 Interstellar0verdrive.

Video demo: clip da *Sintel*, open movie della Blender Foundation —
**© copyright Blender Foundation | durian.blender.org** — licenza
[CC-BY 3.0](https://creativecommons.org/licenses/by/3.0/).
