# Prompt per Claude Design — UI e logo di "Scontrini"

Progetta da zero la UI mobile (Android e iOS) e il logo di **Scontrini**, un'app open source per tenere traccia delle spese fotografando gli scontrini.

## Cosa fa
- Si fotografa uno scontrino (o lo si sceglie dalla galleria); un'AI ne legge esercente, data, totale e ogni singola riga, e assegna una categoria a ogni riga. L'analisi richiede qualche secondo.
- Si consultano tutti i movimenti nel tempo e il dettaglio di ogni scontrino.
- Si correggono i dati letti male: categoria di una riga, importi, esercente, data. L'app segnala quando qualcosa non torna (somma delle righe diversa dal totale, data sospetta, possibile scontrino doppio).
- Si vede quanto si è speso per categoria in un mese.
- Le categorie sono predefinite ma l'utente può aggiungerle, rinominarle, ricolorarle ed eliminarle.
- Al primo avvio si inseriscono indirizzo del server e token di accesso.

## Contesto
- Un solo utente, nessun account. Interfaccia solo in italiano, importi in euro.
- Software libero, zero tracker, attenzione alla privacy: la foto non viene conservata.
- Verrà sviluppata in Flutter: il design deve essere realizzabile lì, con tema chiaro e scuro.

## Logo
Un marchio originale per l'app, leggibile anche a dimensioni piccole. Serve come icona Android (adattiva, con versione monocromatica), icona iOS e splash screen.

## Da consegnare
Le schermate principali in tema chiaro e scuro, i token del design system (colori, tipografia, spaziature) e il logo con le icone.
