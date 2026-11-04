import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _initialized = false;

  static const _palette = [
    '#4CAF50', '#03A9F4', '#795548', '#9C27B0', '#F44336', '#FF9800',
    '#E91E63', '#3F51B5', '#009688', '#607D8B', '#CDDC39', '#FFC107',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final c = AppScope.of(context).config;
      _url.text = c.url;
      _token.text = c.token;
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    final state = AppScope.of(context);
    final url = _url.text.trim();
    if (!url.startsWith('https://')) {
      _snack("L'URL deve iniziare con https://");
      return;
    }
    setState(() => _busy = true);
    try {
      await state.config.save(url: url, token: _token.text);
      await state.api.health();
      await state.configSaved();
      _snack('Connessione riuscita, impostazioni salvate.');
    } catch (e) {
      _snack('Salvate, ma il test di connessione è fallito: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editCategory([Category? cat]) async {
    final state = AppScope.of(context);
    final name = TextEditingController(text: cat?.name ?? '');
    var color = cat?.color ?? _palette.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(cat == null ? 'Nuova categoria' : 'Modifica categoria'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome'), autofocus: true),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in _palette)
                GestureDetector(
                  onTap: () => setLocal(() => color = p),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(int.parse('FF${p.substring(1)}', radix: 16)),
                    child: p == color ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                  ),
                ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      if (cat == null) {
        await state.api.addCategory(name.text.trim(), color);
      } else {
        await state.api.updateCategory(cat.id, name: name.text.trim(), color: color);
      }
      await state.reloadCategories();
    } catch (e) {
      _snack('Operazione non riuscita: $e');
    }
  }

  Future<void> _deleteCategory(Category cat) async {
    final state = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminare "${cat.name}"?'),
        content: const Text('Le righe di questa categoria resteranno senza categoria.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await state.api.deleteCategory(cat.id);
      await state.reloadCategories();
    } catch (e) {
      _snack('Eliminazione non riuscita: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Connessione', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _url,
          decoration: const InputDecoration(labelText: 'URL progetto Supabase', hintText: 'https://xxxx.supabase.co'),
          keyboardType: TextInputType.url,
          autocorrect: false,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _token,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Token app (APP_TOKEN)',
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text('Il token è salvato cifrato sul dispositivo (Keystore/Keychain) e non viene mai inviato a terzi.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save),
          label: const Text('Salva e verifica'),
        ),
        const SizedBox(height: 32),
        Row(children: [
          Expanded(child: Text('Categorie', style: Theme.of(context).textTheme.titleMedium)),
          IconButton(
            onPressed: state.config.isConfigured ? () => _editCategory() : null,
            icon: const Icon(Icons.add),
            tooltip: 'Aggiungi categoria',
          ),
        ]),
        if (state.categories.isEmpty)
          const Padding(padding: EdgeInsets.all(8), child: Text('Nessuna categoria caricata.')),
        for (final c in state.categories)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(backgroundColor: c.colorValue, radius: 10),
            title: Text(c.name),
            onTap: () => _editCategory(c),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Elimina',
              onPressed: () => _deleteCategory(c),
            ),
          ),
        const SizedBox(height: 32),
        Text('Scontrini · software libero, nessun tracker, nessun account.', style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
