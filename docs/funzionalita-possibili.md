# Funzionalità possibili per Scontrini

Analisi delle funzioni presenti nelle app simili negli store (Expensify, Smart Receipts, Wallet, Money Manager, Splitwise, Klippa, Veryfi, Spesa Smart e altre), basata su conoscenza generale del mercato e non su una ricerca aggiornata.

## Cosa fa già l'app

- Scansione da fotocamera o galleria
- Estrazione AI di righe e categorie (BYOK)
- Ricerca e filtro per categoria in Movimenti
- Rilevamento dei duplicati e avvisi
- Statistiche per categoria (grafico a ciambella)
- Export CSV, JSON e PDF
- Backup manuale (ZIP con le foto, se conservate)
- Inserimento manuale di una spesa, con più righe
- Budget mensile, totale e per categoria, con storico e avvisi all'80% e al 100%
- Grafici: ultimi 12 mesi, andamento del mese rispetto al precedente, esercenti
- Ritaglio e raddrizzamento della foto (codice nostro, senza ML Kit)
- Foto conservate (facoltative), nella cartella privata dell'app
- Più scontrini di fila in coda e scontrini lunghi in più foto
- Blocco dell'app con PIN e impronta (facoltativo), schermo sicuro

## Legenda

- ✅ compatibile con la filosofia FOSS
- ⚠️ compatibile solo a certe condizioni
- ❌ non compatibile

## 1. Molto diffuse (quasi tutte le app le hanno)

| Funzione | FOSS | Note |
|---|---|---|
| Budget mensile, totale o per categoria, con avviso se superato | ✅ | Tutto in locale, notifiche locali |
| Inserimento manuale di una spesa senza scontrino | ✅ | Serve anche quando l'AI non è raggiungibile |
| Grafici dell'andamento nel tempo (barre per mese, confronto con il mese prima) | ✅ | Oggi c'è solo la ciambella per categoria |
| Conservare la foto dello scontrino | ✅ | Oggi viene scartata. Si può renderla facoltativa e cifrata nella cartella privata dell'app; serve per resi e garanzie |
| Scansione di più scontrini di fila e di scontrini lunghi in più foto | ✅ | |
| Ritaglio e raddrizzamento automatico della foto | ⚠️ | Il document scanner di Google (ML Kit) richiede Play Services ❌. Va fatto con codice nostro o OpenCV ✅ |
| OCR in locale, senza AI in cloud | ⚠️ | ML Kit ❌. Tesseract o un modello vision locale ✅, ma molto meno precisi |
| Sincronizzazione cloud e multi-dispositivo con account | ❌ | Va contro "nessun account, nessun server". L'alternativa FOSS è la voce seguente |
| Sincronizzazione su una cartella scelta dall'utente (WebDAV, Nextcloud, Syncthing) | ✅ | Con backup cifrato |
| Blocco dell'app con PIN o impronta | ✅ | `local_auth` usa le API di sistema, non Play Services |

## 2. Diffuse (app di fascia media e alta)

| Funzione | FOSS | Note |
|---|---|---|
| Promemoria per garanzie e resi (scadenza a 14 giorni o 2 anni) | ✅ | Molto utile in Italia/UE. Sfrutta la foto conservata |
| Tag ed etichette oltre alle categorie (es. "vacanza", "casa al mare") | ✅ | |
| Spese ricorrenti e abbonamenti | ✅ | |
| Più valute con conversione | ⚠️ | Il campo `currency` esiste già. I tassi vanno presi da una fonte aperta (BCE) o inseriti a mano |
| Storico dei prezzi di un articolo ("il latte costa +12% rispetto a marzo") | ✅ | Le righe sono già salvate: qui l'app può distinguersi |
| Riepilogo per esercente (dove spendo di più) | ✅ | |
| Divisione della spesa tra persone (tipo Splitwise) | ✅ in locale / ❌ se condivisa via server | |
| Condividere uno scontrino come immagine o PDF | ✅ | |
| Widget sulla schermata home (totale del mese, scansione rapida) | ✅ | |
| Modalità aziendale/professionale: note spese e rimborsi | ✅ | Export PDF già presente, va solo esteso |
| Collegamento ai conti bancari (open banking, PSD2) | ❌ | Aggregatori proprietari, token bancari, server intermedi |

## 3. Di nicchia, o che rendono l'app diversa dalle altre

| Funzione | FOSS | Note |
|---|---|---|
| Spese sanitarie e detraibili per il 730 (farmacia, codice fiscale sullo scontrino) | ✅ | Molto italiano, quasi nessuna app lo fa bene |
| Lettura del QR o codice del documento commerciale | ✅ | Con un decoder non ML Kit (es. zxing) |
| Inflazione personale (il tuo paniere nel tempo) | ✅ | |
| Lista della spesa generata dagli articoli comprati spesso | ✅ | |
| Domande in linguaggio naturale ("quanto ho speso in carne a ottobre?") con la chiave AI dell'utente | ⚠️ | FOSS solo se esplicito e opzionale: invia dati aggregati al provider |
| Supporto a Ollama o LM Studio in rete locale (AI tutta sul proprio PC) | ✅ | Oggi l'app accetta solo `https://`, che blocca l'IP locale in `http` |
| Distribuzione su F-Droid | ✅ | Le dipendenze sembrano già compatibili: va verificato che la build sia riproducibile |
| Confronto prezzi tra supermercati con dati condivisi dagli utenti | ❌ | Richiede un server centrale e dati degli utenti in uscita |
| Cashback, offerte, programmi fedeltà, affiliazioni | ❌ | Tracciamento e commerciale per natura |
| Analytics e crash reporting (Firebase, Sentry SaaS) | ❌ | Escluso dal README. Si può solo esportare il log a mano ✅ |
| Funzioni premium o abbonamento in-app | ❌ | Play Billing è proprietario. Le donazioni (Liberapay) sono ✅ |

## Priorità consigliate

Le funzioni che rendono di più tenendo i dati locali:

1. **Conservare la foto (facoltativo) + promemoria garanzie e resi**
2. **Budget per categoria**
3. **Storico prezzi per articolo**: le righe ci sono già, quasi nessuna app lo fa
4. **Inserimento manuale + grafico mensile**
5. **Backup cifrato verso una cartella o WebDAV**: risponde alla richiesta di sincronizzazione senza server

## Vincolo trasversale

Tutto ciò che si appoggia a ML Kit o Play Services (scanner, OCR, codici a barre) va sostituito con librerie aperte, altrimenti si perdono F-Droid e la compatibilità con GrapheneOS.
