# Snapshot F4 (scheletro dell'app)

> Le tavole di F3 citate qui (`design/tavole/`) non sono più nel ramo: le tavole definitive sono nel file di design https://claude.ai/artifact/6hPbiA85ZJxGauwq1w4evQ.

Immagini a 2× della build Debug di F4, in chiaro e in scuro (`SUBVISION_SNAPSHOT_SCHEME=both`), fatte da `DebugSnapshot` dell'app con `SUBVISION_SNAPSHOT=<prefisso>`, `SUBVISION_SNAPSHOT_ADD=<video>`, `SUBVISION_SNAPSHOT_SETTINGS=1`, `SUBVISION_SNAPSHOT_TOOLS=1`. Il nome è il codice della tavola in `design/tavole/png/`.

- T1, T2, T3a/T3b, T4a/T4b: finestra degli strumenti resa da uno stato alimentato a mano (il primo avvio vero, con la cache di Vision già calda, finisce in pochi secondi).
- E0, E1, A0, F0, N1: cattura della finestra vera (`cacheDisplay`, senza permessi). I percorsi dei video sono quelli di una cartella temporanea.
- ST1–ST5: pagine delle Impostazioni rese con `ImageRenderer`: gli interruttori sono segnaposto; `real/ST1-window-dark.webp` è la finestra vera (`screencapture -l`).
- `real/E1-window-dark.webp`: la finestra principale vera con tre video e un file illeggibile.
- A1-placeholder: Anteprima con video, pagina segnaposto in attesa di F5.2.

Formato: WebP dal 14/11/2026 (prima PNG, convertite con `cwebp` per alleggerire il ramo): senza perdita (`-lossless -z 9`) quando il file scende sotto il 60 % del PNG o non supera quello con perdita, altrimenti `-q 90`; stessa risoluzione, il testo resta nitido. Gli scenari QA salvano ancora le catture nuove in PNG.
