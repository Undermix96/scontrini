import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../format.dart';
import '../main.dart';
import '../models.dart';
import 'month_picker.dart';
import 'receipt_screen.dart';

class MovementsScreen extends StatefulWidget {
  const MovementsScreen({super.key});

  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends State<MovementsScreen> {
  DateTime _month = monthStart(DateTime.now());
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
      final list = await s.api.receipts(from: monthStart(_month), to: monthEnd(_month));
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
      await navigator.push(MaterialPageRoute(builder: (_) => ReceiptScreen(receiptId: receipt.id, initial: receipt)));
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Scansione non riuscita: $e')));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

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
    final receipts = _receipts;
    final total = receipts?.fold<double>(0, (s, r) => s + r.total) ?? 0;
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
      body: Column(children: [
        MonthBar(
          month: _month,
          onChanged: (m) {
            setState(() {
              _month = m;
              _receipts = null;
            });
            _load();
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(children: [
            Text('Totale del mese', style: Theme.of(context).textTheme.bodyLarge),
            const Spacer(),
            Text(money(total), style: Theme.of(context).textTheme.titleLarge),
          ]),
        ),
        const Divider(),
        Expanded(child: _body(receipts)),
      ]),
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
              child: Text('Nessuno scontrino in questo mese.\nPremi "Scansiona" per aggiungerne uno.',
                  textAlign: TextAlign.center)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: receipts.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final r = receipts[i];
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.receipt)),
            title: Text(r.merchant?.isNotEmpty == true ? r.merchant! : 'Esercente sconosciuto'),
            subtitle: Text('${dateTime(r.purchasedAt)} · ${r.itemCount} righe'),
            trailing: Text(money(r.total, r.currency), style: Theme.of(ctx).textTheme.titleMedium),
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
