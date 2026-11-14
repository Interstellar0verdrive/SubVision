# Glossario EN/IT · SubVision 2.0

Per chi scrive testi nell'app, nella guida e nelle note di release (F4–F7). I testi dell'app stanno solo nei cataloghi `macos/Native/SubVision/Resources/locales/{en,it}/app.json`: nessun testo fisso nel codice Swift. Dopo ogni modifica ai cataloghi lancia `python3 -I tools/check_locales.py` (stesse chiavi, stessi segnaposto, chiavi ordinate). Le tavole definitive sono nel file di design https://claude.ai/artifact/6hPbiA85ZJxGauwq1w4evQ.

## Regole di stile

1. Chiavi `app.<area>.<nome>`, con le aree `sidebar`, `process`, `inspector`, `preview`, `fix`, `report`, `settings`, `tools`, `alerts`, `menu`, `notify`, `errors`, `steps`, `common`.
2. Segnaposto solo `{nome}`: i numeri, le date e le durate li formatta l'app (`{t}`, `{when}`, `{time}`), mai `{x:.1f}`. Graffe letterali: `{{` e `}}` (per esempio `{{\an8}}`).
3. Plurali con due chiavi `<chiave>.uno` e `<chiave>.altri`, scelte con `{n}`. Per i conteggi composti ("1 fatto · 1 fallito") usa una chiave per pezzo e `app.common.list_separator` (" · ") per unirli.
4. Pulsanti e voci di menu: in inglese le maiuscole dei titoli di macOS ("Show in Finder", "Try Again"); in italiano solo la prima maiuscola ("Mostra nel Finder", "Riprova").
5. Tre puntini "…" (un carattere) solo per le azioni che chiedono qualcosa prima di agire: un pannello, un avviso, un'altra finestra da compilare ("Apri video…", "Importa…", "Scarica…"). Niente puntini per le azioni immediate ("Apri report", "Ferma").
6. Niente scorciatoie nei testi: le mostra il menu. Al loro posto si nomina il menu ("Vista › Mostra inspector") o l'azione ("Esci da SubVision").
7. Titoli degli avvisi come domanda per le conferme ("Fermare tutto il lotto?"), come fatto per gli errori ("FFmpeg non c'è più"); il testo dice cosa succede e cosa resta, in una o due frasi.
8. Seconda persona e verbi diretti: "Trascina qui…", "Scegline un'altra". In italiano il tu, mai il Lei. Nei testi pubblici (guida, README, note di release) la prima persona singolare: "I", mai "we".
9. Apostrofi e virgolette tipografici: ’ “ ” « » (italiano: «» per i nomi di cartella negli avvisi). Spazio tra numero e unità ("28 %", "6 s", "57 MB"); in italiano la virgola decimale ("0,30"), la mette il formattatore dell'app.
10. Gli stessi oggetti si chiamano sempre allo stesso modo (tabella sotto): mai "frame" in italiano nell'app, mai "dialog band" o "subtitle band" in inglese.

## Termini

| English | Italiano | Dove | Note |
|---|---|---|---|
| Process | Elabora | scheda, menu, scheda attività | La pagina e l'azione. "Lotto" è l'insieme dei video di un Avvia. |
| Preview | Anteprima | scheda, menu | |
| Sub fix | Sub fix | scheda, menu | Uguale nelle due lingue. |
| batch | lotto | Elabora, avvisi, notifiche | "Ferma tutto il lotto", "Lotto finito". |
| video / videos | video | ovunque | Invariabile in italiano. |
| frame | fotogramma | Anteprima, tappe, inspector | "fps" resta "fps". |
| dialogue band | banda dialoghi | inspector, Anteprima, tappe | In basso, centrata. Linguetta: "Dialogue" / "Dialoghi". |
| signs band | banda cartelli | inspector, Anteprima, tappe | In alto, con `{\an8}`. Linguetta: "Signs" / "Cartelli". |
| height from the bottom / top | altezza dal basso / dall'alto | inspector, maniglie | In %. |
| centre width | larghezza al centro | inspector, maniglie | Inglese britannico ("centre"), come AnimeUp. |
| step | tappa | Elabora | |
| Extract · Group · OCR ×3 · Refine | Estrazione · Raggruppamento · OCR ×3 · Raffinamento | barre delle tappe, esiti | Codici del motore: extract, group, ocr, refine. "×1" senza lettura multipla. |
| review report | report di revisione | righe, foglio, finestra del report | "Report" da solo nei pulsanti ("Apri report"). |
| revised SRT | SRT revisionato | finestra del report | File `<nome>-revisionato-<data>.srt`. |
| parameters | parametri | inspector | Il pannello si chiama "inspector" in entrambe le lingue. |
| default / defaults | predefinito / predefiniti | inspector, Impostazioni | "Default: 28 %" / "Predefinito: 28 %". |
| Start | Avvia | Elabora, menu | |
| Stop / Stop All | Ferma / Ferma tutto | righe, barra, scheda attività, avvisi | Mai "Interrompi" o "Annulla" per il lotto. |
| stopped | fermato | esiti, strumenti | |
| failed | fallito | esiti, notifiche | "Fallito durante OCR ×3 · dialoghi". |
| done | fatto | esiti, barra | |
| without subtitles | senza sottotitoli | esiti, foglio | Esito giallo: il file è finito ma l'SRT è vuoto. |
| line | riga | righe, Sub fix, report | Una riga dell'SRT (anche su due righe di testo). |
| dropped (in the report) | scartata (nel report) | esiti | Righe tolte ma recuperabili nel report. |
| boundary refined | confine raffinato | esiti | |
| flash | flash | inspector, Sub fix | Riga troppo breve. |
| gap | buco | inspector (report) | Tratto senza sottotitoli. |
| confidence · agreement | confidenza · accordo | prova OCR, report | In %. |
| alternatives | alternative | prova OCR, report | |
| voting OCR | OCR con voto | prova OCR | |
| multiple readings with voting | lettura multipla con voto | inspector | Tre letture: Vision, Vision con contrasto, LiveText. |
| subtitle language | lingua dei sottotitoli | inspector, avvisi | Lingua OCR; diversa dalla lingua dell'app. |
| text recognition | riconoscimento di testo | strumenti, avvisi | Vision di macOS. "Preparing text recognition" / "Preparazione del riconoscimento". |
| tools | strumenti | finestra strumenti, Impostazioni | uv + Python, FFmpeg, FFprobe. |
| engine | motore | stato del motore, Impostazioni | Il sidecar Python. |
| ignore.txt · correzioni.txt | ignore.txt · correzioni.txt | inspector, Impostazioni › Elenchi | Nomi dei file, mai tradotti. "Phrases to ignore" / "Frasi da ignorare", "Automatic corrections" / "Correzioni automatiche". |
| Settings: General · Tools · Lists · Updates | Impostazioni: Generali · Strumenti · Elenchi · Aggiornamenti | finestra ⌘, | |
| Appearance: System · Light · Dark | Aspetto: Sistema · Chiaro · Scuro | Impostazioni › Generali | |
| sidebar · top bar | barra laterale · barra in alto | menu Vista | |
| Show in Finder | Mostra nel Finder | ovunque | |
| Show Log · Open Log in Console | Mostra il log · Apri il log in Console | errori, menu Aiuto | Log dell'app; "Open Log" / "Apri il log" sulla riga è il log del file. |
| Try Again | Riprova | errori | |
| Open Videos… · Open SRT… · Open a Report… | Apri video… · Apri SRT… · Apri un report… | File, pagine | |
| notifications · Dock | notifiche · Dock | Impostazioni, notifiche | |
| too short · noise · merged in a fade | troppo breve · rumore · unita in una dissolvenza | report (flag delle righe) | Codici del motore: too_short, noise, merged_fade. |

I testi del menu che macOS fornisce da sé (Ripeti, Taglia, Copia, Incolla, Zoom, le voci di sistema del menu del Dock come Opzioni ed Esci) non stanno nei cataloghi: li localizza il sistema. Lo stesso vale per i nomi delle lingue del menu OCR (da `Locale`) e per English / Italiano nel selettore della lingua (ognuna nella sua lingua).
