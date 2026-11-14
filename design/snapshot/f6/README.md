# Snapshot F6 (tutte le tavole, codice finale)

> Le tavole di F3 citate qui (`design/tavole/`) non sono più nel ramo: le tavole definitive sono nel file di design https://claude.ai/artifact/6hPbiA85ZJxGauwq1w4evQ.

Immagini a 2× della build Debug di F6 (`native-2.0` a 0b92056), in chiaro e in scuro, una per tavola di `design/tavole/png/` (più varianti col suffisso dove la tavola ne mostra più d'una). Il nome è il codice della tavola. Interfaccia in italiano, finestra principale a 1360×840, N1 e N2 a 760×640 (la finestra intera, come nelle tavole). Le cartelle `f4/` e `f5/` restano come storia: sono state fatte su build intermedie (in `f5/` l'inspector di A3 era vuoto perché precedeva l'unione dei rami).

Due strade, le stesse di F4 e F5:

- `SUBVISION_SNAPSHOT=<prefisso>` con `SUBVISION_SNAPSHOT_SCHEME=both`, `_ADD=<tre video>`, `_PROCESS=1`, `_PREVIEW=1`, `_TOOLS=1`, `_FIX=<srt>`, `_REPORT=<report>` (`DebugSnapshot.swift`): un giro solo, poi l'app esce.
- `SUBVISION_COMMANDS=<file>` (`DebugQA.swift`): l'app pilotata dalla shell con gli stessi metodi dei pulsanti; per F6 si aggiungono i comandi di `DebugCapture.swift` (solo Debug) per le tavole che non avevano ancora una strada: `engine-status`, `vision`, `disk-free`, `batch-fake`, `capture-all` (la finestra con gli avvisi sopra, ognuno disegnato dove sta), `capture-window`, `settings-tab`, `settings-feed`, `alert-show`, `alerts-close`, `menu-shot`, `dock-tile`, `compose`, `gallery`.

Quasi tutte sono catture della finestra vera (`cacheDisplay`, senza permessi), una volta per aspetto. Le clip sono le due demo (`sintel_*_hardsub_demo.mp4`, 55 s) copiate in una cartella temporanea: i percorsi nelle righe sono quelli. Le luci della finestra sono grigie quando l'app non era in primo piano.

## Elabora, inspector, finestra stretta

- E0, A0, F0: pagine vuote, finestra vera.
- E1: finestra vera, tre video pronti (uno con «SRT già presente»), un `.mkv` illeggibile e la nota dei due elementi saltati (`cover.jpg`, `notes.txt`): tutto trascinato davvero con `add`.
- E2, E3, E4, E5, I1, I2, I3-language, N1: stati alimentati a mano (`DebugSnapshot.processStates`), come in F5: un lotto sulle clip demo finisce in pochi secondi. In E3 i nomi di SRT e log sono barrati perché i file non esistono (stato a mano). N1 ora è a 760×640.
- E6: il foglio di fine lotto reso con `ImageRenderer`; `real/E6-window-dark.png` è la finestra vera con il foglio sopra (`screencapture -l`) alla fine di un lotto vero (un file fatto, uno fermato con Ferma tutto, uno rimasto pronto).
- E7: finestra vera con `vision off` (banner rosso, Avvia spento) e `disk-free 6` (la nota gialla legge 6 GB invece dello spazio vero): i due valori sono alimentati a mano, il resto è la pagina vera.
- I2-langmenu: il menu delle lingue di Vision aperto dall'inspector, catturato con `screencapture -l` mentre AppKit lo tiene aperto (`menu-shot lang`). La parte del menu che esce dalla finestra esce grigia (dietro non c'è nulla della finestra da catturare). Il fumetto (?) della tavola non è riprodotto.
- N2: finestra vera a 760×640, ricerca vera dei fotogrammi, inspector sovrapposto.

## Anteprima (A1–A6) e Sub fix (F1–F3)

Come in F5 (`SUBVISION_SNAPSHOT_PREVIEW=1` e `_FIX=<srt>`): ricerca e prova OCR vere, A2 e A5 alimentati a mano, A6 con `batch.running` forzato; F2 dopo un `srt.fix` vero, F3 con le tre note una alla volta (`F3`, `F3-unreadable`, `F3-notsrt`). Ora A3 ha l'inspector popolato.

## Report (R1–R3)

- R1, R2: finestra vera su un report nuovo, generato dal motore sulla clip inglese rinominata `sintel_eng_hardsub_demo-f6.mp4` (vedi sotto, «report che eredita le scelte»); R2 dopo un Salva SRT revisionato vero, con l'avviso in basso.
- R3-gone, R3-loading, R3-savefail: come in F5 (R3-savefail è la scheda dell'avviso resa da sola: nell'app è modale).

## Strumenti e motore (T1–T5)

- T1, T2, T3-download, T3-vision, T4-missing, T4-update: la finestra strumenti resa da stati alimentati a mano (`renderToolsStates`), come in F4.
- T5-starting, T5-failed, T5-gaveup: finestra vera con lo stato del motore impostato a mano (`engine-status`): la pagina al posto delle schede è quella vera; la tavola mostra i tre stati insieme, l'app uno alla volta.

## Avvisi, menu, Dock (O1–O10)

- O1, O2: lotto vero di tre clip, avviso aperto dal pulsante (`stop-file-ask`, `stop-all-ask`), finestra e avviso insieme (`capture-all`). `real/O1-alert-*.png`: lo stesso con `screencapture -l`.
- O3, O4: durante lo stesso lotto. O4 è la funzione vera (`Alerts.closeNotice`); O3 nell'app è modale (`runModal` fermerebbe i comandi), quindi è costruito come in `Alerts.confirmQuit` e mostrato senza ciclo modale: la scheda è la stessa.
- O5, O6: non fatte. L'app non ha questi due avvisi: FFmpeg sparito all'avvio riporta la finestra strumenti (T4), Vision mancante mostra solo il banner di E7 con Avvia spento.
- O7: vero, Avvia con la lingua `hu-HU` (Ungherese, che Vision qui non legge). `real/O7-alert-*.png` con `screencapture -l`.
- O8: i quattro avvisi da soli, uno accanto all'altro (`compose`): cartella senza video e video già nell'elenco con il percorso vero (`add`), aggiornamento con la funzione vera; Importa (modale nell'app) costruito come in `Alerts.importList`.
- O9: i sette menu aperti durante un lotto vero, ognuno con `screencapture -l` mentre è aperto (`menu-shot`), ritagliati e messi in griglia. Il fondo intorno a ogni menu è la finestra.
- O10: il menu del Dock durante il lotto (vero) e la vista dell'icona del Dock con la barra (quella che l'app disegna; il numero sul badge lo disegna il Dock e non c'è). La frazione è quella vera del momento (inizio del primo file), quindi la barra è quasi vuota. Le notifiche di macOS non sono riprodotte.

## Impostazioni (ST1–ST5)

Finestra vera delle Impostazioni (`cacheDisplay`, barra degli strumenti compresa), scheda scelta col clic sul suo elemento (`settings-tab`), app attiva perché gli interruttori siano nell'accento.

- ST1: Generali. ST2-download: Scarica di nuovo in corso (13 di 28 MB, alimentato a mano); ST2-own: «Uno mio…» che non parte (percorso ed errore alimentati a mano, non salvati). ST3: Elenchi (l'avviso di Importa della tavola è in O8). ST4-ok, ST4-available, ST4-error: i tre esiti alimentati a mano. ST5: Strumenti con `batch-fake on`.
- `real/ST1-window-*.png`, `real/ST2-window-*.png`: le stesse finestre con `screencapture -l`, ombra compresa.

## Design system (DS1–DS4)

Non c'è una pagina dell'app per tavola: `DS-gallery-light.png` / `-dark.png` è `SVDesignGallery` di SVDesign (la stessa del test `galleryRenders`), resa con `ImageRenderer`. Copre testo, pulsanti, chip, barre, note, righe delle impostazioni, avvisi e barra laterale; è in inglese, i pezzi AppKit (area di trascinamento, menu) sono segnaposto, e non ha le tabelle dei token di DS1.

## Differenze dalle tavole e cose da guardare

- Corretti dopo queste catture (commit `0ad366a`, «Four small bugs seen in the F6 snapshots»): il report che ereditava le scelte di un report vecchio con lo stesso nome di SRT (`localStorage` della WKWebView conservato tra un report e l'altro: ora l'archivio è non persistente; per questo R1/R2 sono su una copia rinominata), «Annulla Annulla Togli» nel menu Modifica (O9: ora «Annulla Togli dall'elenco»), il selettore di Impostazioni › Aspetto che non seguiva un cambio di tema fatto altrove, l'ombra degli avvisi tagliata dal bordo del pannello (O7 e `real/O7-alert-*` rifatti dopo la correzione; O1, O2, O4, O8 e `real/O1-alert-*` hanno ancora il rettangolo grigio in chiaro).
- Menu Modifica (O9): due «Seleziona tutto» (quello di sistema spento con ⌘A, quello dell'app senza scorciatoia): resta per F7.
- O3: il pulsante «Esci e ferma» è rosso pieno; la tavola lo ha primario.
- O10: la prima riga del menu del Dock («File 1 di 3 · …») non è attenuata come nella tavola.
- N1: a 760 pt le statistiche delle tappe si troncano con «…».
- La nota «2 elementi saltati» resta anche dopo aver tolto tutti i video (visibile in E7, O1–O4, O7): sparisce solo con la ×.
- T5: la barra laterale mostra i conteggi dell'elenco, la tavola i trattini.
