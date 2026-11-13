# Snapshot F5 (le pagine)

Immagini a 2× della build Debug di F5, in chiaro e in scuro (`SUBVISION_SNAPSHOT_SCHEME=both`), fatte da `DebugSnapshot` dell'app con `SUBVISION_SNAPSHOT=<prefisso>`. Il nome è il codice della tavola in `design/tavole/png/`.

## Sub fix (5.3)

Catture della finestra vera (`DebugSnapshot.capture`, `cacheDisplay`) con `SUBVISION_SNAPSHOT_FIX=<srt>` (qui l'SRT demo `sintel_ita_hardsub_demo.srt` della release `demo-assets`, 12 righe, copiato in una cartella temporanea: il percorso nella scheda è quello).

- F0: pagina vuota (area di trascinamento).
- F1: file scelto, le quattro opzioni, nota sui parametri condivisi, Esegui.
- F2: dopo un `srt.fix` vero (nota verde con Mostra nel Finder e Apri, "Creato · 12 righe" con la spunta nella barra laterale); "Togli i flash" spento per mostrare Durata minima attenuata, come nella tavola.
- F3: errore `no_valid_segments` (stato alimentato a mano dopo il run: la tavola mostra tre note insieme, nell'app ne compare una alla volta). `F3-unreadable`: SRT illeggibile (`bad_srt`, riga 214). `F3-notsrt`: trascinato un file che non è `.srt` (nota gialla).
- `real/F2-window-dark.png`: la finestra vera con `screencapture -l`, aspetto scuro, finestra non attiva: gli interruttori accesi sono bianchi (resa di macOS per le finestre inattive; nella finestra attiva sono in accento, come nella F1 chiara).
