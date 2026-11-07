import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../theme/tokens.dart';
import '../warnings.dart';
import '../widgets/common.dart';
import '../widgets/item_editor.dart';
import '../widgets/receipt_photos.dart';
import '../widgets/warnings.dart';

/// Dettaglio di uno scontrino, con modifica delle righe sul posto.
class ReceiptScreen extends StatefulWidget {
  final String receiptId;
  final Receipt? initial;
  const ReceiptScreen({super.key, required this.receiptId, this.initial});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  Receipt? _r;
  String? _error;
  String? _expanded;
  String? _focusNew;
  bool _dirty = false;

  /// Righe tolte dalla schermata ma non ancora dal database (finché si può
  /// annullare): restano nascoste anche quando lo scontrino viene ricaricato.
  final _pendingDeletes = <String>{};
  late final AppState _state = AppScope.read(context);

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null && (init.items.isNotEmpty || init.itemCount == 0)) {
      _r = init;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_r == null) _load();
    });
  }

  @override
  void dispose() {
    // Le liste si aggiornano quando si esce, non a ogni singola modifica.
    if (_dirty) Future.microtask(_state.dataChanged);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await _state.repo.receipt(widget.receiptId);
      if (mounted) setState(() => _r = _withoutPending(r));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Receipt _withoutPending(Receipt r) {
    if (_pendingDeletes.isNotEmpty) r.items = [for (final i in r.items) if (!_pendingDeletes.contains(i.id)) i];
    return r;
  }

  void _snack(String m) => showSnack(context, m);

  // ------------------------------------------------------------ intestazione

  Future<void> _editHeader({bool focusTotal = false}) async {
    final r = _r!;
    final updated = await showModalBottomSheet<Receipt>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _HeaderSheet(receipt: r, focusTotal: focusTotal),
    );
    if (updated != null && mounted) {
      setState(() {
        _r = _withoutPending(updated);
        _dirty = true;
      });
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare lo scontrino?'),
        content: const Text('Lo scontrino e tutte le sue righe verranno eliminati definitivamente.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: ctx.colors.error),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _state.repo.deleteReceipt(widget.receiptId);
      _dirty = true;
      if (mounted) {
        Navigator.pop(context);
        _snack('Scontrino eliminato.');
      }
    } catch (e) {
      _snack('Eliminazione non riuscita: $e');
    }
  }

  // ------------------------------------------------------------ avvisi

  Future<void> _dismiss(ReceiptWarning w) async {
    final r = _r!;
    final before = List<String>.of(r.dismissedWarnings);
    setState(() => r.dismissedWarnings = {...before, w.code}.toList());
    try {
      await _state.repo.setDismissedWarnings(r.id, r.dismissedWarnings);
      _dirty = true;
    } catch (e) {
      if (mounted) setState(() => r.dismissedWarnings = before);
      _snack('Salvataggio non riuscito: $e');
    }
  }

  // ------------------------------------------------------------ righe

  Future<void> _setCategory(ReceiptItem item, int categoryId) async {
    if (item.categoryId == categoryId) return;
    final old = item.categoryId;
    setState(() => item.categoryId = categoryId);
    try {
      await _state.repo.updateItem(item.id, {'category_id': categoryId});
      _dirty = true;
    } catch (e) {
      if (mounted) setState(() => item.categoryId = old);
      _snack('Salvataggio non riuscito: $e');
    }
  }

  /// Salva descrizione e importo se sono cambiati.
  Future<void> _commitItem(ReceiptItem item, String description, String amount) async {
    final desc = description.trim();
    final total = parseAmount(amount) ?? item.total;
    final fields = <String, dynamic>{
      if (desc != item.description) 'description': desc,
      if (cents(total) != cents(item.total)) 'total': total,
    };
    if (fields.isEmpty) return;
    final oldDesc = item.description, oldTotal = item.total;
    void apply(String d, double t) {
      item.description = d;
      item.total = t;
    }

    if (mounted) {
      setState(() => apply(desc, total));
    } else {
      apply(desc, total);
    }
    try {
      await _state.repo.updateItem(item.id, fields);
      _dirty = true;
    } catch (e) {
      if (mounted) {
        setState(() => apply(oldDesc, oldTotal));
        _snack('Salvataggio non riuscito: $e');
      }
    }
  }

  Future<void> _addItem() async {
    final r = _r!;
    try {
      final item = await _state.repo.addItem(r.id, {'description': '', 'total': 0});
      _dirty = true;
      if (!mounted) return;
      setState(() {
        r.items = [...r.items, item];
        _expanded = item.id;
        _focusNew = item.id;
      });
    } catch (e) {
      _snack('Non è stato possibile aggiungere la riga: $e');
    }
  }

  void _removeItem(ReceiptItem item) {
    final r = _r!;
    final index = r.items.indexOf(item);
    _pendingDeletes.add(item.id);
    setState(() {
      r.items = [...r.items]..remove(item);
      if (_expanded == item.id) _expanded = null;
    });
    final repo = _state.repo;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    var undone = false;
    messenger
        .showSnackBar(SnackBar(
          content: Text('Riga "${item.description.isEmpty ? 'senza nome' : item.description}" eliminata'),
          duration: const Duration(seconds: 4),
          // Senza, con l'azione "Annulla" resterebbe aperto e la riga non
          // verrebbe mai eliminata dal database.
          persist: false,
          action: SnackBarAction(
            label: 'Annulla',
            onPressed: () {
              undone = true;
              _pendingDeletes.remove(item.id);
              if (mounted) {
                final cur = _r ?? r;
                setState(() => cur.items = [...cur.items]..insert(index.clamp(0, cur.items.length), item));
              }
            },
          ),
        ))
        .closed
        .then((_) async {
      if (undone) return;
      try {
        await repo.deleteItem(item.id);
        _pendingDeletes.remove(item.id);
        _dirty = true;
        if (!mounted) _state.dataChanged();
      } catch (e) {
        _pendingDeletes.remove(item.id);
        if (mounted) {
          final cur = _r ?? r;
          setState(() => cur.items = [...cur.items]..insert(index.clamp(0, cur.items.length), item));
          _snack('Eliminazione non riuscita: $e');
        }
      }
    });
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = _r;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.gutter, Gap.xs, Gap.gutter, Gap.sm),
            child: ContentWidth(
              child: Row(children: [
                RoundIconButton(icon: Icons.chevron_left, tooltip: 'Indietro', onPressed: () => Navigator.maybePop(context)),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('Scontrino',
                        textAlign: TextAlign.center, style: AppText.title.copyWith(fontSize: 17, color: c.onSurface)),
                  ),
                ),
                MenuAnchor(
                  style: MenuStyle(
                    backgroundColor: WidgetStatePropertyAll(c.surfaceHigh),
                    elevation: const WidgetStatePropertyAll(0),
                    shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.input))),
                  ),
                  menuChildren: [
                    MenuItemButton(
                      leadingIcon: Icon(Icons.delete_outline, color: c.error),
                      onPressed: r == null ? null : _delete,
                      child: Text('Elimina scontrino', style: AppText.titleSmall.copyWith(color: c.error)),
                    ),
                  ],
                  builder: (context, controller, _) => RoundIconButton(
                    icon: Icons.more_horiz,
                    tooltip: 'Altre azioni',
                    onPressed: r == null ? null : () => controller.isOpen ? controller.close() : controller.open(),
                  ),
                ),
              ]),
            ),
          ),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.xl),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, textAlign: TextAlign.center, style: AppText.body.copyWith(color: c.onSurfaceMuted)),
                        const SizedBox(height: Gap.md),
                        OutlinedButton(onPressed: _load, child: const Text('Riprova')),
                      ]),
                    ),
                  )
                : r == null
                    ? const Center(child: CircularProgressIndicator())
                    : _content(r),
          ),
        ]),
      ),
    );
  }

  Widget _content(Receipt r) {
    final c = context.colors;
    final warnings = computeWarnings(r);
    final n = r.items.length;
    return ListView(
      padding: EdgeInsets.fromLTRB(Gap.gutter, 2, Gap.gutter, Gap.xxl + MediaQuery.paddingOf(context).bottom),
      children: [
        ContentWidth(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _headerCard(r, warnings),
            ReceiptPhotos(receiptId: r.id),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text(n == 1 ? '1 riga' : '$n righe', style: AppText.title.copyWith(fontSize: 16, color: c.onSurface)),
                const SizedBox(width: Gap.sm),
                if (n > 0)
                  Expanded(
                    child: Text('Tocca una riga per correggerla',
                        textAlign: TextAlign.end, style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted)),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.card)),
              child: Column(children: [
                for (final item in r.items) _itemRow(r, item),
                AddRowButton(onTap: _addItem),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, Gap.md, 2, 0),
              child: Text(r.aiModel != null ? 'Analizzato con ${r.aiModel}.' : 'Inserito a mano.',
                  style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted)),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _headerCard(Receipt r, List<ReceiptWarning> warnings) {
    final c = context.colors;
    final payment = r.paymentMethod?.trim();
    final dateLine = [longDateTime(r.purchasedAt), if (payment != null && payment.isNotEmpty) _cap(payment)].join(' · ');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.card)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Editable(
                label: 'Esercente: ${r.displayMerchant}. Modifica',
                onTap: _editHeader,
                child: Text.rich(
                  TextSpan(text: r.displayMerchant, children: [
                    const WidgetSpan(child: SizedBox(width: 8)),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Icon(Icons.edit_outlined, size: 16, color: c.onSurfaceMuted),
                    ),
                  ]),
                  style: AppText.title.copyWith(fontSize: 22, letterSpacing: -0.4, color: c.onSurface),
                ),
              ),
              const SizedBox(height: 4),
              _Editable(
                label: 'Data: $dateLine. Modifica',
                onTap: _editHeader,
                child: Text.rich(
                  TextSpan(text: dateLine, children: [
                    const WidgetSpan(child: SizedBox(width: 6)),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Icon(Icons.edit_outlined, size: 14, color: c.onSurfaceMuted),
                    ),
                  ]),
                  style: AppText.body
                      .copyWith(fontSize: 14, fontWeight: FontWeight.w600, height: 1.35, color: c.onSurfaceMuted),
                ),
              ),
            ]),
          ),
          const SizedBox(width: Gap.sm),
          _Editable(
            label: 'Totale: ${moneySpoken(r.total, r.currency)}. Modifica',
            onTap: () => _editHeader(focusTotal: true),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Totale', style: AppText.badge.copyWith(color: c.onSurfaceMuted)),
              const SizedBox(height: 2),
              Text(money(r.total, r.currency), style: AppText.amountLarge.copyWith(color: c.onSurface)),
            ]),
          ),
        ]),
        for (final w in warnings) ...[const SizedBox(height: 14), _banner(r, w)],
      ]),
    );
  }

  Widget _banner(Receipt r, ReceiptWarning w) {
    const b = TextStyle(fontWeight: FontWeight.w800);
    switch (w) {
      case ReceiptWarning.totalMismatch:
        final sum = itemsSum(r);
        final diff = r.total - sum;
        return WarningBanner(
          text: TextSpan(children: [
            const TextSpan(text: 'Le righe sommano '),
            TextSpan(text: money(sum, r.currency), style: b),
            const TextSpan(text: ', il totale è '),
            TextSpan(text: money(r.total, r.currency), style: b),
            TextSpan(text: diff > 0 ? '. Manca ' : '. Avanza '),
            TextSpan(text: money(diff.abs(), r.currency), style: b),
            TextSpan(
                text: diff > 0 ? ': forse una riga non è stata letta.' : ': forse una riga è stata letta due volte.'),
          ]),
          actions: [
            BannerAction('Aggiungi riga', _addItem, filled: true),
            BannerAction('Va bene così', () => _dismiss(w)),
          ],
        );
      case ReceiptWarning.duplicate:
        final other = r.duplicate;
        return WarningBanner(
          text: TextSpan(
            text: other == null
                ? "C'è un altro scontrino con lo stesso totale, data e ora."
                : "C'è un altro scontrino${other.merchant?.trim().isNotEmpty == true ? ' di ${other.merchant!.trim()}' : ''} "
                    'con lo stesso totale, del ${longDate(other.purchasedAt)}.',
          ),
          actions: [
            if (r.duplicateOf != null)
              BannerAction("Apri l'altro", () {
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => ReceiptScreen(receiptId: r.duplicateOf!)));
              }, filled: true),
            BannerAction('Non è un doppione', () => _dismiss(w)),
          ],
        );
      case ReceiptWarning.date:
        return WarningBanner(
          text: TextSpan(children: [
            const TextSpan(text: 'La data letta è '),
            TextSpan(text: longDate(r.purchasedAt), style: b),
            const TextSpan(text: '. Se è sbagliata, correggila.'),
          ]),
          actions: [
            BannerAction('Correggi', _editHeader, filled: true),
            BannerAction('È giusta', () => _dismiss(w)),
          ],
        );
    }
  }

  Widget _itemRow(Receipt r, ReceiptItem item) {
    if (_expanded == item.id) {
      final focus = _focusNew == item.id;
      _focusNew = null;
      return ItemEditor(
        key: ValueKey('edit-${item.id}'),
        item: item,
        categories: _state.categories,
        autofocus: focus,
        onCategory: (id) => _setCategory(item, id),
        onCommit: (d, a, _, __) => _commitItem(item, d, a),
        onClose: () => setState(() => _expanded = null),
      );
    }
    return Dismissible(
      key: ValueKey('row-${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Gap.lg),
        color: context.colors.error.withValues(alpha: 0.16),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Text('Elimina', style: AppText.label.copyWith(color: context.colors.error)),
          const SizedBox(width: 6),
          Icon(Icons.delete_outline, color: context.colors.error),
        ]),
      ),
      onDismissed: (_) => _removeItem(item),
      child: ItemRow(
        item: item,
        category: _state.category(item.categoryId),
        currency: r.currency,
        onTap: () => setState(() => _expanded = item.id),
        onDelete: () => _removeItem(item),
      ),
    );
  }
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class _Editable extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Widget child;
  const _Editable({required this.label, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.sm),
          child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 30), child: child),
        ),
      );
}

/// Pannello di modifica dell'intestazione: esercente, data e ora, pagamento, totale.
class _HeaderSheet extends StatefulWidget {
  final Receipt receipt;
  final bool focusTotal;
  const _HeaderSheet({required this.receipt, required this.focusTotal});

  @override
  State<_HeaderSheet> createState() => _HeaderSheetState();
}

class _HeaderSheetState extends State<_HeaderSheet> {
  late final _merchant = TextEditingController(text: widget.receipt.merchant ?? '');
  late final _payment = TextEditingController(text: widget.receipt.paymentMethod ?? '');
  late final _total = TextEditingController(text: widget.receipt.total.toStringAsFixed(2).replaceAll('.', ','));
  late DateTime _date = widget.receipt.purchasedAt ?? DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _merchant.dispose();
    _payment.dispose();
    _total.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(DateTime.now()) ? DateTime.now() : _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date));
    if (t != null) setState(() => _date = DateTime(_date.year, _date.month, _date.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    final total = parseAmount(_total.text);
    if (total == null) {
      setState(() => _error = 'Scrivi un totale valido, per esempio 12,50.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await AppScope.read(context).repo.updateReceipt(widget.receipt.id, {
        'merchant': _merchant.text.trim(),
        'payment_method': _payment.text.trim().isEmpty ? null : _payment.text.trim(),
        'total': total,
        'purchased_at': _date.toUtc().toIso8601String(),
      });
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (mounted) setState(() => _error = 'Salvataggio non riuscito: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget pickButton(IconData icon, String text, String semantic, VoidCallback onTap) => Expanded(
          child: Semantics(
            button: true,
            label: semantic,
            excludeSemantics: true,
            child: Material(
              color: c.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.input), side: BorderSide(color: c.outline)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Container(
                  height: Sizes.input,
                  padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                  child: Row(children: [
                    Icon(icon, size: 20, color: c.onSurfaceMuted),
                    const SizedBox(width: 10),
                    Expanded(child: Text(text, style: AppText.titleSmall.copyWith(color: c.onSurface))),
                  ]),
                ),
              ),
            ),
          ),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.xxl + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text('Modifica scontrino', style: AppText.title.copyWith(fontSize: 20, color: c.onSurface)),
              ),
            ),
            RoundIconButton(
                icon: Icons.close, tooltip: 'Chiudi', background: c.surfaceHigh, onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 18),
          LabeledField(label: 'Esercente', controller: _merchant, autofocus: !widget.focusTotal),
          const SizedBox(height: Gap.md),
          Text('Data e ora', style: AppText.label.copyWith(color: c.onSurface)),
          const SizedBox(height: Gap.xs),
          Row(children: [
            pickButton(Icons.event_outlined, longDate(_date), 'Data: ${longDate(_date)}. Cambia', _pickDate),
            const SizedBox(width: 10),
            pickButton(Icons.schedule, '${_date.hour.toString().padLeft(2, '0')}:${_date.minute.toString().padLeft(2, '0')}',
                'Ora. Cambia', _pickTime),
          ]),
          const SizedBox(height: Gap.md),
          LabeledField(label: 'Metodo di pagamento', controller: _payment, hint: 'Contanti, carta…'),
          const SizedBox(height: Gap.md),
          LabeledField(
            label: 'Totale',
            controller: _total,
            autofocus: widget.focusTotal,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            error: _error,
          ),
          const SizedBox(height: Gap.lg),
          FilledButton(onPressed: _busy ? null : _save, child: _busy ? const SmallSpinner() : const Text('Salva')),
        ]),
      ),
    );
  }
}
