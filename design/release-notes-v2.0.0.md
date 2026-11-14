**SubVision 2.0: a real Mac app.**

SubVision is now a native macOS app written in SwiftUI. The browser interface of 1.x is gone: the same engine, with its multiple readings and voting, timing refinement, signs band and review report, now runs inside a window that behaves like every other app on the Mac, with its own menus, sheets, alerts, notifications and Dock progress.

I designed every screen from scratch, in light and dark, and rebuilt the app around the way I actually use it: add the videos, check the bands, start, review. A lot changed, so here is the whole picture.

## What's new

### One window, three pages

- **Video, Review and Sub fix** in the sidebar, with what each page is doing written under its name. The Preview opens in a window of its own.
- **A narrow window works too.** Below 1240 pt the sidebar folds into a bar at the top; below 1000 pt the Parameters panel slides over the page.
- **Light and dark**, following macOS or chosen in Settings, and **English and Italian**, switchable on the fly.

### Video

- **Add videos** by dropping files or whole folders, or with ⌘O. Subfolders are included, and anything that isn't a video is skipped with a note that says what was left out. Videos stay where they are: there is no `./videos` folder any more, and the list is kept between launches.
- **A live row for the file in progress**, with its steps (Extract, Group, OCR, Refine) for the dialogue band and the signs band, each with its progress, time left and speed. The steps still to come show an estimate from the previous file.
- **Stop the current file or Stop All**, which 1.x didn't have. A stopped file never leaves a half-written SRT, and the batch goes on with the next one.
- **The outcome stays on each row**: done, done without subtitles, failed (at which step and why, with its log one click away) or stopped. **Process Again** to run a file again.
- **End of the batch:** a sheet with the SRTs made and **Review** for each one, a macOS notification, and progress on the Dock icon while it runs. Closing the window doesn't stop the batch; ⌘Q asks first.

### The Parameters panel

- **All the OCR settings in three tabs**, Reading, Bands and Lines, next to the list instead of a long sidebar. Every value has its explanation and its default, a dot marks the tabs you changed, and **Restore** puts them back (⌘Z undoes it).
- **Kept between launches.** In 1.x they were lost at every reload.
- **The OCR language is a menu** of the languages Vision reads on your Mac, instead of a free-text field that, with an unknown language, gave an empty SRT without an error.

### Preview

- **A window of its own** (⌘Y from a row), with the Parameters panel beside it.
- **Drag the bands on the frame**: the height from the edge, the width from the sides, and the values change in the panel too.
- **Find 20 Frames** looks for frames with text in 20 zones of the video and starts by itself; the thumbnails, in two rows of ten, say which frames have dialogue, signs, both or nothing.
- **Try OCR** (⌘T) shows both bands side by side, with the text read, confidence and agreement, the alternative readings and the final text. Results stay with their frame and say when a parameter change makes them out of date.

### Review

- **A Review page** with every video processed, its lines, the lines dropped, the gaps without subtitles and when it was processed.
- **The review report opens in a window of the app** (⌘R). **Save reviewed SRT** writes the file next to the original, with no save dialog and no detour through Downloads. Your edits are saved as you go in `<video>.review.json`, so closing and reopening keeps them.
- The report is still a plain HTML file that works in a browser, and it follows the language of the app. Reports made by 1.x open too (File › Open a Report…).

### Sub fix

- **Drop an `.srt` or open it** (⇧⌘O), choose what to fix, **Run Sub fix** (⌘↩). The fixed copy goes next to the original.
- **The values shared with Video** (merge gap, line wrap, language, the two lists) are on the same page, and Sub fix works while a batch runs.

### Settings and first launch

- **Settings (⌘,)** in four tabs: General, Tools, Lists, Updates, with each default written under its setting.
- **Nothing to install by hand.** On the first launch a window downloads uv and Python, FFmpeg and FFprobe 9.0.2 (about 107 MB), each from a pinned release and checked against its SHA256, with progress and a retry that picks up where it stopped; then Vision prepares its models (about 30 seconds, once for each version of macOS). After that SubVision works offline.
- **Your own FFmpeg** if you prefer: the Homebrew one, or any folder that has both `ffmpeg` and `ffprobe`.
- **Lists** (`ignore.txt`, `corrections.txt`) edited from Settings, with Import… and a way back to the starter lists.

### Everywhere else

- **Menus and shortcuts:** File, Edit, View, Process, Window and Help menus, and shortcuts for the common actions.
- **Alerts in SubVision's own style:** red for what stops work, yellow for what needs attention, blue for information.
- **A command line** for the same engine: `subvision extract`, `fix` and `preview`, inside the app or from the source tree (see the README).

## What's gone

- **The browser interface** (Streamlit), `run.command` and `requirements.txt`.
- **macOS 10.15–15 and Intel Macs.** 2.0 needs macOS 26 and Apple Silicon. 1.0.0 stays available for older Macs.
- **"Clear /tmp"**: work folders are always removed when a file is done.
- **The `import ocr_core` one-liner**: the command line replaces it.
- **Italian file names.** The review report is now `.review.html`, the reviewed SRT `-reviewed-<date>.srt` and the corrections list `corrections.txt`.

## Updating from 1.0

- **2.0 is a separate app and starts fresh.** It doesn't read the settings or the folders of 1.0, and it doesn't touch them: delete your 1.0 folder when you no longer need it.
- **Your lists:** in Settings › Lists, **Import…** your old `ignore.txt` and `correzioni.txt`; they keep their format.
- **Your SRTs and review reports** stay where they are, and the app opens 1.0 reports too. Edits you made to a report in a browser stay in that browser.
- **Parameters** start from the defaults.

## Which file to download

| File | What it is |
|---|---|
| **`SubVision-v2.0.0-macos-app.zip`** | `SubVision.app`, the native app. Unzip it and drag it into Applications. |

Requires an Apple Silicon Mac (M1 or later) and macOS 26 or later. The first launch downloads Python and the video tools (about 107 MB, each verified by checksum); after that SubVision works offline.

SubVision isn't signed with an Apple Developer ID. If macOS refuses to open it, open **System Settings › Privacy & Security** and click **Open Anyway**.

## What's in the zip

- Only SubVision itself: the app and its engine (the Python code, not Python). Everything else is downloaded from pinned official releases on the first launch.
- FFmpeg is never included: the static build SubVision uses is GPLv3, so it is downloaded on the first launch from [Martin Riedl's macOS builds](https://ffmpeg.martin-riedl.de) and run as a separate program.

SubVision is released under the MIT License.

SHA256:
- `SubVision-v2.0.0-macos-app.zip`: `<SHA256>`

---

**SubVision 2.0: un'app per Mac vera.**

SubVision ora è un'app macOS nativa scritta in SwiftUI. L'interfaccia nel browser della 1.x non c'è più: lo stesso motore, con la lettura multipla e il voto, il raffinamento dei tempi, la banda dei cartelli e il report di revisione, ora gira dentro una finestra che si comporta come ogni altra app del Mac, con i suoi menu, fogli, avvisi, notifiche e avanzamento nel Dock.

Ho disegnato da capo ogni schermata, in chiaro e in scuro, e ho ricostruito l'app intorno al modo in cui la uso davvero: aggiungo i video, controllo le bande, avvio, rivedo. Sono cambiate molte cose, quindi ecco il quadro completo.

## Le novità

### Una finestra, tre pagine

- **Video, Revisione e Sub fix** nella barra laterale, con sotto il nome quello che ogni pagina sta facendo. L'Anteprima si apre in una finestra a sé.
- **Anche una finestra stretta va bene.** Sotto i 1240 pt la barra laterale diventa una barra in alto; sotto i 1000 pt il pannello Parametri scorre sopra la pagina.
- **Chiaro e scuro**, come macOS o scelto nelle Impostazioni, e **italiano e inglese**, che si cambiano al volo.

### Video

- **Aggiungi i video** trascinando file o intere cartelle, o con ⌘O. Le sottocartelle sono incluse, e ciò che non è un video viene saltato con una nota che dice cosa è rimasto fuori. I video restano dove sono: la cartella `./videos` non c'è più, e l'elenco resta fra un avvio e l'altro.
- **Una riga viva per il file in corso**, con le sue tappe (Estrazione, Raggruppamento, OCR, Raffinamento) per la banda dei dialoghi e quella dei cartelli, ognuna con il suo avanzamento, il tempo che manca e la velocità. Le tappe ancora da fare mostrano una stima presa dal file precedente.
- **Ferma il file in corso o Ferma tutto**, che nella 1.x non c'erano. Un file fermato non lascia mai un SRT scritto a metà, e il lotto passa al successivo.
- **L'esito resta sulla riga**: fatto, fatto senza sottotitoli, fallito (a quale tappa e perché, con il suo log a un clic) o fermato. **Elabora di nuovo** per rifare un file.
- **Fine del lotto:** un foglio con gli SRT creati e **Rivedi** per ognuno, una notifica di macOS, e l'avanzamento sull'icona del Dock mentre gira. Chiudere la finestra non ferma il lotto; ⌘Q prima chiede.

### Il pannello Parametri

- **Tutte le impostazioni dell'OCR in tre schede**, Lettura, Bande e Righe, accanto all'elenco invece che in una lunga barra laterale. Ogni valore ha la sua spiegazione e il suo predefinito, un puntino segna le schede cambiate, e **Ripristina** le riporta indietro (⌘Z lo annulla).
- **Restano fra un avvio e l'altro.** Nella 1.x si perdevano a ogni ricarica.
- **La lingua dell'OCR è un menu** con le lingue che Vision legge sul tuo Mac, invece di un campo libero che, con una lingua sconosciuta, dava un SRT vuoto senza errore.

### Anteprima

- **Una finestra a sé** (⌘Y da una riga), con accanto il pannello Parametri.
- **Trascini le bande sul fotogramma**: l'altezza dal bordo, la larghezza dai lati, e i valori cambiano anche nel pannello.
- **Trova 20 fotogrammi** cerca fotogrammi con testo in 20 zone del video e parte da sola; le miniature, in due righe da dieci, dicono quali fotogrammi hanno dialoghi, cartelli, tutti e due o niente.
- **Prova OCR** (⌘T) mostra le due bande affiancate, con il testo letto, confidenza e accordo, le letture alternative e il testo finale. I risultati restano legati al loro fotogramma e dicono quando un parametro cambiato li rende superati.

### Revisione

- **Una pagina Revisione** con ogni video elaborato, le sue righe, le righe scartate, i buchi senza sottotitoli e quando è stato elaborato.
- **Il report di revisione si apre in una finestra dell'app** (⌘R). **Salva SRT revisionato** scrive il file accanto all'originale, senza dialogo di salvataggio e senza passare dalla cartella Download. Le modifiche si salvano man mano in `<video>.review.json`, quindi chiudendo e riaprendo restano.
- Il report è ancora un semplice file HTML che funziona nel browser, e segue la lingua dell'app. Si aprono anche i report fatti dalla 1.x (File › Apri un report…).

### Sub fix

- **Trascina un `.srt` o aprilo** (⇧⌘O), scegli cosa correggere, **Esegui Sub fix** (⌘↩). La copia corretta va accanto all'originale.
- **I valori condivisi con Video** (intervallo di unione, a capo, lingua, i due elenchi) stanno nella stessa pagina, e Sub fix funziona anche durante un lotto.

### Impostazioni e primo avvio

- **Impostazioni (⌘,)** in quattro schede: Generali, Strumenti, Elenchi, Aggiornamenti, con il predefinito scritto sotto ogni voce.
- **Niente da installare a mano.** Al primo avvio una finestra scarica uv e Python, FFmpeg e FFprobe 9.0.2 (circa 107 MB), ognuno da una release fissata e controllato con il suo SHA256, con l'avanzamento e un Riprova che riparte da dove si era fermato; poi Vision prepara i suoi modelli (circa 30 secondi, una volta per ogni versione di macOS). Da lì SubVision funziona offline.
- **Un FFmpeg tuo**, se preferisci: quello di Homebrew, o una cartella qualsiasi che contenga sia `ffmpeg` sia `ffprobe`.
- **Elenchi** (`ignore.txt`, `corrections.txt`) modificati dalle Impostazioni, con Importa… e un modo per tornare agli elenchi di base.

### Tutto il resto

- **Menu e scorciatoie:** i menu File, Modifica, Vista, Elabora, Finestra e Aiuto, e le scorciatoie per le azioni più comuni.
- **Avvisi nello stile di SubVision:** rossi per ciò che ferma il lavoro, gialli per ciò che chiede attenzione, blu per le informazioni.
- **Una riga di comando** per lo stesso motore: `subvision extract`, `fix` e `preview`, dentro l'app o dai sorgenti (vedi il README).

## Cosa è sparito

- **L'interfaccia nel browser** (Streamlit), `run.command` e `requirements.txt`.
- **macOS 10.15–15 e i Mac Intel.** La 2.0 richiede macOS 26 e Apple Silicon. La 1.0.0 resta disponibile per i Mac più vecchi.
- **«Svuota /tmp»**: le cartelle di lavoro si tolgono sempre quando un file è finito.
- **La riga `import ocr_core`**: la sostituisce la riga di comando.
- **I nomi di file in italiano.** Il report di revisione ora è `.review.html`, l'SRT revisionato `-reviewed-<data>.srt` e l'elenco delle correzioni `corrections.txt`.

## Aggiornare dalla 1.0

- **La 2.0 è un'app a sé e riparte da capo.** Non legge le impostazioni né le cartelle della 1.0, e non le tocca: cancella la cartella della 1.0 quando non ti serve più.
- **I tuoi elenchi:** in Impostazioni › Elenchi, **Importa…** i vecchi `ignore.txt` e `correzioni.txt`; il formato resta quello.
- **I tuoi SRT e i report di revisione** restano dove sono, e l'app apre anche i report della 1.0. Le modifiche fatte a un report in un browser restano in quel browser.
- **I parametri** ripartono dai predefiniti.

## Quale file scaricare

| File | Cos'è |
|---|---|
| **`SubVision-v2.0.0-macos-app.zip`** | `SubVision.app`, l'app nativa. Scompattalo e trascinala in Applicazioni. |

Richiede un Mac con Apple Silicon (M1 o successivi) e macOS 26 o successivi. Il primo avvio scarica Python e gli strumenti video (circa 107 MB, ognuno controllato con il checksum); da lì SubVision funziona offline.

SubVision non è firmata con un Apple Developer ID. Se macOS si rifiuta di aprirla, apri **Impostazioni di Sistema › Privacy e sicurezza** e fai clic su **Apri comunque**.

## Cosa c'è nello zip

- Solo SubVision: l'app e il suo motore (il codice Python, non Python). Tutto il resto si scarica al primo avvio da release ufficiali fissate.
- FFmpeg non è mai incluso: la build statica che SubVision usa è GPLv3, quindi si scarica al primo avvio dalle [build per macOS di Martin Riedl](https://ffmpeg.martin-riedl.de) e gira come programma separato.

SubVision è rilasciata con licenza MIT.

SHA256:
- `SubVision-v2.0.0-macos-app.zip`: `<SHA256>`
