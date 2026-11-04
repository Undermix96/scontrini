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
- Il token dell'app **non viene compilato nel binario**: lo inserisci una volta in *Impostazioni* e viene salvato cifrato nel Keystore (Android) o nel Keychain (iOS).

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

Al primo avvio apri **Impostazioni**. L'URL del progetto Supabase è già precompilato (`https://iayyyjzjjjbhczzbphof.supabase.co`): incolla l'`APP_TOKEN` e premi *Salva e verifica*.

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

## Sviluppo locale

```bash
flutter pub get
```

```bash
flutter run --dart-define=SUPABASE_URL=https://iayyyjzjjjbhczzbphof.supabase.co
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
| GET | `/receipts?from&to` | elenco degli scontrini |
| GET/PATCH/DELETE | `/receipts/:id` | dettaglio, modifica o eliminazione |
| PATCH | `/items/:id` | modifica una riga (es. `category_id`) |
| GET/POST | `/categories` | elenco o creazione di una categoria |
| PATCH/DELETE | `/categories/:id` | modifica o eliminazione di una categoria |
| GET | `/stats?from&to` | totali per categoria |

## Licenza

[GPL-3.0-or-later](LICENSE)
