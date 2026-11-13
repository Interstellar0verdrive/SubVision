# Snapshot F5 (le pagine)

Immagini a 2× della build Debug di F5, in chiaro e in scuro (`SUBVISION_SNAPSHOT_SCHEME=both`), fatte da `DebugSnapshot` dell'app con `SUBVISION_SNAPSHOT=<prefisso>` e `SUBVISION_SNAPSHOT_ADD=<video>`. Il nome è il codice della tavola in `design/tavole/png/`.

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
