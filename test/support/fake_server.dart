import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scontrini/api.dart';
import 'package:scontrini/app_state.dart';
import 'package:scontrini/config.dart';

/// Server finto con dati simili a quelli delle tavole del design.
class FakeServer {
  final DateTime now;
  final requests = <http.Request>[];

  /// Se impostato, /scan resta in attesa finché non viene completato.
  Completer<http.Response>? scanCompleter;

  /// Stato restituito da /health (401 per simulare un token rifiutato).
  int healthStatus = 200;

  FakeServer({DateTime? now}) : now = now ?? DateTime.now();

  static const categories = [
    {'id': 1, 'name': 'Alimentari', 'color': '#4CC38A', 'sort_order': 10, 'item_count': 212},
    {'id': 2, 'name': 'Bevande', 'color': '#F0A35A', 'sort_order': 20, 'item_count': 41},
    {'id': 3, 'name': 'Casa', 'color': '#5AA9F0', 'sort_order': 30, 'item_count': 64},
    {'id': 4, 'name': 'Igiene', 'color': '#E67AC4', 'sort_order': 40, 'item_count': 27},
    {'id': 5, 'name': 'Salute', 'color': '#F26D6D', 'sort_order': 50, 'item_count': 12},
    {'id': 9, 'name': 'Svago', 'color': '#A99CFF', 'sort_order': 90, 'item_count': 6},
    {'id': 10, 'name': 'Altro', 'color': '#8E8C9C', 'sort_order': 100, 'item_count': 15},
  ];

  String _at(int daysAgo, int h, int m) =>
      DateTime(now.year, now.month, now.day - daysAgo, h, m).toUtc().toIso8601String();

  List<Map<String, dynamic>> get receipts => [
        {
          'id': 'r1',
          'merchant': 'Esselunga',
          'purchased_at': _at(0, 18, 42),
          'created_at': _at(0, 18, 50),
          'total': 64.2,
          'currency': 'EUR',
          'payment_method': 'carta',
          'items': [
            {'count': 18}
          ],
          'items_sum': 62.7,
          'dominant_category_id': 1,
          'warnings': ['total_mismatch'],
          'dismissed_warnings': [],
          'duplicate_of': null,
        },
        {
          'id': 'r2',
          'merchant': 'Farmacia Comunale',
          'purchased_at': _at(0, 10, 5),
          'created_at': _at(0, 10, 10),
          'total': 18.9,
          'currency': 'EUR',
          'items': [
            {'count': 2}
          ],
          'items_sum': 18.9,
          'dominant_category_id': 5,
          'warnings': [],
          'dismissed_warnings': [],
        },
        {
          'id': 'r3',
          'merchant': 'Coop',
          'purchased_at': _at(1, 19, 2),
          'created_at': _at(1, 19, 5),
          'total': 37.85,
          'currency': 'EUR',
          'items': [
            {'count': 9}
          ],
          'items_sum': 37.85,
          'dominant_category_id': 1,
          'warnings': ['duplicate'],
          'dismissed_warnings': [],
          'duplicate_of': 'r9',
        },
        {
          'id': 'r4',
          'merchant': 'Bar Centrale',
          'purchased_at': _at(1, 8, 15),
          'created_at': _at(1, 8, 20),
          'total': 4.3,
          'currency': 'EUR',
          'items': [
            {'count': 2}
          ],
          'items_sum': 4.3,
          'dominant_category_id': 2,
          'warnings': [],
          'dismissed_warnings': [],
        },
      ];

  Map<String, dynamic> get receiptDetail => {
        ...receipts.first,
        'ai_model': 'google/gemini-2.5-flash',
        'duplicate': null,
        'items': [
          _item('i1', 0, 'Latte intero 1 l', 2, 0.65, 1.3, 1),
          _item('i2', 1, 'Pane casereccio', null, null, 2.1, 1),
          _item('i3', 2, 'Detersivo piatti', null, null, 3.49, 3),
          _item('i4', 3, 'Mele Golden', 1.24, 1.99, 2.47, 1),
          _item('i5', 4, 'Acqua frizzante 6×1,5 l', null, null, 2.94, 2),
          _item('i6', 5, 'Spazzolino', null, null, 50.4, 4),
        ],
      };

  static Map<String, dynamic> _item(String id, int pos, String d, double? q, double? u, double t, int? cat) =>
      {'id': id, 'position': pos, 'description': d, 'quantity': q, 'unit_price': u, 'total': t, 'category_id': cat};

  List<Map<String, dynamic>> stats(Uri uri) {
    final from = DateTime.parse(uri.queryParameters['from']!).toLocal();
    final current = from.year == now.year && from.month == now.month;
    if (!current) {
      return [
        {'category_id': 1, 'total': 300.0},
        {'category_id': 3, 'total': 223.4},
      ];
    }
    return [
      {'category_id': 1, 'total': 236.3},
      {'category_id': 3, 'total': 96.5},
      {'category_id': 2, 'total': 58.2},
      {'category_id': 4, 'total': 41.0},
      {'category_id': 5, 'total': 32.1},
      {'category_id': null, 'total': 18.2},
    ];
  }

  late final client = MockClient((req) async {
    requests.add(req);
    final path = req.url.path.replaceFirst('/functions/v1/api', '');
    http.Response ok(Object body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json; charset=utf-8'});
    if (path == '/health') {
      return healthStatus == 200 ? ok({'ok': true}) : ok({'error': 'Token non valido'}, healthStatus);
    }
    if (path == '/categories') return ok(categories);
    if (path == '/receipts' && req.method == 'GET') {
      final q = req.url.queryParameters['q'];
      final cat = req.url.queryParameters['category_id'];
      var list = receipts;
      if (q != null) list = list.where((r) => '${r['merchant']}'.toLowerCase().contains(q.toLowerCase())).toList();
      if (cat != null) list = list.where((r) => '${r['dominant_category_id']}' == cat).toList();
      return ok(list);
    }
    if (path.startsWith('/receipts/') && req.method == 'GET') return ok(receiptDetail);
    if (path == '/stats') return ok(stats(req.url));
    if (path == '/scan') return scanCompleter?.future ?? ok(receiptDetail, 201);
    return ok({'ok': true});
  });

  AppState state({bool configured = true}) {
    final config = AppConfig();
    if (configured) {
      config.url = 'https://example.supabase.co';
      config.token = 'test-token-test-token-test-token';
    }
    return AppState(config, api: Api(config, client: client));
  }
}
