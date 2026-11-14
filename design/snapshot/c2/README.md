# Snapshot C2 (finestre vere contro le tavole definitive)

Le tavole di riferimento sono quelle definitive e approvate del file di design: https://claude.ai/artifact/6hPbiA85ZJxGauwq1w4evQ (scuro = «Native screens», chiaro = «Native screens · light»). Le vecchie tavole HTML di F3 (`design/tavole/`) non sono più nel ramo.

Catture a 2× delle finestre vere della build Debug (`cacheDisplay`, senza permessi), rifatte il 14/11/2026 sul ramo `c3-fix` dagli scenari `macos/Native/QA/14-c2-snapshots.txt` (nomi `C2-*`, i codici delle tavole del giro C2) e `macos/Native/QA/15-final-boards.txt` (nomi con il codice della tavola definitiva). Due clip demo copiate in una cartella temporanea (i percorsi nelle righe sono quelli), interfaccia in italiano, profilo veloce con la banda cartelli accesa: per questo il pannello segna «4–5 valori diversi dal predefinito» e la prova dice «OCR singolo». Le luci della finestra sono grigie e gli interruttori chiari perché l'app non era in primo piano durante le catture. Erano PNG a 256 colori (median cut); dal 14/11/2026 sono WebP, stessa risoluzione (vedi sotto).

**Scenario 14 (giro C2):**

- `C2-V1-P1`: Video con due video pronti, pulsante «Anteprima» sulle righe, area di trascinamento sotto la lista; pannello Parametri sulla scheda Lettura.
- `C2-V2`: due righe selezionate, barra delle azioni in basso.
- `C2-P2`, `C2-P3`: il pannello sulle schede Bande e Righe.
- `C2-V3`: lotto in corso (tappe, linea sopra DIALOGHI, scheda attività, pannello bloccato).
- `C2-V5`: foglio di fine lotto (`capture-all`: su macOS 26 il foglio compare centrato e staccato dal bordo).
- `C2-R0`, `C2-R1`: Revisione vuota e con i due video, la prima riga aperta.
- `C2-A1`, `C2-A2`, `C2-A3`: la finestra Anteprima prima della prova, dopo la prova con i cartelli «superati», durante il lotto.
- `C2-N1`: finestra a 760×780, pannello sovrapposto con la ×.
- `C2-S1`, `C2-S2`: Sub fix a due colonne e a una colonna.

**Scenario 15 (tavole definitive):**

- `A1-dark`: Anteprima di un video mai cercato: la ricerca parte da sola (zona, barra, Ferma; le zone già fatte in grigio). `A0-dark`: la stessa finestra fermata prima del primo fotogramma (testo, pulsante; i tre passi compaiono quando il riquadro è alto abbastanza, con video 16:9). `A2-dark`: i 20 fotogrammi.
- `A4-dark`, `A4-light`: la prova nelle due bande (la clip demo non ha cartelli: la banda cartelli dice «Nessun testo»). `A5-dark`: un fotogramma senza testo con i cartelli spenti («‹vuoto›», «Accendi la banda cartelli»).
- `E5-dark`, `E5-light`: un lotto fermato (Ferma sul primo file, poi Ferma tutto).
- `E7-dark`, `E7-light`: banner rosso (Vision spento a mano), nota dei due elementi saltati, video illeggibile, nota del disco (spazio libero dato a mano).
- `N1-running-dark`: la riga in corso a 760 pt: i numeri delle tappe non si troncano (voce 46).
- `RV0-light`, `RV1-dark`, `RV1-light`: Revisione vuota e con due video fatti, la prima riga aperta.
- `F0-*`, `F1-*`, `F2-*`, `F3-*`: Sub fix vuota, pronta, fatta, con l'errore di un SRT illeggibile; `F4-*`: a 760×780 (la tavola è a 1040 di altezza).

Differenze note dalle tavole: le clip demo sono 1280×544 (2,35:1), quindi in Anteprima il fotogramma è più basso e i pannelli più alti che nelle tavole (16:9), e in A0 i tre passi non ci stanno; durante la ricerca le miniature non arrivano una per volta (il motore manda i fotogrammi alla fine: i posti delle zone fatte sono grigi); Revisione mostra «0» buchi perché le clip demo non ne hanno; i nomi dei file d'uscita hanno data e ora (`-fixed-20261114_…`), le tavole solo la data. I menu di O9 non sono catture: lo scenario 15 li legge come testo (`menu-dump`).

Formato: WebP dal 14/11/2026 (prima PNG, convertite con `cwebp` per alleggerire il ramo): senza perdita (`-lossless -z 9`) quando il file scende sotto il 60 % del PNG o non supera quello con perdita, altrimenti `-q 90`; stessa risoluzione, il testo resta nitido. Gli scenari QA salvano ancora le catture nuove in PNG.
