import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../format.dart';
import '../main.dart';
import '../models.dart';
import 'receipt_screen.dart';

/// Tutti i movimenti, dal più recente, raggruppati per mese con subtotale.
class MovementsScreen extends StatefulWidget {
  const MovementsScreen({super.key});

  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends State<MovementsScreen> {
  List<Receipt>? _receipts;
  String? _error;
  bool _scanning = false;
  AppState? _state;
  int _seenConfig = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    _state = s;
    if (_seenConfig != s.configVersion) {
      _seenConfig = s.configVersion;
      _load();
    }
  }

  Future<void> _load() async {
    final s = _state!;
    if (!s.config.isConfigured) {
      setState(() => _error = 'Configura URL e token nelle Impostazioni.');
      return;
    }
    setState(() => _error = null);
    try {
      final list = await s.api.allReceipts();
      if (mounted) setState(() => _receipts = list);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _scan(ImageSource source) async {
    final s = _state!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
    if (picked == null) return;
    setState(() => _scanning = true);
    try {
      final bytes = await picked.readAsBytes();
      final name = picked.name.toLowerCase();
      final mime = name.endsWith('.png')
          ? 'image/png'
          : name.endsWith('.webp')
              ? 'image/webp'
              : (name.endsWith('.heic') || name.endsWith('.heif'))
                  ? 'image/heic'
                  : 'image/jpeg';
      if (s.categories.isEmpty) await s.reloadCategories();
      final receipt = await s.api.scan(bytes, mime);
      if (!mounted) return;
      if (receipt.possibleDuplicateOf != null) {
        final keep = await _askDuplicate();
        if (keep == false) {
          await s.api.deleteReceipt(receipt.id);
          messenger.showSnackBar(const SnackBar(content: Text('Doppione eliminato.')));
          await _load();
          return;
        }
      }
      await navigator.push(MaterialPageRoute(builder: (_) => ReceiptScreen(receiptId: receipt.id, initial: receipt)));
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Scansione non riuscita: $e')));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<bool?> _askDuplicate() => showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Possibile doppione'),
          content: const Text('Esiste già uno scontrino con lo stesso totale, data e ora. Vuoi tenerlo comunque?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Elimina il nuovo')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tienilo')),
          ],
        ),
      );

  void _chooseSource() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Scatta foto'),
            onTap: () {
              Navigator.pop(ctx);
              _scan(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Scegli dalla galleria'),
            onTap: () {
              Navigator.pop(ctx);
              _scan(ImageSource.gallery);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Movimenti'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Aggiorna')],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanning || !(_state?.config.isConfigured ?? false) ? null : _chooseSource,
        icon: _scanning
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.document_scanner),
        label: Text(_scanning ? 'Analisi in corso…' : 'Scansiona'),
      ),
      body: _body(_receipts),
    );
  }

  Widget _body(List<Receipt>? receipts) {
    if (_error != null) {
      return Center(
          child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)));
    }
    if (receipts == null) return const Center(child: CircularProgressIndicator());
    if (receipts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: const [
          SizedBox(height: 120),
          Center(
              child: Text('Nessuno scontrino.\nPremi "Scansiona" per aggiungerne uno.', textAlign: TextAlign.center)),
        ]),
      );
    }

    // Raggruppa per mese (le date sono già in ordine decrescente).
    final rows = <Object>[];
    final monthTotals = <DateTime, double>{};
    DateTime? current;
    for (final r in receipts) {
      final d = r.purchasedAt ?? DateTime(1970);
      final m = DateTime(d.year, d.month);
      monthTotals[m] = (monthTotals[m] ?? 0) + r.total;
      if (m != current) {
        rows.add(m);
        current = m;
      }
      rows.add(r);
    }

    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: rows.length,
        itemBuilder: (ctx, i) {
          final row = rows[i];
          if (row is DateTime) {
            return Container(
              color: theme.colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                Text(monthLabel(row), style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(money(monthTotals[row] ?? 0), style: theme.textTheme.titleSmall),
              ]),
            );
          }
          final r = row as Receipt;
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.receipt)),
            title: Text(r.merchant?.isNotEmpty == true ? r.merchant! : 'Esercente sconosciuto'),
            subtitle: Text('${dateTime(r.purchasedAt)} · ${r.itemCount} righe'),
            trailing: Text(money(r.total, r.currency), style: theme.textTheme.titleMedium),
            onTap: () async {
              await Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => ReceiptScreen(receiptId: r.id)));
              _load();
            },
          );
        },
      ),
    );
  }
}
