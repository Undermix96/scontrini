import 'package:flutter_test/flutter_test.dart';
import 'package:scontrini/budget.dart';

import 'support/fake_app.dart';

void main() {
  group('resolveBudget', () {
    const entries = [
      BudgetEntry(null, '2026-03', 400),
      BudgetEntry(null, '2026-09', 500),
      BudgetEntry(1, '2026-09', 150),
      BudgetEntry(1, '2026-11', null), // tolto da novembre
      BudgetEntry(3, '2027-01', 80),
    ];

    test('vale la riga più recente non successiva al mese', () {
      expect(resolveBudget(entries, DateTime(2026, 2)).isEmpty, isTrue);
      expect(resolveBudget(entries, DateTime(2026, 3)).total, 400);
      expect(resolveBudget(entries, DateTime(2026, 8)).total, 400);
      final oct = resolveBudget(entries, DateTime(2026, 10));
      expect(oct.total, 500);
      expect(oct.categories, {1: 150});
    });

    test('un budget tolto non vale più dai mesi successivi', () {
      final nov = resolveBudget(entries, DateTime(2026, 11));
      expect(nov.total, 500);
      expect(nov.categories, isEmpty);
      expect(resolveBudget(entries, DateTime(2027, 1)).categories, {3: 80});
    });

    test('monthKey', () {
      expect(monthKey(DateTime(2026, 3, 31, 23)), '2026-03');
      expect(monthKey(DateTime(987, 12)), '0987-12');
    });
  });

  group('soglie', () {
    test('livello rispetto al budget', () {
      expect(budgetLevel(79.99, 100), BudgetLevel.ok);
      expect(budgetLevel(80, 100), BudgetLevel.near);
      expect(budgetLevel(100, 100), BudgetLevel.near, reason: 'pari al budget non è superato');
      expect(budgetLevel(100.01, 100), BudgetLevel.over);
      expect(budgetLevel(1000, null), BudgetLevel.ok);
    });

    test('solo le soglie appena superate, prima le più gravi e il totale', () {
      const budget = MonthBudget(total: 500, categories: {1: 100, 3: 50});
      final crossings = budgetCrossings(
        budget,
        {1: 70, 3: 45, null: 250}, // totale 365: 73%
        {1: 110, 3: 48, null: 250}, // totale 408: 81,6%
      );
      expect(crossings.map((c) => (c.categoryId, c.level)), [(1, BudgetLevel.over), (null, BudgetLevel.near)]);
      expect(budgetCrossingText(crossings.first, (_) => 'Alimentari'), 'Budget di Alimentari superato');
      expect(budgetCrossingText(crossings.last, (_) => ''), '80% del budget del mese');
      expect(budgetCrossings(budget, {1: 110}, {1: 120}), isEmpty, reason: 'già superato prima');
    });
  });

  group('Repository', () {
    late FakeApp app;
    setUp(() => app = FakeApp(now: DateTime(2026, 11, 20, 12)));
    tearDown(() => app.db.close());

    test('cambiare il budget non tocca i mesi passati', () async {
      final repo = app.repo;
      await repo.setBudget(null, DateTime(2026, 9), 500);
      await repo.setBudget(null, DateTime(2026, 11), 600);
      await repo.setBudget(null, DateTime(2026, 11), 650); // stessa riga, sostituita
      expect((await repo.budgetFor(DateTime(2026, 10))).total, 500);
      expect((await repo.budgetFor(DateTime(2026, 11))).total, 650);
      expect((await repo.budgetFor(DateTime(2027, 4))).total, 650);
      expect((await repo.budgetEntries()).length, 2);

      // Uguale al precedente: nessuna riga nuova.
      await repo.setBudget(null, DateTime(2026, 12), 650);
      expect((await repo.budgetEntries()).length, 2);

      // Tolto da gennaio.
      await repo.setBudget(null, DateTime(2027, 1), null);
      expect((await repo.budgetFor(DateTime(2027, 1))).total, isNull);
      expect((await repo.budgetFor(DateTime(2026, 12))).total, 650);
    });

    test('eliminando una categoria se ne va anche il suo budget', () async {
      await app.repo.addCategory('Animali', '#123456');
      final id = (await app.repo.categories()).firstWhere((c) => c.name == 'Animali').id;
      await app.repo.setBudget(id, DateTime(2026, 11), 30);
      await app.repo.deleteCategory(id);
      expect((await app.repo.budgetFor(DateTime(2026, 11))).isEmpty, isTrue);
    });

    test('soglia superata da uno scontrino appena salvato', () async {
      final repo = app.repo;
      await repo.setBudget(null, DateTime(2026, 11), 100);
      await repo.setBudget(1, DateTime(2026, 11), 20);
      final a = await repo.createReceipt(purchasedAt: DateTime(2026, 11, 5), items: [
        {'description': 'Spesa', 'total': 15.0, 'category_id': 1},
      ]);
      expect(await repo.budgetCrossingFor(a), isNull, reason: '75% della categoria');
      final b = await repo.createReceipt(purchasedAt: DateTime(2026, 11, 6), items: [
        {'description': 'Spesa', 'total': 6.0, 'category_id': 1},
      ]);
      final c = (await repo.budgetCrossingFor(b))!;
      expect((c.categoryId, c.level), (1, BudgetLevel.over));
      final d = await repo.createReceipt(purchasedAt: DateTime(2026, 11, 7), items: [
        {'description': 'Divano', 'total': 85.0, 'category_id': 3}, // totale 106
      ]);
      final e = (await repo.budgetCrossingFor(d))!;
      expect((e.categoryId, e.level), (null, BudgetLevel.over));
      // Scontrino di un altro mese: conta il budget di quel mese (nessuno).
      final old = await repo.createReceipt(purchasedAt: DateTime(2026, 8, 1), items: [
        {'description': 'Vecchio', 'total': 999.0, 'category_id': 1},
      ]);
      expect(await repo.budgetCrossingFor(old), isNull);
    });
  });
}
