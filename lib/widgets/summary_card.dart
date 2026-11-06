import 'package:flutter/material.dart';

import '../format.dart';
import '../theme/tokens.dart';
import 'budget_widgets.dart';

/// Card di riepilogo con il bordo inferiore seghettato, come uno scontrino.
class SummaryCard extends StatelessWidget {
  final String label;
  final String total;
  final String subtitle;
  final VoidCallback? onCamera;
  final VoidCallback? onGallery;

  /// Budget totale del mese (se impostato) e spesa da confrontare.
  final double? budget;
  final double spent;

  const SummaryCard({
    super.key,
    required this.label,
    required this.total,
    required this.subtitle,
    this.onCamera,
    this.onGallery,
    this.budget,
    this.spent = 0,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipPath(
      clipper: const ReceiptEdgeClipper(),
      child: Container(
        color: c.summaryCard,
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 22 + ReceiptEdgeClipper.toothHeight),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            container: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: AppText.body.copyWith(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3, color: c.onSummaryCardMuted)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(total, style: AppText.amountHero.copyWith(color: c.onSummaryCard)),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: AppText.bodySmall.copyWith(color: c.onSummaryCardMuted)),
              if (budget != null) ...[
                const SizedBox(height: Gap.sm),
                BudgetBar(
                  spent: spent,
                  budget: budget!,
                  height: 6,
                  color: ScontriniColors.summaryInk,
                  track: ScontriniColors.summaryGhost,
                ),
                const SizedBox(height: 4),
                Text('${budgetRemaining(spent, budget!)} · budget ${money(budget!)}',
                    style: AppText.bodySmall.copyWith(color: c.onSummaryCardMuted)),
              ],
            ]),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: _CardButton(
                label: 'Fotografa',
                icon: Icons.photo_camera_outlined,
                background: ScontriniColors.summaryInk,
                foreground: Colors.white,
                onTap: onCamera,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CardButton(
                label: 'Galleria',
                icon: Icons.image_outlined,
                background: ScontriniColors.summaryGhost,
                foreground: ScontriniColors.summaryInk,
                onTap: onGallery,
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  const _CardButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: background,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: Sizes.buttonCompact,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 20, color: foreground),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis, style: AppText.button.copyWith(fontSize: 15, color: foreground)),
              ),
            ]),
          ),
        ),
      );
}

/// Rettangolo con angoli superiori arrotondati e denti in basso (10 × 8).
class ReceiptEdgeClipper extends CustomClipper<Path> {
  static const toothWidth = 10.0;
  static const toothHeight = 8.0;
  final double radius;

  const ReceiptEdgeClipper({this.radius = Radii.lg});

  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height, r = radius;
    final base = h - toothHeight;
    final path = Path()
      ..moveTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..lineTo(w, base);
    final n = (w / toothWidth).floor().clamp(1, 10000);
    final tw = w / n;
    for (var i = 0; i < n; i++) {
      final x = w - i * tw;
      path
        ..lineTo(x - tw / 2, h)
        ..lineTo(x - tw, base);
    }
    return path..close();
  }

  @override
  bool shouldReclip(covariant ReceiptEdgeClipper oldClipper) => oldClipper.radius != radius;
}
