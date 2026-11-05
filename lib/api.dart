import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

/// Client per la Edge Function `api`. Nessuna chiamata a servizi terzi:
/// l'app parla solo con il proprio progetto Supabase.
class Api {
  final AppConfig config;
  final http.Client _http;

  Api(this.config, {http.Client? client}) : _http = client ?? http.Client();

  static Uri _uri(String base, String path, [Map<String, String>? query]) =>
      Uri.parse('$base/functions/v1/api$path').replace(queryParameters: query);

  Future<dynamic> _send(String method, String path,
      {Object? body,
      Map<String, String>? query,
      Duration timeout = const Duration(seconds: 30),
      String? url,
      String? token}) async {
    url ??= config.url;
    token ??= config.token;
    if (url.isEmpty || token.isEmpty) throw ApiException(0, 'App non configurata: vai nelle Impostazioni');
    final Uri uri;
    try {
      uri = _uri(url, path, query);
    } catch (_) {
      throw ApiException(0, 'Indirizzo non valido');
    }
    final req = http.Request(method, uri)
      ..headers.addAll({'Content-Type': 'application/json', 'x-app-token': token});
    if (body != null) req.body = jsonEncode(body);
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(timeout));
    } catch (e) {
      throw ApiException(0, 'Connessione non riuscita: $e');
    }
    final text = utf8.decode(res.bodyBytes);
    dynamic data;
    try {
      data = text.isEmpty ? null : jsonDecode(text);
    } catch (_) {
      data = null;
    }
    if (res.statusCode >= 400) {
      final msg = (data is Map && data['error'] != null) ? '${data['error']}' : 'Errore ${res.statusCode}';
      throw ApiException(res.statusCode, msg);
    }
    return data;
  }

  Future<void> health() async => _send('GET', '/health');

  /// Verifica indirizzo e token senza salvarli. Lancia [ApiException] con
  /// status 0 se il server non è raggiungibile e 401 se il token è rifiutato.
  Future<void> probe(String url, String token) async =>
      _send('GET', '/health', url: AppConfig.normalizeUrl(url), token: token.trim(), timeout: const Duration(seconds: 15));

  // Categorie
  Future<List<Category>> categories() async {
    final data = await _send('GET', '/categories') as List;
    return data.map((e) => Category.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> addCategory(String name, String color) =>
      _send('POST', '/categories', body: {'name': name, 'color': color});

  Future<void> updateCategory(int id, {String? name, String? color}) => _send('PATCH', '/categories/$id', body: {
        if (name != null) 'name': name,
        if (color != null) 'color': color,
      });

  Future<void> deleteCategory(int id) => _send('DELETE', '/categories/$id');

  // Scontrini
  Future<Receipt> scan(Uint8List image, String mimeType) async {
    final data = await _send('POST', '/scan',
        body: {'image_base64': base64Encode(image), 'mime_type': mimeType}, timeout: const Duration(seconds: 120));
    return Receipt.fromJson(data as Map<String, dynamic>);
  }

  Future<List<Receipt>> receipts({DateTime? from, DateTime? to, String? q, int? categoryId}) async {
    final data = await _send('GET', '/receipts', query: {
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      if (categoryId != null) 'category_id': '$categoryId',
      'limit': '500',
    }) as List;
    return data.map((e) => Receipt.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Tutti gli scontrini, scaricati a pagine.
  Future<List<Receipt>> allReceipts() async {
    const page = 500;
    final out = <Receipt>[];
    while (true) {
      final data = await _send('GET', '/receipts', query: {'limit': '$page', 'offset': '${out.length}'}) as List;
      out.addAll(data.map((e) => Receipt.fromJson(e as Map<String, dynamic>)));
      if (data.length < page) return out;
    }
  }

  Future<Receipt> receipt(String id) async =>
      Receipt.fromJson(await _send('GET', '/receipts/$id') as Map<String, dynamic>);

  Future<Receipt> updateReceipt(String id, Map<String, dynamic> fields) async =>
      Receipt.fromJson(await _send('PATCH', '/receipts/$id', body: fields) as Map<String, dynamic>);

  Future<void> deleteReceipt(String id) => _send('DELETE', '/receipts/$id');

  /// Ignora gli avvisi indicati per questo scontrino (sostituisce l'elenco).
  Future<Receipt> setDismissedWarnings(String id, List<String> codes) => updateReceipt(id, {'dismissed_warnings': codes});

  Future<void> updateItem(String id, Map<String, dynamic> fields) => _send('PATCH', '/items/$id', body: fields);

  Future<ReceiptItem> addItem(String receiptId, Map<String, dynamic> fields) async => ReceiptItem.fromJson(
      await _send('POST', '/receipts/$receiptId/items', body: fields) as Map<String, dynamic>);

  Future<void> deleteItem(String id) => _send('DELETE', '/items/$id');

  Future<List<CategoryTotal>> stats({DateTime? from, DateTime? to}) async {
    final data = await _send('GET', '/stats', query: {
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
    }) as List;
    return data.map((e) => CategoryTotal.fromJson(e as Map<String, dynamic>)).toList();
  }
}
