import 'package:flutter/material.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../theme/tokens.dart';
import '../warnings.dart';
import '../widgets/budget_widgets.dart';
import '../widgets/common.dart';
import '../widgets/item_editor.dart';
import 'receipt_screen.dart';
import 'scan_screen.dart';

/// Nuova spesa inserita a mano: intestazione e una o più righe, con il
/// totale calcolato dalle righe. Nessuna AI.
class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  late final AppState _state = AppScope.read(context);
  final _merchant = TextEditingController();
  final _payment = TextEditingController();
  final _notes = TextEditingController();
  late DateTime _date = _state.repo.now();
  bool _dateChanged = false;

  final List<ReceiptItem> _items = [];
  String? _expanded;
  String? _focusNew;
  int _nextId = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _addItem();
  }

  @override
  void dispose() {
    _merchant.dispose();
    _payment.dispose();
    _notes.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ righe

  void _addItem() {
    final id = 'draft-${_nextId++}';
    setState(() {
      _items.add(ReceiptItem(
        id: id,
        position: _items.length,
        description: '',
        quantity: null,
        unitPrice: null,
        total: 0,
        // Spesso le righe di una spesa sono della stessa categoria.
        categoryId: _items.isEmpty ? null : _items.last.categoryId,
      ));
      _expanded = id;
      _focusNew = id;
    });
  }

  void _update(ReceiptItem item, String desc, String amount, String qty, String unit) {
    setState(() {
      item.description = desc.trim();
      item.total = parseAmount(amount) ?? 0;
      item.quantity = parseAmount(qty);
      item.unitPrice = item.quantity == null ? null : parseAmount(unit);
    });
  }

  void _remove(ReceiptItem item) => setState(() {
        _items.remove(item);
        if (_expanded == item.id) _expanded = null;
      });

  /// Righe da salvare: quelle con un importo o una descrizione.
  List<ReceiptItem> get _filled => [for (final i in _items) if (cents(i.total) != 0 || i.description.isNotEmpty) i];

  double get _total => _filled.fold<int>(0, (s, i) => s + cents(i.total)) / 100;

  bool get _canSave => !_busy && _filled.any((i) => cents(i.total) != 0);

  bool get _dirty =>
      _merchant.text.trim().isNotEmpty ||
      _payment.text.trim().isNotEmpty ||
      _notes.text.trim().isNotEmpty ||
      _dateChanged ||
      _filled.isNotEmpty;

  // ------------------------------------------------------------ data

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (d != null) {
      setState(() {
        _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute);
        _dateChanged = true;
      });
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date));
    if (t != null) {
      setState(() {
        _date = DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);
        _dateChanged = true;
      });
    }
  }

  // ------------------------------------------------------------ salvataggio

  Future<void> _save() async {
    if (!_canSave) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    try {
      final r = await _state.repo.createReceipt(
        merchant: _merchant.text,
        purchasedAt: _date,
        paymentMethod: _payment.text,
        notes: _notes.text,
        items: [
          for (final i in _filled)
            {
              'description': i.description,
              'total': i.total,
              'quantity': i.quantity,
              'unit_price': i.unitPrice,
              'category_id': i.categoryId,
            },
        ],
      );
      _state.dataChanged();
      if (!mounted) return;
      if (r.possibleDuplicateOf != null && await askDuplicate(context) == false) {
        await _state.repo.deleteReceipt(r.id);
        _state.dataChanged();
        if (mounted) setState(() => _busy = false);
        return;
      }
      final alert = await budgetAlertText(_state, r);
      if (alert != null && mounted) showSnack(context, '$alert.');
      navigator.pushReplacement(MaterialPageRoute(builder: (_) => ReceiptScreen(receiptId: r.id, initial: r)));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, 'Salvataggio non riuscito: $e');
      }
    }
  }

  Future<void> _close() async {
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scartare la spesa?'),
        content: const Text('Quello che hai scritto non verrà salvato.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continua a scrivere')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: ctx.colors.error),
            child: const Text('Scarta'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  // ------------------------------------------------------------ interfaccia

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.gutter, Gap.xs, Gap.gutter, Gap.sm),
              child: ContentWidth(
                child: Row(children: [
                  RoundIconButton(icon: Icons.close, tooltip: 'Chiudi', onPressed: _close),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text('Nuova spesa',
                          textAlign: TextAlign.center, style: AppText.title.copyWith(fontSize: 17, color: c.onSurface)),
                    ),
                  ),
                  const SizedBox(width: Sizes.iconButton),
                ]),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Gap.gutter, 2, Gap.gutter, Gap.lg),
                children: [ContentWidth(child: _form(c))],
              ),
            ),
            _bottomBar(c),
          ]),
        ),
      ),
    );
  }

  Widget _form(ScontriniColors c) {
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
    final time = '${_date.hour.toString().padLeft(2, '0')}:${_date.minute.toString().padLeft(2, '0')}';
    final n = _items.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LabeledField(
        label: 'Esercente',
        controller: _merchant,
        hint: 'Facoltativo',
        textInputAction: TextInputAction.next,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: Gap.md),
      Text('Data e ora', style: AppText.label.copyWith(color: c.onSurface)),
      const SizedBox(height: Gap.xs),
      Row(children: [
        pickButton(Icons.event_outlined, longDate(_date), 'Data: ${longDate(_date)}. Cambia', _pickDate),
        const SizedBox(width: 10),
        pickButton(Icons.schedule, time, 'Ora: $time. Cambia', _pickTime),
      ]),
      const SizedBox(height: Gap.md),
      LabeledField(
        label: 'Metodo di pagamento',
        controller: _payment,
        hint: 'Contanti, carta… (facoltativo)',
        textInputAction: TextInputAction.next,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: Gap.md),
      LabeledField(
        label: 'Note',
        controller: _notes,
        hint: 'Facoltative',
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: Gap.lg),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(n == 1 ? '1 riga' : '$n righe', style: AppText.title.copyWith(fontSize: 16, color: c.onSurface)),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.card)),
        child: Column(children: [
          for (final item in _items) _itemRow(item),
          AddRowButton(onTap: _addItem),
        ]),
      ),
      const SizedBox(height: Gap.xs),
      Text('Per uno sconto scrivi un importo negativo.', style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted)),
    ]);
  }

  Widget _itemRow(ReceiptItem item) {
    if (_expanded == item.id) {
      final focus = _focusNew == item.id;
      _focusNew = null;
      return ItemEditor(
        key: ValueKey('edit-${item.id}'),
        item: item,
        categories: _state.categories,
        autofocus: focus,
        showQuantity: true,
        onCategory: (id) => setState(() => item.categoryId = id),
        onChanged: (d, a, q, u) => _update(item, d, a, q, u),
        onCommit: (d, a, q, u) {
          if (mounted && _items.contains(item)) _update(item, d, a, q, u);
        },
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
      onDismissed: (_) => _remove(item),
      child: ItemRow(
        item: item,
        category: _state.category(item.categoryId),
        currency: 'EUR',
        onTap: () => setState(() => _expanded = item.id),
        onDelete: () => _remove(item),
      ),
    );
  }

  Widget _bottomBar(ScontriniColors c) => Container(
        decoration: BoxDecoration(color: c.background, border: Border(top: BorderSide(color: c.outline))),
        padding: const EdgeInsets.fromLTRB(Gap.gutter, Gap.sm, Gap.gutter, Gap.sm),
        child: ContentWidth(
          child: Row(children: [
            Expanded(
              child: Semantics(
                label: 'Totale ${moneySpoken(_total)}',
                excludeSemantics: true,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('Totale', style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted)),
                  Text(money(_total), style: AppText.amountLarge.copyWith(color: c.onSurface)),
                ]),
              ),
            ),
            FilledButton(
              onPressed: _canSave ? _save : null,
              child: _busy ? const SmallSpinner() : const Text('Salva'),
            ),
          ]),
        ),
      );
}
