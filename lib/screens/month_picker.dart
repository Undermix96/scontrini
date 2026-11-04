import 'package:flutter/material.dart';

import '../format.dart';

/// Barra per scorrere i mesi avanti e indietro.
class MonthBar extends StatelessWidget {
  final DateTime month;
  final ValueChanged<DateTime> onChanged;
  const MonthBar({super.key, required this.month, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Mese precedente',
          onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
        ),
        Text(monthLabel(month), style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Mese successivo',
          onPressed: isCurrent ? null : () => onChanged(DateTime(month.year, month.month + 1)),
        ),
      ],
    );
  }
}

DateTime monthStart(DateTime d) => DateTime(d.year, d.month);
DateTime monthEnd(DateTime d) => DateTime(d.year, d.month + 1);
