# Scontrini

App **Android e iOS**, open source e senza tracker, per fotografare gli scontrini.
La foto viene letta da un modello AI vision scelto da te, con **la tua chiave API** (BYOK), che estrae
totale, esercente, data e **ogni singola riga**, e **assegna una categoria a ogni riga**.
Tutti i dati restano **solo sul telefono**.

- Nessun account, nessun server: l'app parla soltanto con il servizio AI che configuri.
- Nessun SDK di analytics, crash reporting, pubblicità, Firebase o Google Play Services.
- Le foto non vengono conservate: vanno al servizio AI per la lettura e poi vengono scartate.
- Con OpenRouter l'app chiede `data_collection: deny`, cioè di usare solo fornitori che non conservano i dati e non li usano per l'addestramento.

## Architettura

```
App Flutter ──(HTTPS, la tua chiave)──▶ OpenRouter o servizio compatibile OpenAI (lettura + categorie)
     │
     └──▶ SQLite del sistema (drift + sqflite): scontrini, righe, categorie, impostazioni
```

- **Database**: [drift](https://drift.simonbinder.eu) sopra il SQLite del sistema operativo, tramite [sqflite](https://pub.dev/packages/sqflite) (`drift_sqflite`), nella cartella dati privata dell'app (`<Application Support>/db/scontrini.sqlite`). Resta tra un aggiornamento e l'altro; si perde solo disinstallando l'app.
- **Niente FFI nell'app**: il backend FFI di drift registra funzioni SQL come callback create a runtime in memoria eseguibile, che GrapheneOS segnala come *DCL via memory*. Con sqflite questo non succede e nell'APK non c'è una libreria SQLite precompilata. Per lo stesso motivo niente upsert (`ON CONFLICT DO UPDATE`): il SQLite di Android 7–10 non lo supporta.
- **Aggiornamenti dello schema**: migrazioni versionate (`schemaVersion` in `lib/data/db.dart`), con gli schemi salvati in `drift_schemas/` e test di migrazione generati. Prima di ogni migrazione l'app salva una copia del file del database (`scontrini.pre-upgrade.sqlite`).
- **Importi** in centesimi interi, **date** in UTC.
- **Budget mensili** (totale e per categoria): ogni valore vale dal mese in cui lo imposti in poi, così cambiarlo non tocca i mesi passati. Avviso nell'app quando uno scontrino supera l'80% o il 100%. Entrano nel backup (formato versione 2; i backup della versione 1 si ripristinano ancora).
- **Chiave API**: solo nel Keystore (Android) o nel Keychain (iOS). Non è mai nel binario, nel repository o nei backup.
- **Blocco dell'app (facoltativo)**: PIN di 4–8 cifre salvato solo come hash PBKDF2-HMAC-SHA256 con salt nel Keystore/Keychain, attese crescenti dopo 5 errori; impronta o Face ID con le API di sistema ([local_auth](https://pub.dev/packages/local_auth), BiometricPrompt di AndroidX, niente Play Services), sempre con il PIN come riserva. Si riblocca dopo il tempo scelto fuori dall'app (default 1 minuto); il tempo passato in fotocamera, galleria o selettore di file non conta. Facoltativo anche lo schermo sicuro (`FLAG_SECURE` su Android, sfocatura nelle app recenti su iOS), acceso di default insieme al blocco. Le impostazioni del blocco non entrano nel backup.
- **Backup di sistema disattivato**: su Android `allowBackup="false"` e regole di estrazione che escludono backup su cloud e trasferimento a un nuovo telefono; su iOS la cartella del database è esclusa dal backup iCloud. I dati escono dal telefono solo con il backup manuale dell'app.

## Primo avvio

Al primo avvio scegli:

1. **Inizia**: scegli il servizio AI, il modello e incolla la chiave, poi *Verifica e inizia*. La configurazione viene salvata solo se la chiave funziona.
2. **Ripristina da un backup**: scegli un file di backup; poi inserisci la chiave (che il backup non contiene).

Poi il passo **Proteggi l'app**, facoltativo: PIN, impronta e "Nascondi nelle app recenti". Si può saltare e cambiare in seguito da *Impostazioni → Sicurezza*.

Servizi supportati:

| Servizio | Indirizzo | Modello |
|---|---|---|
| OpenRouter (consigliato) | fisso, `https://openrouter.ai/api/v1` | default `google/gemini-2.5-flash`, qualsiasi modello vision |
| Altro servizio compatibile OpenAI | a scelta, solo `https://` (es. `https://api.openai.com/v1`) | obbligatorio, deve leggere le immagini |

La chiave OpenRouter si crea su openrouter.ai, alla voce *Keys*. Servizio, modello e chiave si cambiano in *Impostazioni*.

## Backup ed esportazione

**Backup** (*Impostazioni → Dati → Crea backup*): un file JSON (`scontrini-backup-AAAA-MM-GG.json`) salvato dove scegli tu con il selettore di sistema (Download, una cartella sincronizzata, una chiavetta…). Contiene scontrini, righe, categorie e le impostazioni AI, **mai la chiave**.

**Ripristino**: solo al primo avvio, quando l'app non contiene ancora dati. Per ripristinare su un'app già in uso bisogna disinstallarla e reinstallarla. Il ripristino è tutto o niente: se il file non è valido non viene importato nulla.

**Esportazione** (*Impostazioni → Dati → Esporta*), per un mese, un anno, un intervallo o tutto:

| Formato | Contenuto |
|---|---|
| CSV righe articolo | una riga per articolo: data, ora, esercente, descrizione, categoria, quantità, prezzo, importo |
| CSV scontrini | una riga per scontrino: totale, somma righe, pagamento, note, avvisi |
| JSON completo | stessa struttura del backup, senza impostazioni (non si può ripristinare) |
| PDF riepilogo | totale, spese per categoria e per mese, elenco degli scontrini |

I CSV sono pensati per Excel e LibreOffice in italiano: separatore `;`, virgola decimale, date `gg/mm/aaaa`, UTF-8 con BOM.

## Build (GitHub Actions)

Il workflow [`Build app`](.github/workflows/build.yml) parte **solo manualmente**: vai in *Actions → Build app → Run workflow*.

- **Android**: APK release, uno per ABI, **firmato con la chiave release del progetto**. La chiave è nei secrets del repo (già configurati):
  - `ANDROID_KEYSTORE_BASE64`: il file `.jks` codificato in base64
  - `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`

  Il log del passo *Prepara keystore di firma* mostra "Firma release configurata". Se i secrets mancassero (per esempio in un fork), il workflow segnala un avviso e firma con la chiave di debug: un APK così non si installa sopra quello firmato con la chiave release.

  Per creare un nuovo keystore (solo per un fork o se la chiave andasse persa):

  ```bash
  keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 4096 -validity 10000 -alias scontrini
  ```

  ```bash
  base64 -w0 release.jks
  ```

  Per aggiornare l'app senza perdere i dati, ogni APK va firmato **con la stessa chiave**: Android rifiuta un aggiornamento firmato diversamente e l'unica via sarebbe disinstallare (backup e ripristino). Conserva una copia del keystore e delle password fuori da GitHub: i secrets non si possono rileggere.
- **iOS**: IPA **non firmato**, da installare con AltStore o Sideloadly. Con un Apple ID gratuito va rifirmato ogni 7 giorni.

### Versioni

Le versioni seguono la data (CalVer) e sono assegnate dal workflow, senza modificare `pubspec.yaml`:

- **nome**: la data della build nel fuso Europe/Rome, per esempio `2026.11.5`;
- **numero di build**: il numero dell'esecuzione del workflow, sempre crescente, che distingue più build nello stesso giorno.

In *Impostazioni → Informazioni* compare come `2026.11.5 (build 57)`; nelle build locali come "sviluppo". Gli artifact hanno lo stesso nome (`scontrini-android-2026.11.5-b57`). Su Android il `versionCode` include anche l'offset per architettura che Flutter aggiunge con `--split-per-abi`.

> **Aggiornamento dalla versione con server Supabase.** La vecchia versione salvava i dati su un server. Questa li tiene sul telefono e non li importa: all'avvio si riparte da zero con il primo avvio (servizio AI e chiave).

## Sviluppo locale

```bash
flutter pub get
```

```bash
flutter run
```

Test (usano un database SQLite in memoria via FFI, con il SQLite del sistema di sviluppo — `winsqlite3` su Windows, `libsqlite3.so.0` su Linux, vedi `hooks` in `pubspec.yaml` — e un servizio AI finto):

```bash
flutter test
```

Dopo una modifica alle tabelle in `lib/data/db.dart` rigenera il codice (i file `*.g.dart` sono nel repository, la CI non li genera):

```bash
dart run build_runner build
```

Per una nuova versione dello schema: incrementa `latestSchemaVersion`, aggiungi il passo in `migration`, poi salva lo schema e genera i test di migrazione:

```bash
dart run drift_dev make-migrations
```

Schermate in tema chiaro e scuro, da confrontare con le tavole del design (finiscono in `tool/screenshots/out/`):

```bash
flutter test tool/screenshots --update-goldens
```

Icone e splash si rigenerano dai PNG in `assets/branding/` (ricavati dagli SVG di `docs/design/brand/`):

```bash
dart run flutter_launcher_icons
```

```bash
dart run flutter_native_splash:create
```

## Struttura

| Percorso | Contenuto |
|---|---|
| `lib/data/db.dart` | tabelle, migrazioni, categorie iniziali |
| `lib/data/repository.dart` | ricerca, filtri, statistiche, avvisi, salvataggio delle letture |
| `lib/data/backup.dart` | backup, ripristino, esportazione JSON |
| `lib/ai/ai_client.dart` | chiamata al servizio AI: prompt, schema JSON, errori |
| `lib/export/` | CSV e PDF |
| `lib/config.dart` | impostazioni e chiave API |

## Design

La specifica della UI, i token del design system e il marchio con le icone sono in [`docs/design/`](docs/design/README.md).

Font: [Manrope](https://github.com/googlefonts/manrope) (SIL Open Font License 1.1), incluso nell'app in `assets/fonts/`.

## Licenza

[GPL-3.0-or-later](LICENSE)
