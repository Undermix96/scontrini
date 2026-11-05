import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme/tokens.dart';
import 'category_widgets.dart';
import 'common.dart';

/// Apre il pannello "Nuova categoria" / "Modifica categoria".
/// Restituisce true se qualcosa è cambiato.
Future<bool?> showCategorySheet(BuildContext context, Category? cat) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _CategorySheet(cat: cat),
    );

class _CategorySheet extends StatefulWidget {
  final Category? cat;
  const _CategorySheet({required this.cat});

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late final TextEditingController _name = TextEditingController(text: widget.cat?.name ?? '');
  late String _color;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final cat = widget.cat;
    if (cat != null) {
      _color = cat.color;
    } else {
      // Primo colore della griglia non ancora usato.
      final used = AppScope.read(context).categories.map((c) => c.color.toUpperCase()).toSet();
      _color = categoryPalette
          .firstWhere((p) => !used.contains(p.hex.toUpperCase()), orElse: () => categoryPalette.first)
          .hex;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _duplicate {
    final n = _name.text.trim().toLowerCase();
    return AppScope.read(context).categories.any((c) => c.id != widget.cat?.id && c.name.toLowerCase() == n);
  }

  Future<void> _save() async {
    final state = AppScope.read(context);
    final name = _name.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.cat == null) {
        await state.api.addCategory(name, _color);
      } else {
        await state.api.updateCategory(widget.cat!.id, name: name, color: _color);
      }
      await state.reloadCategories();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Salvataggio non riuscito: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final cat = widget.cat!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminare "${cat.name}"?'),
        content: const Text('Le righe di questa categoria resteranno senza categoria.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final state = AppScope.read(context);
    setState(() => _busy = true);
    try {
      await state.api.deleteCategory(cat.id);
      await state.reloadCategories();
      state.dataChanged();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Eliminazione non riuscita: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cat = widget.cat;
    final dup = _duplicate;
    final canSave = !_busy && _name.text.trim().isNotEmpty && !dup;
    final count = cat?.itemCount;
    return Padding(
      padding: EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.xxl + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(cat == null ? 'Nuova categoria' : 'Modifica categoria',
                    style: AppText.title.copyWith(fontSize: 20, color: c.onSurface)),
              ),
            ),
            RoundIconButton(
                icon: Icons.close, tooltip: 'Chiudi', background: c.surfaceHigh, onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 18),
          LabeledField(
            label: 'Nome',
            controller: _name,
            autofocus: cat == null,
            prefix: Padding(
              padding: const EdgeInsets.all(18),
              child: CategoryDot(color: hexColor(_color), size: 14),
            ),
            error: dup ? 'Esiste già una categoria con questo nome.' : null,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 18),
          Text('Colore', style: AppText.label.copyWith(color: c.onSurface)),
          const SizedBox(height: 10),
          ColorGrid(selectedHex: _color, panelColor: c.surface, onChanged: (h) => setState(() => _color = h)),
          if (cat != null) ...[
            const SizedBox(height: 18),
            Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: count == null
                        ? 'Se la elimini, le sue righe restano '
                        : 'Se la elimini, ${count == 1 ? 'la sua riga resta' : 'le sue $count righe restano'} '),
                TextSpan(text: 'senza categoria', style: TextStyle(color: c.onSurface, fontWeight: FontWeight.w800)),
                const TextSpan(text: '.'),
              ]),
              style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: Gap.sm),
            Text(_error!, style: AppText.bodySmall.copyWith(color: c.error)),
          ],
          const SizedBox(height: 18),
          Row(children: [
            if (cat != null) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _delete,
                  style: OutlinedButton.styleFrom(foregroundColor: c.error),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Elimina'),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: FilledButton(
                onPressed: canSave ? _save : null,
                child: _busy ? const SmallSpinner() : const Text('Salva'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
