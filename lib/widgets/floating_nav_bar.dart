import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme/tokens.dart';

/// Spazio da lasciare in fondo alle liste perché non finiscano sotto la barra.
double navBarSpace(BuildContext context) => 28 + Sizes.fab + 24 + MediaQuery.paddingOf(context).bottom;

class _NavItem {
  final AppTab tab;
  final String label;
  final IconData icon;
  const _NavItem(this.tab, this.label, this.icon);
}

const _items = [
  _NavItem(AppTab.movements, 'Movimenti', Icons.receipt_long_outlined),
  _NavItem(AppTab.stats, 'Spese', Icons.pie_chart_outline),
  _NavItem(AppTab.categories, 'Categorie', Icons.sell_outlined),
  _NavItem(AppTab.settings, 'Impostazioni', Icons.tune),
];

/// Barra di navigazione flottante con il pulsante fotocamera.
class FloatingNavBar extends StatelessWidget {
  final AppTab current;
  final ValueChanged<AppTab> onSelect;
  final VoidCallback? onCamera;

  const FloatingNavBar({super.key, required this.current, required this.onSelect, required this.onCamera});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Stack(alignment: Alignment.bottomCenter, children: [
        // Sfumatura: la lista non si legge sotto la barra.
        IgnorePointer(
          child: Container(
            height: 130 + bottom,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [c.background.withValues(alpha: 0), c.background],
                stops: const [0, 0.55],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, 28 + bottom),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Gap.maxContent),
            child: Row(children: [
              Expanded(
                child: Semantics(
                  container: true,
                  label: 'Navigazione principale',
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: c.navBar,
                      borderRadius: BorderRadius.circular(Radii.pill),
                      border: Border.all(color: c.navBarOutline),
                    ),
                    // La voce attiva prende la larghezza della sua etichetta
                    // (almeno 1,6 volte una voce inattiva), lasciando 44 a
                    // ciascuna delle altre.
                    child: LayoutBuilder(builder: (context, box) {
                      final inactiveMin = Sizes.touch * (_items.length - 1);
                      final unit = box.maxWidth / (_items.length - 1 + 1.6);
                      return Row(children: [
                        for (final it in _items)
                          if (it.tab == current)
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: unit * 1.6,
                                maxWidth: (box.maxWidth - inactiveMin).clamp(unit * 1.6, box.maxWidth),
                              ),
                              child: _NavButton(item: it, active: true, onTap: () => onSelect(it.tab)),
                            )
                          else
                            Expanded(child: _NavButton(item: it, active: false, onTap: () => onSelect(it.tab))),
                      ]);
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: 'Fotografa uno scontrino',
                child: Semantics(
                  button: true,
                  label: 'Fotografa uno scontrino',
                  excludeSemantics: true,
                  child: Material(
                    color: c.summaryCard,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onCamera,
                      child: const SizedBox.square(
                        dimension: Sizes.fab,
                        child: Icon(Icons.photo_camera_outlined, size: 26, color: ScontriniColors.summaryInk),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]);
  }
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool active;
  final VoidCallback onTap;
  const _NavButton({required this.item, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      excludeSemantics: true,
      child: Tooltip(
        message: active ? '' : item.label,
        child: Material(
          color: active ? c.cta : Colors.transparent,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: Sizes.navItem,
              child: active
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(item.icon, size: 20, color: c.navActiveIcon),
                        const SizedBox(width: 8),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(item.label,
                                maxLines: 1,
                                style: AppText.label.copyWith(fontSize: 14, fontWeight: FontWeight.w800, color: c.onCta)),
                          ),
                        ),
                      ]),
                    )
                  : Icon(item.icon, size: 22, color: c.onSurfaceMuted),
            ),
          ),
        ),
      ),
    );
  }
}
