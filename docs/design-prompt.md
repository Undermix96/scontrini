# Prompt per Claude Design — UI e logo di "Scontrini"

Progetta da zero la UI mobile e il logo di **Scontrini**, un'app Android e iOS open source (GPL-3.0) per tenere traccia delle spese fotografando gli scontrini.

## Il prodotto
- L'utente fotografa uno scontrino. Un modello AI legge totale, esercente, data, metodo di pagamento e **ogni singola riga**, e assegna una categoria a ogni riga. I dati vengono salvati online.
- Un solo utente, **nessun account né login**. Lingua: **solo italiano**. Valuta prevalente: EUR (formato `12,50 €`).
- Valori del progetto: software libero, **zero tracker**, privacy. La foto non viene conservata. Il tono deve essere sobrio, affidabile e amichevole, non da app bancaria e non "giocoso".
- Verrà implementata in **Flutter con Material 3** (ColorScheme da un colore seed, temi chiaro e scuro). Proponi un design realizzabile con componenti Material 3 standard, eventualmente personalizzati: niente effetti che richiedano librerie proprietarie.

## Dati da rappresentare
- **Scontrino**: esercente (può mancare), data e ora, totale, valuta, metodo di pagamento (può mancare), numero di righe, modello AI usato.
- **Riga**: descrizione, quantità e prezzo unitario (opzionali), importo (negativo per gli sconti), categoria.
- **Categoria**: nome e colore. Predefinite: Alimentari, Bevande, Casa, Igiene, Salute, Trasporti, Ristorazione, Abbigliamento, Svago, Altro. L'utente può aggiungerle, rinominarle, ricolorarle ed eliminarle.

## Schermate da progettare (mobile, ~390×844, chiaro e scuro)
1. **Movimenti** (home): tutti gli scontrini dal più recente, raggruppati per mese con intestazione e totale del mese. Ogni voce mostra esercente, data e ora, numero di righe e totale. Pull-to-refresh. Pulsante primario evidente **"Scansiona"**. Stato vuoto illustrato e stato di errore.
2. **Scelta sorgente**: bottom sheet con "Scatta foto" e "Scegli dalla galleria".
3. **Analisi in corso**: attesa di 5-20 secondi mentre l'AI legge lo scontrino. Serve un feedback che rassicuri, non un semplice spinner.
4. **Dettaglio scontrino**: intestazione con esercente, data, metodo di pagamento e totale ben in evidenza, e azioni Modifica ed Elimina. Elenco righe con chip della categoria colorato, che si tocca per cambiarla; quantità × prezzo quando servono; sconti negativi distinguibili. Prevedi due avvisi:
   - la somma delle righe non coincide con il totale;
   - la data letta è più vecchia di due mesi, con il pulsante "Modifica".
5. **Cambia categoria**: bottom sheet con l'elenco delle categorie colorate e quella selezionata.
6. **Modifica scontrino / riga**: dialog o form per esercente, totale e data (scontrino) e per descrizione e importo (riga).
7. **Possibile doppione**: dialog "Esiste già uno scontrino con lo stesso totale, data e ora" con "Elimina il nuovo" e "Tienilo".
8. **Categorie / statistiche**: selettore del mese (precedente/successivo), totale del mese e spesa per categoria con barre o un grafico ad anello leggibile, importi e percentuali.
9. **Impostazioni**: URL del progetto e token dell'app (campo nascosto con mostra/nascondi), pulsante "Salva e verifica", gestione categorie (aggiungi, modifica nome e colore da una palette di 12 colori, elimina) e una nota di privacy ("nessun tracker, nessun account").
10. **Primo avvio / onboarding** (1-2 schermate): spiega che serve il token e porta alle Impostazioni.

Navigazione: barra inferiore con 3 voci, **Movimenti**, **Categorie**, **Impostazioni**.

## Requisiti di design
- **Design system**:
  - colore seed proposto, con palette per tema chiaro e scuro;
  - tipografia con un font open source (es. Inter, Atkinson Hyperlegible o Noto Sans);
  - scala di spaziature, raggi e elevazioni.
- **Colori delle categorie**: 12 colori distinguibili tra loro, con contrasto WCAG AA nei temi chiaro e scuro, e varianti per chip e barre.
- **Accessibilità**:
  - target tattili di almeno 48 dp;
  - testi leggibili con font scalato al 130%;
  - nessuna informazione affidata solo al colore (es. sconti con segno "−" e non solo in rosso).
- **Numeri**: allineati a destra, in cifre tabellari; il totale è sempre l'elemento più evidente.
- **Microcopy**: tutto in italiano, breve e chiaro, anche per errori ("Connessione non riuscita", "L'immagine non sembra uno scontrino").

## Logo e icona
- Il simbolo deve richiamare **uno scontrino** (carta con bordo dentellato o strappato). Può combinarlo con un tocco di "lettura" o "scansione" o con un segno di spunta, ma senza robot o cliché AI.
- Deve funzionare anche a 24 px: forme semplici, al massimo 2-3 colori.
- Il marchio deve essere originale: niente somiglianze con app o marchi esistenti.
- **Da consegnare**:
  - simbolo e logotipo "Scontrini" orizzontale, in SVG;
  - **icona adattiva Android**: livello di primo piano e sfondo separati, safe zone 66/108;
  - **versione monocromatica** per le icone a tema di Android 13+;
  - **icona iOS** 1024×1024 senza trasparenza;
  - versione per sfondo chiaro e per sfondo scuro;
  - splash screen semplice.

## Da consegnare in totale
- Tutte le schermate sopra, in tema chiaro e scuro, con gli stati vuoto, caricamento ed errore.
- I token del design system: colori, tipografia, spaziature e raggi, con i valori esadecimali e le dimensioni in dp, pronti da riportare in un `ThemeData` di Flutter.
- Il logo e le icone nei formati indicati.
