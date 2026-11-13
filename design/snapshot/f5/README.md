# Snapshot F5 (le pagine)

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
