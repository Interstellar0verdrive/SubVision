# Snapshot F5.1 (Elabora in corso e inspector)

Immagini a 2× della build Debug di F5.1, in chiaro e in scuro (`SUBVISION_SNAPSHOT_SCHEME=both`), fatte da `DebugSnapshot` dell'app con `SUBVISION_SNAPSHOT=<prefisso>`, `SUBVISION_SNAPSHOT_ADD=<tre video>` e `SUBVISION_SNAPSHOT_PROCESS=1`. Il nome è il codice della tavola in `design/tavole/png/`.

- E2, E3, E4, E5, I1, I2, I3, N1: cattura della finestra vera (`cacheDisplay`) con gli stati alimentati a mano (`DebugSnapshot.processStates`): un lotto sulle clip demo finisce in venti secondi, troppo in fretta per fermare ogni stato con i numeri delle tavole. I percorsi dei video sono quelli di una cartella temporanea; il terzo video è una copia della clip italiana.
- I3: la variante centrale della tavola (lingua salvata che Vision non ha, nota gialla e menu evidenziato); la variante sinistra (inspector bloccato) è in E2; la destra (liste mancanti) non è riprodotta.
- E6: il foglio di fine lotto reso con `ImageRenderer` (un foglio è un'altra finestra: `cacheDisplay` della principale non lo prende); `real/E6-window-dark.png` è la finestra vera con il foglio sopra (`screencapture -l`), alla fine di un lotto vero sulle due clip demo con il profilo veloce.
- `real/E2-window-dark.png`, `real/E5-window-dark.png`: finestra vera durante un lotto di tre clip (OCR del secondo file in corso) e dopo Ferma sul secondo file e Ferma tutto sul terzo (`cacheDisplay`, scenario `DebugQA`).
- `real/E3-window-dark.png`: finestra vera dopo il lotto, prima riga aperta (tempi e file).

Scenario `DebugQA` usato per le catture vere (comandi in `DebugQA.swift`): `params fast`, `add <clip>,<clip>`, `start`, `wait-step 1 ocr 90`, `capture …`, `stop-file`, `wait-file 1 30`, `wait-step 2 extract 60`, `stop-all`, `wait-batch 30`, `states`, `expand 0`, `capture …`.
