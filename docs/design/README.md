# Design di Scontrini — specifica per l'implementazione

Questo documento descrive la nuova UI e il nuovo marchio di Scontrini. Serve a chi li implementa in Flutter: dice cosa costruire, con quali valori e dove il design si discosta dal codice attuale.

Il brief di partenza è [`../design-prompt.md`](../design-prompt.md).

> **Fonte visiva.** Le tavole sono su un canvas Claude Design: <https://claude.ai/artifact/CtnxCyrLDNmC7JyVtuH7tZ>. Il link è privato: chiedi al maintainer di condividerlo. Il sorgente delle tavole è anche in [`canvas/`](canvas/) (vedi [Contenuto della cartella](#contenuto-della-cartella)). In caso di dubbio valgono i valori di questo documento e di [`tokens.json`](tokens.json).

## Indice

1. [Contenuto della cartella](#contenuto-della-cartella)
2. [Principi](#principi)
3. [Token](#token)
4. [Tema Flutter](#tema-flutter)
5. [Componenti](#componenti)
6. [Schermate](#schermate)
7. [Navigazione](#navigazione)
8. [Avvisi sui dati](#avvisi-sui-dati)
9. [Logo, icone e splash](#logo-icone-e-splash)
10. [Accessibilità](#accessibilità)
11. [Differenze rispetto al codice attuale](#differenze-rispetto-al-codice-attuale)
12. [Decisioni aperte](#decisioni-aperte)
13. [Checklist di accettazione](#checklist-di-accettazione)

---

## Contenuto della cartella

| Percorso | Cosa contiene |
|---|---|
| `README.md` | Questa specifica. |
| `tokens.json` | Tutti i token in formato leggibile da macchina: colori dei due temi, categorie, tipografia, spaziature, raggi, misure. |
| `brand/icon.svg` | Icona completa 1024 × 1024 con sfondo pieno. Sorgente per iOS e per i PNG. |
| `brand/icon-small.svg` | Variante per 24 px e meno, senza le righe sottili. |
| `brand/adaptive-foreground.svg` | Android adattiva: livello in primo piano, 108 dp, trasparente. |
| `brand/adaptive-monochrome.svg` | Android 13+: icona a tema, monocromatica. |
| `brand/mark.svg` | Marchio con angoli arrotondati, per lo splash e per l'uso dentro l'app. |
| `canvas/*.dc.html` | Sorgente delle tavole del canvas, una per file. È HTML con un runtime proprietario: **non si apre da solo nel browser**, ma ogni valore (colori, misure, testi) è leggibile nel codice. |
| `canvas/canvas.json` | Disposizione delle tavole sul canvas. |

Corrispondenza tra tavole e schermate:

| Tavola | Schermata |
|---|---|
| `Main.dc.html` | Logo, icone, splash |
| `Tokens.dc.html` | Token del design system |
| `Setup.dc.html` | Primo avvio |
| `Home.dc.html` | Movimenti |
| `Scan.dc.html` | Analisi in corso |
| `Receipt.dc.html` | Dettaglio scontrino, con una riga in modifica |
| `Stats.dc.html` | Spese per categoria |
| `Categories.dc.html` | Categorie, con il pannello di modifica aperto |
| `*Light.dc.html` | La stessa schermata in tema chiaro (importa quella scura con `theme="light"`) |

In ogni tavola di schermata, i colori dei due temi sono nell'oggetto `P = { dark: {...}, light: {...} }` dentro lo `<script>` in fondo al file.

---

## Principi

- **Scuro per primo, chiaro alla pari.** Base quasi nera, superfici antracite, un solo accento lavanda. Il tema chiaro rispecchia la stessa gerarchia. L'app segue il tema di sistema (`ThemeMode.system`).
- **Niente ombre.** La profondità viene da tre livelli di superficie: `background` → `surface` → `surfaceHigh`.
- **Angoli molto arrotondati**, pulsanti principali a pillola.
- **Un solo elemento decorativo**: il bordo inferiore seghettato della card di riepilogo, come uno scontrino. Non usarlo altrove.
- **Gli importi comandano.** Sono il testo più grande e più pesante di ogni riga, con cifre a larghezza fissa.
- **Il colore della categoria è un segnale, non uno sfondo**: compare come pallino o barra, mai sotto il testo.
- **Niente risorse di rete per la UI.** Font e icone sono inclusi nell'app (vedi [Tipografia](#tipografia)).

---

## Token

I valori completi sono in [`tokens.json`](tokens.json). Qui ci sono i più importanti e come usarli.

### Colori

| Token | Scuro | Chiaro | Uso |
|---|---|---|---|
| `background` | `#0C0C10` | `#F4F3F8` | Sfondo della schermata |
| `surface` | `#17171D` | `#FFFFFF` | Card, liste, campi di testo, pannelli |
| `surfaceHigh` | `#22222A` | `#ECEAF4` | Elementi dentro una card (avatar, pulsanti tondi, binari delle barre) |
| `outline` | `#2C2C36` | `#E0DEEA` | Bordi dei campi a riposo |
| `outlineStrong` | `#3A3A46` | `#D3D0E0` | Bordi dei pulsanti secondari, maniglia del pannello |
| `onSurface` | `#F4F3F8` | `#14131A` | Testo principale |
| `onSurfaceMuted` | `#A3A1B3` | `#5E5B6E` | Testo secondario, icone inattive |
| `primary` | `#A99CFF` | `#5B4BDB` | Link, bordo del campo attivo, accenti |
| `summaryCard` | `#A598FF` | `#B4A9FF` | Card di riepilogo, pulsante fotocamera |
| `onSummaryCard` | `#14112B` | `#14112B` | Testo sulla card di riepilogo (scuro in **entrambi** i temi) |
| `onSummaryCardMuted` | `#3A3370` | `#3A3370` | Testo secondario sulla card di riepilogo |
| `cta` / `onCta` | `#F4F3F8` / `#0C0C10` | `#14131A` / `#FFFFFF` | Pulsante principale, voce attiva della barra di navigazione |
| `warning` | `#F5B14C` | `#B86E00` | Solo icone di avviso |
| `warningContainer` | `#3A2C12` | `#FFF1DA` | Sfondo di banner e badge di avviso |
| `onWarningContainer` | `#FFD99A` | `#6B4000` | Testo di banner e badge di avviso |
| `error` | `#FF8A80` | `#C62828` | Azioni distruttive ("Elimina"), errori |
| `success` | `#5FD39B` | `#1B7F4E` | Spunte di completamento, variazioni di spesa in calo |

> Su `summaryCard` il testo è sempre scuro. Il bianco su quella lavanda non raggiunge il contrasto minimo (4,5:1) per il testo piccolo.

### Colori delle categorie

Le categorie hanno lo stesso colore in tutti e due i temi. La tabella riporta i colori proposti per le 10 categorie iniziali (`defaultCategories` in `lib/data/db.dart`):

| Categoria | Attuale nel seed | Proposto |
|---|---|---|
| Alimentari | `#4CAF50` | `#4CC38A` |
| Bevande | `#03A9F4` | `#F0A35A` |
| Casa | `#795548` | `#5AA9F0` |
| Igiene | `#9C27B0` | `#E67AC4` |
| Salute | `#F44336` | `#F26D6D` |
| Trasporti | `#FF9800` | `#6FD3D3` |
| Ristorazione | `#E91E63` | `#E8D45A` |
| Abbigliamento | `#3F51B5` | `#7C8CF8` |
| Svago | `#009688` | `#A99CFF` |
| Altro | `#607D8B` | `#8E8C9C` |

I colori proposti sono pensati per pallini su fondo scuro e chiaro. Il colore resta salvato nel database: l'app lo legge da `Category.color`, non lo fissa nel codice. Applicarli è una decisione aperta (vedi [Decisioni aperte](#decisioni-aperte)).

**Selettore colore** (per creare o ricolorare una categoria): 12 colori fissi, in questo ordine. I nomi servono come etichetta di accessibilità.

`#4CC38A` Verde · `#5AA9F0` Azzurro · `#F0A35A` Arancio · `#E67AC4` Rosa · `#F26D6D` Rosso · `#C9A76B` Sabbia · `#A99CFF` Lavanda · `#8E8C9C` Grigio · `#6FD3D3` Turchese · `#E8D45A` Giallo · `#7C8CF8` Blu · `#B07A5A` Terra

Una categoria con un colore fuori da questa lista (per esempio creata con la versione attuale dell'app) si mostra comunque: nel selettore non risulta selezionato nessun colore.

Il riquadro morbido dietro il pallino, nella lista Categorie, è il colore della categoria al 16% di opacità (`color.withValues(alpha: 0.16)`).

### Tipografia

Font: **Manrope** (SIL Open Font License 1.1), pesi 500, 600, 700 e 800.

- Includi i file `.ttf` in `assets/fonts/` e dichiarali in `pubspec.yaml`. **Non usare il pacchetto `google_fonts`**: scarica i font da Google a runtime, il che contrasta con il principio "zero tracker".
- I file ufficiali sono su <https://github.com/sharanda/manrope>. Copia anche `OFL.txt` accanto ai font.

| Stile | Dimensione / peso | Altro | Dove |
|---|---|---|---|
| `amountHero` | 42 / 800 | spaziatura −1,2; interlinea 1,05; cifre fisse | Totale del mese nella card di riepilogo |
| `amountLarge` | 26 / 800 | spaziatura −0,6; cifre fisse | Totale nel dettaglio scontrino |
| `amount` | 16 / 800 | cifre fisse | Importi nelle liste (15 nelle righe dello scontrino) |
| `headline` | 26 / 800 | spaziatura −0,5 | Titolo delle schermate principali ("Spese", "Categorie") |
| `headlineOnboarding` | 30 / 800 | spaziatura −0,6; interlinea 1,15 | Titolo del primo avvio |
| `title` | 18 / 800 | | Titoli di sezione, titolo della barra superiore |
| `titleSmall` | 15 / 700 | | Nome dell'esercente o della categoria nelle liste |
| `body` | 15 / 500 | interlinea 1,5 | Testo descrittivo |
| `bodySmall` | 13 / 600 | interlinea 1,45 | Sottotitoli, note, testi d'aiuto |
| `label` | 13 / 700 | | Etichette dei campi, intestazioni dei gruppi per giorno |
| `badge` | 12 / 700 | | Badge di avviso, etichette piccole |
| `button` | 16 / 700 | | Pulsanti grandi (15 nei pulsanti da 52 dp) |

Cifre a larghezza fissa: `fontFeatures: [FontFeature.tabularFigures()]`.

**Formato degli importi.** Usa `money()` di `lib/format.dart`, che produce `64,20 €` (formato `it_IT`). Le tavole mostrano `€ 64,20` solo per brevità: entrambe le forme sono corrette in italiano, e il formato della libreria evita codice su misura.

### Spaziature

Base 4: `4 · 8 · 12 · 16 · 20 · 24 · 32 · 48`.

- Margine laterale della schermata: **20**.
- Spazio sopra il primo contenuto, sotto la barra di stato: usa `SafeArea` più 8. Le tavole mostrano 56 dalla cima del telefono.
- Spazio tra card o sezioni: 12–16. Spazio interno di una card: 16–20.
- Righe di lista: 10–12 sopra e sotto, 14–16 ai lati.

### Raggi

| Token | Valore | Dove |
|---|---|---|
| `sm` | 12 | Pulsanti icona dentro i campi, piccoli riquadri |
| `chip` | 14 | Avatar delle righe, riquadri delle categorie nei token |
| `input` | 16 | Campi di testo, banner di avviso |
| `md` | 20 | Gruppi di lista, card informative |
| `card` | 24 | Card del dettaglio, lista Categorie |
| `lg` | 28 | Card di riepilogo (solo angoli superiori), grafico |
| `sheet` | 32 | Angoli superiori dei pannelli dal basso |
| `pill` | 999 | Pulsanti, chip, barra di navigazione, badge |

### Misure

- Area toccabile minima: **44 × 44**.
- Pulsante principale: altezza 56 (52 nella card di riepilogo).
- Pulsanti tondi a icona: 44.
- Chip: altezza 36.
- Campi di testo: altezza 56 nel primo avvio e nel pannello, 44 nella riga in modifica.
- Barra di navigazione: voci da 48 dentro una pillola con 6 di spazio interno; pulsante fotocamera da 62.
- Avatar delle righe in lista: 44.

---

## Tema Flutter

Le tavole non sono Material puro, ma si mappano bene su un `ColorScheme` di Material 3 con una `ThemeExtension` per i colori che Material non ha.

**`ColorScheme`** (uno per tema, costruito a mano, **non** con `colorSchemeSeed`):

| `ColorScheme` | Token |
|---|---|
| `surface` | `background` |
| `surfaceContainer` | `surface` |
| `surfaceContainerHigh` | `surfaceHigh` |
| `onSurface` | `onSurface` |
| `onSurfaceVariant` | `onSurfaceMuted` |
| `outline` | `outlineStrong` |
| `outlineVariant` | `outline` |
| `primary` | `primary` |
| `onPrimary` | `onCta` |
| `primaryContainer` | `summaryCard` |
| `onPrimaryContainer` | `onSummaryCard` |
| `inverseSurface` | `cta` |
| `onInverseSurface` | `onCta` |
| `error` | `error` |
| `scrim` | `scrim` |

Imposta anche `scaffoldBackgroundColor = background`.

**`ThemeExtension<ScontriniColors>`** con: `warning`, `warningContainer`, `onWarningContainer`, `warningOutline`, `success`, `onSummaryCardMuted`, `navBar`, `navBarOutline`, `navActiveIcon`.

**Temi dei componenti** da impostare una volta sola:

- `FilledButtonThemeData`: sfondo `cta`, testo `onCta`, `StadiumBorder`, altezza minima 56, stile `button`.
- `OutlinedButtonThemeData`: bordo `outlineStrong` da 1, `StadiumBorder`, altezza 56.
- `InputDecorationTheme`: `filled: true`, `fillColor: surface`, bordo `outline` da 1 a riposo e `primary` da 1,5 col focus, raggio 16, nessuna etichetta flottante (l'etichetta sta sopra il campo, stile `label`).
- `BottomSheetThemeData`: sfondo `surface`, angoli superiori 32, maniglia 40 × 5 in `outlineStrong`.
- `CardTheme`: `elevation: 0`, colore `surface`.
- `DividerTheme`: nessun divisore nelle liste. La separazione viene dagli spazi.

---

## Componenti

### Card di riepilogo con bordo seghettato

Card della schermata Movimenti.

- Sfondo `summaryCard`; angoli superiori 28, inferiori a zero.
- Spazio interno 20 ai lati e sopra, 22 sotto.
- Sotto la card c'è una striscia di denti dello stesso colore: ogni dente è un triangolo **largo 10, alto 8**, con la punta in basso. La striscia è larga quanto la card e il numero di denti è `larghezza / 10`. Implementala con un `CustomClipper<Path>` sulla card intera (rettangolo più zigzag) oppure con un `CustomPainter` sotto.
- Contenuto:
  1. Etichetta "Speso a {mese}" (14 / 600, `onSummaryCardMuted`).
  2. Totale (`amountHero`, `onSummaryCard`).
  3. Riga "{n} scontrini · {k} da controllare" (13 / 600, `onSummaryCardMuted`). Se `k = 0`, mostra solo "{n} scontrini".
  4. Due pulsanti affiancati, alti 52, a pillola:
     - **Fotografa**: sfondo `#14112B`, testo bianco, icona fotocamera.
     - **Galleria**: sfondo bianco al 55%, testo `#14112B`, icona immagine.

### Barra di navigazione flottante

Sostituisce la `NavigationBar` di Material.

- Posizionata in basso, 20 dai lati e 28 dal fondo (più l'inset di sistema). Il contenuto scorre sotto.
- Sopra il fondo dello schermo c'è una sfumatura alta 130, da `background` trasparente a `background` pieno al 55%, così la lista non si legge sotto la barra.
- È fatta di due elementi affiancati con 10 di spazio:
  1. **Pillola** con sfondo `navBar`, bordo `navBarOutline` da 1 e 6 di spazio interno. Contiene 4 voci alte 48.
     - Voce **attiva**: pillola `cta` con icona (colore `navActiveIcon`) ed etichetta (14 / 800, `onCta`). Occupa 1,6 volte lo spazio di una voce inattiva.
     - Voci **inattive**: solo icona, `onSurfaceMuted`.
  2. **Pulsante fotocamera**: cerchio da 62, sfondo `summaryCard`, icona `#14112B`. Apre la scelta fotocamera/galleria e poi la schermata Analisi in corso.
- Ordine delle voci: Movimenti · Spese · Categorie · Impostazioni.
- Ogni voce inattiva ha un `Semantics(label:)` col suo nome. La voce attiva ha `selected: true`.
- Su schermate secondarie (dettaglio scontrino, analisi) la barra non c'è.

### Pulsanti

| Tipo | Aspetto | Esempi |
|---|---|---|
| Principale | `FilledButton`, pillola `cta`, alto 56 | "Prova e collega", "Salva" |
| Secondario | `OutlinedButton`, bordo `outlineStrong`, testo `onSurface` | "Annulla" |
| Distruttivo | Come il secondario, ma testo e icona `error` | "Elimina" |
| Tondo a icona | Cerchio da 44, sfondo `surface` (o `surfaceHigh` dentro un pannello) | Indietro, mese precedente/successivo, cerca, chiudi |
| Compatto nel banner | Alto 36, pillola; pieno `onWarningContainer` su `warningContainer`, oppure con bordo `warningOutline` | "Aggiungi riga", "Va bene così" |
| Compatto nell'intestazione | Alto 44, pillola `cta`, icona + testo | "Nuova" (categoria) |

### Riga di lista (scontrino)

- Avatar da 44, raggio 14, sfondo `surfaceHigh`, con l'iniziale dell'esercente (16 / 800).
- In basso a destra dell'avatar c'è un pallino da 14 con il colore della categoria prevalente e un bordo da 2,5 nel colore della card, per staccarlo dall'avatar.
- Al centro:
  - nome dell'esercente (`titleSmall`, una riga, con i puntini se è troppo lungo);
  - sotto, **o** il sottotitolo "{n} righe · {categoria}" (`bodySmall`, `onSurfaceMuted`), **o** il badge di avviso.
- A destra: importo (`amount`).
- Le righe di uno stesso giorno stanno in un gruppo con sfondo `surface` e raggio 20. Sopra ogni gruppo c'è l'intestazione del giorno (`label`, `onSurfaceMuted`): "Oggi · giovedì 5", "Ieri · mercoledì 4", poi "Martedì 3"…
- "Categoria prevalente" vuol dire la categoria con l'importo più alto nello scontrino. Se il dato non è disponibile nell'elenco, mostra il pallino in `onSurfaceMuted` e ometti la categoria dal sottotitolo (vedi [Decisioni aperte](#decisioni-aperte)).

### Badge di avviso

Pillola con spazio interno 2 × 8, sfondo `warningContainer`, testo `onWarningContainer` (`badge`) e un triangolo di avviso da 12. Testi: "Totale da verificare", "Possibile doppione", "Data da verificare". Se uno scontrino ha più avvisi, mostra solo il primo nell'ordine della sezione [Avvisi sui dati](#avvisi-sui-dati).

### Banner di avviso

Riquadro con raggio 16 e spazio interno 12 × 14, sfondo `warningContainer`, testo `onWarningContainer` (14 / 600, importi in grassetto). A sinistra c'è un'icona di avviso da 20 in `warning`; sotto il testo, uno o due pulsanti compatti. Il banner ha `Semantics(liveRegion: true)`.

### Chip di categoria (selezione singola)

Alto 36, pillola, spazio interno 0 × 12, con un pallino da 10 e il nome (13 / 700).

- **Non selezionato**: sfondo trasparente, bordo `outline`, testo `onSurface`.
- **Selezionato**: sfondo `cta`, testo `onCta`, nessun bordo visibile.

I chip vanno a capo (`Wrap`, spazio 6). Si comportano come pulsanti di opzione per l'accessibilità.

### Campi di testo

L'etichetta sta sopra il campo (`label`, 8 di spazio), poi il campo. Il campo può avere un'icona iniziale (20, `onSurfaceMuted`) e un pulsante finale da 44 (per esempio "Mostra token"). Il testo d'aiuto va sotto (`bodySmall`, `onSurfaceMuted`). Il campo del token è oscurato di default.

### Pannello dal basso (modifica categoria)

`showModalBottomSheet` con `isScrollControlled: true`, sfondo `surface`, angoli superiori 32, spazio interno 12 sopra, 20 ai lati e 32 sotto. Contiene, nell'ordine: la maniglia, il titolo con il pulsante Chiudi, il campo Nome (con il pallino del colore corrente dentro), la griglia di colori, la nota sull'eliminazione e i pulsanti Elimina e Salva affiancati.

### Griglia di colori

6 colonne, spazio 10, cerchi alti 46. Il colore selezionato ha un anello da 3 in `onSurface` e, all'interno, un anello da 3 nel colore del pannello, che crea uno stacco. Ogni cerchio ha come etichetta di accessibilità il nome del colore e lo stato selezionato.

### Grafico a ciambella

- Diametro 168, spessore 18, raggio del tracciato 70.
- Il binario sotto è `surfaceHigh`.
- I segmenti partono da ore 12 in senso orario, ordinati per importo decrescente, con uno spazio di 3 tra l'uno e l'altro.
- Al centro: "Totale" (12 / 700, `onSurfaceMuted`) e l'importo (22 / 800).
- Implementalo con un `CustomPainter` (archi con `StrokeCap.butt`), senza librerie di grafici.
- Per l'accessibilità, l'intero grafico ha un'etichetta riassuntiva del tipo "Spese di novembre: Alimentari 49%, Casa 20%…".

### Barre per categoria

Sotto il nome, una barra alta 6 con raggio 3 su binario `surfaceHigh`. La lunghezza è relativa alla **categoria più alta** (che riempie tutta la barra), non al totale. A destra del nome ci sono la percentuale sul totale (13 / 700, `onSurfaceMuted`) e l'importo.

### Passaggi dell'analisi

Lista verticale dentro una card `surface`, righe alte almeno 48. Stati:

- **Fatto**: cerchio da 26 pieno `success` con la spunta.
- **In corso**: anello da 22 con il tratto superiore `primary` (`CircularProgressIndicator`).
- **Da fare**: anello tratteggiato da 22 in `outline`, testo `onSurfaceMuted` a peso 500.

A destra di ogni passaggio c'è il valore letto, se c'è (13 / 600, `onSurfaceMuted`).

### Icone

Le tavole usano icone a tratto disegnate a mano. In Flutter usa le icone Material incluse nel framework, nella variante a contorno. Non scaricare icone da internet.

| Nel design | Material |
|---|---|
| Movimenti (tre righe) | `Icons.receipt_long_outlined` o `Icons.notes` |
| Spese (torta) | `Icons.pie_chart_outline` |
| Categorie (etichetta) | `Icons.sell_outlined` |
| Impostazioni (cursori) | `Icons.tune` |
| Fotocamera | `Icons.photo_camera_outlined` |
| Galleria | `Icons.image_outlined` |
| Avviso | `Icons.warning_amber_rounded` |
| Server | `Icons.dns_outlined` |
| Token | `Icons.key_outlined` |
| Privacy | `Icons.verified_user_outlined` |
| Mostra token | `Icons.visibility_outlined` / `Icons.visibility_off_outlined` |
| Modifica | `Icons.edit_outlined` |
| Elimina | `Icons.delete_outline` |
| Aggiungi | `Icons.add` |
| Chiudi | `Icons.close` |
| Indietro / avanti | `Icons.chevron_left` / `Icons.chevron_right` |
| Cerca | `Icons.search` |
| Altro | `Icons.more_horiz` |

---

## Schermate

Le misure si riferiscono a un telefono da 390 × 844 punti. Su schermi più larghi il contenuto resta largo al massimo 560 e centrato.

### 1. Primo avvio — `Setup.dc.html`

**Quando**: all'avvio, se `AppConfig.isConfigured` è falso. Sostituisce l'attuale apertura diretta sulla scheda Impostazioni.

Dall'alto:

1. Marchio da 64 (`brand/mark.svg`).
2. Titolo "Collega il tuo server" (`headlineOnboarding`).
3. Testo "Scontrini salva i dati sul server che scegli tu. Ti servono l'indirizzo e il token di accesso." (`body`, `onSurfaceMuted`).
4. Campo **Indirizzo del server**: icona server, tastiera URL, nessuna correzione automatica.
5. Campo **Token di accesso**: icona chiave, oscurato, pulsante Mostra/Nascondi. Aiuto: "Lo trovi nel file di configurazione del server. Resta solo su questo telefono, nell'archivio sicuro del sistema."
6. Card informativa (`surface`, raggio 20): icona scudo in `success` su riquadro `surfaceHigh`, titolo "Nessun account, nessun tracker", testo "La foto serve solo per la lettura e poi viene eliminata. Restano i dati dello scontrino."
7. In fondo alla schermata: il pulsante principale **"Prova e collega"** e la riga "Software libero · codice sorgente". Il link apre il repository nel browser di sistema.

**Comportamento**:

- "Prova e collega" verifica la connessione (come fa oggi "Salva e verifica" in Impostazioni). Durante la verifica il pulsante mostra un indicatore e resta disabilitato.
- Se la verifica riesce, salva la configurazione e apre Movimenti.
- Se fallisce, mostra l'errore sotto il campo interessato: indirizzo non raggiungibile → sotto l'indirizzo; token rifiutato → sotto il token. Il testo è in `error` e la configurazione non viene salvata.
- Il pulsante è disabilitato finché uno dei due campi è vuoto.

### 2. Movimenti — `Home.dc.html`

Scheda principale. Sostituisce `MovementsScreen`.

1. **Barra superiore** (senza `AppBar`): pulsante tondo "mese precedente", nome del mese (`title`, per esempio "Novembre 2026" da `monthLabel()`), pulsante tondo "mese successivo" (in `onSurfaceMuted` e disabilitato sul mese corrente). A destra c'è il pulsante Cerca: vedi [Decisioni aperte](#decisioni-aperte).
2. **Card di riepilogo** del mese selezionato (vedi [Componenti](#card-di-riepilogo-con-bordo-seghettato)).
3. **Titolo "Movimenti"** con il link "Filtra" a destra (vedi [Decisioni aperte](#decisioni-aperte)).
4. **Lista per giorno**, dal più recente. Ogni riga apre il dettaglio dello scontrino.
5. **Barra di navigazione flottante**.

**Stati**:

- *Caricamento*: tre gruppi segnaposto grigi (`surfaceHigh`) al posto della lista. La card di riepilogo mostra "—" come totale.
- *Mese vuoto*: la card mostra "0,00 €" e "Nessuno scontrino". Al posto della lista: "Nessuno scontrino a {mese}. Fotografane uno per iniziare." (`body`, `onSurfaceMuted`, centrato).
- *Errore di rete*: un banner `surface` al posto della lista, con il messaggio e il pulsante secondario "Riprova".
- *Analisi in corso in sottofondo*: se l'utente torna indietro durante l'analisi, in cima alla lista compare una riga segnaposto "Lettura in corso…" con un indicatore.

Il cambio mese aggiorna sia la card sia la lista. Basta il mese visibile: la lista non scorre all'infinito tra i mesi.

### 3. Analisi in corso — `Scan.dc.html`

**Quando**: dopo aver scelto una foto, con la fotocamera o dalla galleria.

1. Barra superiore: pulsante Indietro e titolo "Lettura dello scontrino".
2. Riquadro alto 340, `surface`, raggio 28, con l'**anteprima della foto scelta** (in `BoxFit.cover`, angoli arrotondati) e una linea orizzontale `primary` alta 3 che scorre dall'alto in basso in continuazione (circa 1,6 s, con andata e ritorno). Nella tavola, al posto della foto, c'è uno scontrino disegnato.
3. Titolo "Sto leggendo le righe…" (24 / 800) e sottotitolo "Di solito bastano una decina di secondi."
4. Lista dei passaggi: **Esercente e data**, **Totale**, **Righe e importi**, **Categorie**.
5. In fondo: la nota "Finita la lettura, la foto viene eliminata." con l'icona scudo, e il pulsante secondario **"Annulla"**.

**Comportamento**:

- L'API `/scan` oggi risponde in un'unica volta, senza avanzamento. Finché è così, i passaggi avanzano **a tempo** (circa 2 s ciascuno) e l'ultimo resta "in corso" fino alla risposta; i valori a destra compaiono solo alla risposta. Se in futuro l'API manderà l'avanzamento, i passaggi lo seguiranno.
- Alla risposta, apri il **dettaglio dello scontrino appena creato**, sostituendo questa schermata.
- Se la risposta segnala un possibile doppione (`possibleDuplicateOf`), mostra prima la finestra di conferma che c'è già oggi, con i testi attuali ("Possibile doppione", "Elimina il nuovo" / "Tienilo"), nello stile del tema.
- "Annulla" o Indietro interrompono la richiesta e tornano a Movimenti.
- In caso di errore, il titolo diventa "Non sono riuscito a leggerlo", il passaggio in corso diventa un cerchio `error` con la ×, e i pulsanti sono "Riprova" (principale) e "Annulla".
- La foto vive solo in memoria (o in un file temporaneo cancellato subito dopo): è il requisito di privacy del brief.

### 4. Dettaglio scontrino — `Receipt.dc.html`

Sostituisce `ReceiptScreen`.

1. Barra superiore: Indietro, titolo "Scontrino", pulsante "Altre azioni" (menu con "Elimina scontrino", che apre la conferma attuale).
2. **Card di intestazione** (`surface`, raggio 24, spazio interno 18):
   - a sinistra: il nome dell'esercente (22 / 800) con la matita, e sotto la data e l'ora (14 / 600, `onSurfaceMuted`, formato "Gio 5 novembre 2026 · 18:42") con la matita. Toccare l'uno o l'altra apre la modifica dell'intestazione;
   - a destra: "Totale" (12 / 700) e l'importo (`amountLarge`). Toccarlo apre la modifica del totale;
   - sotto, dentro la stessa card, gli eventuali **banner di avviso** (vedi [Avvisi sui dati](#avvisi-sui-dati)).
3. Intestazione delle righe: "{n} righe" (16 / 800) e a destra "Tocca una riga per correggerla" (13 / 600, `onSurfaceMuted`).
4. **Lista delle righe** in una card `surface`. Ogni riga mostra:
   - la descrizione (`titleSmall`);
   - sotto, il pallino della categoria, il nome della categoria e, se ci sono, quantità e prezzo unitario ("2 × 0,65 €" oppure "1,24 kg");
   - a destra, l'importo (15 / 800).
5. In fondo alla lista, la nota attuale "Analizzato con {modello}." (`bodySmall`, `onSurfaceMuted`).

**Modifica di una riga** (cambia rispetto a oggi: tocco semplice invece di pressione prolungata, e modifica nella lista invece di una finestra):

- Toccare una riga la **espande sul posto**: riquadro `surfaceHigh` con bordo `primary` da 1,5 e raggio 18. Contiene i campi "Descrizione" e "Importo" affiancati (l'importo è largo 92, allineato a destra, tastiera decimale) e sotto i **chip di categoria** di tutte le categorie, in ordine `sortOrder`.
- Scegliere un chip salva subito la categoria. Descrizione e importo si salvano quando il campo perde il focus o con "Fatto" sulla tastiera.
- Può essere espansa una riga alla volta: toccarne un'altra chiude la prima.
- Una riga senza categoria mostra il pallino `onSurfaceMuted` e il testo "Senza categoria".
- Aggiungere una riga ("Aggiungi riga" nel banner) inserisce in fondo una riga vuota già espansa, con il focus sulla descrizione.
- Eliminare una riga: trascinandola verso sinistra (`Dismissible`), con un "Annulla" nello snackbar per qualche secondo.

### 5. Spese per categoria — `Stats.dc.html`

Scheda "Spese". Sostituisce `StatsScreen`.

1. Intestazione: "Spese" (`headline`) e a destra il **selettore del mese** compatto (pillola `surface` con le frecce e il nome del mese).
2. **Card del grafico** (`surface`, raggio 28): a sinistra la ciambella, a destra due dati impilati:
   - "Rispetto a {mese precedente}": la differenza in euro, in `success` se la spesa è calata e in `onSurface` se è cresciuta (vedi [Decisioni aperte](#decisioni-aperte));
   - "Categoria principale": il nome della categoria più alta.
3. **Lista delle categorie** con spesa nel mese, dalla più alta: pallino, nome, percentuale, importo e barra. Toccare una categoria apre Movimenti filtrato su quella categoria e su quel mese (se il filtro viene implementato), altrimenti la riga non è toccabile.

Le categorie senza spesa nel mese non compaiono. Le righe senza categoria compaiono come "Senza categoria", in grigio `#8E8C9C`. Se il mese è vuoto, al posto di grafico e lista c'è il messaggio "Nessuna spesa a {mese}."

### 6. Categorie — `Categories.dc.html`

Nuova scheda. Oggi la gestione delle categorie sta dentro Impostazioni.

1. Intestazione: "Categorie" (`headline`) e a destra il pulsante compatto **"Nuova"**.
2. Testo "L'AI assegna ogni riga a una di queste categorie. Puoi cambiarle quando vuoi." (`body`, `onSurfaceMuted`).
3. **Lista** in una card `surface`, ordinata per `sortOrder`. Ogni riga è alta 56: riquadro da 32 con il colore al 16% e il pallino, nome, numero di righe ("64 righe"), freccia. Toccarla apre il pannello di modifica.

**Pannello "Modifica categoria"** (o "Nuova categoria"):

- Campo **Nome**, con dentro il pallino del colore selezionato.
- **Colore**: la griglia dei 12 colori.
- Solo in modifica: la nota "Se la elimini, le sue {n} righe restano senza categoria." e il pulsante distruttivo **"Elimina"**. Elimina chiede conferma con la finestra attuale.
- Pulsante principale **"Salva"**, disabilitato se il nome è vuoto o già usato da un'altra categoria. Il nome duplicato mostra l'errore "Esiste già una categoria con questo nome." sotto il campo.
- In creazione il colore proposto è il primo della griglia non ancora usato.

Il numero di righe per categoria richiede un dato che l'API forse non fornisce (vedi [Decisioni aperte](#decisioni-aperte)). Se manca, la colonna resta vuota.

### 7. Impostazioni (senza tavola)

Il design non ha una tavola dedicata. Costruiscila con gli stessi componenti del Primo avvio:

- titolo "Impostazioni" (`headline`);
- sezione **Connessione**: gli stessi due campi del Primo avvio, già compilati, e il pulsante "Salva e verifica";
- card informativa sulla privacy;
- sezione **Informazioni**: versione dell'app, link al codice sorgente, licenza (GPL-3.0).

---

## Navigazione

```
Primo avvio ──(configurato)──► Shell con barra flottante
                                ├─ Movimenti ──► Dettaglio scontrino
                                ├─ Spese
                                ├─ Categorie ──► pannello modifica
                                └─ Impostazioni
Pulsante fotocamera (da Movimenti, Spese, Categorie)
   └─ scelta Fotocamera / Galleria ──► Analisi in corso ──► Dettaglio scontrino nuovo
```

- La scelta tra fotocamera e galleria resta un pannello dal basso, come oggi ("Scatta foto" / "Scegli dalla galleria"), nello stile del tema. I pulsanti **Fotografa** e **Galleria** della card di riepilogo saltano la scelta e vanno direttamente alla sorgente.
- Indietro su Android: dalla scheda Movimenti esce dall'app; dalle altre schede torna a Movimenti.

---

## Avvisi sui dati

Il design mostra gli avvisi in due punti: come **badge** nella riga di Movimenti e come **banner** nel dettaglio. Badge e banner hanno sempre gli stessi colori di avviso; cambiano solo i testi.

| Avviso | Quando (logica attuale o proposta) | Badge | Banner nel dettaglio | Azioni del banner |
|---|---|---|---|---|
| Totale da verificare | La somma delle righe è diversa dal totale per più di 0,01 € (logica già presente in `ReceiptScreen`) | "Totale da verificare" | "Le righe sommano **{somma}**, il totale è **{totale}**. Manca/Avanza **{differenza}**: forse una riga non è stata letta / è stata letta due volte." | "Aggiungi riga" · "Va bene così" |
| Possibile doppione | Stesso totale, data e ora di un altro scontrino (logica attuale di `/scan`) | "Possibile doppione" | "C'è un altro scontrino di {esercente} con lo stesso totale, del {data}." | "Apri l'altro" · "Non è un doppione" |
| Data da verificare | Oggi `ReceiptScreen` lo mostra se la data è più vecchia di 60 giorni rispetto a oggi, quindi l'avviso compare anche su scontrini corretti ma vecchi. Proposta: confrontare con la data di creazione (`created_at`) invece che con oggi, e segnalare anche le date future | "Data da verificare" | "La data letta è **{data}**. Se è sbagliata, correggila." | "Correggi" · "È giusta" |

- Ordine di priorità, se ci sono più avvisi: Totale → Doppione → Data. Il badge mostra solo il primo; il dettaglio mostra tutti i banner, uno sotto l'altro.
- "Va bene così", "Non è un doppione" ed "È giusta" fanno sparire l'avviso **per quello scontrino**. Serve un campo persistente (vedi [Decisioni aperte](#decisioni-aperte)).
- Il conteggio "{k} da controllare" della card di riepilogo è il numero di scontrini del mese con almeno un avviso aperto.

---

## Logo, icone e splash

### Il marchio

È uno scontrino bianco con il bordo inferiore seghettato, inclinato di −8°, su un quadrato viola `#6A5AE0`. Dentro ci sono due righe di testo viola e, in basso a destra, un blocco corto e scuro `#14112B`, che rappresenta il totale. Il disegno sta in una griglia di 108 × 108 e lo scontrino resta dentro la zona sicura di 66 dp di Android.

Non modificare proporzioni, inclinazione o colori. Sotto i 24 px usa `icon-small.svg`, senza le righe sottili.

### Generare i file

I sorgenti sono SVG. Per ottenere i PNG e le risorse native si consigliano due strumenti di sviluppo open source (licenza MIT), che girano solo in fase di build e non finiscono nell'app:

- `flutter_launcher_icons` per le icone dell'app;
- `flutter_native_splash` per lo splash.

Entrambi vogliono PNG in ingresso. Esporta gli SVG a 1024 px con qualsiasi strumento libero, per esempio `rsvg-convert -w 1024 -h 1024 icon.svg -o icon.png` oppure Inkscape. Metti i PNG in `assets/branding/` (cartella da creare).

**Android** (adattiva, API 26+):

- Sfondo: colore pieno `#6A5AE0`.
- Primo piano: `adaptive-foreground.svg` esportato a 432 × 432 (108 dp a xxxhdpi).
- Monocromatica (API 33+, icone a tema): `adaptive-monochrome.svg` esportato a 432 × 432. Il sistema la ricolora: le righe sono ritagliate a vuoto, non disegnate in un secondo colore.
- Icona per le versioni precedenti: `icon.svg`.

**iOS**: `icon.svg` a 1024 × 1024, **senza canale alfa** (`remove_alpha_ios: true`). La maschera arrotondata la applica il sistema.

**Splash**:

- Sfondo pieno: scuro `#0C0C10`, chiaro `#F4F3F8`, secondo il tema di sistema.
- Al centro `mark.svg`, largo circa 96 dp. Nessuna scritta, nessuna animazione.
- Android 12+ usa la Splash API di sistema: icona `adaptive-foreground` su sfondo `#6A5AE0` (`android_12.icon_background_color`) dentro il cerchio di 160 dp; sfondo della schermata come sopra.

Esempio di configurazione (in `pubspec.yaml` o in file separati):

```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: assets/branding/icon.png
  remove_alpha_ios: true
  adaptive_icon_background: "#6A5AE0"
  adaptive_icon_foreground: assets/branding/adaptive-foreground.png
  adaptive_icon_monochrome: assets/branding/adaptive-monochrome.png

flutter_native_splash:
  color: "#F4F3F8"
  color_dark: "#0C0C10"
  image: assets/branding/mark.png
  image_dark: assets/branding/mark.png
  android_12:
    color: "#F4F3F8"
    color_dark: "#0C0C10"
    image: assets/branding/adaptive-foreground.png
    icon_background_color: "#6A5AE0"
    icon_background_color_dark: "#6A5AE0"
```

---

## Accessibilità

- **Contrasto**: tutte le coppie testo/sfondo dei token superano 4,5:1; il testo grande (24 pt e oltre) supera almeno 3:1. Non introdurre grigi nuovi senza verificarli.
- **Aree toccabili** di almeno 44 × 44, anche per i pulsanti a sola icona e i cerchi del selettore colore.
- **Etichette**: ogni pulsante a sola icona ha un `tooltip` o un `Semantics(label:)` (per esempio "Mese precedente", "Cerca", "Fotografa uno scontrino", "Altre azioni", "Mostra token").
- **Colore mai da solo**: gli avvisi hanno sempre testo e icona; le categorie hanno sempre il nome accanto al pallino.
- **Testo ingrandito**: la UI deve reggere un `textScaler` fino a 1,3 senza tagliare gli importi. Le righe crescono in altezza; il nome dell'esercente si tronca prima dell'importo.
- **Lettore di schermo**: ogni riga di lista si legge come un'unica frase, per esempio "Esselunga, 64,20 euro, totale da verificare". Il grafico ha un'etichetta riassuntiva.
- **Movimento ridotto**: se `MediaQuery.disableAnimations` è vero, la linea di scansione resta ferma.

---

## Differenze rispetto al codice attuale

| Area | Oggi | Con il nuovo design |
|---|---|---|
| Tema | `colorSchemeSeed: Colors.teal` | `ColorScheme` costruiti a mano + `ThemeExtension` (vedi [Tema Flutter](#tema-flutter)) |
| Font | Quello di sistema | Manrope incluso nell'app |
| Navigazione | `NavigationBar`: Movimenti · Categorie (statistiche) · Impostazioni | Barra flottante: Movimenti · Spese · Categorie · Impostazioni, più il pulsante fotocamera |
| Statistiche | Scheda "Categorie" | Scheda "Spese" |
| Gestione categorie | Dentro Impostazioni | Scheda propria "Categorie" |
| Primo avvio | Apre Impostazioni | Schermata dedicata "Collega il tuo server" |
| Avvio della scansione | FAB esteso "Scansiona" e pannello di scelta | Pulsante fotocamera nella barra e pulsanti nella card di riepilogo |
| Durante la scansione | Il FAB mostra "Analisi in corso…" | Schermata dedicata con anteprima e passaggi |
| Dopo la scansione | Torna alla lista | Apre il dettaglio dello scontrino nuovo |
| Movimenti | Lista con intestazioni per mese | Un mese alla volta, card di riepilogo, gruppi per giorno, badge di avviso |
| Modifica di una riga | Pressione prolungata → finestra | Tocco → espansione sul posto con chip di categoria |
| Avvisi nel dettaglio | Card `tertiaryContainer` / `errorContainer` | Banner di avviso con azioni |
| Icona e splash | Quelli predefiniti di Flutter | Marchio Scontrini |

La logica (API, modelli, `AppState`, salvataggio sicuro del token) non cambia, salvo i punti seguenti.

---

## Decisioni aperte

Decisioni prese per l'implementazione (novembre 2026):

1. **Colori delle categorie del seed**: la migrazione `20261105000000_design.sql` applica la nuova palette a tutte e 10 le categorie predefinite.
2. **Categoria prevalente e avvisi nell'elenco**: `GET /receipts` restituisce `items_sum`, `dominant_category_id` e `warnings`, calcolati dal server.
3. **Avvisi ignorati**: colonna `dismissed_warnings text[]` sugli scontrini, aggiornata con `PATCH /receipts/:id`.
4. **Possibile doppione**: colonna `duplicate_of`, salvata da `/scan` (con recupero per gli scontrini già presenti). Il dettaglio riceve anche esercente e data dell'altro scontrino.
5. **Numero di righe per categoria**: `GET /categories` restituisce `item_count`.
6. **Confronto col mese precedente**: seconda chiamata a `/stats`.
7. **Cerca e Filtra**: implementati. Cerca su esercente e descrizione delle righe (`q`), Filtra per categoria (`category_id`). Toccare una categoria in Spese apre Movimenti filtrato.
8. **Aggiungere ed eliminare righe**: `POST /receipts/:id/items` e `DELETE /items/:id`. L'eliminazione col trascinamento si annulla dallo snackbar.
9. **Formato degli importi**: resta `64,20 €` (`money()`).

Altre scelte:

- **Indietro e Annulla durante l'analisi**: Indietro lascia proseguire la lettura in sottofondo (riga "Lettura in corso…" in Movimenti, poi uno snackbar con "Apri"); Annulla la interrompe e, se il server ha comunque salvato lo scontrino, l'app lo elimina appena arriva la risposta.
- **Metodo di pagamento**: compare nel dettaglio dopo data e ora ("Gio 5 novembre 2026 · 18:42 · Carta") ed è modificabile.
- **Avviso sulla data**: confronta la data letta con `created_at` (più vecchia di 60 giorni o più di un giorno nel futuro).
- **Font**: il repository `sharanda/manrope` indicato sopra non esiste più. I file in `assets/fonts/` sono istanze statiche (500–800) del font variabile OFL pubblicato in `google/fonts`.

---

## Checklist di accettazione

- [ ] Tema chiaro e scuro seguono il sistema; tutti i colori vengono dai token, nessun valore esadecimale sparso nelle schermate (tranne quelli dentro `ScontriniColors`).
- [ ] Manrope incluso come asset, con `OFL.txt`; nessuna richiesta di rete per font o icone.
- [ ] Barra di navigazione flottante con 4 voci e pulsante fotocamera; la voce attiva è riconoscibile anche dal lettore di schermo.
- [ ] La card di riepilogo ha il bordo seghettato (denti 10 × 8) e il testo scuro in entrambi i temi.
- [ ] Il flusso di scansione passa da Analisi in corso e finisce nel dettaglio dello scontrino nuovo; Annulla interrompe davvero la richiesta.
- [ ] La foto non viene scritta su disco in modo permanente.
- [ ] Nel dettaglio, una riga si modifica con un tocco e la categoria si salva scegliendo un chip.
- [ ] Gli avvisi compaiono come badge in lista e come banner nel dettaglio, con i testi di questo documento.
- [ ] La scheda Categorie permette di creare, rinominare, ricolorare (12 colori) ed eliminare una categoria.
- [ ] Icona adattiva Android con versione monocromatica, icona iOS senza canale alfa, splash chiaro e scuro.
- [ ] Aree toccabili di almeno 44, etichette su tutti i pulsanti a icona, nessun testo tagliato con il testo ingrandito a 1,3.
