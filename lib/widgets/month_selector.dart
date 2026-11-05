import 'package:flutter/material.dart';

import '../format.dart';
import '../theme/tokens.dart';
import 'common.dart';

DateTime monthStart(DateTime d) => DateTime(d.year, d.month);
DateTime monthEnd(DateTime d) => DateTime(d.year, d.month + 1);

bool isCurrentMonth(DateTime month) {
  final now = DateTime.now();
  return month.year == now.year && month.month == now.month;
}

/// Barra superiore di Movimenti: freccia, nome del mese, freccia.
class MonthNav extends StatelessWidget {
  final DateTime month;
  final ValueChanged<DateTime> onChanged;
  const MonthNav({super.key, required this.month, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final current = isCurrentMonth(month);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      RoundIconButton(
        icon: Icons.chevron_left,
        tooltip: 'Mese precedente',
        onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
      ),
      const SizedBox(width: Gap.sm),
      Flexible(
        child: Text(monthLabel(month),
            style: AppText.title.copyWith(color: c.onSurface), overflow: TextOverflow.ellipsis, maxLines: 1),
      ),
      const SizedBox(width: Gap.sm),
      RoundIconButton(
        icon: Icons.chevron_right,
        tooltip: 'Mese successivo',
        onPressed: current ? null : () => onChanged(DateTime(month.year, month.month + 1)),
      ),
    ]);
  }
}

/// Selettore compatto a pillola (scheda Spese).
class CompactMonthSelector extends StatelessWidget {
  final DateTime month;
  final ValueChanged<DateTime> onChanged;
  const CompactMonthSelector({super.key, required this.month, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final current = isCurrentMonth(month);
    Widget arrow(IconData icon, String tip, VoidCallback? onTap) => Tooltip(
          message: tip,
          child: Semantics(
            button: true,
            enabled: onTap != null,
            label: tip,
            excludeSemantics: true,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox.square(
                dimension: Sizes.touch,
                child: Icon(icon, size: 20, color: onTap == null ? c.onSurfaceMuted.withValues(alpha: 0.5) : c.onSurface),
              ),
            ),
          ),
        );
    return Material(
      color: c.surface,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        arrow(Icons.chevron_left, 'Mese precedente', () => onChanged(DateTime(month.year, month.month - 1))),
        Text(shortMonthLabel(month), style: AppText.label.copyWith(color: c.onSurface, fontSize: 14)),
        arrow(Icons.chevron_right, 'Mese successivo',
            current ? null : () => onChanged(DateTime(month.year, month.month + 1))),
      ]),
    );
  }
}
