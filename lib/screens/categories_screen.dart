import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme/tokens.dart';
import '../widgets/category_sheet.dart';
import '../widgets/common.dart';
import '../widgets/floating_nav_bar.dart';

/// Scheda Categorie: elenco, creazione e modifica.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  int _seen = -1;
  String? _error;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    if (_seen != s.dataVersion) {
      _seen = s.dataVersion;
      _load();
    }
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    if (!s.config.isConfigured) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await s.reloadCategories();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Category? cat]) async {
    final changed = await showCategorySheet(context, cat);
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cats = AppScope.of(context).categories;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(Gap.gutter, Gap.xs, Gap.gutter, navBarSpace(context)),
          children: [
            ContentWidth(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Semantics(
                        header: true, child: Text('Categorie', style: AppText.headline.copyWith(color: c.onSurface))),
                  ),
                  CompactButton(label: 'Nuova', icon: Icons.add, onPressed: () => _edit()),
                ]),
                const SizedBox(height: Gap.md),
                Text("L'AI assegna ogni riga a una di queste categorie. Puoi cambiarle quando vuoi.",
                    style: AppText.body.copyWith(fontSize: 14, height: 1.45, color: c.onSurfaceMuted)),
                const SizedBox(height: Gap.md),
                if (_error != null && cats.isEmpty)
                  _Message(text: _error!, onRetry: _load)
                else if (cats.isEmpty && _loading)
                  const Padding(padding: EdgeInsets.all(Gap.xxl), child: Center(child: CircularProgressIndicator()))
                else if (cats.isEmpty)
                  const _Message(text: 'Nessuna categoria. Toccando "Nuova" puoi crearne una.')
                else
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.card)),
                    child: Column(children: [for (final cat in cats) _CategoryRow(cat: cat, onTap: () => _edit(cat))]),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final Category cat;
  final VoidCallback onTap;
  const _CategoryRow({required this.cat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final count = cat.itemCount;
    final countText = count == null ? '' : (count == 1 ? '1 riga' : '$count righe');
    return Semantics(
      button: true,
      label: '${cat.name}${countText.isEmpty ? '' : ', $countText'}. Modifica',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: cat.colorValue.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: CategoryDot(color: cat.colorValue, size: 12),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(child: Text(cat.name, style: AppText.titleSmall.copyWith(color: c.onSurface))),
            if (countText.isNotEmpty)
              Text(countText, style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted, height: 1)),
            const SizedBox(width: Gap.xs),
            Icon(Icons.chevron_right, size: 18, color: c.onSurfaceMuted),
          ]),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;
  const _Message({required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.md)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(text, style: AppText.body.copyWith(color: c.onSurfaceMuted), textAlign: TextAlign.center),
        if (onRetry != null) ...[
          const SizedBox(height: Gap.md),
          OutlinedButton(onPressed: onRetry, child: const Text('Riprova')),
        ],
      ]),
    );
  }
}
