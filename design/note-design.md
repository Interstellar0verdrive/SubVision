# SubVision 2.0 · note di design

Note di lavoro della fase F3 (design). Le risposte di C1 vanno scritte sotto ogni dubbio ("Risposta: …"); dove manca una risposta vale la raccomandazione, già applicata nell'inventario (`inventario-app-nativa.md`, i rimandi **[?n]**) e nelle tavole.

## Dubbi aperti per C1

1. **Inspector anche in Anteprima, non in Sub fix.** D5 parla di "inspector a destra della pagina Elabora", ma in Anteprima le bande si trascinano e la prova OCR usa lingua, lettura multipla, confidenza, a capo e correzioni: cambiarli senza tornare in Elabora è comodo. **Raccomandazione:** lo stesso inspector (stessi valori, stesso ⌥⌘I) su Elabora e Anteprima; Sub fix mostra solo una nota con i valori che usa (unione, a capo, lingua, elenchi) e il link "Mostra i parametri" che apre Elabora con l'inspector.
2. **Inspector in finestra stretta.** Con la finestra minima di 720 pt un inspector di 300 pt lascia 420 pt alla pagina. **Raccomandazione:** accanto alla pagina sopra i 1000 pt di finestra; sotto, sovrapposto da destra con ombra, chiuso da Esc, clic fuori o ⌥⌘I (tavola N2). La soglia si verifica in F5.5.
3. **Colore d'accento.** I token arrivano da AnimeUp 2.1 (ciano `#2AC9DE` nello scuro, con la sua controparte chiara già tarata per i contrasti). Un accento diverso darebbe a SubVision una faccia sua ma obbliga a rifare le misure di contrasto nei due temi. **Raccomandazione:** stesso ciano nella 2.0; DS1 mostra accanto un'alternativa per SubVision, da scegliere a C1.
4. **Colori delle bande sul fotogramma.** Oggi dialoghi verdi e cartelli azzurri; nel design system il verde vuol dire "fatto". Sul fotogramma il contesto è diverso e chi viene dalla 1.x li riconosce. **Raccomandazione:** verde e blu come oggi, ognuno con una linguetta col nome ("Dialoghi", "Cartelli") così il colore non deve spiegarsi da solo; i testi nuovi non citano più i colori.
5. **Report di revisione in tema chiaro e nella finestra dell'app.** L'HTML di oggi è solo scuro (`color-scheme: dark`) e il suggerimento in alto parla di Chrome, Edge e Safari e della cartella Download, che nella finestra dell'app non valgono più. **Raccomandazione:** in F1.10 il report prende una palette chiara con `prefers-color-scheme` (la WKWebView segue l'aspetto dell'app, il browser quello del sistema) e il suggerimento cambia quando c'è il ponte ("Salva SRT revisionato lo scrive accanto all'originale"). È lavoro del motore: va messo nel brief di F1.10.
6. **Lingua e autore del log del file.** La regola 1.4 dice che il motore non formatta testi per l'utente, ma il `.log` accanto al video è scritto dal motore e l'utente lo apre ("Apri il log"). Oggi è nella lingua dell'interfaccia. **Raccomandazione:** il log resta del motore, nella lingua passata a `batch.start` (`lang`), con un piccolo catalogo in `batch.py` che eredita le chiavi `step_start`, `step_done`, `step_aborted`, `rate_avg`, `log_error`, `times_summary`, `log_result` e i testi di log di `_CORE_I18N`. Le barre dell'app invece ricevono solo numeri.
7. **Lingua del report.** Il report è generato una volta, nella lingua dell'app al momento del lotto; cambiare lingua dopo non lo traduce. **Raccomandazione:** va bene così (è un file sul disco, come oggi); la descrizione di Impostazioni › Lingua lo dice ("Vale anche per i report di revisione nuovi").
8. **Elenco dei video persistito.** AnimeUp tiene l'elenco fra un avvio e l'altro. Per SubVision è utile per riaprire i report dei lotti passati. **Raccomandazione:** sì, elenco ed esiti restano finché non si tolgono le righe; una riga col file sparito dice "File non trovato" in giallo; "Togli i finiti" pulisce in un colpo.
9. **Cosa elabora Avvia.** Con l'elenco persistito, Avvia non deve rifare i file già fatti. **Raccomandazione:** Avvia elabora solo le righe "pronte"; le righe finite tengono il loro esito; "Elabora di nuovo" (riga, menu contestuale) rimette una riga fatta, fallita o fermata in "pronta".
10. **Video aggiunti durante il lotto.** `batch.start` riceve l'elenco all'inizio; il motore non ha un `batch.add`. **Raccomandazione:** i video trascinati durante il lotto entrano come righe "pronte" per il lotto dopo (nota nella barra: "2 pronti per il prossimo lotto"). Alternativa: aggiungere `batch.add` al protocollo in F1.8 e accodarli (mezzo giorno in più).
11. **Pagine durante il lotto.** Oggi Anteprima e Sub fix sono disabilitate. Il motore fa un lavoro lungo alla volta (`busy`). **Raccomandazione:** Anteprima in sola lettura (si sfogliano i fotogrammi già trovati, niente ricerca, prova o maniglie: i parametri sono bloccati); Sub fix usabile, perché `srt.fix` è breve e non usa Vision. Serve che in F1.8 `srt.fix` non risponda `busy` durante un lotto.
12. **Cosa si blocca nelle Impostazioni durante il lotto.** Il piano (4.3) dice "blocco durante un lotto". **Raccomandazione:** solo Strumenti ed Elenchi (il lotto li usa); Generali (lingua, aspetto, notifiche, Dock) e Aggiornamenti restano libere.
13. **Profilo "Veloce".** Il docstring di `OcrParams` descrive un profilo veloce (fps 6, salto 1, senza lettura multipla né cartelli, ~10–15 min a episodio) che la UI di oggi non offre. **Raccomandazione:** non nella 2.0 (si cambia a mano e "Predefinito" riporta indietro); da riprendere dopo, eventualmente come menu "Profilo" in testa all'inspector.
14. **Come si vede il predefinito nell'inspector.** Nelle Impostazioni ogni voce ha "Predefinito: …" sotto; nell'inspector, con 19 voci in 300 pt, non c'è spazio. **Raccomandazione:** il predefinito sta nel fumetto (?) della voce; un puntino d'accento accanto ai valori diversi dal predefinito; "Predefinito" per gruppo e "Ripristina tutti i predefiniti" nel menu ⋯.
15. **Scorciatoie.** ⌘↩ fa Avvia in Elabora e Esegui Sub fix in Sub fix (due voci di menu con la stessa scorciatoia, mai attive insieme); ⌘R apre il report (in AnimeUp ⌘R era Rianalizza); ⌘T Prova OCR; ⌘. Ferma tutto, ⌥⌘. Ferma il file in corso; ⇧⌘O Apri SRT…, ⌥⌘O Apri un report…. **Raccomandazione:** così; da verificare in F4 che AppKit scelga la voce attiva per ⌘↩.
16. **Spazio sul disco (S9).** I fotogrammi temporanei di un episodio a 12 fps possono arrivare a qualche GB nella cartella di stato. **Raccomandazione:** niente cifra fissa nella riga; nota gialla nella barra in basso solo sotto una soglia (proposta: meno di 10 GB liberi sul disco interno); disco pieno a metà = file fallito con messaggio chiaro.
17. **Barra laterale senza blocco centrale.** Senza "Questo Mac" tra le schede e la scheda attività resta vetro vuoto. **Raccomandazione:** lasciarlo vuoto (è lo spazio delle schede attività); alternativa da mostrare in DS4: un riepilogo minimo dei parametri ("Italiano · 12 fps · cartelli sì") che apre l'inspector.
18. **Nomi delle tappe.** Oggi: Estrazione fotogrammi, Analisi ridondanza, OCR x3 letture, Raffinamento tempi. La terminologia del piano dice "tappe extract/group/ocr/refine". **Raccomandazione:** etichette corte sulle barre: IT Estrazione · Raggruppamento · OCR ×3 · Raffinamento; EN Extract · Group · OCR ×3 · Refine. Nel fumetto della tappa la frase lunga (cosa fa).
19. **Menu della lingua OCR.** Vision dà codici BCP-47 (anche varianti come `zh-Hans`, `zh-Hant`, `pt-BR`). **Raccomandazione:** nomi nella lingua dell'app (`Locale.localizedString`), ordine alfabetico, codice in grigio a destra, predefinito `it-IT`; i valori di testo della 1.x ("Italian", "italiano") non si migrano (nessuna migrazione dalla 1.x). Lingua salvata che il Mac non ha più → nota gialla nell'inspector e avviso O7.
20. **"Un ffmpeg mio".** **Raccomandazione:** si sceglie l'eseguibile `ffmpeg` o la sua cartella; `ffprobe` deve stare nella stessa cartella (caso Homebrew); la riga dice la versione trovata. Niente versione minima imposta. Se `-version` non risponde la riga è rossa e il lotto non parte: compare l'avviso O5b ("Usa quelli scaricati" / "Scegli…"), così l'app non cambia strumento in silenzio.
21. **"Svuota /tmp" sparisce.** Serviva anche per il debug (tenere i fotogrammi). **Raccomandazione:** nessun controllo nell'app; per il debug una variabile d'ambiente del motore (`SUBVISION_KEEP_WORK=1`), documentata in `macos/Native/README.md`.
22. **Conferma del salvataggio dell'SRT revisionato.** Il ponte con risposta (spike S2) permette al report di dire "SRT salvato in …"; l'app può anche mostrare un avviso nativo con "Mostra nel Finder". **Raccomandazione:** entrambi: il report mostra il suo "salvato ✓" come oggi, la finestra un avviso nativo in basso con il nome del file e Mostra nel Finder, che sparisce dopo qualche secondo.
23. **Quante notifiche.** Con lotti lunghi una notifica per file può essere troppa. **Raccomandazione:** una per file solo nei lotti di più file e solo se la finestra non è in primo piano; quella di fine lotto sempre (se le notifiche sono accese).
24. **Preparazione del riconoscimento dopo il primo avvio.** **Chiuso dallo spike S5 (13/11):** i ~30 s non sono un download e non dipendono dalla lingua (it, en, ja, ko, uk: 0,1–0,2 s ciascuna dopo il primo); è la compilazione dei modelli per il Neural Engine, in cache in `~/Library/Caches/<eseguibile>/…/<build di macOS>`: una volta per utente, di nuovo dopo un aggiornamento di macOS o se si svuotano le cache; se si chiude durante la preparazione la cache non si scrive e si rifà la volta dopo. Quindi: la riga 4 della finestra strumenti compare al primo avvio e dopo un aggiornamento di macOS ("una volta per ogni versione di macOS, circa 30 secondi"), mai per un cambio di lingua; nessuna scheda attività nella barra laterale; chiudendo durante la preparazione nessun avviso, solo la nota sulla riga ("Se chiudi ora, la preparazione ripartirà al prossimo avvio"). Tavole T2 e T4; inventario §0 e §1 aggiornati. Il menu della lingua OCR ha le 33 lingue del livello "accurate" (tavola I2).

### Dubbi nuovi emersi disegnando (3.2)

25. **Misura della finestra principale.** Il brief di 3.2 diceva 1240 × 780; ho usato **1360 × 840**, la misura di avvio di AnimeUp (`WindowSizer.toMain`, verificata nel codice). A 1240 la barra laterale c'è ancora (si piega sotto i 1240) e con l'inspector aperto la pagina resta di 696 pt. **Raccomandazione:** avvio a 1360 × 840, minima 720 × 640, piega sotto i 1240 come AnimeUp.
26. **Colonna Dimensioni con l'inspector aperto.** Con barra laterale e inspector la pagina è di 816 pt: durata, fps, dimensioni e due pulsanti non ci stanno. **Raccomandazione:** con l'inspector aperto (e nella finestra stretta) la colonna Dimensioni sparisce; la risoluzione resta nel fumetto della riga (tavole E2, I1, N1).
27. **Plurali.** Le tavole mostrano i testi con un valore fisso ("1 fatto", "3 SRT pronti"); i cataloghi di 3.3 avranno le forme `.uno` / `.altri` come AnimeUp (per esempio `app.bar.finished`, `app.fin.title_*`, `app.side.videos*`).
28. **Righe delle tappe.** Con il trascorso, l'ETA e la velocità la colonna dei numeri non ci stava nella pagina stretta. **Raccomandazione:** nella tappa in corso solo conteggio, ETA e velocità ("10.565 / 17.040 · ETA 23:40 · 4,5 fps"); il trascorso del file sta in testa alla riga; la tappa finita dice totale, durata e velocità media (tavole E2, DS3).
29. **Ferma tutto in due posti.** Durante il lotto Ferma tutto è sia nella scheda attività della barra laterale sia nella barra in basso di Elabora (e nel menu del Dock). **Raccomandazione:** tenerli tutti (la barra laterale si vede da ogni pagina, la barra in basso è dove si guarda il lotto, il Dock quando la finestra è chiusa); nella finestra stretta la scheda attività non c'è e resta la barra in basso (N1).
30. **Miniature dell'Anteprima.** La striscia di 20 miniature sotto il fotogramma (A3) non richiede un cambio di protocollo: l'app le ricava dai fotogrammi interi di `preview.done`. Da confermare in F5.2 che non pesi (20 JPEG piccoli).
31. **Icone.** Nelle tavole le icone sono segnaposto (SVG semplici al posto dei simboli SF; per gli avvisi: stop-file, stop-all, quit, window-close riprese come idea da AnimeUp; tool-missing, vision, language, list nuove). Quelle definitive arrivano in F4, disegnate per SubVision.

### Dubbi del 3.1 nelle tavole

| Dubbio | Dove si vede | Stato |
|---|---|---|
| ?1 inspector in Anteprima, non in Sub fix | A3 (inspector aperto, l'altezza cambia nei due posti), F1 (nota con “Mostra i parametri”) | visibile, da confermare |
| ?2 inspector sovrapposto sotto 1000 pt | N2 | visibile |
| ?3 accento | DS1 (A di AnimeUp, B proprio di SubVision) | da scegliere a C1 |
| ?4 colori delle bande | DS1, A3, A4 (verde e blu con linguetta) | visibile |
| ?5 report in chiaro e suggerimento adattato | R1–R3 in chiaro mostrano la palette proposta e il testo del suggerimento nuovo | visibile, lavoro di F1.10 |
| ?6 log del file | E3, E4 (Apri il log; il log non si vede nelle tavole) | invariato |
| ?7 lingua del report | ST1 (descrizione della Lingua) | visibile |
| ?8 elenco persistito | E3, E5 (righe finite che restano) | visibile |
| ?9 Avvia solo sulle righe pronte | E3 (Avvia spento, Elabora di nuovo), E5 (Avvia acceso per la riga tornata pronta) | visibile |
| ?10 video aggiunti durante il lotto | E2 (chip “2 pronti per il prossimo lotto” nella barra) | visibile |
| ?11 Anteprima in sola lettura, Sub fix libera | A6, F0–F3 (nessun blocco) | visibile |
| ?12 Impostazioni bloccate solo in parte | ST5 | visibile |
| ?13 niente profilo Veloce | I1 (nessun menu Profilo) | invariato |
| ?14 predefinito nell'inspector | I2 (puntino, Predefinito attivo, fumetto con predefinito e intervallo) | visibile |
| ?15 scorciatoie | O9 | visibile |
| ?16 spazio su disco | E7 | visibile, soglia da fissare |
| ?17 barra laterale senza blocco centrale | DS4, tutte le pagine | visibile |
| ?18 nomi delle tappe | E2, DS3 (Estrazione · Raggruppamento · OCR ×3 · Raffinamento) | visibile |
| ?19 menu della lingua | I2 (33 lingue, nome e codice) | visibile |
| ?20 un ffmpeg mio | ST2 (destra), O5 | visibile |
| ?21 Svuota /tmp | — (nessun controllo) | invariato |
| ?22 conferma del salvataggio | R2 | visibile |
| ?23 quante notifiche | O10 | visibile |
| ?24 preparazione del riconoscimento | T2, T4 | chiuso (S5) |

## Tavole

> **14/11/2026:** la cartella `design/tavole/` (tavole HTML e PNG di F3) è stata tolta dal ramo: le tavole definitive, approvate, sono nel file di design https://claude.ai/artifact/6hPbiA85ZJxGauwq1w4evQ (scuro e chiaro, «Native screens»). Quello che segue descrive le tavole di F3 com'erano; il controllo dei cataloghi è ora `python3 -I tools/check_locales.py`.

Pagine HTML in `design/tavole/` (aprire `index.html`): ognuna con il selettore Chiaro / Scuro / Sistema e il selettore EN / IT; `?theme=light|dark`, `?lang=en|it`, `?board=<codice>`. Token, testo e componenti copiati da AnimeUp 2.1 (`tavole.css`, `tavole.js`, `kit.js`); i testi dell'interfaccia sono tutti in `strings.js` ([inglese, italiano], base di 3.3). PNG in `design/tavole/png/<codice>-light.png` e `-dark.png`, in italiano, rifatti da `screenshot.sh` (Chrome headless; `LANGS="it en"` aggiunge quelli in inglese in `png/en/`). Il fotogramma dell'Anteprima è della clip demo Sintel (© Blender Foundation, CC-BY 3.0), in `design/tavole/img/`.

| Codice | Pagina | PNG |
|---|---|---|
| DS1–DS4 | `ds.html#DS1` … `#DS4` | `png/DS1-light.png` … `png/DS4-dark.png` |
| T1–T5 | `strumenti.html#T1` … `#T5` | `png/T1-light.png` … |
| E0–E7 | `elabora.html#E0` … `#E7` | `png/E0-light.png` … |
| I1–I3 | `inspector.html#I1` … `#I3` | `png/I1-light.png` … |
| A0–A6 | `anteprima.html#A0` … `#A6` | `png/A0-light.png` … |
| F0–F3 | `subfix.html#F0` … `#F3` | `png/F0-light.png` … |
| R1–R3 | `report.html#R1` … `#R3` | `png/R1-light.png` … |
| ST1–ST5 | `impostazioni.html#ST1` … `#ST5` | `png/ST1-light.png` … |
| O1–O10 | `avvisi.html#O1` … `#O10` | `png/O1-light.png` … |
| N1–N2 | `stretta.html#N1` … `#N2` | `png/N1-light.png` … |

L'elenco completo, con titolo e anteprima di ogni tavola, è in `index.html`.

## Convenzioni delle tavole

- Codici: DS design system, T strumenti, E Elabora, I inspector, A Anteprima, F Sub fix, R report, ST Impostazioni, O avvisi e menu, N finestra stretta. Elenco completo in fondo all'inventario (51 tavole).
- Ogni tavola in chiaro e scuro; una lingua per PNG, entrambe nella pagina HTML.
- Componenti e misure di AnimeUp 2.1 copiati in `SubVisionKit` citando la provenienza; nessun legame con AnimeUp.

## Cataloghi (3.3)

`macos/Native/SubVision/Resources/locales/en/app.json` e `it/app.json`: **528 chiavi** per lingua, di cui 32 plurali (64 chiavi `.uno` / `.altri`), JSON piatto ordinato per chiave. Aree: alerts 36, common 24, errors 17, fix 25, inspector 63, menu 45, notify 11, preview 46, process 94, report 10, settings 59, sidebar 32, steps 26, tools 40. Controllo: `python3 -I design/tavole/check_locales.py` (stesse chiavi, stessi segnaposto, coppie di plurali complete, solo `{nome}`, chiavi ordinate e nelle aree note); `design/tavole/build_strings.py` rigenera `strings.js` delle tavole dai cataloghi, che da ora sono la fonte. Glossario e regole di stile in `design/glossario.md`.

Cosa è cambiato rispetto ai testi delle tavole di 3.2:
- chiavi rinominate nelle aree del `Localizer` (`app.side.*` → `app.sidebar.*`, `app.set.*` → `app.settings.*`, `app.insp.*` → `app.inspector.*`, `app.row.*` / `app.bar.*` / `app.fin.*` → `app.process.*`, `app.step.*` / `app.band.*` → `app.steps.*`, ecc.);
- i conteggi sono plurali `.uno` / `.altri` e i conteggi composti sono spezzati in pezzi uniti da `app.common.list_separator` (per esempio "3 video · 1 fallito", "1 fatto · 1 senza sottotitoli · 1 fallito", l'esito della riga);
- i valori d'esempio sono diventati segnaposto (versioni di FFmpeg, Python e SubVision, MB, numero di lingue, nome del file importato, spazio sul disco);
- tolte le scorciatoie dai testi (`(⌘O)`, `(⌥⌘I)`, "Esci con ⌘Q", "Impostazioni (⌘,)");
- tolte le chiavi della scheda attività "Preparo il riconoscimento" (S5);
- aggiunte: le 19 spiegazioni (?) dell'inspector e "Predefinito: … · Intervallo …", le etichette di accessibilità dei pulsanti con sola icona (Impostazioni, inspector, Altre azioni, chiudi la nota, fotogramma precedente/successivo, maniglie delle bande), gli stati delle righe e degli strumenti, i titoli dei pannelli Apri, le spiegazioni delle tappe, i tre flag delle righe (too_short, noise, merged_fade), i 15 codici d'errore del motore più `bad_srt` e `unknown`, versione e GitHub del piè della barra laterale.

Le tavole sono state rigenerate (15 PNG cambiati: E0, E1, E7, O4, O8, O10, ST3, T2) e nessuna mostra chiavi mancanti o segnaposto vuoti, in nessuna delle due lingue.

### Dubbi nuovi (cataloghi)

32. **Testi con il 20 fisso.** "Trova 20 fotogrammi", "In nessuna delle 20 zone…", "Divide il video in 20 zone…" hanno il numero nel testo, perché è una costante del design (D6). Se in F5.2 diventa un parametro, passano a `{n}`.
33. **"1 in corso".** `app.sidebar.running` non è un plurale: il motore elabora un file alla volta.
34. **Menu di sistema.** Ripeti, Taglia, Copia, Incolla, Zoom e le voci di sistema del menu del Dock non stanno nei cataloghi (li localizza macOS); stanno invece le voci nostre (Annulla Togli, Seleziona tutto nell'elenco, Contrai, SubVision ⌘0). Da verificare in F4 che il menu Modifica di SwiftUI non le duplichi.
35. **Nomi delle lingue.** Il menu OCR prende i nomi da `Locale` nella lingua dell'app (nessuna chiave); "English" e "Italiano" del selettore restano ognuno nella sua lingua, come in AnimeUp.
36. **Errori del motore.** Le chiavi `app.errors.<codice>` usano `{detail}`, `{tool}`, `{path}`, `{line}`: in F1.8 il motore deve mandare questi campi nell'errore (oltre a `code`), altrimenti l'app mostra solo il testo senza dettagli.

37. **Icone più grandi (richiesta dell'utente a C1).** Le icone delle tavole sembravano piccole: i segnaposto SVG disegnano dentro circa il 78 % del loro riquadro, mentre un simbolo SF al corpo che `SVDesign` usa riempie quasi tutto il suo. Per far coincidere la misura visibile con AnimeUp e con il codice (`SidebarTab` 14 pt, `ChromeIconButton` 13 pt, `TopBarSegment` 12 pt, pulsanti 12/11/10 pt per grande/normale/piccolo, `NoteView` 14 pt, stato delle righe 10 pt) i riquadri dei segnaposto sono stati ingranditi di circa 1,3×: scheda della barra laterale 15 → 20 (riquadro 26 invariato), ingranaggio e pulsanti dell'inspector 15/16 → 18, segmenti della barra in alto 12 → 15, icone nei pulsanti 11/10 → 15 grande, 13 normale, 12 piccolo, note 15 → 18, cerchio di stato delle righe 10 → 13, spunta e X delle tappe 12 → 14, chevron dei gruppi 11 → 13, ⋯ e × dell'inspector 14/12 → 16/14, piè della barra laterale (aggiorna, GitHub) 11/13 → 14/16, scheda attività 11 → 13 e aggiornamento 12 → 14, link con icona 10 → 12, chevron dei menu a comparsa 10 → 12, spunta delle caselle 10 → 11, frecce dell'Anteprima 14 → 16 (cerchio 30 invariato), schede delle Impostazioni 20 → 24, icone sparse (più, info, errore, documento, cartella, ok) +2. Le icone degli avvisi restano a 40 pt, come `AlertPanel`. **Per l'app non cambia nessuna misura**: i corpi di `SVDesign` restano quelli e le tavole ora mostrano la stessa grandezza visibile; se a C1 le icone sembrano ancora piccole, va alzato il corpo in `SVDesign` (per esempio la scheda a 15 pt e l'ingranaggio a 14 pt) e qui di pari passo. PNG rifatti.

38. **Correzioni dopo C1 (note dell'utente sul canvas).** Tavole approvate, accento ciano confermato (?3 chiuso). Tre ritocchi, misurati sui pixel con Chrome a 2× (`scratchpad/tools/measure.sh`): (a) **etichette dei pulsanti**: nei pulsanti grandi (30 pt) e piccoli (22 pt) la scritta stava 0,5–1 pt più in basso del centro (maiuscole "Ferma", "Scarica": spazio sopra/sotto 10,5/9,5 e 7/6 pt); la causa è la stessa di AnimeUp (l'ascendente di SF Pro arrotondato per eccesso nel box di riga; lì il rimedio era `.btn .t{position:relative;top:-1px}`). Qui l'etichetta sta in uno `<span class="t">` alzato di **0,5 pt** solo nelle misure grande e piccola (ora 10/10 e 6,5/6,5–7; un quarto di punto non viene reso); il pulsante normale (26 pt) era già centrato entro 0,5 pt e non si tocca. Stesso mezzo punto per il testo dei chip (18 pt: da 3,5/3 a 3/3,5). Nell'app `SVLabelStyle` ha già la spinta di 1 pt per i simboli SF: da verificare in F4 sul pixel, con la stessa misura. (b) **Cerchi di stato delle righe** (pronto, in corso, fatto, senza sottotitoli, fallito, fermato, illeggibile; anche le righe della finestra strumenti): cerchio 18 → **22 pt**, simbolo 13 → **14**, colonna 18 → 22, rientro del dettaglio 47 → 51; spinner della riga in corso 14 → 16. Il triangolo di avviso ha un disegno suo (`warnc`), dentro il 68 % del riquadro: 9,5 × 8,2 pt, vertici a 6,2 pt dal centro contro i 10 pt del raggio interno (prima 10,7 × 9,3 in un cerchio da 18: 0,8 pt dal bordo). Spunta, X e quadrato di stop restano entro 8 pt dal centro: nessun simbolo tocca l'anello; l'altro cerchio con simbolo (frecce dell'Anteprima, 30 pt, chevron 16) era già largo. Nell'app: `StatusCircle` 22 pt con simbolo a 14 pt. (c) **Aree di trascinamento** (Elabora vuota, "trascina altri video", Anteprima vuota, Sub fix vuota): tratteggio da 1,5 pt `boxLine` (22 %/25 %) a **2 pt** in un token nuovo `dropLine` (bianco 40 % nello scuro, nero 40 % nel chiaro), raggio 12 invariato; con un file sopra l'area (`.drop.over`, stato non disegnato nelle tavole) il tratteggio diventa accento e il fondo `soft`. Nell'app: `DropArea` con `strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))` nel colore `dropLine`, accento in `.onDrop` hover.


39. **Barra del lotto sull'icona del Dock (nota dell'utente a C1).** Nella tavola O10 chiara il riempimento usava `--primary` del tema chiaro (#0275B6) sul fondo nero al 55 %: quasi invisibile. L'app disegna il Dock una volta sola, non per aspetto (`DockColors.standard`: ciano #2AC9DE). **Applicato:** la tavola usa il ciano in tutti e due i temi, come l'app; il fondo della barra passa dal 55 % al 72 % di nero (anche in `DockColors`), così ciano e fondo si distinguono anche sopra l'icona chiara, che è bianca.

40. **Sfondo tratteggiato delle aree di trascinamento (nota dell'utente a C1).** Oltre al bordo tratteggiato (dubbio 38), l'interno dell'area ha fasce diagonali a 135°: 14 px di fascia e 14 px di spazio, token `dropHatch` = bianco 3,5 % (scuro) / nero 3 % (chiaro). Prima erano righe sottili (2 px ogni 10, 6/5 %): l'utente le ha trovate di disturbo alla lettura; fasce larghe e tenui non spezzano il testo. Con un file sopra l'area (`.drop.over`) il tratteggio lascia il posto al fondo `soft` dell'accento. Per l'app: `DropArea` disegna lo stesso motivo (per esempio un `Canvas` con fasce a 45°, larghe 14 pt con 14 pt di spazio), sotto il bordo `StrokeStyle(lineWidth: 2, dash: [6, 4])`.
