import 'package:flutter_test/flutter_test.dart';
import 'package:scontrini/models.dart';

void main() {
  test('Receipt in elenco legge il conteggio righe', () {
    final r = Receipt.fromJson({
      'id': 'a',
      'merchant': 'Coop',
      'purchased_at': '2026-11-04T10:00:00Z',
      'total': '12.50',
      'currency': 'EUR',
      'items': [
        {'count': 3}
      ],
    });
    expect(r.total, 12.5);
    expect(r.itemCount, 3);
    expect(r.items, isEmpty);
  });

  test('Receipt di dettaglio legge le righe', () {
    final r = Receipt.fromJson({
      'id': 'b',
      'total': 5,
      'items': [
        {
          'id': 'i1',
          'position': 0,
          'description': 'Latte',
          'quantity': 2,
          'unit_price': 1.2,
          'total': 2.4,
          'category_id': 1
        },
        {
          'id': 'i2',
          'position': 1,
          'description': 'Sconto',
          'quantity': null,
          'unit_price': null,
          'total': -0.4,
          'category_id': null
        },
      ],
    });
    expect(r.currency, 'EUR');
    expect(r.items.length, 2);
    expect(r.items[1].total, -0.4);
    expect(r.items[1].categoryId, isNull);
  });

  test('Colore categoria da esadecimale', () {
    final c = Category.fromJson({'id': 1, 'name': 'Alimentari', 'color': '#4CAF50', 'sort_order': 10});
    expect(c.colorValue.toARGB32(), 0xFF4CAF50);
  });
}
