# Snapshot F5 (le pagine)

Immagini a 2× della build Debug di F5, in chiaro e in scuro (`SUBVISION_SNAPSHOT_SCHEME=both`), fatte da `DebugSnapshot` dell'app con `SUBVISION_SNAPSHOT=<prefisso>`. Il nome è il codice della tavola in `design/tavole/png/`.

## Report (5.4)

Finestra vera del report (`SUBVISION_SNAPSHOT_REPORT=<report.revisione.html>`), aperta sul report 2.0 generato dal motore sul clip demo `sintel_eng_hardsub_demo.mp4` (profilo veloce, lingua dell'interfaccia italiana) in una cartella temporanea. La WKWebView disegna fuori processo e `cacheDisplay` la lascia vuota: la cattura compone la cornice (`cacheDisplay`) con `takeSnapshot` della WKWebView e, quando c'è, l'avviso in basso reso di nuovo sopra (`ReportWindowController.capture`).

- R1: report aperto, barra dell'app con nome del file, Mostra nel Finder e Apri nel browser; la pagina segue l'aspetto dell'app (`prefers-color-scheme` dalla `NSApp.appearance`, non dal sistema).
- R2: dopo Salva SRT revisionato passato dal ponte: l'SRT scritto accanto al report, l'avviso in basso con il nome e Mostra nel Finder (sparisce da solo dopo 6 s). Il report mostra il suo "SRT salvato ✓ (percorso)" nella barra in alto, che con un percorso lungo manda a capo i controlli per un paio di secondi (vedi il resoconto: richiesta al motore).
- R3-gone: il file non c'è più, nota rossa con Chiudi; Mostra nel Finder e Apri nel browser disabilitati.
- R3-loading: lo spinner con "Carico il report…" mentre la pagina carica (la WKWebView è nascosta fino a `didFinish`).
- R3-savefail: l'avviso del salvataggio impossibile accanto all'originale, reso da solo con `ImageRenderer` (`SVAlertCard`): è modale, e nella finestra vera la cattura non lo raggiunge. Il flusso vero (rifiuto della promessa al report, Scegli dove salvarlo… → pannello Salva → risposta `{ok, path}`) è provato con `report-elsewhere` di `DebugQA` su una cartella in sola lettura.

Le luci della finestra sono grigie perché l'app non è in primo piano durante la cattura.
