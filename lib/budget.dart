/// Budget mensili: risoluzione per mese e soglie di avviso.
///
/// Un budget vale dal mese in cui è stato impostato in poi, finché non viene
/// cambiato: modificare il budget di novembre non tocca ottobre.
library;

import 'warnings.dart';

/// `AAAA-MM` del mese di [d].
String monthKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

/// Una riga della tabella dei budget.
class BudgetEntry {
  /// Null: budget totale del mese.
  final int? categoryId;
  final String fromMonth;

  /// Null: da questo mese il budget è tolto.
  final double? amount;

  const BudgetEntry(this.categoryId, this.fromMonth, this.amount);
}

/// Budget in vigore in un mese.
class MonthBudget {
  final double? total;
  final Map<int, double> categories;

  const MonthBudget({this.total, this.categories = const {}});

  bool get isEmpty => total == null && categories.isEmpty;
  double? of(int? categoryId) => categoryId == null ? total : categories[categoryId];
}

/// Per ogni categoria (e per il totale) vale la riga più recente con
/// `fromMonth` non successivo al mese.
MonthBudget resolveBudget(Iterable<BudgetEntry> entries, DateTime month) {
  final key = monthKey(month);
  final latest = <int?, BudgetEntry>{};
  for (final e in entries) {
    if (e.fromMonth.compareTo(key) > 0) continue;
    final cur = latest[e.categoryId];
    if (cur == null || e.fromMonth.compareTo(cur.fromMonth) > 0) latest[e.categoryId] = e;
  }
  return MonthBudget(
    total: latest[null]?.amount,
    categories: {
      for (final MapEntry(:key, :value) in latest.entries)
        if (key != null && value.amount != null) key: value.amount!,
    },
  );
}

/// Livello di spesa rispetto al budget.
enum BudgetLevel { ok, near, over }

/// Soglia di avviso: 80%.
const budgetNearRatio = 0.8;

BudgetLevel budgetLevel(double spent, double? budget) {
  if (budget == null || budget <= 0) return BudgetLevel.ok;
  if (cents(spent) > cents(budget)) return BudgetLevel.over;
  if (spent >= budget * budgetNearRatio) return BudgetLevel.near;
  return BudgetLevel.ok;
}

/// Soglia superata con un nuovo scontrino.
class BudgetCrossing {
  /// Null: budget totale.
  final int? categoryId;
  final BudgetLevel level;
  const BudgetCrossing(this.categoryId, this.level);
}

/// Soglie (80% o 100%) superate passando dalle spese [before] a [after]
/// (per categoria; la chiave null è "senza categoria"). Prima il totale,
/// poi le categorie; prima il superamento, poi l'80%.
List<BudgetCrossing> budgetCrossings(MonthBudget budget, Map<int?, double> before, Map<int?, double> after) {
  double sum(Map<int?, double> m) => m.values.fold(0, (a, b) => a + b);
  final out = <BudgetCrossing>[];
  void check(int? id, double b, double a, double? limit) {
    final from = budgetLevel(b, limit), to = budgetLevel(a, limit);
    if (to.index > from.index) out.add(BudgetCrossing(id, to));
  }

  check(null, sum(before), sum(after), budget.total);
  for (final MapEntry(:key, :value) in budget.categories.entries) {
    check(key, before[key] ?? 0, after[key] ?? 0, value);
  }
  out.sort((a, b) {
    final l = b.level.index.compareTo(a.level.index);
    if (l != 0) return l;
    return (a.categoryId == null ? 0 : 1).compareTo(b.categoryId == null ? 0 : 1);
  });
  return out;
}

/// Frase breve per l'avviso: "budget del mese superato", "80% del budget di Casa".
String budgetCrossingText(BudgetCrossing c, String Function(int id) categoryName) {
  final what = c.categoryId == null ? 'del mese' : 'di ${categoryName(c.categoryId!)}';
  return c.level == BudgetLevel.over ? 'Budget $what superato' : '80% del budget $what';
}
