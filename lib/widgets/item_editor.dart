import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../models.dart';
import '../theme/tokens.dart';
import 'category_widgets.dart';
import 'common.dart';

/// Righe di uno scontrino: riga chiusa, riga in modifica e "Aggiungi riga".
/// Usate dal dettaglio e dall'inserimento manuale.

class ItemRow extends StatelessWidget {
  final ReceiptItem item;
  final Category? category;
  final String currency;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const ItemRow({
    super.key,
    required this.item,
    required this.category,
    required this.currency,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = item.quantity;
    String? qty;
    if (q != null && q != 1 && item.unitPrice != null) {
      qty = '${quantity(q)} × ${money(item.unitPrice!, currency)}';
    } else if (q != null && q != q.roundToDouble()) {
      qty = quantity(q);
    }
    final catName = category?.name ?? 'Senza categoria';
    final desc = item.description.isEmpty ? '(senza descrizione)' : item.description;
    return Semantics(
      button: true,
      label: '$desc, ${moneySpoken(item.total, currency)}, $catName${qty == null ? '' : ', $qty'}. Tocca per modificare',
      excludeSemantics: true,
      customSemanticsActions: {const CustomSemanticsAction(label: 'Elimina riga'): onDelete},
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 11),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.titleSmall.copyWith(color: item.description.isEmpty ? c.onSurfaceMuted : c.onSurface)),
                const SizedBox(height: 3),
                Row(children: [
                  CategoryDot(color: category?.colorValue ?? c.onSurfaceMuted, size: 9),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(qty == null ? catName : '$catName · $qty',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted, height: 1.3)),
                  ),
                ]),
              ]),
            ),
            const SizedBox(width: Gap.sm),
            Text(money(item.total, currency), style: AppText.amountSmall.copyWith(color: c.onSurface)),
          ]),
        ),
      ),
    );
  }
}

/// Riga espansa: descrizione, importo e chip di categoria (con
/// [showQuantity] anche quantità e prezzo unitario, che calcolano l'importo).
class ItemEditor extends StatefulWidget {
  final ReceiptItem item;
  final List<Category> categories;
  final bool autofocus;
  final ValueChanged<int> onCategory;
  final void Function(String description, String amount, String quantity, String unitPrice) onCommit;
  final VoidCallback onClose;
  final bool showQuantity;

  /// Chiamato a ogni modifica (oltre a [onCommit] quando la riga si chiude).
  final void Function(String description, String amount, String quantity, String unitPrice)? onChanged;

  const ItemEditor({
    super.key,
    required this.item,
    required this.categories,
    required this.autofocus,
    required this.onCategory,
    required this.onCommit,
    required this.onClose,
    this.showQuantity = false,
    this.onChanged,
  });

  @override
  State<ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<ItemEditor> {
  late final _desc = TextEditingController(text: widget.item.description);
  late final _amount = TextEditingController(text: _amountText(widget.item.total));
  late final _qty = TextEditingController(text: widget.item.quantity == null ? '' : quantity(widget.item.quantity!));
  late final _unit =
      TextEditingController(text: widget.item.unitPrice == null ? '' : _amountText(widget.item.unitPrice!));
  final _descFocus = FocusNode();
  final _amountFocus = FocusNode();
  final _qtyFocus = FocusNode();
  final _unitFocus = FocusNode();

  static String _amountText(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  /// Quantità e prezzo unitario compilati: l'importo si calcola da solo.
  void _recompute() {
    final q = parseAmount(_qty.text), u = parseAmount(_unit.text);
    if (q != null && u != null) _amount.text = _amountText((q * u * 100).round() / 100);
    _changed();
  }

  void _changed() => widget.onChanged?.call(_desc.text, _amount.text, _qty.text, _unit.text);

  @override
  void initState() {
    super.initState();
    for (final f in [_descFocus, _amountFocus, _qtyFocus, _unitFocus]) {
      f.addListener(_onFocus);
    }
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _descFocus.requestFocus());
    }
  }

  void _onFocus() {
    if (![_descFocus, _amountFocus, _qtyFocus, _unitFocus].any((f) => f.hasFocus)) _commit();
  }

  void _commit() => widget.onCommit(_desc.text, _amount.text, _qty.text, _unit.text);

  @override
  void dispose() {
    // Chiusa toccando un'altra riga: salva quello che è stato scritto.
    final d = _desc.text, a = _amount.text, q = _qty.text, u = _unit.text;
    final commit = widget.onCommit;
    scheduleMicrotask(() => commit(d, a, q, u));
    for (final f in [_descFocus, _amountFocus, _qtyFocus, _unitFocus]) {
      f.dispose();
    }
    for (final t in [_desc, _amount, _qty, _unit]) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    InputDecoration deco() => InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          fillColor: c.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.sm), borderSide: BorderSide(color: c.outline)),
          enabledBorder:
              OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.sm), borderSide: BorderSide(color: c.outline)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.sm), borderSide: BorderSide(color: c.primary, width: 1.5)),
        );
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(t, style: AppText.badge.copyWith(color: c.onSurfaceMuted)),
        );
    return Container(
      margin: const EdgeInsets.all(6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.primary, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              label('Descrizione'),
              TextField(
                controller: _desc,
                focusNode: _descFocus,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _changed(),
                onSubmitted: (_) => _amountFocus.requestFocus(),
                style: AppText.titleSmall.copyWith(fontWeight: FontWeight.w600, color: c.onSurface),
                decoration: deco(),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              label('Importo'),
              TextField(
                controller: _amount,
                focusNode: _amountFocus,
                textAlign: TextAlign.right,
                onChanged: (_) => _changed(),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\-]'))],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _commit(),
                style: AppText.amountSmall.copyWith(fontWeight: FontWeight.w700, color: c.onSurface),
                decoration: deco(),
              ),
            ]),
          ),
        ]),
        if (widget.showQuantity) ...[
          const SizedBox(height: Gap.sm),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                label('Quantità (facoltativa)'),
                TextField(
                  controller: _qty,
                  focusNode: _qtyFocus,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _recompute(),
                  onSubmitted: (_) => _unitFocus.requestFocus(),
                  style: AppText.titleSmall.copyWith(fontWeight: FontWeight.w600, color: c.onSurface),
                  decoration: deco(),
                ),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                label('Prezzo unitario'),
                TextField(
                  controller: _unit,
                  focusNode: _unitFocus,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => _recompute(),
                  onSubmitted: (_) => _commit(),
                  style: AppText.titleSmall.copyWith(fontWeight: FontWeight.w600, color: c.onSurface),
                  decoration: deco(),
                ),
              ]),
            ),
          ]),
        ],
        const SizedBox(height: Gap.sm),
        Row(children: [
          Expanded(child: label('Categoria')),
          Semantics(
            button: true,
            label: 'Chiudi la modifica',
            excludeSemantics: true,
            child: InkWell(
              onTap: () {
                FocusScope.of(context).unfocus();
                widget.onClose();
              },
              customBorder: const CircleBorder(),
              child: SizedBox.square(dimension: Sizes.touch, child: Icon(Icons.expand_less, color: c.onSurfaceMuted)),
            ),
          ),
        ]),
        Semantics(
          label: 'Categoria della riga',
          container: true,
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final cat in widget.categories)
              CategoryChip(
                name: cat.name,
                color: cat.colorValue,
                selected: widget.item.categoryId == cat.id,
                onTap: () => widget.onCategory(cat.id),
              ),
          ]),
        ),
      ]),
    );
  }
}

class AddRowButton extends StatelessWidget {
  final VoidCallback onTap;
  const AddRowButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 13),
        child: Row(children: [
          Icon(Icons.add, size: 20, color: c.primary),
          const SizedBox(width: 8),
          Text('Aggiungi riga', style: AppText.titleSmall.copyWith(color: c.primary)),
        ]),
      ),
    );
  }
}

