import 'package:flutter_test/flutter_test.dart';
import 'package:scontrini/widgets/trend_charts.dart';

import '../support/fake_app.dart';

void main() {
  late FakeApp app;
  setUp(() => app = FakeApp(now: DateTime(2026, 11, 20, 12)));
  tearDown(() => app.db.close());

  Future<void> add(DateTime at, List<(double, int?)> items, {String? merchant}) => app.repo.createReceipt(
        merchant: merchant,
        purchasedAt: at,
        items: [for (final (t, c) in items) {'description': 'x', 'total': t, 'category_id': c}],
      );

  test('totali mese per mese, anche di una sola categoria', () async {
    await add(DateTime(2026, 1, 15), [(10, 1), (5, 3)]);
    await add(DateTime(2026, 10, 31, 23, 30), [(20, 1)]); // ultima mezz'ora del mese, ora locale
    await add(DateTime(2026, 11, 1, 0, 10), [(7, 3)]);
    await add(DateTime(2025, 12, 31), [(99, 1)]); // fuori dal periodo
    final all = await app.repo.monthlyTotals(DateTime(2026, 1), 11);
    expect(all.length, 11);
    expect(all[0], 15);
    expect(all[9], 20);
    expect(all[10], 7);
    expect(all.sublist(1, 9).every((v) => v == 0), isTrue);
    final cat1 = await app.repo.monthlyTotals(DateTime(2026, 1), 11, categoryId: 1);
    expect(cat1[0], 10);
    expect(cat1[10], 0);
  });

  test('totali giorno per giorno del mese', () async {
    await add(DateTime(2026, 2, 1, 8), [(3, 1)]);
    await add(DateTime(2026, 2, 28, 22), [(4, 1), (1, 2)]);
    final feb = await app.repo.dailyTotals(DateTime(2026, 2));
    expect(feb.length, 28);
    expect(feb.first, 3);
    expect(feb.last, 5);
    expect((await app.repo.dailyTotals(DateTime(2026, 3))).length, 31);
  });

  test('esercenti raggruppati senza distinguere maiuscole e spazi', () async {
    await add(DateTime(2026, 11, 2), [(10, 1)], merchant: 'Coop');
    await add(DateTime(2026, 11, 3), [(15, 1)], merchant: '  COOP '); // più recente: questa grafia
    await add(DateTime(2026, 11, 4), [(30, 1)], merchant: 'Esselunga');
    await add(DateTime(2026, 11, 5), [(99, 1)]); // senza esercente: escluso
    await add(DateTime(2026, 10, 5), [(500, 1)], merchant: 'Coop'); // altro mese
    final list = await app.repo.merchantTotals(DateTime(2026, 11), DateTime(2026, 12));
    expect(list.map((m) => (m.name, m.total, m.receipts)), [('Esselunga', 30.0, 1), ('COOP', 25.0, 2)]);
  });

  test('assi con valori tondi', () {
    expect(niceCeil(0), 1);
    expect(niceCeil(123.75), 200);
    expect(niceCeil(201), 250);
    expect(niceCeil(1800), 2000);
    expect(shortMoney(250), '250 €');
    expect(shortMoney(1500), '1,5k €');
    expect(shortMoney(2000), '2k €');
  });
}
