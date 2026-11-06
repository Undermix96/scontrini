import 'package:flutter/material.dart';

import '../app_state.dart';
import '../budget.dart';
import '../format.dart';
import '../models.dart';
import '../theme/tokens.dart';
import '../warnings.dart';
import 'common.dart';

Color budgetColor(ScontriniColors c, BudgetLevel l, {Color? normal}) => switch (l) {
      BudgetLevel.ok => normal ?? c.primary,
      BudgetLevel.near => c.warning,
      BudgetLevel.over => c.error,
    };

/// Barra sottile di avanzamento della spesa rispetto al budget.
class BudgetBar extends StatelessWidget {
  final double spent;
  final double budget;
  final Color? color;
  final Color? track;
  final double height;

  const BudgetBar({super.key, required this.spent, required this.budget, this.color, this.track, this.height = 8});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final level = budgetLevel(spent, budget);
    final f = budget <= 0 ? 0.0 : (spent / budget).clamp(0, 1).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Stack(children: [
        Container(height: height, color: track ?? c.surfaceHigh),
        FractionallySizedBox(
          widthFactor: f,
          child: Container(height: height, color: color ?? budgetColor(c, level)),
        ),
      ]),
    );
  }
}

/// "Restano 120,00 €" / "Superato di 12,00 €".
String budgetRemaining(double spent, double budget) {
  final diff = (cents(budget) - cents(spent)) / 100;
  return diff >= 0 ? 'Restano ${money(diff)}' : 'Superato di ${money(-diff)}';
}

/// Card del budget totale nella scheda Spese.
class BudgetCard extends StatelessWidget {
  final DateTime month;
  final double spent;
  final double? budget;

  /// Null: il budget di quel mese non si modifica più (mese passato).
  final VoidCallback? onEdit;

  const BudgetCard({super.key, required this.month, required this.spent, required this.budget, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = budget;
    if (b == null) {
      if (onEdit == null) return const SizedBox.shrink();
      return Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
            child: Row(children: [
              Icon(Icons.savings_outlined, color: c.primary),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text('Imposta un budget mensile', style: AppText.titleSmall.copyWith(color: c.primary)),
              ),
              Icon(Icons.chevron_right, color: c.onSurfaceMuted),
            ]),
          ),
        ),
      );
    }
    final level = budgetLevel(spent, b);
    final pct = b <= 0 ? 0 : (spent / b * 100).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.xs, Gap.lg),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.lg)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Semantics(
              container: true,
              label: 'Budget di ${monthName(month)}: speso ${moneySpoken(spent)} su ${moneySpoken(b)}, $pct%. '
                  '${budgetRemaining(spent, b)}',
              excludeSemantics: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Budget di ${monthName(month)}', style: AppText.badge.copyWith(color: c.onSurfaceMuted)),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: money(spent), style: AppText.title.copyWith(color: c.onSurface)),
                    TextSpan(text: '  di ${money(b)}', style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted)),
                  ]),
                ),
              ]),
            ),
          ),
          if (onEdit != null)
            IconButton(
              tooltip: 'Modifica budget',
              onPressed: onEdit,
              icon: Icon(Icons.edit_outlined, color: c.onSurfaceMuted, size: 20),
            ),
        ]),
        const SizedBox(height: Gap.sm),
        Padding(
          padding: const EdgeInsets.only(right: Gap.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            BudgetBar(spent: spent, budget: b),
            const SizedBox(height: Gap.xs),
            Row(children: [
              Expanded(
                child: Text(budgetRemaining(spent, b),
                    style: AppText.bodySmall
                        .copyWith(color: level == BudgetLevel.ok ? c.onSurfaceMuted : budgetColor(c, level))),
              ),
              Text('$pct%', style: AppText.label.copyWith(color: c.onSurfaceMuted)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Pannello per impostare il budget totale e quelli delle categorie, validi
/// da [month] in poi. Vero se qualcosa è cambiato.
Future<bool> showBudgetSheet(BuildContext context, DateTime month) async {
  final s = AppScope.read(context);
  final current = await s.repo.budgetFor(month);
  if (!context.mounted) return false;
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _BudgetSheet(month: month, current: current),
  );
  if (changed == true) s.dataChanged();
  return changed == true;
}

class _BudgetSheet extends StatefulWidget {
  final DateTime month;
  final MonthBudget current;
  const _BudgetSheet({required this.month, required this.current});

  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  late final AppState _s = AppScope.read(context);
  late final _total = TextEditingController(text: _text(widget.current.total));
  late final Map<int, TextEditingController> _cats = {
    for (final cat in _s.categories) cat.id: TextEditingController(text: _text(widget.current.categories[cat.id])),
  };
  String? _error;
  bool _busy = false;

  static String _text(double? v) => v == null ? '' : v.toStringAsFixed(2).replaceAll('.', ',').replaceAll(',00', '');

  @override
  void dispose() {
    _total.dispose();
    for (final t in _cats.values) {
      t.dispose();
    }
    super.dispose();
  }

  /// Null se vuoto; NaN se non valido.
  double? _value(TextEditingController t) {
    if (t.text.trim().isEmpty) return null;
    final v = parseAmount(t.text);
    return v == null || v < 0 ? double.nan : v;
  }

  Future<void> _save() async {
    final total = _value(_total);
    final cats = {for (final e in _cats.entries) e.key: _value(e.value)};
    if (total?.isNaN == true || cats.values.any((v) => v?.isNaN == true)) {
      setState(() => _error = 'Scrivi importi validi, per esempio 450 o 120,50.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    bool same(double? a, double? b) => (a == null || a == 0 ? null : cents(a)) == (b == null ? null : cents(b));
    var changed = false;
    try {
      if (!same(total, widget.current.total)) {
        await _s.repo.setBudget(null, widget.month, total);
        changed = true;
      }
      for (final e in cats.entries) {
        if (!same(e.value, widget.current.categories[e.key])) {
          await _s.repo.setBudget(e.key, widget.month, e.value);
          changed = true;
        }
      }
      if (mounted) Navigator.pop(context, changed);
    } catch (e) {
      if (mounted) setState(() => _error = 'Salvataggio non riuscito: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget amountField(TextEditingController t, {String? label, Widget? leading, bool autofocus = false}) => Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 10)],
            if (label != null)
              Expanded(child: Text(label, style: AppText.titleSmall.copyWith(color: c.onSurface)))
            else
              const Spacer(),
            SizedBox(
              width: 130,
              child: TextField(
                controller: t,
                autofocus: autofocus,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: AppText.amountSmall.copyWith(color: c.onSurface),
                decoration: const InputDecoration(hintText: 'Nessuno', suffixText: '€', isDense: true),
              ),
            ),
          ],
        );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.md),
              children: [
                Semantics(
                  header: true,
                  child: Text('Budget mensile', style: AppText.title.copyWith(fontSize: 20, color: c.onSurface)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Vale da ${monthLabel(widget.month).toLowerCase()} in poi: i mesi precedenti mantengono il budget '
                  'che avevano. Lascia vuoto per non avere un budget.',
                  style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted),
                ),
                const SizedBox(height: Gap.lg),
                amountField(_total, label: 'Totale del mese'),
                const SizedBox(height: Gap.lg),
                Text('Per categoria (facoltativo)', style: AppText.label.copyWith(color: c.onSurfaceMuted)),
                const SizedBox(height: Gap.xs),
                for (final cat in _s.categories)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: amountField(_cats[cat.id]!,
                        label: cat.name, leading: CategoryDot(color: cat.colorValue, size: 12)),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: Gap.sm),
                  Text(_error!, style: AppText.bodySmall.copyWith(color: c.error)),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.gutter, Gap.xs, Gap.gutter, Gap.lg),
            child: FilledButton(
                onPressed: _busy ? null : _save, child: _busy ? const SmallSpinner() : const Text('Salva')),
          ),
        ]),
      ),
    );
  }
}

/// Avviso dopo il salvataggio di uno scontrino, se ha superato una soglia
/// del budget: "Budget di Casa superato". Null se nessuna.
Future<String?> budgetAlertText(AppState s, Receipt receipt) async {
  try {
    final crossing = await s.repo.budgetCrossingFor(receipt);
    if (crossing == null) return null;
    return budgetCrossingText(crossing, (id) => s.category(id)?.name ?? 'categoria');
  } catch (_) {
    return null;
  }
}
