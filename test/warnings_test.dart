import 'package:flutter_test/flutter_test.dart';
import 'package:scontrini/models.dart';
import 'package:scontrini/warnings.dart';

ReceiptItem _item(double total) =>
    ReceiptItem(id: '$total', position: 0, description: 'x', quantity: null, unitPrice: null, total: total, categoryId: null);

Receipt _receipt({
  double total = 10,
  List<double> items = const [10],
  DateTime? purchasedAt,
  DateTime? createdAt,
  String? duplicateOf,
  List<String> dismissed = const [],
}) =>
    Receipt(
      id: 'r',
      total: total,
      currency: 'EUR',
      items: items.map(_item).toList(),
      purchasedAt: purchasedAt ?? DateTime(2026, 11, 5),
      createdAt: createdAt ?? DateTime(2026, 11, 5, 12),
      duplicateOf: duplicateOf,
      dismissedWarnings: dismissed,
    );

void main() {
  test('nessun avviso se tutto torna', () {
    expect(computeWarnings(_receipt()), isEmpty);
  });

  test('tolleranza di un centesimo sul totale', () {
    expect(computeWarnings(_receipt(total: 10.01)), isEmpty);
    expect(computeWarnings(_receipt(total: 10.02)), [ReceiptWarning.totalMismatch]);
  });

  test('somma con decimali non dà falsi positivi', () {
    expect(computeWarnings(_receipt(total: 0.3, items: [0.1, 0.2])), isEmpty);
  });

  test('scontrino senza righe non segnala il totale', () {
    expect(computeWarnings(_receipt(items: [])), isEmpty);
  });

  test('data troppo vecchia o futura rispetto alla scansione', () {
    final created = DateTime(2026, 11, 5);
    expect(computeWarnings(_receipt(purchasedAt: DateTime(2026, 8, 1), createdAt: created)), [ReceiptWarning.date]);
    expect(computeWarnings(_receipt(purchasedAt: DateTime(2026, 11, 7), createdAt: created)), [ReceiptWarning.date]);
    expect(computeWarnings(_receipt(purchasedAt: DateTime(2026, 10, 1), createdAt: created)), isEmpty);
  });

  test('ordine di priorità e avvisi ignorati', () {
    final r = _receipt(total: 12, duplicateOf: 'x', purchasedAt: DateTime(2025, 1, 1));
    expect(computeWarnings(r), [ReceiptWarning.totalMismatch, ReceiptWarning.duplicate, ReceiptWarning.date]);
    r.dismissedWarnings = ['total_mismatch', 'date'];
    expect(computeWarnings(r), [ReceiptWarning.duplicate]);
  });

  test('somma righe al centesimo', () {
    expect(itemsSum(_receipt(items: [0.1, 0.2])), 0.3);
  });
}
