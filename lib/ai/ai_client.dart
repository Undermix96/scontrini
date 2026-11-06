import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Servizio AI a cui l'app manda la foto. Entrambi usano il formato
/// `/chat/completions` di OpenAI.
enum AiProvider {
  openRouter('openrouter', 'OpenRouter'),
  openAiCompatible('openai_compatible', 'Altro servizio');

  final String code;
  final String label;
  const AiProvider(this.code, this.label);

  static AiProvider fromCode(String? code) =>
      values.firstWhere((p) => p.code == code, orElse: () => AiProvider.openRouter);
}

const openRouterBaseUrl = 'https://openrouter.ai/api/v1';
const defaultOpenRouterModel = 'google/gemini-2.5-flash';

/// Configurazione di una chiamata: tutto ciò che serve tranne la foto.
class AiEndpoint {
  final AiProvider provider;

  /// Solo per [AiProvider.openAiCompatible], es. https://api.openai.com/v1
  final String baseUrl;
  final String model;
  final String apiKey;

  const AiEndpoint({required this.provider, this.baseUrl = '', required this.model, required this.apiKey});

  String get effectiveBaseUrl => provider == AiProvider.openRouter ? openRouterBaseUrl : normalizeBaseUrl(baseUrl);

  static String normalizeBaseUrl(String url) => url.trim().replaceAll(RegExp(r'/+$'), '');
}

/// Errore della chiamata all'AI. [kind] permette alle schermate di mostrare
/// il messaggio sotto il campo giusto.
enum AiErrorKind { network, badKey, badUrl, badModel, noCredit, rateLimit, notReceipt, badResponse, other }

class AiException implements Exception {
  final AiErrorKind kind;
  final String message;
  AiException(this.kind, this.message);
  @override
  String toString() => message;
}

/// Risultato della lettura: il JSON dello schema e il modello che ha risposto.
class AiScan {
  final Map<String, dynamic> parsed;
  final String model;
  AiScan(this.parsed, this.model);
}

const _maxImageBytes = 9 * 1024 * 1024;

/// Parti al massimo per uno scontrino lungo (foto nella stessa richiesta).
const maxScanParts = 6;
final _mimeOk = RegExp(r'^image/(jpeg|png|webp|heic|heif)$');

/// Chiama direttamente il servizio AI scelto dall'utente con la sua chiave.
/// Nessun server intermedio: la foto va solo lì e non viene salvata.
class AiClient {
  final http.Client _http;
  AiClient({http.Client? client}) : _http = client ?? http.Client();

  Map<String, String> _headers(AiEndpoint e) => {
        'Authorization': 'Bearer ${e.apiKey.trim()}',
        'Content-Type': 'application/json',
        if (e.provider == AiProvider.openRouter) 'X-Title': 'Scontrini',
      };

  Uri _uri(AiEndpoint e, String path) {
    final base = e.effectiveBaseUrl;
    final uri = Uri.tryParse('$base$path');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw AiException(AiErrorKind.badUrl, "L'indirizzo deve iniziare con https://");
    }
    return uri;
  }

  Future<http.Response> _send(http.BaseRequest req, Duration timeout) async {
    try {
      return await http.Response.fromStream(await _http.send(req).timeout(timeout));
    } catch (e) {
      throw AiException(AiErrorKind.network, 'Connessione non riuscita. Controlla la rete e riprova.');
    }
  }

  static AiException _httpError(int status, String body, {bool probing = false}) {
    String detail = '';
    try {
      final j = jsonDecode(body);
      final err = j is Map ? j['error'] : null;
      detail = err is Map ? '${err['message'] ?? ''}' : (err is String ? err : '');
    } catch (_) {}
    switch (status) {
      case 401:
      case 403:
        return AiException(AiErrorKind.badKey, 'Il servizio ha rifiutato la chiave. Controlla di averla copiata per intero.');
      case 402:
        return AiException(AiErrorKind.noCredit, 'Credito esaurito sul servizio AI.');
      case 404:
        return probing
            ? AiException(AiErrorKind.badUrl, 'A questo indirizzo non risponde un servizio compatibile OpenAI.')
            : AiException(AiErrorKind.badModel, 'Modello non trovato. Controlla il nome del modello.');
      case 429:
        return AiException(AiErrorKind.rateLimit, 'Troppe richieste: riprova tra poco.');
    }
    final suffix = detail.isEmpty ? '' : ': ${detail.length > 200 ? '${detail.substring(0, 200)}…' : detail}';
    return AiException(AiErrorKind.other, 'Errore del servizio AI ($status)$suffix');
  }

  /// Verifica chiave e indirizzo senza salvarli.
  Future<void> probe(AiEndpoint e) async {
    if (e.apiKey.trim().isEmpty) throw AiException(AiErrorKind.badKey, 'Inserisci la chiave API');
    final path = e.provider == AiProvider.openRouter ? '/key' : '/models';
    final req = http.Request('GET', _uri(e, path))..headers.addAll(_headers(e));
    final res = await _send(req, const Duration(seconds: 15));
    if (res.statusCode >= 400) throw _httpError(res.statusCode, utf8.decode(res.bodyBytes), probing: true);
  }

  /// Legge lo scontrino nella foto. [categories] sono i nomi tra cui l'AI
  /// deve scegliere per ogni riga.
  Future<AiScan> scan(AiEndpoint e, Uint8List image, String mime, List<String> categories) =>
      scanParts(e, [(image, mime)], categories);

  /// Legge uno scontrino fotografato in più parti (scontrino lungo), dall'alto
  /// in basso, con una sola richiesta.
  Future<AiScan> scanParts(AiEndpoint e, List<(Uint8List, String)> parts, List<String> categories) async {
    if (parts.isEmpty || parts.length > maxScanParts) {
      throw AiException(AiErrorKind.other, 'Da 1 a $maxScanParts foto per scontrino');
    }
    final size = parts.fold<int>(0, (s, p) => s + p.$1.length);
    if (size > _maxImageBytes) throw AiException(AiErrorKind.other, 'Immagine troppo grande');
    if (parts.any((p) => !_mimeOk.hasMatch(p.$2))) {
      throw AiException(AiErrorKind.other, 'Formato immagine non supportato');
    }
    if (e.model.trim().isEmpty) throw AiException(AiErrorKind.badModel, 'Indica il modello da usare nelle Impostazioni');

    final body = requestBody(e, [for (final (b, m) in parts) (base64Encode(b), m)], categories);
    var res = await _post(e, body);
    // Alcuni servizi compatibili non supportano json_schema: un secondo
    // tentativo senza, affidandosi alle istruzioni del prompt.
    if (res.statusCode == 400 && e.provider == AiProvider.openAiCompatible) {
      res = await _post(e, Map.of(body)..remove('response_format'));
    }
    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode >= 400) throw _httpError(res.statusCode, text);
    return parseResponse(text, e.model);
  }

  Future<http.Response> _post(AiEndpoint e, Map<String, dynamic> body) {
    final req = http.Request('POST', _uri(e, '/chat/completions'))
      ..headers.addAll(_headers(e))
      ..body = jsonEncode(body);
    return _send(req, const Duration(seconds: 120));
  }

  /// Corpo della richiesta: il prompt e una o più immagini (base64, tipo).
  static Map<String, dynamic> requestBody(AiEndpoint e, List<(String, String)> images, List<String> categories) => {
        'model': e.model.trim(),
        'temperature': 0,
        // Chiede ai provider di OpenRouter di non conservare/usare i dati per training.
        if (e.provider == AiProvider.openRouter) 'provider': {'data_collection': 'deny'},
        'response_format': {
          'type': 'json_schema',
          'json_schema': {'name': 'receipt', 'strict': true, 'schema': receiptSchema(categories)},
        },
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt(categories, parts: images.length)},
              for (final (b64, mime) in images)
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:$mime;base64,$b64'}
                },
            ],
          },
        ],
      };

  static AiScan parseResponse(String text, String model) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw AiException(AiErrorKind.badResponse, 'Risposta del servizio AI non interpretabile');
    }
    final choices = data['choices'];
    var content = choices is List && choices.isNotEmpty ? '${choices.first['message']?['content'] ?? ''}' : '';
    content = content.trim().replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '');
    content = content.replaceFirst(RegExp(r'```$'), '').trim();
    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      throw AiException(AiErrorKind.badResponse, 'Risposta del modello non interpretabile');
    }
    if (parsed['is_receipt'] == false) {
      throw AiException(AiErrorKind.notReceipt, "L'immagine non sembra uno scontrino");
    }
    return AiScan(parsed, (data['model'] as String?) ?? model);
  }

  static String prompt(List<String> categories, {int parts = 1}) => [
        'Sei un sistema OCR per scontrini (spesso italiani).',
        if (parts > 1)
          'Le $parts immagini sono parti consecutive dello STESSO scontrino lungo, nell\'ordine dall\'alto in basso: '
              'leggile come un unico scontrino. Le righe che compaiono in due parti per la sovrapposizione '
              'delle foto vanno contate una volta sola.',
        'Estrai esercente, data/ora, totale complessivo, valuta, metodo di pagamento e TUTTE le righe articolo.',
        'Per ogni riga indica descrizione leggibile, quantità, prezzo unitario, importo totale della riga',
        'e assegna una categoria scegliendo SOLO tra: ${categories.join(', ')}.',
        "Sconti e abbuoni vanno come righe con importo negativo, nella categoria dell'articolo scontato se evidente, altrimenti 'Altro'.",
        'Ignora righe di IVA, subtotali, resto e totali: non sono articoli.',
        'Usa il punto come separatore decimale. Se un dato non è leggibile usa null.',
        'Rispondi solo con il JSON richiesto.',
      ].join(' ');

  static Map<String, dynamic> receiptSchema(List<String> categories) => {
        'type': 'object',
        'additionalProperties': false,
        'required': ['is_receipt', 'merchant', 'purchased_at', 'total', 'currency', 'payment_method', 'items'],
        'properties': {
          'is_receipt': {'type': 'boolean', 'description': "false se l'immagine non è uno scontrino/ricevuta"},
          'merchant': {
            'type': ['string', 'null'],
            'description': "Nome dell'esercente"
          },
          'purchased_at': {
            'type': ['string', 'null'],
            'description': "Data e ora d'acquisto ISO 8601, es. 2026-11-04T18:30:00"
          },
          'total': {'type': 'number', 'description': 'Totale pagato (TOTALE COMPLESSIVO)'},
          'currency': {'type': 'string', 'description': 'Codice ISO 4217, es. EUR'},
          'payment_method': {
            'type': ['string', 'null'],
            'description': 'contanti, carta, bancomat, ...'
          },
          'items': {
            'type': 'array',
            'items': {
              'type': 'object',
              'additionalProperties': false,
              'required': ['description', 'quantity', 'unit_price', 'total', 'category'],
              'properties': {
                'description': {'type': 'string'},
                'quantity': {
                  'type': ['number', 'null']
                },
                'unit_price': {
                  'type': ['number', 'null']
                },
                'total': {'type': 'number', 'description': 'Importo della riga; negativo per sconti'},
                'category': {'type': 'string', 'enum': categories},
              },
            },
          },
        },
      };
}
