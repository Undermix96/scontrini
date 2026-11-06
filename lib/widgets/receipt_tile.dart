import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../theme/tokens.dart';
import 'warnings.dart';

/// Riga di un scontrino nell'elenco Movimenti.
class ReceiptTile extends StatelessWidget {
  final Receipt receipt;
  final Category? category;
  final VoidCallback onTap;

  const ReceiptTile({super.key, required this.receipt, required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = receipt;
    final name = r.displayMerchant;
    final warning = r.warnings.isEmpty ? null : r.warnings.first;
    final rows = r.itemCount == 1 ? '1 riga' : '${r.itemCount} righe';
    final subtitle = category == null ? rows : '$rows · ${category!.name}';
    final spoken = [
      name,
      moneySpoken(r.total, r.currency),
      if (warning != null) warning.label.toLowerCase() else subtitle,
    ].join(', ');
    return Semantics(
      button: true,
      label: spoken,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            _Avatar(initial: name.characters.first.toUpperCase(), dot: category?.colorValue ?? c.onSurfaceMuted),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.titleSmall.copyWith(color: c.onSurface)),
                const SizedBox(height: 3),
                if (warning != null)
                  WarningBadge(warning: warning)
                else
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w500, color: c.onSurfaceMuted)),
              ]),
            ),
            const SizedBox(width: Gap.sm),
            Text(money(r.total, r.currency), style: AppText.amount.copyWith(color: c.onSurface)),
          ]),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String initial;
  final Color dot;
  const _Avatar({required this.initial, required this.dot});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox.square(
      dimension: Sizes.avatar,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: Sizes.avatar,
          height: Sizes.avatar,
          decoration: BoxDecoration(color: c.surfaceHigh, borderRadius: BorderRadius.circular(Radii.chip)),
          alignment: Alignment.center,
          child: Text(initial, style: AppText.amount.copyWith(color: c.onSurface)),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle, border: Border.all(color: c.surface, width: 2.5)),
          ),
        ),
      ]),
    );
  }
}

/// Riga segnaposto per un'analisi in sottofondo.
class PendingScanTile extends StatelessWidget {
  final VoidCallback onTap;

  /// Letture in attesa o in corso.
  final int count;
  const PendingScanTile({super.key, required this.onTap, this.count = 1});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: count > 1 ? 'Lettura in corso, $count scontrini' : 'Lettura in corso',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Container(
              width: Sizes.avatar,
              height: Sizes.avatar,
              decoration: BoxDecoration(color: c.surfaceHigh, borderRadius: BorderRadius.circular(Radii.chip)),
              alignment: Alignment.center,
              child: SizedBox.square(
                  dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: c.primary)),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(count > 1 ? 'Lettura in corso… ($count scontrini)' : 'Lettura in corso…',
                  style: AppText.titleSmall.copyWith(color: c.onSurfaceMuted)),
            ),
          ]),
        ),
      ),
    );
  }
}
