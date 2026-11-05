import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'common.dart';

/// Chip di categoria a selezione singola (si comporta come un pulsante di opzione).
class CategoryChip extends StatelessWidget {
  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const CategoryChip({super.key, required this.name, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: name,
      excludeSemantics: true,
      child: Material(
        color: selected ? c.cta : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: selected ? c.cta : c.outline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: Sizes.chip,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              CategoryDot(color: color, size: 10),
              const SizedBox(width: 6),
              Text(name, style: AppText.label.copyWith(color: selected ? c.onCta : c.onSurface)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Griglia dei 12 colori per le categorie.
class ColorGrid extends StatelessWidget {
  final String? selectedHex;
  final ValueChanged<String> onChanged;

  /// Colore del pannello che contiene la griglia (per lo stacco dell'anello).
  final Color panelColor;

  const ColorGrid({super.key, required this.selectedHex, required this.onChanged, required this.panelColor});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      const cols = 6, gap = 10.0;
      final size = ((box.maxWidth - gap * (cols - 1)) / cols).clamp(Sizes.touch, 56.0);
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final p in categoryPalette)
          Semantics(
            label: p.name,
            button: true,
            inMutuallyExclusiveGroup: true,
            checked: p.hex.toUpperCase() == selectedHex?.toUpperCase(),
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => onChanged(p.hex),
              child: SizedBox(
                width: size,
                height: 46,
                child: Center(
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: p.color,
                      shape: BoxShape.circle,
                      border: p.hex.toUpperCase() == selectedHex?.toUpperCase()
                          ? Border.all(color: c.onSurface, width: 3)
                          : null,
                    ),
                    child: p.hex.toUpperCase() == selectedHex?.toUpperCase()
                        ? Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: panelColor, width: 3),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}
