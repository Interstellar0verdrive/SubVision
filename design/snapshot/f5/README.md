# Snapshot F5 (le pagine)

> Le tavole di F3 citate qui (`design/tavole/`) non sono più nel ramo: le tavole definitive sono nel file di design https://claude.ai/artifact/6hPbiA85ZJxGauwq1w4evQ.

Immagini a 2× della build Debug di F5, in chiaro e in scuro (`SUBVISION_SNAPSHOT_SCHEME=both`), fatte da `DebugSnapshot` dell'app con `SUBVISION_SNAPSHOT=<prefisso>` e `SUBVISION_SNAPSHOT_ADD=<video>`. Il nome è il codice della tavola in `design/tavole/png/`.

## Elabora in corso e inspector (5.1)

Con `SUBVISION_SNAPSHOT_ADD=<tre video>` e `SUBVISION_SNAPSHOT_PROCESS=1`.

- E2, E3, E4, E5, I1, I2, I3, N1: cattura della finestra vera (`cacheDisplay`) con gli stati alimentati a mano (`DebugSnapshot.processStates`): un lotto sulle clip demo finisce in venti secondi, troppo in fretta per fermare ogni stato con i numeri delle tavole. I percorsi dei video sono quelli di una cartella temporanea; il terzo video è una copia della clip italiana.
- I3: la variante centrale della tavola (lingua salvata che Vision non ha, nota gialla e menu evidenziato); la variante sinistra (inspector bloccato) è in E2; la destra (liste mancanti) non è riprodotta.
- E6: il foglio di fine lotto reso con `ImageRenderer` (un foglio è un'altra finestra: `cacheDisplay` della principale non lo prende); `real/E6-window-dark.png` è la finestra vera con il foglio sopra (`screencapture -l`), alla fine di un lotto vero sulle due clip demo con il profilo veloce.
- `real/E2-window-dark.png`, `real/E5-window-dark.png`: finestra vera durante un lotto di tre clip (OCR del secondo file in corso) e dopo Ferma sul secondo file e Ferma tutto sul terzo (`cacheDisplay`, scenario `DebugQA`).
- `real/E3-window-dark.png`: finestra vera dopo il lotto, prima riga aperta (tempi e file).

Scenario `DebugQA` usato per le catture vere (comandi in `DebugQA.swift`): `params fast`, `add <clip>,<clip>`, `start`, `wait-step 1 ocr 90`, `capture …`, `stop-file`, `wait-file 1 30`, `wait-step 2 extract 60`, `stop-all`, `wait-batch 30`, `states`, `expand 0`, `capture …`.

## Anteprima (5.2)

Con `SUBVISION_SNAPSHOT_PREVIEW=1` sulla clip demo `sintel_ita_hardsub_demo.mp4` (55 s). Tutte catture della finestra vera (`cacheDisplay`, senza permessi); ricerca e prova OCR eseguite davvero dal motore.

- A1: Anteprima pronta, prima della ricerca.
- A2: ricerca in corso, stato alimentato a mano (zona 12 di 20, 9 con testo): sulla demo la ricerca vera finisce in pochi secondi, meno di quanto servono le due catture.
- A3: 20 fotogrammi trovati (19 con testo), inspector aperto, maniglia della banda dialoghi tenuta a 31 % con l'etichetta dei valori (lo stato di trascinamento è impostato dal codice: lo stesso che il gesto imposta).
- A4: Prova OCR sul primo fotogramma con testo, i due pannelli (la banda cartelli è vuota sulla demo).
- A5: stato alimentato a mano, perché sulla demo non si riproduce: i fotogrammi senza testo (nota gialla), la durata non letta (nota rossa), un risultato della prova con la banda dialoghi vuota e i cartelli "IL MERCATO", superato da parametri cambiati.
- A6: durante il lotto (`batch.running` forzato): nota blu, maniglie e prova spente, menu Video e ricerca disabilitati.
- N2: finestra a 900 pt con l'inspector sovrapposto alla pagina Anteprima.
- `real/A3-window-dark.png`, `real/A4-window-dark.png`: la finestra vera (`screencapture -l`) dopo lo scenario `DebugQA` (`find-frames`, `drag-handle`, `try-ocr`).

Nota: i valori delle bande sono quelli di `UserDefaults` al momento della cattura (`ocr.bottomKeepPct`, `ocr.keepWPct`, `ocr.topBand`…), condivisi con l'inspector.

## Sub fix (5.3)

Catture della finestra vera (`DebugSnapshot.capture`, `cacheDisplay`) con `SUBVISION_SNAPSHOT_FIX=<srt>` (qui l'SRT demo `sintel_ita_hardsub_demo.srt` della release `demo-assets`, 12 righe, copiato in una cartella temporanea: il percorso nella scheda è quello).

- F0: pagina vuota (area di trascinamento).
- F1: file scelto, le quattro opzioni, nota sui parametri condivisi, Esegui.
- F2: dopo un `srt.fix` vero (nota verde con Mostra nel Finder e Apri, "Creato · 12 righe" con la spunta nella barra laterale); "Togli i flash" spento per mostrare Durata minima attenuata, come nella tavola.
- F3: errore `no_valid_segments` (stato alimentato a mano dopo il run: la tavola mostra tre note insieme, nell'app ne compare una alla volta). `F3-unreadable`: SRT illeggibile (`bad_srt`, riga 214). `F3-notsrt`: trascinato un file che non è `.srt` (nota gialla).
- `real/F2-window-dark.png`: la finestra vera con `screencapture -l`, aspetto scuro, finestra non attiva: gli interruttori accesi sono bianchi (resa di macOS per le finestre inattive; nella finestra attiva sono in accento, come nella F1 chiara).

## Report (5.4)

Finestra vera del report (`SUBVISION_SNAPSHOT_REPORT=<report.revisione.html>`), aperta sul report 2.0 generato dal motore sul clip demo `sintel_eng_hardsub_demo.mp4` (profilo veloce, lingua dell'interfaccia italiana) in una cartella temporanea. La WKWebView disegna fuori processo e `cacheDisplay` la lascia vuota: la cattura compone la cornice (`cacheDisplay`) con `takeSnapshot` della WKWebView e, quando c'è, l'avviso in basso reso di nuovo sopra (`ReportWindowController.capture`).

- R1: report aperto, barra dell'app con nome del file, Mostra nel Finder e Apri nel browser; la pagina segue l'aspetto dell'app (`prefers-color-scheme` dalla `NSApp.appearance`, non dal sistema).
- R2: dopo Salva SRT revisionato passato dal ponte: l'SRT scritto accanto al report, l'avviso in basso con il nome e Mostra nel Finder (sparisce da solo dopo 6 s). Il report mostra il suo "SRT salvato ✓ (percorso)" nella barra in alto, che con un percorso lungo manda a capo i controlli per un paio di secondi (vedi il resoconto: richiesta al motore).
- R3-gone: il file non c'è più, nota rossa con Chiudi; Mostra nel Finder e Apri nel browser disabilitati.
- R3-loading: lo spinner con "Carico il report…" mentre la pagina carica (la WKWebView è nascosta fino a `didFinish`).
- R3-savefail: l'avviso del salvataggio impossibile accanto all'originale, reso da solo con `ImageRenderer` (`SVAlertCard`): è modale, e nella finestra vera la cattura non lo raggiunge. Il flusso vero (rifiuto della promessa al report, Scegli dove salvarlo… → pannello Salva → risposta `{ok, path}`) è provato con `report-elsewhere` di `DebugQA` su una cartella in sola lettura.

Le luci della finestra sono grigie perché l'app non è in primo piano durante la cattura.
