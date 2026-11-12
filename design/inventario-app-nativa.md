# Inventario schermate e stati · SubVision 2.0 (app nativa SwiftUI)

Attività 3.1 del piano (`piano-app-nativa.md`, fase F3). Scritto il 12/11/2026.

Fonti: l'app 1.0.0 (`app.py`, 693 righe; `i18n.py`, 141 chiavi × EN/IT; `OcrParams` in `ocr_core.py` riga 122; il report di revisione, `_QC_TEMPLATE` e `_QC_I18N` dalla riga 925), le decisioni D1–D14 con le risposte della 7.3 (tutte **a**, tranne **D2 = b**: pacchetto locale `macos/Native/SubVisionKit`, e **D10 = b**: tema chiaro e scuro), il protocollo del sidecar (1.4), gli spike S2 (report in WKWebView: funziona, `showSaveFilePicker` non esiste) e S3 (lo stop è immediato: al massimo 153 ms, nessuno stato "sto fermando"). Modello di forma: l'inventario di AnimeUp e la sua app 2.1 (viste e design system in sola lettura: `SidebarView`, `TopBar`, `SettingsView`, `ToolsSetupView`, `Alerts`, `Commands`, `RunViews`, `Components`, `SettingsKit`, `AlertPanel`, `Tokens` con `Color(dark:light:)`).

Legenda: ⧉ c'è già in AnimeUp 2.1 (componente o tavola da adattare: si copia in `SubVisionKit`, citando la provenienza) · ◻︎ da disegnare · ✕ sparisce nella 2.0 · **[D#]** decisione del piano · **[?n]** dubbio n in `note-design.md` · `(E2)` codice della tavola di 3.2 (elenco in fondo).

Differenze da AnimeUp che valgono ovunque: niente calibrazione né "Questo Mac"; niente pagina Start (Elabora è la home, con uno stato vuoto che spiega i tre passi); i parametri sono molti e cambiano spesso (inspector, D5); il risultato di un file è un **trittico SRT + report di revisione + log**, non un video; il lotto vive dentro il sidecar e non sopravvive all'app (D7: niente pausa, niente ripresa, niente file di lavoro da scartare).

Ogni tavola esiste in versione **chiara e scura** (D10). I testi sono in inglese e italiano; qui riporto l'italiano e, dove la parola conta, l'inglese tra parentesi. I testi definitivi arrivano con i cataloghi in 3.3.

---

## 0. Cornice (sempre presente)

- ⧉ Finestra unica con barra laterale a vetro (236 pt, rientro 8), pallini dentro la barra laterale, ingranaggio delle Impostazioni nella prima riga. Finestra minima 720 × 640, come AnimeUp. `(DS4, E1)`
- ⧉ Tre schede nella barra laterale, ognuna col suo sottotitolo di stato e un segno a destra (spinner se lavora, spunta se ha finito e non è la pagina aperta) `(DS4)`:

  | Scheda | Simbolo (proposta) | Sottotitolo, per stato |
  |---|---|---|
  | **Elabora** (Process) ⌘1 | `captions.bubble` | nessun video: "Nessun video" · pronti: "3 video" · lotto: "3 video · 1 in corso" (3 videos · 1 processing) · finito: "3 video · 3 fatti", "3 video · 1 fallito", "3 video · 1 fermato" (il caso peggiore vince: fallito > fermato > senza sottotitoli) |
  | **Anteprima** (Preview) ⌘2 | `viewfinder` | senza video: "Nessun video" · pronta: nome del video scelto · ricerca: "Ricerca · zona 12 di 20" · fatta: "20 fotogrammi · 14 con testo" · durante il lotto: "Sola lettura" |
  | **Sub fix** ⌘3 | `text.badge.checkmark` | nessun file: "Nessun SRT" · scelto: nome del `.srt` · fatto: "Creato · 118 righe" · errore: "Nessun segmento valido" |

- ⧉ Slot della scheda attività in fondo alla barra laterale (`ActivityCard`), una sola alla volta, in quest'ordine `(DS4)`:
  1. **Lotto in corso**: "Elabora · File 2 di 3 · nome.mkv", seconda riga "Fine verso le 14:20" (solo quando c'è una stima, cioè dal secondo file o dopo la prima tappa), barra con la frazione del lotto, pulsante **Ferma tutto**. Clic sulla scheda: va in Elabora. Niente Pausa (D7).
  2. **Aggiornamento disponibile** (gialla, `UpdateCard`): "È disponibile SubVision v2.0.1", "Novità" e **Scarica…** (apre la release su GitHub).
  3. Nessuna scheda per la ricerca dei fotogrammi dell'Anteprima (dura 15–40 s, basta lo spinner sulla scheda) né per la preparazione del riconoscimento (dopo lo spike S5 si fa solo nella finestra strumenti, **[?24]** chiuso).
- ⧉ Piè della barra laterale: "SubVision 2.0.0" (fumetto: "Motore v2.0.0 · Python 3.13.12"), freccia **Controlla aggiornamenti** (spinner mentre chiede), link **GitHub** a destra. `(DS4)`
- ◻︎ Tra le schede e lo slot attività non c'è altro (niente "Questo Mac"). **[?17]**
- ⧉ **Finestra stretta** (N1 di AnimeUp): sotto 1240 pt, o con la barra laterale nascosta da Vista, al suo posto una barra in alto di 52 pt: pallini a sinistra, le tre pagine come controllo a segmenti al centro (spinner sulla pagina che lavora, capsula col numero dei video su Elabora), a destra il pulsante dell'inspector (solo su Elabora e Anteprima) e l'ingranaggio. Vista › Mostra barra laterale è disabilitato sotto la soglia. Velo sfumato sotto la barra quando la pagina scorre. `(N1)`
- ◻︎ **Inspector in finestra stretta**: sopra i 1000 pt di finestra sta accanto alla pagina; sotto, si apre sovrapposto da destra con ombra e si chiude con Esc, con un clic fuori o di nuovo con ⌥⌘I. **[?2]** `(N2)`
- ⧉ **Stato del motore** al posto della pagina (`EngineStatusView`): "Avvio del motore…" con spinner; "Il motore non è partito" (nota rossa con l'errore, **Riprova**, **Mostra il log**); "Il motore si è fermato più volte di fila" (solo **Mostra il log**). `(T5)`
- ✕ Titolo con emoji "🎬 SubVision — Hardsub → SRT (Apple Vision)": il nome sta nel titolo della finestra e in Informazioni su SubVision.
- ✕ Selettore della lingua in cima alla barra laterale (va in Impostazioni › Generali, segue il sistema).
- ✕ Piè di pagina Streamlit con versione e "⭐ GitHub" (va nel piè della barra laterale), avviso di aggiornamento azzurro (va nella scheda gialla e in Impostazioni › Aggiornamenti).

## 1. Primo avvio · finestra degli strumenti (T)

Finestra a sé, larga 600 pt, prima della finestra principale (come la T1 di AnimeUp). Si chiude da sola e diventa la finestra principale quando tutte e quattro le righe sono pronte. **[D11, D12]**

- ⧉ Intestazione: icona dell'app 64 pt, "Benvenuto in SubVision", "Prima del primo video, SubVision ha bisogno dei suoi strumenti: circa 108 MB, scaricati una volta, ognuno verificato col suo checksum pubblicato."
- ⧉ Riga di stato sopra l'elenco: "Scarico 2 di 3 · 30 di 57 MB · manca circa un minuto"; durante la quarta riga: "Preparo il riconoscimento · circa 30 secondi, una volta per ogni versione di macOS".
- ◻︎ Quattro righe (icona di stato, nome e versione, a cosa serve, barra a byte quando c'è, MB a destra):

  | # | Riga | A cosa serve | MB | Avanzamento |
  |---|---|---|---|---|
  | 1 | **uv + Python 3.13** | motore e riconoscimento (uv, Python, pacchetti) | 51 | spinner fino a `hello` (nessuna barra: uv non dà i byte) |
  | 2 | **FFmpeg 9.0.2** | legge i fotogrammi | 28 | barra a byte da `tools.progress` |
  | 3 | **FFprobe 9.0.2** | durata e framerate | 28 | barra a byte |
  | 4 | **Preparazione del riconoscimento** | Vision compila i suoi modelli per il Neural Engine (una volta per utente e per versione di macOS) | — | barra a tempo stimato (30 s) o indeterminata, poi la durata vera da `warmup.done` |

- ◻︎ Stati di ogni riga: **in attesa** (cerchio vuoto, testo secondario) · **in corso** (spinner, fondo tenue d'accento, testo pieno) · **pronto** (spunta verde) · **errore** (croce rossa, fondo rosso tenue, chip "fermato").
- ⧉ Stati della finestra:
  - **in corso** `(T1)`: in basso "Gli strumenti restano dentro SubVision; sul Mac non si installa altro." e **Esci**;
  - **preparazione del riconoscimento** `(T2)`: righe 1–3 pronte, riga 4 in corso;
  - **errore** `(T3)`: nota rossa sopra l'elenco: "Lo scaricamento si è fermato. La connessione è caduta mentre si scaricava FFmpeg. Ciò che è già fatto resta: Riprova riparte da lì."; variante checksum: "FFmpeg è arrivato danneggiato, quindi è stato messo da parte."; variante riga 4: "Il riconoscimento di testo non è partito. Il log dice perché." (è il caso "Vision mancante" al primo avvio). Pulsanti: link rosso **Mostra il log**, **Esci**, **Riprova** (primario);
  - **ritorno con uno strumento solo** `(T4)`: se all'avvio manca ffmpeg o ffprobe scaricato (cancellato a mano, checksum non valido), la finestra torna con la sola riga mancante; uv e Python non si mostrano se sono già a posto.
  - **ritorno dopo un aggiornamento di macOS** `(T4)`: la cache dei modelli di Vision è legata alla build di macOS (spike S5), quindi torna la sola riga 4, "una volta per ogni versione di macOS, circa 30 secondi"; mai per un cambio di lingua OCR. Se si chiude durante la preparazione, nessun avviso: la riga dice "Se chiudi ora, la preparazione ripartirà al prossimo avvio" e la volta dopo si rifà.
- ✕ "Svuota /tmp", `run.command`, `requirements.txt`, virtualenv nel progetto: il lanciatore del motore se ne occupa da solo.

## 2. Elabora (E) · la home

Pagina con intestazione ("Elabora", sotto "Estrae i sottotitoli impressi nei video e scrive un SRT, un report di revisione e un log accanto a ogni video."), elenco dei video, barra in basso fissa, inspector a destra apribile (⌥⌘I, pulsante `sidebar.right` nell'intestazione). **[D5]**

### 2.1 Stati della pagina

- ◻︎ **E0 · vuota.** Tre passi numerati (`NumberedSteps` di AnimeUp) e un'area di trascinamento `(E0)`:
  1. **Aggiungi i video** — "Trascina qui video o cartelle, oppure Apri video… (⌘O). Le sottocartelle sono incluse." Formati: .mkv .mp4 .mov .avi .m4v .webm.
  2. **Controlla bande e parametri** — "In Anteprima trascini le bande sul fotogramma finché i sottotitoli ci cadono dentro; l'inspector (⌥⌘I) tiene gli altri parametri."
  3. **Avvia** — "Per ogni video: l'SRT, il report di revisione e il log accanto al file. I predefiniti puntano alla massima accuratezza: un episodio di 24 minuti richiede circa 1,5–2 ore."
- ◻︎ **E1 · con video, pronto** `(E1)`. Una riga per video:
  - bordo sinistro di stato (grigio "pronto"), nome del file (al massimo due righe), cartella in piccolo e in mono;
  - colonne numeriche in mono, allineate a destra: durata (`1:23:45`), fps (`23,976`), risoluzione (`1920×1080`), da `videos.probe`;
  - chip neutro "SRT già presente" (fumetto: "Il nuovo SRT prende data e ora nel nome: nome_20261112_221400.srt") quando accanto al video c'è già `nome.srt`;
  - menu contestuale: **Mostra nel Finder**, **Apri in Anteprima**, **Togli dall'elenco** (⌫, anche su più righe, annullabile con ⌘Z);
  - tutti i video dell'elenco entrano nel lotto: niente caselle (oggi una casella per video, tutte spuntate);
  - in fondo all'elenco, "Trascina qui altri video o cartelle".
- ◻︎ **E1 · casi della riga pronta**:
  - **file illeggibile** (errore di `videos.probe`): bordo rosso, "Non si legge: nessuna traccia video" (o il motivo), riga attenuata, esclusa dal lotto; si toglie con ⌫;
  - **elementi saltati** al trascinamento (non video, estensione sconosciuta): nota gialla sopra l'elenco "2 elementi saltati: non sono video" con l'elenco nel fumetto, chiudibile;
  - **video già nell'elenco**: avviso blu (O8).
- ◻︎ **Barra in basso** (fissa, vetro) `(E1–E3)`:
  - pronto: a sinistra "3 video · 2 h 14 min in tutto" e la nota "SRT, report e log accanto a ogni video. Se l'SRT c'è già, il nuovo prende data e ora nel nome."; a destra **Avvia** (primario, ⌘↩); con 0 video pronti Avvia è disabilitato;
  - in corso: "File 2 di 3 · fine verso le 14:20" e **Ferma tutto** (secondario rosso);
  - finito: "3 fatti · 1 senza sottotitoli" e **Togli i finiti**; Avvia torna attivo se ci sono righe pronte **[?9]**;
  - spazio stretto sul disco interno (sotto una soglia **[?16]**): nota gialla "Restano 6 GB sul disco interno: un episodio a 12 fps usa fino a ~3 GB di fotogrammi temporanei".
- ◻︎ **E2 · in corso** `(E2)`. La riga del file in corso si apre e mostra le tappe, una barra per tappa, in gruppi per banda:
  - **Dialoghi**: Estrazione · Raggruppamento · OCR ×3 · Raffinamento; **Cartelli** (se la banda è attiva): le stesse quattro. "×3" diventa "×1" senza lettura multipla; Raffinamento sparisce se è spento **[?18]**;
  - tappa in attesa: "in attesa · stima ~12 min (dal file precedente)"; tappa in corso: barra d'accento, "1.840 / 17.000 fotogrammi · trascorso 4:12 · ETA 31:40 · 7,3 fps" (unità: fotogrammi, o righe per il raffinamento; velocità in fps o righe/s); tappa finita: spunta verde, "17.000 fotogrammi in 38:12 · media 7,4 fps";
  - in testa alla riga: "File 2 di 3", nome, "trascorso 41:20", pulsante **Ferma** (questo file);
  - righe dopo: "in attesa", con la stima del file intero quando c'è;
  - l'inspector resta visibile ma bloccato (§3);
  - si possono ancora trascinare video: entrano come righe pronte per il lotto dopo **[?10]**; le righe in corso o in attesa non si possono togliere (⌫ disabilitato su di loro).
- ◻︎ **E3 · finita, con esiti** `(E3)`. Ogni riga dice cosa è venuto fuori:

  | Esito | Bordo e icona | Testo | Azioni |
  |---|---|---|---|
  | **fatto** | verde, spunta | "118 righe · 7 scartate (nel report) · 52 confini raffinati · 1 h 32 min"; se l'SRT c'era già: "nuovo nome con data e ora" | **Apri report** (⌘R) · menu ⋯: Mostra nel Finder (seleziona SRT, report e log), Apri l'SRT, Apri il log (Console) |
  | **fatto, senza sottotitoli** | giallo | "Nessun sottotitolo trovato. Controlla le bande in Anteprima e la lingua OCR." | Apri report (se generato) · Apri il log · Apri in Anteprima |
  | **fallito** | rosso, croce | "Fallito durante OCR · dialoghi: <errore>" | Apri il log · **Elabora di nuovo** |
  | **fermato** | grigio | "Fermato durante Estrazione · cartelli. Nessun SRT a metà." | **Elabora di nuovo** |
  | **non partito** (dopo Ferma tutto) | grigio, nessuna icona | torna "pronto" | — |

  Riga finita aperta (clic sulla freccia): tempi per tappa ("Estrazione 2:10 · Raggruppamento 0:12 · OCR 1:20:03 · Raffinamento 8:40"), i tre file del trittico con nome e cartella, il risultato del log (righe, scartate, confini raffinati, tempo).
- ◻︎ **E4 · file fallito** `(E4)`: la riga aperta con la tappa che si è fermata in rosso ("OCR · dialoghi — interrotta"), le tappe dopo in grigio, il messaggio d'errore in mono, **Apri il log**, **Elabora di nuovo**. Disco pieno e ffmpeg sparito a metà finiscono qui come errori del file.
- ◻︎ **E5 · file fermato e lotto fermato** `(E5)`: dopo **Ferma** il file diventa "fermato" e il lotto passa al successivo; dopo **Ferma tutto** il file in corso è "fermato" e quelli dopo tornano "pronto". Nessuno stato intermedio "sto fermando" (S3: lo stop arriva in meno di 0,2 s).
- ◻︎ **E6 · foglio di fine lotto** `(E6)` (come il riepilogo della coda di AnimeUp):
  - titolo per caso: "3 SRT pronti" · "2 SRT pronti · 1 senza sottotitoli" · "1 SRT pronto · 1 fallito" · "Lotto fermato · 1 SRT pronto";
  - una riga per file con esito e **Apri report**; in basso **Mostra nel Finder** (seleziona gli SRT creati) e **OK** (primario);
  - si apre alla fine del lotto se la finestra è aperta; altrimenti alla riapertura della finestra; se l'app viene chiusa prima di vederlo, al prossimo avvio (regola di AnimeUp).
- ◻︎ **E7 · banner e note in pagina** `(E7)`:
  - **Vision mancante** (`hello.vision` falso): banner rosso in cima "Il riconoscimento di testo di macOS non risponde. SubVision usa Vision: il motore non riesce a caricarlo." con **Riprova** e **Mostra il log**; Avvia disabilitato (sostituisce `vision_missing` e `vision_unavailable`);
  - **lingua OCR non disponibile su questo Mac**: nota gialla in cima all'inspector (§3) e avviso O7 se si preme Avvia.

### 2.2 Notifiche e Dock **[D7 di AnimeUp, D8]**

- ◻︎ Notifiche di macOS `(O10)`: file fatto ("nome.mkv · 118 righe, report pronto"), file senza sottotitoli, file fallito, lotto finito ("Lotto finito · 3 SRT pronti, 1 con avvisi"). Clic: apre la finestra su Elabora col foglio E6. Una notifica per file solo nei lotti di più file **[?23]**.
- ⧉ Icona del Dock con la barra della frazione del lotto mentre lavora (`DockProgress`, colori dei token). Menu del Dock: "File 2 di 3 · nome", **Ferma tutto**, "Mostra SubVision".
- ✕ Toast "Batch completato ✅", elenco di messaggi verdi/gialli/rossi sopra il pulsante, **Reset messaggi**: gli esiti stanno nelle righe e nel foglio.

## 3. Inspector dei parametri (I) **[D5, D13]**

Pannello a destra di Elabora e di Anteprima **[?1]**, largo 300 pt, aperto e chiuso con ⌥⌘I (Vista › Mostra/Nascondi inspector) o col pulsante nell'intestazione della pagina. Stato aperto/chiuso e gruppi aperti/chiusi persistiti. Valori in `UserDefaults`, persistiti tra gli avvii (oggi si perdevano a ogni ricarica).

- ◻︎ Intestazione: "Parametri" (Parameters), sotto "Predefiniti = massima accuratezza (un episodio di 24 min ≈ 1,5–2 h)". Nessun profilo "Veloce" nella 2.0 **[?13]**.
- ◻︎ Cinque gruppi chiudibili, ognuno con **Predefinito** (pulsante piccolo a destra del titolo, attivo solo se il gruppo ha valori diversi dai predefiniti). Ogni voce: etichetta, valore in mono, fumetto (?) con la spiegazione di oggi riscritta più corta e il predefinito; un puntino d'accento accanto ai valori cambiati **[?14]**. In fondo: menu ⋯ con **Ripristina tutti i predefiniti**.
- ◻︎ Tabella delle voci (i 20 parametri della barra laterale di oggi; il ventunesimo controllo, la lingua dell'interfaccia, va in Impostazioni):

  | Gruppo | Voce (IT / EN, proposta) | Controllo | Predefinito | Intervallo · passo | `OcrParams` | Oggi |
  |---|---|---|---|---|---|---|
  | **OCR** | Lingua dei sottotitoli / Subtitle language | menu con le 33 lingue del livello "accurate" di Vision su questo Mac (`hello.languages`, spike S5), nomi nella lingua dell'app, codice BCP-47 in grigio **[?19]** | Italiano (`it-IT`) | lingue del Mac | `lang_hint` | campo di testo libero "Lingua (hint)" |
  | | Fotogrammi al secondo / Frames per second | `SnapSlider` a 5 tacche | 12 | 4 · 6 · 8 · 10 · 12 | `fps` | `select_slider` |
  | | Lettura multipla con voto / Multiple readings with voting | interruttore | acceso | — | `multi_variant` | casella |
  | | Raffina i tempi al fotogramma nativo / Refine timing to native frames | interruttore | acceso | — | `refine_timing` | casella |
  | | Confidenza minima / Minimum confidence | cursore + valore | 0,30 | 0,00–1,00 · 0,05 | `min_confidence` | `slider` |
  | **Banda dialoghi** | Altezza dal basso / Height from the bottom | cursore + campo, legato alle maniglie dell'Anteprima | 28 % | 5–80 · 1 | `bottom_keep_pct` | `slider` |
  | | Larghezza al centro / Centre width | cursore + campo, idem | 96 % | 50–100 · 1 | `keep_w_pct` | `slider` |
  | **Banda cartelli** | Leggi anche i cartelli in alto ({\an8}) / Read signs at the top too | interruttore nel titolo del gruppo | acceso | — | `top_band` | casella |
  | | Altezza dall'alto / Height from the top | cursore + campo; disabilitato se la banda è spenta | 22 % | 5–50 · 1 | `top_keep_pct` | `slider` |
  | | Larghezza al centro / Centre width | cursore + campo; idem | 100 % | 50–100 · 1 | `top_keep_w_pct` | `slider` |
  | **Segmenti** | Durata minima di una riga / Shortest line | campo numerico + stepper, "s" | 0,20 s | 0,05–2,00 · 0,05 | `min_duration` | `number_input` |
  | | Unisci righe simili entro / Merge similar lines within | campo + stepper, "s" | 0,6 s | 0,0–2,0 · 0,1 | `merge_gap` | `number_input` |
  | | A capo oltre / Wrap lines at | campo + stepper, "caratteri" | 42 | 28–64 · 2 | `wrap_width` | `number_input` |
  | **Avanzate** | Report di revisione / Review report | interruttore | acceso | — | `qc_report` | casella |
  | | Segnala buchi senza sottotitoli oltre / Flag gaps longer than | campo + stepper, "s"; disabilitato senza report | 6 s | 2–30 · 1 | `qc_gap_warn` | `number_input` |
  | | Salta fotogrammi quasi uguali / Skip near-identical frames | `SnapSlider` 0–4 (0 = "nessuno") | 0 | 0–4 · 1 | `skip_hamming` | `slider` "Skip Hamming" |
  | | Letture OCR in parallelo / Parallel OCR reads | stepper | 4 | 1–8 · 1 | `workers` | `slider` |
  | | Usa ignore.txt / Use ignore.txt | interruttore + "12 frasi" (da `lists.status`) | acceso | — | `ignore_lines` | casella |
  | | Usa correzioni.txt / Use correzioni.txt | interruttore + "4 correzioni" | acceso | — | `corrections` | casella |

- ✕ "Svuota /tmp a fine processo": sparisce, il motore pulisce sempre (anche su stop e all'avvio, gli orfani `voc26_*`). **[?21]**
- Restano non esposti, come oggi: `recognition_level` ("accurate"), `qc_conf_warn` (0,80), `qc_agree_warn` (0,70).
- ◻︎ Stati dell'inspector:
  - **chiuso** (si vede in E1–E5) e **aperto con i gruppi aperti** `(I1)`;
  - **gruppi chiusi, valori cambiati, Predefinito attivo, menu della lingua aperto** `(I2)`;
  - **bloccato durante il lotto** `(I3)`: nota blu in cima "Bloccati durante il lotto: il lotto usa i valori con cui è partito." e controlli disabilitati;
  - **lingua non disponibile** `(I3)`: nota gialla in cima "Italiano non è tra le lingue di Vision su questo Mac. Scegline un'altra." (la lingua salvata non è in `hello.languages`, per esempio dopo un aggiornamento di macOS);
  - **elenco mancante** `(I3)`: accanto a "Usa ignore.txt" in giallo "file mancante" con link **Impostazioni…** (oggi: "ignore.txt non trovato: uso solo i filtri interni.").

## 4. Anteprima (A) **[D6]**

Pagina a sé. Usa i video dell'elenco di Elabora. Le bande si trascinano sul fotogramma; i valori sono gli stessi dell'inspector (anch'esso apribile qui) e cambiano in entrambi i posti. I parametri restano globali per il lotto.

- ◻︎ **A0 · vuota** `(A0)`: nessun video in Elabora. Spiegazione in tre righe (trova i fotogrammi col testo, regola le bande, prova l'OCR) e area di trascinamento: i video aggiunti da qui entrano nell'elenco di Elabora e l'Anteprima resta aperta.
- ◻︎ **A1 · pronta** `(A1)`: in alto menu **Video** (i video dell'elenco, il primo scelto) e **Trova 20 fotogrammi** (primario), fumetto: "Divide il video in 20 zone e in ognuna cerca un fotogramma con testo nella banda dialoghi (fino a 3 tentativi per zona). Se una zona non ha testo, mostra comunque un fotogramma. Richiede 15–40 s." Sotto, il riquadro del fotogramma vuoto con un segnaposto.
- ◻︎ **A2 · ricerca in corso** `(A2)`: barra "Zona 12 di 20 · 9 con testo" (da `preview.progress`), **Ferma** (`preview.stop`); il menu Video è disabilitato.
- ◻︎ **A3 · fotogramma con bande e maniglie** `(A3)`:
  - fotogramma intero (dal motore, `preview.done`), adattato alla pagina;
  - **banda dialoghi** (verde, come oggi **[?4]**) ancorata al bordo basso e centrata: maniglia sul bordo superiore per l'altezza, maniglie sui bordi laterali per la larghezza, simmetriche;
  - **banda cartelli** (blu) ancorata al bordo alto, solo se attiva: maniglia sul bordo inferiore e sui lati;
  - limiti: dialoghi altezza 5–80 %, larghezza 50–100 %; cartelli altezza 5–50 %, larghezza 50–100 %; valori arrotondati al punto percentuale; durante il trascinamento un'etichetta "Altezza 28 % · Larghezza 96 %" accanto alla maniglia; il cursore del mouse cambia (ridimensiona su/giù, sinistra/destra);
  - navigazione: frecce ◀ ▶ ai lati e tasti ← →, "Fotogramma 4 di 20 · 00:12:34", badge: "Testo nei dialoghi" (verde), "Testo in alto · cartello" (blu), "Nessun testo" (grigio);
  - striscia di 20 miniature sotto il fotogramma con un puntino per quelle con testo; riepilogo "20 fotogrammi · 14 con testo, 6 senza (zone mute del video)";
  - **Prova OCR su questo fotogramma** (⌘T).
  - I fotogrammi trovati restano per video finché l'app è aperta: cambiando video e tornando non si cercano di nuovo.
- ◻︎ **A4 · prova OCR con i due pannelli** `(A4)` (da `preview.test`, pochi secondi, spinner "Leggo…" nel pannello):
  - due pannelli affiancati (uno sopra l'altro se la pagina è stretta): **Banda dialoghi** e **Banda cartelli ({\an8})**, il secondo solo con la banda attiva;
  - in ciascuno: "OCR con voto · 120 ms · 3 varianti"; il testo votato in un riquadro (o "‹vuoto›"); "Confidenza 92 % · accordo 100 %"; le alternative come chip; **Testo finale** (dopo pulizia, filtri, correzioni e a capo, con `{\an8}` davanti per i cartelli), sola lettura e copiabile, col fumetto "È ciò che finirebbe nell'SRT.";
  - se cambiano le bande o un parametro dopo la prova: nota piccola gialla "I parametri sono cambiati: prova di nuovo".
- ◻︎ **A5 · nessun testo** `(A5)`:
  - nessuna zona con testo: nota gialla "In nessuna delle 20 zone c'è testo nella banda dialoghi. Allarga la banda o controlla la lingua OCR."; i fotogrammi si vedono comunque;
  - una banda senza testo nella prova: "Nessun testo in questa banda." nel pannello;
  - durata non valida: nota rossa "Non riesco a leggere la durata di questo video."; fotogramma non disponibile: "Anteprima non disponibile." al posto dell'immagine.
- ◻︎ **A6 · durante il lotto** `(A6)`: nota blu "Durante il lotto l'Anteprima è in sola lettura: le bande sono quelle con cui è partito." I fotogrammi già trovati si sfogliano; ricerca, prova OCR e maniglie disabilitate. **[?11]**

## 5. Sub fix (F)

Corregge un `.srt` esistente senza rifare l'OCR. Uscita `<nome>-fixed-<data>.srt` accanto al sorgente.

- ◻︎ **F0 · vuota** `(F0)`: area di trascinamento "Trascina qui un file .srt, oppure Apri SRT… (⇧⌘O)" e a cosa serve: "Gli SRT fatti da Elabora sono già puliti. Sub fix serve per quelli che vengono da fuori (vecchi SRT, file scaricati o modificati a mano) o per applicare le nuove regole di correzioni.txt a puntate già elaborate: in pochi secondi, senza rielaborare il video."
- ◻︎ **F1 · pronto** `(F1)`:
  - scheda del file: nome, cartella, "642 righe · 23:40", **Cambia…**;
  - quattro opzioni (persistite): **Unisci righe duplicate o simili** (acceso); **Togli le righe senza sottotitoli** (acceso; "frasi tipo 'Non ci sono sottotitoli…' e quelle di ignore.txt"); **Togli i flash troppo brevi** (acceso); **Durata minima** 0,2 s, 0,1–2,0 passo 0,1, disabilitato se i flash restano;
  - nota "Usa anche i parametri di Elabora: unione entro 0,6 s, a capo a 42, Italiano, ignore.txt e correzioni.txt se attivi." con link **Mostra i parametri** (apre Elabora con l'inspector) **[?1]**;
  - **Esegui Sub fix** (primario, ⌘↩).
- ◻︎ **F2 · fatto** `(F2)`: nota verde "Creato: nome-fixed-20261112_221400.srt (618 righe)" con **Mostra nel Finder** e **Apri**. Durante l'esecuzione (meno di un secondo) solo uno spinner nel pulsante.
- ◻︎ **F3 · errore** `(F3)`: nota rossa "Nessun segmento valido dopo la pulizia." (errore `no_valid_segments`); "Non riesco a leggere questo SRT: <motivo>."; file trascinato che non è `.srt`: nota gialla "Sub fix accetta solo file .srt".
- Durante il lotto Sub fix resta usabile (`srt.fix` è breve e non usa Vision). **[?11]**
- ✕ Scelta "Da ./videos" / "Carica file", tendina degli `.srt` di `./videos`, caricamento in `tmp/`: si trascina o si apre il file dov'è.

## 6. Finestra del report di revisione (R) **[D8]**

- ◻︎ **R1 · report aperto** `(R1)`: finestra a sé (una per report; Finestra › elenco), titolo "nome.revisione.html", contenuto in WKWebView (`loadFileURL`), il report di oggi con la sua barra (contatore, "unisci duplicati", Ripristina tutto, **Salva SRT revisionato**). Barra della finestra: **Apri nel browser** e **Mostra nel Finder**. Si apre da **Apri report** sulla riga, da ⌘R con la riga selezionata, dal foglio E6, e da File › Apri un report… (⌥⌘O, anche per i report fatti dalla 1.x). Caricamento: spinner al centro (300–400 ms).
- ◻︎ **R2 · SRT revisionato salvato** `(R2)`: il pulsante del report passa dal ponte e scrive `<nome>-revisionato-<data>.srt` accanto all'originale, senza pannello; in basso nella finestra un avviso nativo "SRT revisionato salvato · nome-revisionato-20261112-2214.srt" con **Mostra nel Finder**, che sparisce da solo dopo qualche secondo **[?22]**. Lo stato dell'editor si salva da solo in `<nome>.revisione.json` (nessuna interfaccia: il report dice già "salvato ✓").
- ◻︎ **R3 · errori** `(R3)`: report spostato o cancellato: nota rossa al posto della pagina "Il report non c'è più: nome.revisione.html." con **Chiudi**; salvataggio impossibile accanto all'originale (cartella non scrivibile, disco staccato): avviso rosso "Non riesco a salvare l'SRT revisionato accanto all'originale." con **Scegli dove salvarlo…** (pannello Salva) e **Annulla**.
- Il file HTML resta sul disco e si apre in un browser come oggi.
- Il report ha oggi solo il tema scuro e un suggerimento scritto per Chrome e Safari; nell'app va adattato **[?5]**. La sua lingua è quella dell'app al momento del lotto **[?7]**.

## 7. Impostazioni (finestra ⌘,) (ST) **[D5, D10, D11]**

`SettingsKit` di AnimeUp: finestra di 640 pt, schede con simbolo, gruppi, una riga per voce con descrizione e "Predefinito: …" sotto.

- ◻︎ **ST1 · Generali** `(ST1)`:
  - **Lingua**: English / Italiano (capsule); "Parte nella lingua di macOS; in inglese se non è una di queste. Vale anche per i report di revisione nuovi."
  - **Aspetto**: Sistema / Chiaro / Scuro; "Sistema segue l'aspetto di macOS."; Predefinito: Sistema. Cambia al volo finestra, fogli, avvisi e finestre dei report.
  - gruppo **Durante l'elaborazione**: **Notifiche di macOS** ("File finito, lotto finito, problemi."; Predefinito: acceso), **Avanzamento sull'icona del Dock** (Predefinito: acceso).
- ◻︎ **ST2 · Strumenti** `(ST2)`:
  - **FFmpeg e FFprobe**: menu "Quelli scaricati (9.0.2, verificati)" / "Uno mio…"; Predefinito: quelli scaricati. Con "Uno mio…": campo del percorso + **Scegli…** (accetta l'eseguibile `ffmpeg` o la sua cartella; ffprobe deve stare accanto **[?20]**), riga di stato "ffmpeg 7.1 · ffprobe 7.1 · /opt/homebrew/bin" oppure in giallo "ffprobe non è nella stessa cartella" / in rosso "Non parte: <errore>".
  - **Versione**: "ffmpeg 9.0.2 · ffprobe 9.0.2 · verificati col checksum"; **Scarica di nuovo** (scarica e verifica di nuovo, con avanzamento nella riga).
  - righe informative: **Motore** "SubVision 2.0.0 · Python 3.13.12"; **Riconoscimento** "Vision · 30 lingue · LiveText disponibile" (da `hello`).
- ◻︎ **ST3 · Elenchi** `(ST3)`:
  - **Frasi da ignorare · ignore.txt**: "12 frasi · una per riga, # per i commenti"; **Modifica…** (apre il file nell'editor di testo di sistema), **Importa…** (pannello Apri, poi avviso O8 "Sostituisci / Aggiungi in fondo / Annulla"), **Mostra nel Finder**;
  - **Correzioni automatiche · correzioni.txt**: "4 correzioni · formato `sbagliato => giusto`"; stessi pulsanti;
  - nota: "Valgono per i lotti nuovi e per Sub fix; ogni lotto può spegnerle nell'inspector (Avanzate)."; i conteggi si aggiornano quando la finestra torna in primo piano (`lists.status`).
  - I file vivono nella cartella di stato (`~/Library/Application Support/SubVision`), copiati dai predefiniti al primo avvio.
- ◻︎ **ST4 · Aggiornamenti** `(ST4)`: **Controlla da solo** ("A ogni avvio, al massimo una volta al giorno, in sottofondo."; Predefinito: acceso); riquadro di stato "SubVision v2.0.0 è aggiornato" / "È disponibile SubVision v2.0.1" (giallo) / "GitHub non ha risposto", "Ultimo controllo oggi alle 22:14", **Controlla ora** (spinner); link **Note di rilascio** e **SubVision su GitHub**.
- ◻︎ **ST5 · bloccate durante il lotto** `(ST5)`: Strumenti ed Elenchi mostrano la nota gialla "Bloccate mentre un lotto è in corso. Il lotto usa gli strumenti e gli elenchi con cui è partito." e sono disabilitate; Generali e Aggiornamenti restano libere **[?12]**.

## 8. Avvisi (O)

`AUAlert` di AnimeUp: icona 40 pt, titolo, testo, pulsanti a destra; rosso per ciò che ferma o perde lavoro, giallo per ciò che chiede attenzione, blu per le informazioni. Icone riusate dove esistono (`stopFile`, `stopAll`, `quit`, `windowClose`, `folderEmpty`, `error`, `info`, `update`); nuove da disegnare: `tool-missing`, `vision`, `language`.

| # | Avviso | Tono · icona | Titolo | Testo | Pulsanti (primario per primo) |
|---|---|---|---|---|---|
| O1 | **Ferma questo file** | rosso · stop-file | "Fermare nome.mkv?" | "Non resta un SRT a metà. Il lotto passa al file successivo." | **Ferma** · Continua (Esc) |
| O2 | **Ferma tutto** | rosso · stop-all | "Fermare tutto il lotto?" | "Il file in corso si ferma subito, senza SRT a metà; quelli dopo non partono. Gli SRT già fatti restano." | **Ferma tutto** · Continua |
| O3 | **Esci con lotto in corso** | giallo · quit | "Uscire mentre un lotto è in corso?" | "Uscendo fermi nome.mkv (file 2 di 3) e quelli dopo. Gli SRT già fatti restano." | **Esci e ferma** · Annulla |
| O4 | **Chiudi la finestra con lotto in corso** (solo la prima volta) | blu · window-close | "SubVision continua a lavorare" | "Chiudere la finestra non ferma il lotto: l'avanzamento resta sull'icona del Dock. Esci con ⌘Q per fermare tutto." | **OK** · casella "Non mostrare più" |
| O5a | **ffmpeg mancante** (scaricato, sparito prima di Avvia) | rosso · tool-missing | "FFmpeg non c'è più" | "Serve per leggere i fotogrammi. Scaricalo di nuovo (57 MB con FFprobe) o indica il tuo nelle Impostazioni." | **Scarica di nuovo** · Impostazioni… · Annulla |
| O5b | **ffmpeg mancante** (il mio) | rosso · tool-missing | "Il tuo FFmpeg non risponde" | "/opt/homebrew/bin/ffmpeg non c'è più o non parte." | **Usa quelli scaricati** · Scegli… · Annulla |
| O6 | **Vision mancante** (Avvia o Prova OCR con `hello.vision` falso) | rosso · vision | "Il riconoscimento di testo non risponde" | "SubVision legge i sottotitoli con Vision di macOS, ma il motore non riesce a caricarlo. Il log dice perché." | **Riprova** · Mostra il log |
| O7 | **Lingua non supportata** (errore `bad_params` di `batch.start`) | giallo · language | "Italiano non è tra le lingue di questo Mac" | "Vision qui legge 30 lingue. Con una lingua che non conosce, l'SRT uscirebbe vuoto: scegline una nell'inspector." | **Scegli la lingua** (apre l'inspector sul menu) · Annulla |
| O8a | Cartella senza video | giallo · folder-empty | "Nessun video in «Serie»" | "Ho guardato solo la cartella, non le sottocartelle." | **Cerca nelle sottocartelle** · OK |
| O8b | Video già nell'elenco | blu · info | "Quel video è già nell'elenco" / "Quei 3 video sono già nell'elenco" | "Non è stato aggiunto nulla di nuovo." | **OK** |
| O8c | Importa un elenco | blu · info | "Importare correzioni.txt?" | "Nell'elenco ci sono già 4 correzioni." | **Aggiungi in fondo** · Sostituisci · Annulla |
| O8d | Aggiornamenti (dal menu o dal piè) | blu / giallo / rosso · update | "SubVision v2.0.0 è aggiornato" · "È disponibile SubVision v2.0.1" · "GitHub non ha risposto" | — · "Novità: …" · "Riprova più tardi." | **OK** · **Scarica…** + Più tardi · **OK** |
| — | **Nessun segmento valido** (Sub fix) | nota rossa in pagina, non modale (F3) | "Nessun segmento valido dopo la pulizia." | — | — |
| — | SRT revisionato non salvato (report) | rosso · error | vedi R3 | | **Scegli dove salvarlo…** · Annulla |

Tutti in `(O1)–(O8)`; O8a–O8d in una tavola sola.

## 9. Menu, scorciatoie, Dock (O9, O10)

Ogni pulsante della finestra ha il suo comando nel menu; le voci che non valgono si attenuano, non spariscono (regola di AnimeUp). `(O9)`

- **SubVision**: Informazioni su SubVision (con il link al progetto) · Controlla aggiornamenti… · Impostazioni… ⌘, · servizi, nascondi · **Esci da SubVision** ⌘Q (con lotto in corso → O3).
- **File**: Apri video… ⌘O (file e cartelle, "Includi le sottocartelle" nel pannello, acceso) · Apri SRT… ⇧⌘O (va in Sub fix) · Apri un report… ⌥⌘O · — · **Apri report** ⌘R (riga finita selezionata) · Mostra nel Finder ⇧⌘R · Apri il log del file · — · Togli dall'elenco ⌫ · Chiudi ⌘W.
- **Modifica**: standard (Annulla anche per Togli dall'elenco; Seleziona tutto nell'elenco).
- **Vista**: Elabora ⌘1 · Anteprima ⌘2 · Sub fix ⌘3 · — · Mostra/Nascondi barra laterale ⌃⌘S (disabilitata in finestra stretta) · Mostra/Nascondi inspector ⌥⌘I · — · Schermo intero.
- **Elabora** (menu dell'app): **Avvia** ⌘↩ · **Ferma il file in corso** ⌥⌘. · **Ferma tutto** ⌘. · — · Trova 20 fotogrammi · Prova OCR su questo fotogramma ⌘T · Fotogramma precedente ⌘← · Fotogramma successivo ⌘→ · — · **Esegui Sub fix** ⌘↩ (attiva solo nella pagina Sub fix, quando Avvia non lo è) **[?15]**.
- **Finestra**: standard · SubVision ⌘0 (riapre la finestra principale) · le finestre dei report aperte.
- **Aiuto**: Guida di SubVision (README) · Apri il log in Console ⌥⌘L (log dell'app) · Segnala un problema…
- ⧉ Menu del Dock e notifiche: §2.2. `(O10)`

## 10. Stato salvato e riapertura

- Elenco dei video di Elabora con i loro esiti: resta fra un avvio e l'altro finché non si tolgono le righe; una riga il cui file è sparito dice "File non trovato" in giallo **[?8]**.
- Parametri dell'inspector, gruppi aperti, inspector aperto/chiuso, opzioni di Sub fix, video scelto in Anteprima, dimensione della finestra: in `UserDefaults`.
- Nessun lavoro sopravvive all'app (D7): all'avvio nessuna ripresa, il motore cancella i `voc26_*` orfani.
- Riapertura: sempre su Elabora; il foglio E6 non visto si riapre al primo avvio.
- ✕ `.ui_prefs.json` (lingua e cache degli aggiornamenti): `UserDefaults`.
- ✕ Cartelle `videos/` e `tmp/` nel progetto: i video si aprono dove sono; il lavoro va in `<stato>/tmp`.

---

## 11. Dove finisce ogni voce della UI di oggi

Parte dalla 7.1 del piano e la completa. Destinazioni: **riga** (riga del file in Elabora), **barra** (barra in basso di Elabora), **foglio** (E6), **inspector**, **Impostazioni**, **pagina** (Anteprima o Sub fix), **report** (finestra R), **avviso** (O), **notifica**, **log** (il `.log` del file, scritto dal motore **[?6]**), **sparisce**. "Fumetto" = il (?) della voce nell'inspector o nella pagina, con il testo riscritto in 3.3.

### 11.1 Riepilogo (7.1 del piano, completata)

| Oggi (Streamlit) | Nella 2.0 |
|---|---|
| Selettore lingua UI in barra laterale | Impostazioni › Generali › Lingua (segue il sistema) |
| 21 controlli della barra laterale | 20 nell'inspector (D5), persistiti; la lingua UI in Impostazioni; "Svuota /tmp" sparisce |
| `recognition_level`, `qc_conf_warn`, `qc_agree_warn` (mai esposti) | restano non esposti |
| Elenco `./videos` con caselle | elenco della pagina Elabora (trascinamento, ⌘O con sottocartelle), tutti nel lotto, ⌫ per togliere |
| Avvia / Reset messaggi | Avvia (⌘↩) nella barra in basso · gli esiti stanno nelle righe e nel foglio E6 |
| Righe tappa ⬜ / barra / ✅ / ❌ | riga per file con tappe a barre per banda, ETA, velocità; Ferma per file e Ferma tutto |
| Toast "lotto finito" | notifica + foglio E6 + Dock |
| Log `.log` accanto al video | uguale; "Apri il log" lo apre in Console |
| Anteprima: selectbox, 20 fotogrammi, ◀ ▶, rettangoli PIL | pagina Anteprima, fotogrammi interi dal motore, bande in SwiftUI con maniglie, frecce e miniature |
| Test OCR su fotogramma | "Prova OCR su questo fotogramma" (⌘T), due pannelli |
| Sub fix: radio da ./videos / upload | trascinamento o Apri SRT… (⇧⌘O); uscita accanto al sorgente |
| Piè di pagina versione + GitHub + avviso aggiornamento | piè della barra laterale, scheda gialla, Impostazioni › Aggiornamenti |
| `.ui_prefs.json` | `UserDefaults` |
| `ignore.txt`, `correzioni.txt` nel progetto | cartella di stato, Impostazioni › Elenchi (Modifica…, Importa…) |
| Report `.revisione.html` aperto nel browser | finestra dell'app (D8), "Apri nel browser" resta |
| Errore Vision in cima alla pagina | banner E7, riga 4 della finestra strumenti (T3), avviso O6 |
| Campo libero "Lingua (hint)" | menu delle lingue di Vision (D13), avviso O7 |
| Pagine disabilitate durante il lotto | Anteprima in sola lettura (A6), Sub fix usabile, inspector e Impostazioni (Strumenti, Elenchi) bloccati |

### 11.2 Le 141 chiavi di `i18n.py`

Generale

| Chiave | Oggi | Nella 2.0 |
|---|---|---|
| `app_title` | titolo della pagina con emoji | sparisce; nome nel titolo della finestra e in Informazioni su SubVision |
| `vision_missing` | errore rosso in cima (pip install ocrmac, macOS 10.15+) | banner E7 + T3 (riga 4) + avviso O6, testo nuovo senza pip |
| `ui_lang_label`, `ui_lang_help` | etichetta e aiuto del selettore lingua (nel codice c'è un testo fisso bilingue) | Impostazioni › Generali › Lingua, con descrizione |

Barra laterale · Opzioni OCR

| Chiave | Oggi | Nella 2.0 |
|---|---|---|
| `ocr_options` | titolo della sezione | inspector: titolo "Parametri" e gruppo "OCR" |
| `ocr_caption` | "Default = massima accuratezza…" | sottotitolo dell'inspector; frase sui tempi anche nel passo 3 di E0 |
| `lang_hint_label`, `lang_hint_help` | campo libero + aiuto | inspector › OCR › Lingua dei sottotitoli (menu, D13) + fumetto |
| `fps_label`, `fps_help` | `select_slider` + aiuto | inspector › OCR › Fotogrammi al secondo + fumetto |
| `multi_variant_label`, `multi_variant_help` | casella + aiuto | inspector › OCR › Lettura multipla con voto + fumetto |
| `refine_label`, `refine_help` | casella + aiuto | inspector › OCR › Raffina i tempi + fumetto |
| `min_conf_label`, `min_conf_help` | cursore + aiuto | inspector › OCR › Confidenza minima + fumetto |

Barra laterale · Banda dialoghi

| Chiave | Oggi | Nella 2.0 |
|---|---|---|
| `band_bottom_header` | titolo della sezione | inspector: titolo del gruppo "Banda dialoghi"; anche titolo del pannello A4 |
| `bottom_pct_label`, `bottom_pct_help` | cursore + aiuto ("riquadro VERDE") | inspector › Altezza dal basso + fumetto (senza il colore); maniglia superiore della banda in A3 |
| `width_pct_label`, `width_pct_help` | cursore + aiuto | inspector › Larghezza al centro + fumetto; maniglie laterali in A3 |

Barra laterale · Banda cartelli

| Chiave | Oggi | Nella 2.0 |
|---|---|---|
| `band_top_header` | titolo della sezione | inspector: titolo del gruppo "Banda cartelli" |
| `top_band_label`, `top_band_help` | casella + aiuto | interruttore nel titolo del gruppo + fumetto |
| `top_pct_label`, `top_pct_help` | cursore + aiuto ("riquadro AZZURRO") | inspector › Altezza dall'alto + fumetto; maniglia inferiore della banda cartelli in A3 |
| `top_w_pct_label`, `top_w_pct_help` | cursore + aiuto | inspector › Larghezza al centro (cartelli) + fumetto; maniglie laterali in A3 |

Barra laterale · Segmenti

| Chiave | Oggi | Nella 2.0 |
|---|---|---|
| `segments_header` | titolo della sezione | inspector: gruppo "Segmenti" |
| `min_dur_label`, `min_dur_help` | campo + aiuto | inspector › Durata minima di una riga + fumetto |
| `merge_gap_label`, `merge_gap_help` | campo + aiuto | inspector › Unisci righe simili entro + fumetto; citato nella nota di Sub fix (F1) |
| `wrap_label`, `wrap_help` | campo + aiuto | inspector › A capo oltre + fumetto; citato nella nota di Sub fix |

Barra laterale · Avanzate

| Chiave | Oggi | Nella 2.0 |
|---|---|---|
| `advanced` | espansore "Avanzate" | inspector: gruppo "Avanzate" (chiuso di predefinito) |
| `qc_report_label`, `qc_report_help` | casella + aiuto | inspector › Report di revisione + fumetto |
| `qc_gap_label`, `qc_gap_help` | campo + aiuto | inspector › Segnala buchi oltre + fumetto |
| `skip_ham_label`, `skip_ham_help` | cursore "Skip Hamming" + aiuto | inspector › Salta fotogrammi quasi uguali + fumetto |
| `workers_label`, `workers_help` | cursore + aiuto | inspector › Letture OCR in parallelo + fumetto |
| `use_ignore_label`, `use_ignore_help` | casella + aiuto | inspector › Usa ignore.txt (con il conteggio) + fumetto; descrizione in Impostazioni › Elenchi |
| `use_corrections_label`, `use_corrections_help` | casella + aiuto | inspector › Usa correzioni.txt (con il conteggio) + fumetto; descrizione in Impostazioni › Elenchi |
| `clean_tmp_label`, `clean_tmp_help` | casella "Svuota /tmp" + aiuto | **sparisce** (il motore pulisce sempre) |
| `ignore_missing` | nota "ignore.txt non trovato" | inspector: "file mancante" accanto alla voce (I3), Impostazioni › Elenchi |

Schede

| Chiave | Oggi | Nella 2.0 |
|---|---|---|
| `tab_run`, `tab_prev`, `tab_fix` | schede Elabora / Anteprima / Sub fix | schede della barra laterale e segmenti della barra in alto (N1), menu Vista ⌘1–⌘3 |

Elabora

| Chiave | Oggi | Nella 2.0 |
|---|---|---|
| `select_videos` | sottotitolo "Seleziona i video" | sparisce (nessuna selezione); intestazione della pagina Elabora |
| `no_videos_warn` | "Nessun video in ./videos…" | stato vuoto E0 |
| `outputs_caption` | nota sulle uscite | nota nella barra in basso (E1) e passo 3 di E0 |
| `start_btn`, `start_btn_help` | "▶ Avvia OCR" + aiuto | **Avvia** nella barra in basso + menu Elabora ⌘↩; aiuto nel passo 3 di E0 |
| `reset_msgs_btn` | "Reset messaggi" | **sparisce** (esiti nelle righe; "Togli i finiti" nella barra) |
| `select_at_least_one` | avviso senza video scelti | sparisce: Avvia disabilitato senza righe pronte |
| `vision_unavailable` | errore al via | avviso O6 |
| `band_dialogues`, `band_signs` | "dialoghi", "cartelli" nelle etichette delle tappe | gruppi di tappe nella riga in corso (E2), esiti "fallito durante OCR · dialoghi" (E3) |
| `step_extract`, `step_group`, `step_ocr`, `step_refine` | nomi delle tappe | nomi delle barre delle tappe (E2) **[?18]**; "OCR ×{n}" resta |
| `file_header` | "#### 🎞️ File {n}/{tot} — {name}" | testa della riga in corso "File 2 di 3", scheda attività della barra laterale, menu del Dock |
| `srt_existed_note` | "(l'SRT esisteva già)" | chip "SRT già presente" (E1) e "nuovo nome con data e ora" nell'esito (E3) |
| `waiting`, `waiting_est` | "in attesa", "stima ~{est} (dal file precedente)" | tappe e righe in attesa (E2) |
| `step_waiting_row` | riga ⬜ STEP i/n | sparisce come formato: la tappa in attesa è una barra grigia (E2) |
| `unit_rows_s`, `unit_fps` | unità della velocità | velocità delle tappe (E2): "righe/s", "fps" |
| `rate_avg`, `rate_live` | velocità media e dal vivo | tappa finita "media 7,4 fps" e tappa in corso "7,3 fps" (E2); `rate_avg` anche nel log |
| `step_done` | riga verde ✅ "concluso in …" | tappa finita (E2) + log |
| `step_start` | solo nel log | log |
| `step_aborted` | riga rossa ❌ "interrotto" | tappa interrotta nella riga fallita (E4) + log |
| `eta` | " — ETA {eta}" | tappa in corso (E2) |
| `step_progress` | testo della barra in corso | tappa in corso: conteggio, trascorso, ETA, velocità (E2) |
| `log_error` | "ERRORE: {e}" nel log | log |
| `msg_error` | messaggio rosso "{name}: errore — {e}" | esito "fallito" della riga (E3, E4), foglio E6, notifica |
| `times_summary` | "⏱ {times}" | riga finita aperta (tempi per tappa) + log |
| `log_result` | "RISULTATO: …" nel log | log; gli stessi numeri nell'esito della riga (E3) |
| `qc_note` | "· report di revisione: **{name}**" | pulsante **Apri report** sulla riga e nel foglio |
| `msg_no_subs` | messaggio giallo "nessun sottotitolo trovato" | esito "fatto, senza sottotitoli" (E3), foglio E6, notifica |
| `msg_done` | messaggio verde con righe, scartate, raffinati, totale, tempi | esito "fatto" della riga (E3), foglio E6, notifica |
| `batch_done_toast` | toast "Batch completato ✅" | notifica di fine lotto + foglio E6 |

Anteprima

| Chiave | Oggi | Nella 2.0 |
|---|---|---|
| `prev_subheader` | "Anteprima ritaglio + test OCR" | intestazione della pagina Anteprima |
| `disabled_while_busy` | "Disabilitata durante l'elaborazione." (Anteprima e Sub fix) | nota A6 (Anteprima in sola lettura); Sub fix non si blocca |
| `no_videos_info` | "Nessun video in ./videos." | stato vuoto A0 |
| `video_select_label`, `video_select_help` | selectbox + aiuto | menu **Video** in A1 + fumetto |
| `extract_frames_btn`, `extract_frames_help` | pulsante + aiuto | **Trova 20 fotogrammi** + fumetto (A1) |
| `invalid_duration` | avviso | nota rossa A5 |
| `searching_frames` | testo iniziale della barra | A2, prima del primo evento |
| `zone_progress` | "Zona {done}/{tot} — {found} frame col testo" | barra di A2, sottotitolo della scheda Anteprima |
| `frames_caption` | riepilogo dei fotogrammi | riepilogo sotto le miniature (A3), sottotitolo della scheda |
| `badge_top_text`, `badge_bottom_text`, `badge_no_text` | badge con emoji | badge del fotogramma (A3) e puntini delle miniature |
| `frame_caption`, `frame_caption_top` | didascalia con la legenda dei colori | "Fotogramma 4 di 20 · 00:12:34" (A3); la legenda sparisce (le bande hanno il nome sulla linguetta) |
| `preview_unavailable` | avviso | segnaposto "Anteprima non disponibile." (A5) |
| `test_ocr_btn`, `test_ocr_help` | "🔍 Test OCR su questo frame" + aiuto | **Prova OCR su questo fotogramma** (⌘T) + fumetto (A3) |
| `band_bottom_title`, `band_top_title` | titoli dei risultati con emoji | titoli dei due pannelli (A4) |
| `ocr_vote_caption` | "OCR con voto ({ms} ms, {n} varianti)" | riga in testa al pannello (A4) |
| `empty_text` | "<VUOTO>" | "‹vuoto›" nel riquadro del testo votato (A4) |
| `conf_agree`, `alts_suffix` | confidenza, accordo, alternative | riga dei valori e chip delle alternative (A4) |
| `final_text_label`, `final_text_help` | area di testo + aiuto | **Testo finale** + fumetto (A4) |
| `no_text_in_band` | avviso | "Nessun testo in questa banda." nel pannello (A5) |

Sub fix

| Chiave | Oggi | Nella 2.0 |
|---|---|---|
| `fix_subheader` | sottotitolo della scheda | intestazione della pagina Sub fix |
| `fix_caption` | a cosa serve | testo dello stato vuoto F0 (più corto) |
| `fx_merge_label`, `fx_merge_help` | casella + aiuto ("Gap max nella sidebar") | opzione in F1 + fumetto ("unione dall'inspector") |
| `fx_ignore_label`, `fx_ignore_help` | casella + aiuto | opzione in F1 + fumetto |
| `fx_flash_label`, `fx_flash_help` | casella + aiuto | opzione in F1 + fumetto |
| `fx_min_label`, `fx_min_help` | campo + aiuto | **Durata minima** in F1 + fumetto |
| `source_label`, `source_from_videos`, `source_upload`, `source_help` | radio della sorgente | **sparisce** (trascinamento o Apri SRT…) |
| `srt_select_label`, `no_srt_info` | tendina degli `.srt` di ./videos | **sparisce**; scheda del file scelto e stato vuoto F0 |
| `upload_srt_label` | caricamento | **sparisce**; area di trascinamento F0 e **Cambia…** in F1 |
| `run_fix_btn` | "Esegui Sub fix" | **Esegui Sub fix** (F1, ⌘↩) |
| `no_valid_segments` | errore | nota rossa F3 (errore `no_valid_segments` del motore) |
| `fix_created` | "Creato: {name} ({n} righe)" | nota verde F2 con Mostra nel Finder e Apri |
| `generic_error` | "Errore: {e}" | nota rossa F3 ("Non riesco a leggere questo SRT: …") e testi degli avvisi d'errore |

Piè di pagina e aggiornamenti

| Chiave | Oggi | Nella 2.0 |
|---|---|---|
| `footer` | "SubVision v{version} — ⭐ GitHub" | piè della barra laterale (versione, GitHub), Informazioni su SubVision |
| `update_available` | nota "Nuova versione disponibile — vai alle release" | scheda gialla della barra laterale, Impostazioni › Aggiornamenti, avviso O8d |

Totale: 141 chiavi, ognuna con una destinazione (verificato con uno script sulle chiavi di `i18n.STRINGS["it"]`).

### 11.3 Controlli e testi senza chiave

| Oggi | Nella 2.0 |
|---|---|
| `page_icon` 🎬, CSS dei fumetti (?) | icona dell'app; fumetti nativi (`.help` / popover) |
| Caselle dei video (`v_<nome>`) | sparisce: tutto l'elenco entra nel lotto |
| Pulsanti ◀ ▶ dell'Anteprima | frecce ai lati del fotogramma, tasti ← →, ⌘← ⌘→ nel menu |
| `st.progress` della ricerca, `st.empty` delle tappe | barre native (A2, E2) |
| `st.code` e `st.text_area` del test OCR | riquadri di testo dei pannelli A4 (sola lettura, copiabili) |
| Rettangoli verde e azzurro disegnati con PIL | bande in SwiftUI con maniglie (A3) |
| Lock `busy` + `st.rerun` | stato del lotto nel modello dell'app; controlli bloccati (I3, A6, ST5) |
| `step_durations` in sessione (stime dal file precedente) | calcolate nel motore (`batch.py`), mostrate nelle tappe in attesa |
| Controllo aggiornamenti in `updates.py` (cache una volta al giorno) | controllo nativo (ST4, piè, scheda gialla) |
| `_CORE_I18N` (14 testi di avanzamento e log del motore) | spariscono dall'interfaccia: il motore manda numeri (`batch.step`); i testi del log restano nel motore **[?6]** |
| `_QC_I18N` (testi del report) | restano nel motore; il report è generato lì (R1) **[?5, ?7]** |

---

## 12. Tavole previste per 3.2

Tavole HTML in `design/tavole/`, ognuna in versione **chiara e scura** con il suo PNG, testi EN e IT (una lingua per immagine, l'altra nella stessa pagina HTML). Codici: DS design system, T strumenti, E Elabora, I inspector, A Anteprima, F Sub fix, R report, ST Impostazioni, O avvisi e menu, N finestra stretta.

| Tavola | Contenuto e stati coperti |
|---|---|
| **DS1** · Colori e token | token chiaro/scuro copiati da AnimeUp 2.1 (`Color(dark:light:)`), rampe verde/giallo/rosso/accento, colori delle due bande sul fotogramma, contrasti **[?3, ?4]** |
| **DS2** · Testo, pulsanti, link | scala tipografica, ruoli dei pulsanti (primario, secondario, distruttivo, avviso, semplice) in tre misure, link sottolineati per tono |
| **DS3** · Componenti | riga del file (pronto, in corso, fatto, senza sottotitoli, fallito, fermato, illeggibile), barra di tappa (attesa, corso, fatta, interrotta), chip, note (blu, gialla, rossa, verde), controlli dell'inspector (cursore con valore, campo con stepper, interruttore, menu lingua, Predefinito, puntino), maniglie e linguette delle bande |
| **DS4** · Barra laterale | schede con i sottotitoli di tutti gli stati, segni a destra, schede attività (lotto, aggiornamento), piè con versione e GitHub |
| **T1** · Strumenti · download | quattro righe: pronta, in corso con barra, in attesa; riga di stato "Scarico 2 di 3" |
| **T2** · Strumenti · riconoscimento | righe 1–3 pronte, riga 4 in corso con stima di 30 s |
| **T3** · Strumenti · errore | download fermato, checksum, riconoscimento non partito; Mostra il log, Esci, Riprova |
| **T4** · Strumenti · uno solo | ritorno con la sola riga FFmpeg |
| **T5** · Motore | avvio in corso, motore non partito, fermato più volte |
| **E0** · Elabora vuota | tre passi, area di trascinamento, formati |
| **E1** · Elabora con video | tre righe pronte, chip "SRT già presente", file illeggibile, nota elementi saltati, barra con Avvia, inspector chiuso |
| **E2** · Elabora in corso | riga a tappe per due bande (fatta, in corso con ETA e velocità, in attesa con stima), righe in attesa, Ferma, Ferma tutto, inspector aperto e bloccato, scheda attività |
| **E3** · Elabora finita | esiti fatto, senza sottotitoli, fallito, fermato; riga finita aperta con tempi e trittico; Togli i finiti |
| **E4** · File fallito | riga aperta con la tappa interrotta e l'errore, Apri il log, Elabora di nuovo |
| **E5** · File fermato | dopo Ferma (lotto che continua) e dopo Ferma tutto (righe tornate pronte) |
| **E6** · Foglio di fine lotto | tutto ok; con un senza sottotitoli e un fallito |
| **E7** · Banner e note | Vision mancante (banner rosso, Avvia disabilitato), spazio sul disco stretto |
| **I1** · Inspector aperto | cinque gruppi aperti con i predefiniti |
| **I2** · Inspector cambiato | gruppi chiusi, valori cambiati con puntino, Predefinito attivo, menu della lingua aperto, fumetto (?) |
| **I3** · Inspector bloccato e note | bloccato durante il lotto; lingua non disponibile; elenco mancante |
| **A0** · Anteprima vuota | nessun video, area di trascinamento |
| **A1** · Anteprima pronta | menu Video, Trova 20 fotogrammi, segnaposto |
| **A2** · Ricerca | barra "Zona 12 di 20 · 9 con testo", Ferma |
| **A3** · Fotogramma con bande | due bande con maniglie, una maniglia trascinata con l'etichetta, badge, frecce, miniature |
| **A4** · Prova OCR | due pannelli: testo votato, valori, alternative, testo finale con {\an8}; pannello in lettura |
| **A5** · Nessun testo | nessuna zona con testo, banda vuota nella prova, durata non valida |
| **A6** · Anteprima durante il lotto | sola lettura con la nota blu |
| **F0** · Sub fix vuota | area di trascinamento, a cosa serve |
| **F1** · Sub fix pronta | file scelto, quattro opzioni, nota sui parametri condivisi, Esegui |
| **F2** · Sub fix fatto | nota verde con Mostra nel Finder e Apri |
| **F3** · Sub fix errore | nessun segmento valido, SRT illeggibile, file non .srt |
| **R1** · Report | finestra con il report caricato, Apri nel browser, Mostra nel Finder |
| **R2** · SRT revisionato | avviso "salvato" con Mostra nel Finder |
| **R3** · Errori del report | report sparito, salvataggio non riuscito (avviso con Scegli dove salvarlo…) |
| **ST1** · Generali | lingua, aspetto, notifiche, Dock |
| **ST2** · Strumenti | quelli scaricati; uno mio con errore; Scarica di nuovo in corso |
| **ST3** · Elenchi | ignore e correzioni con conteggi, Modifica…, Importa…, avviso Importa |
| **ST4** · Aggiornamenti | aggiornato, disponibile, GitHub non ha risposto |
| **ST5** · Bloccate | Strumenti durante il lotto |
| **O1** · Ferma questo file | avviso rosso |
| **O2** · Ferma tutto | avviso rosso |
| **O3** · Esci con lotto in corso | avviso giallo |
| **O4** · Chiudi la finestra | avviso blu con "Non mostrare più" |
| **O5** · FFmpeg mancante | scaricato sparito; il mio che non risponde |
| **O6** · Vision mancante | avviso rosso |
| **O7** · Lingua non supportata | avviso giallo |
| **O8** · Avvisi minori | cartella senza video, già nell'elenco, importa un elenco, aggiornamenti |
| **O9** · Barra dei menu | SubVision, File, Modifica, Vista, Elabora, Finestra, Aiuto, aperti uno accanto all'altro, con le scorciatoie |
| **O10** · Notifiche e Dock | notifiche (file, lotto, fallito), menu del Dock, icona con avanzamento |
| **N1** · Finestra stretta | barra in alto con Elabora in corso (spinner, capsula col numero) |
| **N2** · Stretta con inspector | inspector sovrapposto da destra |

51 tavole × 2 temi. Disegnate in 3.2: `design/tavole/index.html` (pagine, ancore e PNG); alcuni titoli si sono precisati disegnando (A5 "Nessun testo e casi della prova", R3 "Errori del report e caricamento", T4 "Ritorno" con l'aggiornamento di macOS). Le future immagini del README corrispondono a: `app_main` → E1, `app_preview` → A3, `app_processing` → E2, `app_testocr` → A4, `app_subfix` → F2, `review_report` → R1.
