import 'package:flutter/material.dart';

import '../format.dart';
import '../main.dart';
import '../models.dart';

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

  @override
  void initState() {
    super.initState();
    _r = widget.initial;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_r == null && _error == null) _load();
  }

  Future<void> _load() async {
    try {
      final r = await AppScope.of(context).api.receipt(widget.receiptId);
      if (mounted) setState(() => _r = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickCategory(ReceiptItem item) async {
    final state = AppScope.of(context);
    final chosen = await showModalBottomSheet<Category>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Categoria')),
          for (final c in state.categories)
            ListTile(
              leading: CircleAvatar(backgroundColor: c.colorValue, radius: 10),
              title: Text(c.name),
              trailing: c.id == item.categoryId ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, c),
            ),
        ]),
      ),
    );
    if (chosen == null || chosen.id == item.categoryId) return;
    final old = item.categoryId;
    setState(() => item.categoryId = chosen.id);
    try {
      await state.api.updateItem(item.id, {'category_id': chosen.id});
    } catch (e) {
      setState(() => item.categoryId = old);
      _snack('Salvataggio non riuscito: $e');
    }
  }

  Future<void> _editItem(ReceiptItem item) async {
    final desc = TextEditingController(text: item.description);
    final tot = TextEditingController(text: item.total.toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifica riga'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: desc, decoration: const InputDecoration(labelText: 'Descrizione')),
          TextField(
            controller: tot,
            decoration: const InputDecoration(labelText: 'Importo'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final total = double.tryParse(tot.text.replaceAll(',', '.')) ?? item.total;
    try {
      await AppScope.of(context).api.updateItem(item.id, {'description': desc.text.trim(), 'total': total});
      setState(() {
        item.description = desc.text.trim();
        item.total = total;
      });
    } catch (e) {
      _snack('Salvataggio non riuscito: $e');
    }
  }

  Future<void> _editHeader() async {
    final r = _r!;
    final merchant = TextEditingController(text: r.merchant ?? '');
    final total = TextEditingController(text: r.total.toStringAsFixed(2));
    var date = r.purchasedAt ?? DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Modifica scontrino'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: merchant, decoration: const InputDecoration(labelText: 'Esercente')),
            TextField(
              controller: total,
              decoration: const InputDecoration(labelText: 'Totale'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(dateTime(date)),
              onPressed: () async {
                final d = await showDatePicker(
                    context: ctx, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime.now());
                if (d != null) setLocal(() => date = DateTime(d.year, d.month, d.day, date.hour, date.minute));
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final updated = await AppScope.of(context).api.updateReceipt(r.id, {
        'merchant': merchant.text.trim(),
        'total': double.tryParse(total.text.replaceAll(',', '.')) ?? r.total,
        'purchased_at': date.toUtc().toIso8601String(),
      });
      setState(() => _r = updated);
    } catch (e) {
      _snack('Salvataggio non riuscito: $e');
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
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AppScope.of(context).api.deleteReceipt(widget.receiptId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('Eliminazione non riuscita: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final r = _r;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scontrino'),
        actions: [
          if (r != null) IconButton(onPressed: _editHeader, icon: const Icon(Icons.edit), tooltip: 'Modifica'),
          if (r != null) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline), tooltip: 'Elimina'),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : r == null
              ? const Center(child: CircularProgressIndicator())
              : _content(context, state, r),
    );
  }

  Widget _content(BuildContext context, AppState state, Receipt r) {
    final theme = Theme.of(context);
    final itemsSum = r.items.fold<double>(0, (s, i) => s + i.total);
    final mismatch = r.items.isNotEmpty && (itemsSum - r.total).abs() > 0.01;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ListTile(
          title: Text(r.merchant?.isNotEmpty == true ? r.merchant! : 'Esercente sconosciuto',
              style: theme.textTheme.titleLarge),
          subtitle: Text([
            dateTime(r.purchasedAt),
            if (r.paymentMethod != null && r.paymentMethod!.isNotEmpty) r.paymentMethod!,
          ].join(' · ')),
          trailing: Text(money(r.total, r.currency), style: theme.textTheme.headlineSmall),
        ),
        if (mismatch)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('La somma delle righe (${money(itemsSum, r.currency)}) non coincide con il totale. '
                    'Controlla le righe o il totale.'),
              ),
            ),
          ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child:
              Text('Righe (${r.items.length}) — tocca la categoria per cambiarla', style: theme.textTheme.labelLarge),
        ),
        for (final item in r.items)
          ListTile(
            title: Text(item.description),
            subtitle: Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: CircleAvatar(
                    backgroundColor: state.category(item.categoryId)?.colorValue ?? Colors.grey, radius: 6),
                label: Text(state.category(item.categoryId)?.name ?? 'Senza categoria'),
                onPressed: () => _pickCategory(item),
                visualDensity: VisualDensity.compact,
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(money(item.total, r.currency), style: theme.textTheme.titleSmall),
                if (item.quantity != null && item.quantity != 1)
                  Text('${_qty(item.quantity!)} × ${item.unitPrice != null ? money(item.unitPrice!, r.currency) : '—'}',
                      style: theme.textTheme.bodySmall),
              ],
            ),
            onLongPress: () => _editItem(item),
          ),
        if (r.aiModel != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Analizzato con ${r.aiModel}. Tieni premuta una riga per modificarla.',
                style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }

  String _qty(double q) => q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toString().replaceAll('.', ',');
}
