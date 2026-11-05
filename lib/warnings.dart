import 'models.dart';

/// Calcola gli avvisi aperti di uno scontrino con le sue righe.
///
/// Stessa logica di `computeWarnings` nella Edge Function
/// (supabase/functions/api/index.ts): tenerle allineate. Il dettaglio la usa
/// per aggiornare i banner subito dopo una modifica, senza ricaricare.
List<ReceiptWarning> computeWarnings(Receipt r) {
  final out = <ReceiptWarning>[];
  if (r.items.isNotEmpty) {
    final sum = r.items.fold<int>(0, (s, i) => s + cents(i.total));
    if ((sum - cents(r.total)).abs() > 1) out.add(ReceiptWarning.totalMismatch);
  }
  if (r.duplicateOf != null) out.add(ReceiptWarning.duplicate);
  final p = r.purchasedAt, c = r.createdAt;
  if (p != null && c != null) {
    if (p.isBefore(c.subtract(const Duration(days: 60))) || p.isAfter(c.add(const Duration(days: 1)))) {
      out.add(ReceiptWarning.date);
    }
  }
  return out.where((w) => !r.dismissedWarnings.contains(w.code)).toList();
}

int cents(double v) => (v * 100).round();

/// Somma delle righe in euro, arrotondata al centesimo.
double itemsSum(Receipt r) => r.items.fold<int>(0, (s, i) => s + cents(i.total)) / 100;
