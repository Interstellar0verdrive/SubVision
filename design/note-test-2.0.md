# Note di test · SubVision 2.0 (app nativa)

**13/11/2026** · ramo `native-2.0`, commit `0a83ac5` (fusione dei quattro rami di F5) · build Debug · revisione 5.5 (Opus, solo occhio: nessuna modifica al codice).

Come è stata fatta: app vera lanciata con una cartella di stato propria (`~/Library/Application Support/SubVision-f5-review`), pilotata da `DebugQA` e guardata nella finestra reale (catture di finestra, non `ImageRenderer`), in scuro e in chiaro, in italiano e in inglese, a 1360×840 e a 760×640. Lotti veri sulle clip demo (profilo veloce, 3–4 file, con Ferma, Ferma tutto, video aggiunto durante il lotto, lingua non supportata), Anteprima con ricerca e prova OCR vere, Sub fix con SRT buono, vuoto, illeggibile e file non `.srt`, report 2.0 e report della 1.x (ponte iniettato), report sparito. Avvisi O1, O2, O7 aperti dai pulsanti veri (AXPress). Catture nuove in `design/snapshot/f5/review/`.

Gravità: **piccola** = un agente la corregge in pochi minuti · **media** = per 6.1 · **decisione** = spetta all'utente. Ogni voce: tavola · cosa fa l'app · cosa dice la tavola (misura se c'è) · gravità · stato.

---

## Elabora (E1–E7, O1, O2)

Corrisponde alle tavole: intestazione con descrizione, colonne Durata/FPS/Dimensioni (Dimensioni sparisce con l'inspector), striscia "Trascina qui altri video o cartelle", riga in corso con tappe per banda (spunta, barra, "50 / 309 · ETA 0:09 · 28 fps"), riga in attesa con "circa 16 s (dal file precedente)", riga fatta con "12 righe · 16 s" e Apri report + ⋯, chip "SRT già presente" dopo un primo giro, "1 pronto per il prossimo lotto" quando si aggiunge un video durante il lotto (dubbio 10), Ferma tutto con ⌘. nella barra in basso, scheda attività in barra laterale, foglio di fine lotto "3 SRT pronti" / "4 SRT pronti" con Apri report, Mostra gli SRT nel Finder e OK, righe fermate con "Fermato durante OCR ×1 · dialoghi. Nessun SRT a metà." ed Elabora di nuovo, "Lotto fermato · 2 fermati · 2 pronti", avvisi O1 e O2 (testi identici alle tavole, Ferma rosso pieno, Continua). **"12 righe" sono 12 cue** (l'SRT ha 54 righe di testo): il conteggio è giusto, e l'SRT dell'italiano è identico byte per byte a quello della release `demo-assets`.

1. **E2/I1 · pulsante dell'inspector sparisce su Elabora quando l'inspector è aperto.** L'intestazione mostra solo "Apri video…"; la tavola ha anche il pulsante `sidebar.right` (acceso). In Anteprima invece c'è. Causa: `compact` di `ProcessView.swift:62` include `model.inspectorOpen` e la riga 36 nasconde `InspectorButton` quando è `compact`. Basta legare il pulsante solo alla larghezza della finestra. — **piccola** · [fatto 13/11 dal coordinatore: pulsante legato alla larghezza della finestra]
2. **O1 · "Ferma" può fermare un altro file.** L'avviso è modale (`runModal`) e, mentre è aperto, gli eventi del motore non vengono letti (vedi 3); alla conferma `stopCurrentFile` chiama `stop(all: false)` (`AppModel+Run.swift:194-199`), che ferma il file in corso *per il motore*, non quello nominato nell'avviso. Se il file nominato è finito mentre l'avviso era aperto, si ferma il successivo. Controllare in app non basta (il modello è fermo al file vecchio): serve `batch.stop` con l'id del file (vedi "Richieste al motore"). — **media** · [fatto 13/11 · `991350f`, `6fa3df6`: l'avviso non è modale e Ferma manda `batch.stop` con l'indice del file nominato; se nel frattempo è finito il motore risponde `not_running` e non ferma il successivo (scenario QA 03)]
3. **O1/O2 · con l'avviso aperto il lotto sembra fermo.** Con "Fermare tutto il lotto?" aperto per circa due minuti, la riga è rimasta a "230 / 294 · ETA 0:02" mentre il trascorso andava avanti (2:35 → 2:39); il motore intanto ha finito tutti e quattro i file, e alla chiusura (Continua) la lista è passata in un colpo a "4 fatti". Anche Dock e notifiche restano fermi. È il `runModal` sincrono di `SVAlert` che blocca il consumatore degli eventi sul MainActor (anche i comandi `DebugQA` restano in coda). Da decidere: avviso come foglio asincrono, oppure lasciare così ma tenere il consumatore fuori dal ciclo modale. — **media** · [fatto 13/11 · `991350f`: O1 e O2 con `SVAlert.present`, senza ciclo modale: righe, Dock e notifiche vanno avanti sotto l'avviso, che si chiude da solo se il file o il lotto finisce; anche O4, O7, O8 e gli errori (`a026056`)]
4. **E6 · a fine lotto l'app salta su Elabora.** Da Anteprima (e da Sub fix) la fine del lotto porta la finestra su Elabora per mostrare il foglio (`AppModel+Run.swift:345`, `if worthASheet { tab = .process }`), anche se si stava lavorando su un'altra pagina. La tavola dice solo che il foglio "si apre alla fine del lotto (o alla riapertura, se non visto)". Alternativa: mostrare il foglio quando si torna su Elabora (il riepilogo resta "non visto"), oppure un avviso nella barra laterale. — **decisione** · [da fare]
5. **E1/E2 · nomi lunghi su due righe.** "Sintel episodio lungo con un nome molto lungo per la riga.mp4" va a capo su due righe (con l'inspector aperto, e con il chip "SRT già presente" finisce in "…per la riga.…" e l'estensione sparisce); le tavole hanno una riga sola. `ProcessRows.swift:60` ha `lineLimit(2)`; il foglio di fine lotto tronca al centro ("Sintel episodio lungo con…olto lungo per la riga.mp4"). Proposta: `lineLimit(1)` con `.truncationMode(.middle)` come nel foglio. — **piccola** · [fatto 13/11 dal coordinatore: `lineLimit(1)` con troncamento al centro]
6. **E3 · colonna File della riga aperta.** Nell'app la colonna FILE parte subito dopo TEMPI (x≈511 a 1360 pt), nella tavola è allineata sotto la colonna Durata (x≈886); con l'inspector aperto i nomi dei file si troncano al centro ("sintel_ita_hardsub_d…o_20261113_152055.srt"). Etichetta "Report di revisione" contro "Report" della tavola. — **piccola** · [fatto 13/11 · `3cd472b`: due colonne larghe uguali, FILE parte a metà riga; nomi troncati solo se non ci stanno; etichetta «Report»]
7. **E5 · righe tornate pronte dopo Ferma tutto.** La tavola scrive "pronto" sotto il nome; l'app non scrive nulla (come in E1, dove la tavola non lo scrive). Da allineare: o "pronto" anche nell'app dopo Ferma tutto, o via dalla tavola. — **piccola** · [fatto 13/11 · `3cd472b`: le righe tornate pronte dopo Ferma tutto scrivono «pronto»; in E1 resta vuoto]
8. **E2 · scheda attività con la barra di avanzamento.** L'app aggiunge una barra sotto "File 2 di 3 · nome"; la tavola E2 non ce l'ha (solo testo, "Fine verso le…", Ferma tutto). La barra è utile; va solo deciso se tenerla e aggiornare la tavola. — **decisione** · [da fare]
9. **E2/DS3 · tappe finite senza velocità.** "330 fotogrammi in 0:00" senza "· N fps" per Estrazione e Raggruppamento (sulla demo durano meno di un secondo); OCR finita invece ha "308 fotogrammi in 0:12 · 25 fps" come nel dubbio 28. Da riguardare su un episodio vero: se la velocità manca anche con durate lunghe, è un errore. — **piccola** (da verificare) · [fatto 13/11 · verificato nel codice: la velocità compare quando la tappa dura più di un secondo (`StepLine.averageRate`); sulla demo estrazione e raggruppamento durano meno, su un episodio vero no]
10. **E4 · testo dell'errore (stato alimentato a mano, snapshot `f5/E4`).** La riga dice "Fallito durante OCR ×3 · dialoghi: Qualcosa è andato storto: OCRError: Vision request failed (-1) · frame 000412.jpg" su due righe; la tavola: "Fallito durante OCR ×3 · dialoghi: Vision request failed (-1)". Il riquadro sotto le tappe mostra "unknown (OCRError: …)" con il codice grezzo e senza la riga "log: ~/…/nome.log" della tavola. Non riprodotto con un errore vero (serve un video che fallisca a metà): da rifare in 6.1 con lo scenario "video corrotto". — **media** · [fatto 13/11 · `6fa3df6`, `e808320`: errore vero nello scenario QA 04 (video danneggiato, ffmpeg si arrende): la riga dice la tappa e il testo corto del motore («ffmpeg exited with status 69: Decode error rate … exceeds maximum …»), senza «Qualcosa è andato storto» né il nome dell'eccezione; il riquadro ha il dettaglio e «log: …» cliccabile]
11. **E2 · spinner della riga in corso 16 pt** (`StatusCircle`, `Components.swift:471`) contro 14 della tavola, già nella 9.2.7 (nota 38). A occhio nella finestra non disturba. — **decisione** (tenere o portare a 14) · [da fare]
12. **E6 · foglio di fine lotto al centro.** Su macOS 26 il foglio compare staccato e centrato, non appeso al bordo alto come nella tavola: è il sistema, nessuna correzione; solo da sapere per gli screenshot del README. — nessuna · [da fare: aggiornare la tavola se serve]
13. **E3 · doppio clic su una riga finita apre il report** (scelta dell'agente di 5.1, non nelle tavole). Non provato con il mouse (vedi in fondo). Da confermare con l'utente se lo vuole. — **decisione** · [da fare]
14. **E1/E3 · peso del nome del file.** Nell'app il nome è `.medium` 12,5 pt e appare più marcato del "regular" della tavola; con quattro righe la lista è un po' più pesante delle tavole. — **piccola** (da valutare) · [fatto 13/11 · `3cd472b`: peso regolare, come nelle tavole]

## Inspector (I1–I3)

Corrisponde: gruppi OCR, Banda dialoghi, Banda cartelli (interruttore nell'intestazione), Segmenti, Avanzate; puntino d'accento sui valori cambiati e "Predefinito" in accento solo sui gruppi cambiati (dubbio 14); menu ⋯ e ×; nota blu "Bloccati durante il lotto" e controlli attenuati durante il lotto; nota gialla e menu della lingua evidenziato con una lingua che Vision non ha (I3, provato con `la-VA`); valori in `it` con la virgola, in `en` con il punto; `qcConfWarn`/`qcAgreeWarn` non esposti, come dice l'inventario (riga 154: "restano non esposti").

15. **I1 (E2, A6) · interruttore "Banda cartelli" non attenuato durante il lotto.** È disabilitato ma resta bianco pieno, mentre il resto del gruppo è al 45 %: sembra ancora attivo. `InspectorView.swift:358` ha `.disabled(locked)` senza `.opacity(locked ? 0.45 : 1)`. Cattura: `review/A6-interruttore-cartelli-non-attenuato-dark.png`. — **piccola** · [fatto 13/11 dal coordinatore: `.opacity` sul gruppo dell'interruttore]
16. **I1/I2 · nome della lingua.** Il menu mostra "Italiano (Italia) it-IT", la tavola "Italiano it-IT" (il codice in grigio dice già la regione). Proposta: nome della sola lingua quando nell'elenco di Vision c'è una sola variante, nome completo solo per le lingue con più varianti (zh-Hans/zh-Hant, pt-BR…). — **piccola** · [fatto 13/11 · `3cd472b`: «Italiano» quando Vision ha una sola variante, il nome intero per zh-Hans/zh-Hant, pt-BR…; vale anche per O7]
17. **I3 · "Scegli la lingua" di O7** apre/lascia aperto l'inspector ma non apre il menu della lingua (la tavola dice "apre l'inspector sul menu della lingua"). Con il controllo in background non si può vedere se il menu riceve il fuoco: da riprovare a mano. — **piccola** (da verificare) · [fatto 13/11 · `3cd472b`: «Scegli la lingua» apre l'inspector sul gruppo OCR e poi il menu della lingua (scenario QA 05); da guardare una volta a mano]

## Anteprima (A1–A6)

Corrisponde: menu Video, "Trova 20 fotogrammi" primario poi "Cerca di nuovo" secondario, stato vuoto, fotogramma con le due bande e le linguette "Cartelli"/"Dialoghi" (dubbio 4), maniglie bianche, frecce, "Fotogramma 8 di 20 · 00:00:20" con il badge "Testo nei dialoghi", striscia di 20 miniature con il puntino, "20 fotogrammi · 19 con testo, 1 senza (zone mute del video)", i due pannelli della prova OCR (testo votato, confidenza e accordo, testo finale in mono, "‹vuoto›" e "Nessun testo in questa banda."), A6 durante il lotto (nota blu, maniglie e prova spente, menu Video e ricerca spenti). Ricerca vera in pochi secondi, prova OCR vera in 100 ms.

18. **A1/A3 · "Trova 20 fotogrammi" spento per un video già elaborato.** `canFindFrames` richiede `video.state == .ready` (`AppModel+Preview.swift:84-86`): dopo un lotto (stato `done`, ma anche `noSubs`, `failed`, `stopped`) la ricerca non parte più, e "Cerca di nuovo" resta grigio. È proprio il caso d'uso del "SRT vuoto, controllo le bande in Anteprima" (E3 lo suggerisce). Va bene ogni video leggibile e non in corso. Cattura: `review/A1-trova-spento-video-fatto-dark.png`. — **piccola** · [fatto 13/11 dal coordinatore: ogni video leggibile e non in corso (`state != .unreadable`)]
19. **A4 · "1 varianti" e "OCR con voto" con il voto spento.** Con "Lettura multipla con voto" spenta (profilo veloce) il pannello dice "OCR con voto · 102 ms · 1 varianti" (EN "Voting OCR · … · 1 variants"). La chiave `app.preview.vote` non ha la coppia `.uno/.altri` e il testo non cambia quando le varianti sono 1. Proposta: chiave plurale e, con una sola variante, "OCR singolo · 102 ms" / "Single OCR · 102 ms" (`OcrTestPanels.swift:83`, cataloghi `it` e `en`). Cattura: `review/A4-1varianti-voto-spento-dark.png`. — **piccola** · [fatto 13/11 dal coordinatore: chiave plurale `app.preview.vote.uno/.altri` ("1 variante"); il testo "OCR singolo" non è stato cambiato]
20. **A1 · descrizione stretta con l'inspector aperto.** In A1 con l'inspector aperto la descrizione della pagina sta in una colonna di ~220 pt a sinistra del menu Video e va a capo in quattro righe; nella tavola (senza inspector) è su due righe larghe. Proposta: descrizione a tutta larghezza sotto la riga del titolo, come in Elabora. — **piccola** · [fatto 13/11 · `3cd472b`: con l'inspector aperto la descrizione va sotto la riga del titolo, a tutta larghezza]
21. **A3 · larghezza del fotogramma.** A 1360 pt senza inspector il fotogramma arriva a 940 pt (resoconto 5.2), nella tavola A3 è 640 (con inspector: app 672, simile). Con l'inspector e dopo la prova OCR (A4) scende a ~370 pt e le maniglie diventano piccole. Da decidere se fissare un massimo (640–720) o lasciarlo crescere. — **decisione** · [da fare]
22. **A3 · posizione di "Prova OCR su questo fotogramma".** L'app lo mette subito sotto la striscia delle miniature (y≈633 a 840 pt di finestra), la tavola in fondo alla pagina (y≈887). Da allineare in un senso o nell'altro. — **piccola** · [fatto 13/11 · `3cd472b`: «Prova OCR su questo fotogramma» in fondo alla pagina, come nella tavola]
23. **A3 · sottotitolo della barra laterale troncato.** "19 di 20 fotogrammi con t…" (la tavola fa stare "15 di 20 fotogrammi con testo"). In inglese "19 of 20 frames with text" ci sta. Proposta: "19/20 con testo" o testo più corto in `it`. — **piccola** · [fatto 13/11 · `3cd472b`: in italiano «19 su 20 con testo»]
24. **A3 · trascinamento vero delle maniglie** non provato (vedi in fondo); la funzione che il gesto chiama è provata dall'agente di 5.2. — [da fare a mano]

## Sub fix (F0–F3)

Corrisponde: scheda del file con nome, cartella, "12 righe · 0:52" e Cambia…, "COSA CORREGGERE" con i quattro controlli e Durata minima attenuata quando i flash restano, nota dei parametri condivisi con "Mostra i parametri", Esegui Sub fix con ⌘↩, nota verde "Creato: …-fixed-20261113_152312.srt (12 righe)" con Mostra nel Finder e Apri, "Creato · 12 righe" nella barra laterale, F3 (nessun segmento valido; SRT illeggibile "la riga 1 non ha i tempi"; "Sub fix accetta solo file .srt.") una nota alla volta, larghezza del contenuto 720 pt come nella tavola. Nella finestra stretta tutto ci sta.

25. **F2 · spunta della barra laterale assente sulla pagina selezionata.** La tavola F2 mostra la spunta verde accanto a "Sub fix" mentre si è su Sub fix; l'app la mostra solo quando si è su un'altra pagina (`MainSplit.swift:183`, `tab.done && tab.id != selection`). Se la scelta è voluta, aggiornare la tavola; altrimenti togliere la condizione. — **piccola** · [fatto 13/11 dal coordinatore: spunta anche sulla pagina selezionata (`MainSplit`)]
26. **F1 · SRT illeggibile accettato senza avviso.** Un file `.srt` che non è un SRT si sceglie senza nota, la scheda dice "0 righe · –" e Esegui è acceso; l'errore arriva solo dopo Esegui. Proposta: con 0 righe lette, nota rossa subito o Esegui spento. — **piccola** · [fatto 13/11 · `3cd472b`: con zero blocchi temporizzati la nota rossa compare subito e Esegui resta spento]
27. **Dubbio 15 · ⌘↩.** Con l'evento vero (`NSApp.sendEvent`, finestra chiave, `fix-menu`) e 4 video pronti: su Sub fix ⌘↩ esegue il fix e il lotto non parte (stati ancora `ready`); su Elabora avvia il lotto e il fix no. Menu: "Avvia" spento su Sub fix, "Esegui Sub fix" spento su Elabora. La pressione fisica dei tasti non l'ho potuta fare (vedi in fondo). — corrisponde · [da confermare a mano]

## Report (R1–R3)

Corrisponde: finestra a sé (1100×780) con l'icona del documento, il nome del file, Mostra nel Finder e Apri nel browser; report 2.0 "bridged" e report della 1.x "legacy" con il ponte iniettato; Salva SRT revisionato scrive `nome-revisionato-20261113-1524.srt` accanto, sia per il 2.0 sia per la 1.x; avviso in basso "SRT revisionato salvato · nome · Mostra nel Finder" (R2); report sparito con la nota rossa e Chiudi, Mostra nel Finder e Apri nel browser spenti (R3); il menu Finestra elenca il report.

28. **R2 · intestazione del report che va a capo dopo il salvataggio.** Per 2–3 s dopo Salva, il "SRT salvato ✓ (percorso)" del report spinge i controlli: titolo su due righe, "12 righe incluse su 12" su quattro, pulsanti alti 67 pt; poi torna normale e la spunta sparisce (la tavola R2 tiene un "✓" accanto a Salva). È il testo del motore (vedi "Richieste al motore"). — **media** (motore) · [fatto 13/11 · `6fa3df6`: con il ponte il report scrive solo «SRT salvato ✓» (il percorso nel tooltip) e la nota ha una larghezza fissa: la barra non va più a capo]
29. **R1 · aspetto del report.** Il contenuto è l'HTML del motore com'è oggi: emoji 🎬 e 💾, pulsante Salva blu (non ciano), legenda dei colori, "100%" senza spazio, tag "cartello ↑ {\an8}" e "originale" sotto ogni riga, testo "Salva SRT revisionato crea nome-revisionato-data.srt accanto al video"; la tavola R1 mostra lo stesso report ripulito (accento ciano, "98 %", niente emoji, una riga di istruzioni). Le tavole dicono "il report di oggi": se l'utente vuole l'aspetto della tavola serve un ritocco del modello HTML del motore. — **decisione** · [da fare]
30. **R2 · nome dell'SRT revisionato al minuto.** Due salvataggi nello stesso minuto danno lo stesso nome; il report chiede di sovrascrivere con `confirm()`, che l'app mostra come avviso blu con il testo come titolo e niente testo sotto (non visto: nella prova la risposta era automatica). Da guardare a mano che l'avviso sia leggibile. — **piccola** (da verificare) · [fatto 13/11 · `b46cf43`: la domanda di sovrascrittura è un avviso dell'app con titolo, testo, Sostituisci e Annulla; da guardare una volta a mano (C2)]

## Avvisi e notifiche (O1, O2, O7, O10)

Corrisponde: O1 "Fermare nome?" e O2 "Fermare tutto il lotto?" con i testi e i pulsanti delle tavole, carta di 280 pt, icona rossa; O7 con "Vision qui legge 33 lingue…", Scegli la lingua (primario) e Annulla.

31. **O7 · nome della lingua in minuscolo a inizio frase.** "latino (Città del Vaticano) non è tra le lingue di questo Mac" (l'inspector scrive "Latino"). `Alerts.swift:117` usa `localizedString` senza la maiuscola che `InspectorView.languageName` aggiunge (riga 176). Cattura: `review/O7-lingua-minuscola-dark.png`. — **piccola** · [fatto 13/11 dal coordinatore: maiuscola iniziale anche nell'avviso]
32. **O1/O2/O7 · icone diverse dalle tavole.** O1 usa il cerchio con il quadrato (`stop-file.svg` di AnimeUp), la tavola un documento con lo stop; O2 cerchio con quadrato e righe contro i due fogli con lo stop; O7 globo con fumetto contro globo con la ×. Fa parte del 9.2.6. — **decisione** · [da fare]
33. **O10 · notifiche e Dock** non verificati (le notifiche non si vedono dal controllo in background; la regola del dubbio 23, una per file solo nei lotti multipli e a finestra non in primo piano, resta da provare). — [da fare a mano]

## Finestra stretta (N1, N2) · 9.2.5

A 760×640 (misura della tavola), scuro e chiaro: barra in alto con pallini, controllo a segmenti (Elabora con la capsula del numero, Anteprima, Sub fix), pulsante dell'inspector e ingranaggio; titolo senza descrizione; colonna Dimensioni sparita; riga in corso con le tappe dialoghi e cartelli che ci stanno ("20 / 308"); inspector sovrapposto da destra (N2) su Elabora e su Anteprima; Sub fix senza pulsante dell'inspector; Anteprima mette le informazioni del fotogramma sotto l'immagine e la pagina scorre. Catture: `review/N2-760-dark.png`, `review/N1-760-light.png`.

34. **N1 · spinner nel segmento Elabora dopo la capsula.** L'app mostra "Elabora ④ ⟳"; la tavola mette lo spinner al posto dell'icona, prima della parola ("⟳ Elabora 3"). — **piccola** · [fatto 13/11 · `3cd472b`: lo spinner prende il posto dell'icona, prima della parola]
35. **N2 · Esc, clic fuori e ⌥⌘I** per chiudere l'inspector sovrapposto non provati (servono tasti e clic veri); l'ombra a sinistra del pannello è appena visibile in scuro. Soglia del dubbio 2 (1000 pt) non provata tra 1000 e 1240 pt. — [da fare a mano]

## Trasversali

Corrisponde: chiaro e scuro (accento ciano in scuro, blu in chiaro come I1-light), cataloghi `it`/`en` senza testi mancanti nelle pagine viste, numeri con la virgola in italiano e il punto in inglese.

36. **9.2.6 · icone SF contro i segnaposto delle tavole.** Barra laterale: Elabora `captions.bubble` (tavola: riquadro con le righe del sottotitolo), Sub fix lista con la spunta, Anteprima `viewfinder` (simile); piè con `</>` al posto dell'octocat; note con i simboli pieni (`info.circle.fill`, `exclamationmark.triangle.fill`, `exclamationmark.circle.fill`) dove le tavole e DS3 hanno i contorni. Da decidere se disegnare glifi propri o aggiornare le tavole ai simboli SF. — **decisione** · [da fare]
37. **Accessibilità in inglese.** Con l'interfaccia in inglese le frecce dell'Anteprima si chiamano "Indietro"/"Avanti" e il pulsante del piè "Aggiorna": sono le etichette predefinite dei simboli SF nella lingua del sistema. Mettere `.accessibilityLabel(model.t(…))` su `PreviewView.swift:273` e sul pulsante di `MainSplit.swift:209`. — **piccola** · [fatto 13/11 dal coordinatore: `accessibilityLabel` sulle frecce e sul pulsante del piè]
38. **9.2.7 · differenze minori rimaste da F4** (non riguardate qui una per una: formato "Ultimo controllo oggi, 12:10", controlli a segmenti di ST1, link di ST4, descrizione di Lingua in ST1): restano come scritte nel piano; la voce sullo spinner è la 11. — [lasciate così 13/11: restano come in 9.2.7, visibili negli snapshot `f6` (ST1, ST4); nessuna blocca]

## Voci nuove di F6 (13/11)

Viste negli snapshot di `design/snapshot/f6/` e negli scenari QA.

39. **R1 · un report nuovo eredita le scelte di uno vecchio** con lo stesso nome di SRT: senza `.revisione.json` la pagina legge `localStorage`, che la WKWebView conservava fra un report e l'altro. — **media** · [fatto 13/11 · `0ad366a`: archivio web non persistente; lo stato vive nel `.revisione.json`]
40. **O9 · «Annulla Annulla Togli»** nel menu Modifica (il sistema aggiunge già «Annulla»). — **piccola** · [fatto 13/11 · `0ad366a`: «Annulla Togli dall'elenco»]
41. **ST1 · Aspetto non segue un cambio di tema fatto altrove** (menu, comando). — **piccola** · [fatto 13/11 · `0ad366a`]
42. **O1–O8 · ombra degli avvisi tagliata** dal bordo del pannello (rettangolo grigio in chiaro). — **piccola** · [fatto 13/11 · `0ad366a`: margine di 84 pt]
43. **N1 · la finestra non scendeva sotto 720×672**: la tavola stretta è 760×640 (finestra intera). — **piccola** · [fatto 13/11 · `a026056`: minimo 720×640, scenario QA 07]
44. **O9 · due «Seleziona tutto»** nel menu Modifica (quello di sistema spento con ⌘A, quello dell'app senza scorciatoia, `Commands.swift:57`). — **piccola** · [da fare in F7]
45. **E1 · la nota «2 elementi saltati» resta** anche dopo aver tolto tutti i video; sparisce solo con la ×. — **piccola** · [da fare in F7]
46. **N1 · a 760 pt le statistiche delle tappe si troncano** con «…» nella riga in corso. — **piccola** · [da fare in F7]
47. **O3 · «Esci e ferma» rosso pieno** (la tavola lo ha primario); **O10** · la prima riga del menu del Dock non è attenuata. — **piccola** · [da fare in F7]

---

## Cose che non ho potuto provare

Il controllo a schermo intero è stato interrotto due volte (l'utente stava usando il Mac), quindi niente tasti né gesti veri; ho usato solo il controllo in background (AXPress sui pulsanti, catture di finestra) e `DebugQA`.

- ⌘↩ e ⌘. premuti sulla tastiera fisica (provato solo con `NSApp.sendEvent`, voce 27); Invio = Ferma ed Esc = Continua sugli avvisi O1/O2.
- Doppio clic su una riga finita (voce 13), menu contestuale delle righe, menu ⋯ "Altre azioni".
- Trascinamento vero delle maniglie delle bande e verifica del valore nell'inspector (voce 24).
- Esc / clic fuori sull'inspector sovrapposto (voce 35).
- Notifiche e barra del Dock (voce 33); O3/O4 (uscita e chiusura con lotto in corso).
- E4 con un errore vero del motore (voce 10); R3 "salvataggio impossibile" (cartella in sola lettura) e l'avviso di sovrascrittura (voce 30).
- Ferma su un file che finisce mentre l'avviso è aperto (voce 2): dedotto dal codice e dal blocco degli eventi visto nella voce 3, non riprodotto fino in fondo.

## Richieste al motore

- **`batch.stop` con l'id del file** (`{"all": false, "file": "<id>"}`): ferma solo se quel file è ancora in corso, altrimenti risponde `ok: false, reason: "not_running"` (voce 2).
- **Messaggio "salvato" del report più corto** (solo "SRT salvato ✓", il percorso nel `title`), oppure non mostrarlo quando il ponte c'è: l'app mostra già il suo avviso (voce 28).
- **Aspetto del report** come la tavola R1 (accento ciano, niente emoji, "98 %", istruzioni in una riga), se l'utente lo vuole (voce 29).
- **Testo dell'errore di una tappa** senza il prefisso "Qualcosa è andato storto:" e con il percorso del log, così la riga e il riquadro di E4 non lo ripetono (voce 10).

## Riepilogo per gravità

- **piccola** (20): 1, 5, 6, 7, 9, 14, 15, 16, 17, 18, 19, 20, 22, 23, 25, 26, 30, 31, 34, 37 — tutte fatte (8 in F5, le altre 12 in F6).
- **media** (4): 2, 3, 10, 28 — fatte in F6.
- **decisione** (8): 4, 8, 11, 13, 21, 29, 32, 36 — restano all'utente (sezione «C2 · cosa provare»).
- Note senza gravità (prove a mano, cose che corrispondono, rimandi): 12, 24, 27, 33, 35, 38.
- Voci nuove di F6 (39–47): fatte 39–43; restano 44–47 (piccole, per F7).

---

## C2 · cosa provare

L'app è in `/Applications/SubVision.app` (build Release di F6, firma ad hoc). Al primo avvio scarica gli strumenti (uv, Python, ffmpeg, circa 110 MB) e prepara Vision. Scrivi le note qui sotto, numerate da 48, con «[da fare]».

**Prove a mano** (non si possono fare da `DebugQA`):

1. ⌘↩ sulla tastiera: su Elabora avvia il lotto, su Sub fix esegue il fix (e non il lotto). ⌘. ferma tutto, con l'avviso.
2. Sugli avvisi Ferma / Ferma tutto: Invio = Ferma, Esc = Continua; con l'avviso aperto le righe devono andare avanti.
3. Doppio clic su una riga finita, menu contestuale delle righe, menu ⋯.
4. Anteprima: trascinare le maniglie delle bande e vedere il valore cambiare nell'inspector.
5. Finestra stretta: Esc, clic fuori e ⌥⌘I chiudono l'inspector sovrapposto; prova anche fra 1000 e 1240 pt di larghezza.
6. Notifiche (una per file solo nei lotti di più video e con la finestra non in primo piano) e barra nel Dock.
7. ⌘Q e chiusura della finestra con un lotto in corso (O3, O4).
8. Report: cartella in sola lettura (nota gialla, «Scegli dove salvarlo…»), due salvataggi nello stesso minuto (avviso Sostituisci: si legge bene?).
9. Lingua non supportata (O7): «Scegli la lingua» apre davvero il menu della lingua?
10. Un episodio vero con i parametri predefiniti: risultato, tempi, velocità delle tappe (voce 9).

**Decisioni** (rispondi con la lettera; oggi l'app fa la prima):

- **Voce 4 · fine lotto mentre sei su Anteprima o Sub fix.** L'app salta su Elabora per mostrare il foglio. (a) sì, come ora; (b) no: il foglio aspetta che tu torni su Elabora; (c) no, e un segno nella barra laterale.
- **Voce 8 · barra di avanzamento nella scheda attività** (non c'è nella tavola E2). (a) tenerla e aggiornare la tavola; (b) toglierla.
- **Voce 11 · spinner della riga in corso.** (a) 16 pt come ora; (b) 14 pt come la tavola.
- **Voce 13 · doppio clic su una riga finita.** (a) apre il report, come ora; (b) non fa nulla; (c) mostra l'SRT nel Finder.
- **Voce 21 · larghezza del fotogramma in Anteprima.** (a) cresce con la finestra, fino a 940 pt, come ora; (b) al massimo 640 pt come la tavola; (c) al massimo 720 pt.
- **Voce 29 · aspetto del report.** (a) l'HTML del motore com'è; (b) come la tavola R1 (accento ciano, «98 %», niente emoji, istruzioni in una riga): un ritocco del modello del motore.
- **Voci 32 e 36 · icone.** (a) i simboli SF di oggi, e si aggiornano le tavole; (b) glifi disegnati come nelle tavole, per barra laterale e avvisi; (c) misto: avvisi disegnati, barra laterale SF. E nel piè: (a) `</>` come ora; (b) il gatto di GitHub.
