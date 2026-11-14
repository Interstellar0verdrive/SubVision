# Immagini dei README 2.0 · da produrre

Le usano `README.md` (le `_en`) e `README.it.md` (le `_it`). Vanno nel ramo `assets`, cartella `screenshots/2.0/`, e i README le leggono da
`https://raw.githubusercontent.com/Interstellar0verdrive/SubVision/assets/screenshots/2.0/<nome>`. Finché non ci sono, i README mostrano immagini rotte: vanno caricate insieme alla fusione in `main`.

Regole comuni: catture della **finestra vera** (non `ImageRenderer`), PNG, finestra principale a **1360×840** salvo dove detto, app in primo piano (colori degli interruttori giusti), lingua dell'app uguale al suffisso (`_en` in inglese, `_it` in italiano), video demo Sintel (release `demo-assets`) o altri video senza diritti di terzi, nessun percorso personale leggibile (cartella neutra, es. `~/Movies/SubVision demo/`), nessuna notifica o altra app nell'inquadratura. Ombra della finestra inclusa, sfondo trasparente.

| # | File | Tema | Stato dell'app da catturare |
|---|---|---|---|
| 1 | `icon_256.png` | — | l'icona dell'app (`SubVision.icon`) a 256×256, sfondo trasparente; una sola, senza lingua |
| 2 | `video_dark_en.png` / `video_dark_it.png` | scuro | **immagine principale.** Pagina Video con 3 video in elenco durante un lotto: il primo fatto («12 righe · elaborato in 00:16» e Rivedi), il secondo in corso con le tappe Dialoghi e Cartelli aperte (Estrazione e Raggruppamento finite, OCR a metà con «N / M · ETA · fps»), il terzo in attesa con la stima; barra laterale con la scheda «Lotto in corso»; pannello Parametri fisso a destra sulla scheda Lettura |
| 3 | `video_light_en.png` / `video_light_it.png` | chiaro | lo stesso stato della 2 in chiaro (è la `<source>` del `<picture>` per chi ha GitHub in chiaro) |
| 4 | `first_launch_dark_en.png` / `first_launch_dark_it.png` | scuro | finestra del primo avvio (strumenti): uv + Python pronto, FFmpeg in download con barra e «N di M MB», FFprobe e Preparazione del riconoscimento in attesa. Da una cartella di stato vuota (`SUBVISION_STATO` di prova) o alimentata a mano (`SUBVISION_SNAPSHOT_TOOLS=1`), ma catturata come finestra vera. Nel README è mostrata a 640 px di larghezza |
| 5 | `video_finished_dark_en.png` / `video_finished_dark_it.png` | scuro | pagina Video a lotto finito con il **foglio di fine lotto** davanti («3 SRT pronti», una riga per file con «Rivedi», «Mostra gli SRT nel Finder», «Vai a Revisione»); sotto, le righe finite con i loro esiti (almeno una «senza sottotitoli» o «fermato» per far vedere gli esiti diversi, se viene naturale) |
| 6 | `parameters_light_en.png` / `parameters_light_it.png` | chiaro | il solo **pannello Parametri** (ritaglio di 340 pt più margine) sulla scheda **Bande**: schema del fotogramma con Cartelli in alto e Dialoghi in basso, i quattro cursori, interruttore Cartelli acceso; almeno un valore cambiato, così si vedono il puntino sulla scheda e «1 valore diverso dal predefinito · ↺ Ripristina». Nel README sta a destra a 360 px |
| 7 | `preview_window_dark_en.png` / `preview_window_dark_it.png` | scuro | **finestra Anteprima** (1280×860) su un fotogramma con testo sia nei dialoghi sia nei cartelli (badge «Testo nei dialoghi e nei cartelli»), le due bande con le maniglie, le due righe da 10 miniature, e sotto i pannelli Dialoghi e Cartelli **compilati** dopo Prova OCR (testo, confidenza e accordo, testo finale con `{\an8}` per i cartelli); pannello Parametri a destra |
| 8 | `review_dark_en.png` / `review_dark_it.png` | scuro | pagina **Revisione** con 3 video elaborati, una riga aperta (tempi, file, nota dei buchi), e **davanti, spostata in basso a destra, la finestra del report** («Revisione · <video>») con qualche riga visibile, una evidenziata come dubbia con le letture alternative. Se due finestre sovrapposte rendono male, due catture affiancate in un'unica immagine |
| 9 | `subfix_dark_en.png` / `subfix_dark_it.png` | scuro | pagina **Sub fix** larga (due colonne): a sinistra File selezionato (un `.srt` demo, «12 righe · 00:52») e Cosa correggere, a destra «Condivisi con Video»; in basso la nota verde «Creato: …-fixed-<data>.srt (12 righe)» con Mostra nel Finder e Apri |

In tutto 17 file (1 + 8 coppie EN/IT).

Facoltative, non usate dai README: `settings_tools_dark_*.png` (Impostazioni › Strumenti con il menu FFmpeg aperto), `narrow_dark_*.png` (finestra 760×640 con la barra in alto). Le catture C2 in `design/snapshot/c2/` possono servire da punto di partenza, ma sono state fatte con l'app non in primo piano (colori degli interruttori) e con dati di prova: vanno rifatte.

I vecchi file del ramo `assets` (`screenshots/app_*.png`, `review_report_en.png`) restano per i README della 1.0.0 nel tag `v1.0.0`: non vanno cancellati.
