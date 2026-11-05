import 'package:flutter/material.dart';

import '../models.dart';
import '../theme/tokens.dart';

/// Badge di avviso per le righe dell'elenco.
class WarningBadge extends StatelessWidget {
  final ReceiptWarning warning;
  const WarningBadge({super.key, required this.warning});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.warningContainer, borderRadius: BorderRadius.circular(Radii.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.warning_amber_rounded, size: 12, color: c.onWarningContainer),
        const SizedBox(width: 4),
        Flexible(
          child: Text(warning.label,
              style: AppText.badge.copyWith(color: c.onWarningContainer), overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

class BannerAction {
  final String label;
  final VoidCallback onPressed;
  final bool filled;
  const BannerAction(this.label, this.onPressed, {this.filled = false});
}

/// Banner di avviso con testo e uno o due pulsanti compatti.
class WarningBanner extends StatelessWidget {
  final InlineSpan text;
  final List<BannerAction> actions;

  const WarningBanner({super.key, required this.text, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = AppText.body.copyWith(fontSize: 14, fontWeight: FontWeight.w600, height: 1.45, color: c.onWarningContainer);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: c.warningContainer, borderRadius: BorderRadius.circular(Radii.input)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded, size: 20, color: c.warning),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(text, style: style),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final a in actions) _BannerButton(action: a),
                ]),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

class _BannerButton extends StatelessWidget {
  final BannerAction action;
  const _BannerButton({required this.action});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: action.filled ? c.onWarningContainer : Colors.transparent,
      shape: StadiumBorder(side: action.filled ? BorderSide.none : BorderSide(color: c.warningOutline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: action.onPressed,
        child: Container(
          height: 36,
          constraints: const BoxConstraints(minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(
            widthFactor: 1,
            child: Text(action.label,
                style: AppText.buttonSmall.copyWith(color: action.filled ? c.warningContainer : c.onWarningContainer)),
          ),
        ),
      ),
    );
  }
}
