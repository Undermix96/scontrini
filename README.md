# Scontrini

App **Android e iOS**, open source e senza tracker, per fotografare gli scontrini.
La foto viene analizzata da un modello vision tramite [OpenRouter](https://openrouter.ai), che estrae
totale, esercente, data e **ogni singola riga**, e **assegna una categoria a ogni riga**.
I dati vengono salvati in un database [Supabase](https://supabase.com).

- Nessun account o login: un solo profilo.
- Nessun SDK di analytics, crash reporting, pubblicità, Firebase o Google Play Services.
- Le foto non vengono conservate: servono per l'analisi e poi vengono scartate.
- A OpenRouter viene chiesto `data_collection: deny`, cioè di instradare la richiesta solo verso provider che non conservano i dati e non li usano per il training.

## Architettura

```
App Flutter ──(HTTPS, header x-app-token)──▶ Supabase Edge Function "api" ──▶ OpenRouter (OCR + categorie)
                                                     │
                                                     └──▶ Postgres (receipts, receipt_items, categories)
```

- Le tabelle hanno **RLS attiva senza policy** e nessun privilegio per `anon` e `authenticated`: dall'esterno non si possono né leggere né scrivere.
- La Edge Function usa la service role, che resta sul server, e accetta solo richieste con il token `APP_TOKEN`.
- La chiave OpenRouter esiste **solo** nei secrets di Supabase, mai nell'app né nel repo.
- Il token dell'app **non viene compilato nel binario**: lo inserisci una volta al primo avvio e viene salvato cifrato nel Keystore (Android) o nel Keychain (iOS).

## Configurazione

### 1. Secrets di Supabase

Dalla dashboard del progetto vai in **Edge Functions → Secrets** e aggiungi:

| Nome | Valore |
|---|---|
| `OPENROUTER_API_KEY` | la tua chiave OpenRouter (`sk-or-...`) |
| `APP_TOKEN` | una stringa casuale lunga, almeno 24 caratteri (vedi sotto) |
| `OPENROUTER_MODEL` | *(opzionale)* modello vision, default `google/gemini-2.5-flash` |

Per generare un token casuale:

```bash
openssl rand -base64 36
```

In PowerShell:

```powershell
[Convert]::ToBase64String((1..36 | % { [byte](Get-Random -Max 256) }))
```

### 2. App

Al primo avvio l'app chiede **indirizzo del server** e **token di accesso**. L'URL del progetto Supabase è già precompilato (`https://iayyyjzjjjbhczzbphof.supabase.co`): incolla l'`APP_TOKEN` e premi *Prova e collega*. La configurazione viene salvata solo se la verifica riesce; la puoi cambiare in seguito da *Impostazioni*.

## Build (GitHub Actions)

Il workflow [`Build app`](.github/workflows/build.yml) parte **solo manualmente**: vai in *Actions → Build app → Run workflow*.

- **Android**: APK release, uno per ABI. Se configuri questi secrets nel repo, l'APK è firmato con la tua chiave; altrimenti viene firmato con la chiave di debug.
  - `ANDROID_KEYSTORE_BASE64`: il file `.jks` codificato in base64
  - `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`

  Per creare un keystore:

  ```bash
  keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 4096 -validity 10000 -alias scontrini
  ```

  ```bash
  base64 -w0 release.jks
  ```
- **iOS**: IPA **non firmato**, da installare con AltStore o Sideloadly. Con un Apple ID gratuito va rifirmato ogni 7 giorni.

Variabile del repo (non segreta): `SUPABASE_URL`, che viene precompilata nell'app.

### Versioni

Le versioni seguono la data (CalVer) e sono assegnate dal workflow, senza modificare `pubspec.yaml`:

- **nome**: la data della build nel fuso Europe/Rome, per esempio `2026.11.5`;
- **numero di build**: il numero dell'esecuzione del workflow, sempre crescente, che distingue più build nello stesso giorno.

In *Impostazioni → Informazioni* compare come `2026.11.5 (build 57)`; nelle build locali come "sviluppo". Gli artifact hanno lo stesso nome (`scontrini-android-2026.11.5-b57`). Su Android il `versionCode` include anche l'offset per architettura che Flutter aggiunge con `--split-per-abi`.

> **Aggiornamento da una build con versione 0.1.0 (Android).** `flutter_secure_storage` è passato dalla 9 alla 11, che non legge più i dati salvati con il vecchio sistema. Al primo avvio l'app chiede di nuovo indirizzo e token: l'indirizzo è già precompilato, basta incollare il token. I dati sul server non cambiano.

## Sviluppo locale

```bash
flutter pub get
```

```bash
flutter run --dart-define=SUPABASE_URL=https://iayyyjzjjjbhczzbphof.supabase.co
```

Test:

```bash
flutter test
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

Backend:
- schema: `supabase/migrations/`
- Edge Function: `supabase/functions/api/`

Per deployarli con la Supabase CLI:

```bash
npx supabase functions deploy api --project-ref iayyyjzjjjbhczzbphof --no-verify-jwt
```

## API della Edge Function

Tutte le richieste richiedono l'header `x-app-token`.

| Metodo | Percorso | Descrizione |
|---|---|---|
| GET | `/health` | test della connessione |
| POST | `/scan` | `{image_base64, mime_type}`: analizza e salva uno scontrino |
| GET | `/receipts?from&to&q&category_id` | elenco degli scontrini, con ricerca, filtro, avvisi e categoria prevalente |
| GET/PATCH/DELETE | `/receipts/:id` | dettaglio, modifica (anche `dismissed_warnings`) o eliminazione |
| POST | `/receipts/:id/items` | aggiunge una riga |
| PATCH/DELETE | `/items/:id` | modifica (es. `category_id`) o elimina una riga |
| GET/POST | `/categories` | elenco (con il numero di righe) o creazione di una categoria |
| PATCH/DELETE | `/categories/:id` | modifica o eliminazione di una categoria |
| GET | `/stats?from&to` | totali per categoria |

## Design

La specifica della UI, i token del design system e il marchio con le icone sono in [`docs/design/`](docs/design/README.md).

Font: [Manrope](https://github.com/googlefonts/manrope) (SIL Open Font License 1.1), incluso nell'app in `assets/fonts/`.

## Licenza

[GPL-3.0-or-later](LICENSE)
