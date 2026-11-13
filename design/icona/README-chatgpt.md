# SubVision icons — handoff to Claude

## File da utilizzare

- `masters/SubVision-Light-1024.png`: versione light, fondo bianco pieno.
- `masters/SubVision-Dark-1024.png`: versione dark, fondo antracite pieno.
- I master sono PNG RGBA sRGB, 1024 × 1024, alpha completamente opaco: nessuna maschera, angoli arrotondati, ombra esterna o sfondo della tavola. Importarli come immagini piatte in Icon Composer; evitare una seconda cornice o ulteriori effetti vetro sul disegno già composto.
- `masters-rounded/`: stessi pixel con maschera squircle continua (superellisse, esponente 5), angoli trasparenti, per README e anteprime. È un'approssimazione geometrica della squircle; la maschera di sistema resta quella applicata da macOS/Icon Composer.
- `SubVision-Light.iconset` e `SubVision-Dark.iconset`: 10 PNG standard ciascuno. Le icone legacy hanno già la maschera; non aggiungerne una seconda.
- `SubVision-Light.icns` e `SubVision-Dark.icns`: contenitori ICNS con 10 rappresentazioni PNG standard. Selezione/integrazione dell'aspetto light/dark da gestire nel progetto; i due ICNS non impostano automaticamente il cambio tema.
- `preview/`: ciascun tema su sfondo chiaro, scuro e a scacchiera; PNG reali a 16, 32 e 64 px; tavola `size-proof.png` con campioni 1:1 e zoom nearest-neighbor.

## Disegno e differenze fra temi

Fotogramma generico in scala di grigi con due righe di sottotitolo. Una lente senza manico mostra frammenti di “About the” / “another day”, orizzontali e ingranditi. Conservati riflesso, curvatura ottica e materiali del concept approvato.

| Elemento | Light | Dark |
|---|---|---|
| Fondo pieno | #FFFFFF | #171717 |
| Accento di riferimento | petrolio #006E84 | ciano #2AC9DE |
| Testo nella lente | antracite, circa #202727 | ciano, circa #2AC9DE |
| Fotogramma | grigi neutri | grigi neutri |

I colori della lente hanno gradienti, riflessi e antialiasing: gli HEX sono riferimenti di palette, non valori uniformi di tutti i pixel. Il bordo light è più scuro per contrastare con il fondo bianco; nella dark il bordo e il testo sono più luminosi e l'interno della lente è scuro.

## Allineamento e margini

Canvas condiviso 1024 × 1024. Fotogramma: x=100, y=180, larghezza=824, altezza=582. Lente: x=383, y=418, larghezza=450, altezza=460. Le stesse maschere e coordinate sono usate in entrambe le versioni; sovrapponendo i file le sagome coincidono. Il disegno importante rimane nella fascia x=100…924, y=180…878, con almeno 100 px dal bordo.

## Provenienza e limiti

Asset raster derivati dal concept approvato, ricomposti su fondi pieni: non un progetto Icon Composer a livelli né originali vettoriali. Fotogramma e lente dei due temi sono stati normalizzati nelle identiche sagome di destinazione; i dettagli raster interni e le luci mantengono le lievi differenze del rendering approvato. La risoluzione nativa degli elementi estratti dalla tavola è inferiore a 1024 px: i master sono ricampionati Lanczos, non nuovi rendering ad alta risoluzione. Lente ellittica e proporzioni sono conservate dal concept.

## Tagli macOS

16×16, 16×16@2x; 32×32, 32×32@2x; 128×128, 128×128@2x; 256×256, 256×256@2x; 512×512, 512×512@2x. Dimensioni fisiche: 16, 32, 32, 64, 128, 256, 256, 512, 512, 1024 px. Nessuna correzione ottica specifica per i tagli piccoli: derivano tutti dallo stesso master per coerenza.
