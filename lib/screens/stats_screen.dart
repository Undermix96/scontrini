import 'package:flutter/material.dart';

import '../format.dart';
import '../main.dart';
import '../models.dart';
import 'month_picker.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  DateTime _month = monthStart(DateTime.now());
  List<CategoryTotal>? _totals;
  String? _error;
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
      final t = await s.api.stats(from: monthStart(_month), to: monthEnd(_month));
      t.sort((a, b) => b.total.compareTo(a.total));
      if (mounted) setState(() => _totals = t);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final totals = _totals;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spese per categoria'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Aggiorna')],
      ),
      body: Column(children: [
        MonthBar(
          month: _month,
          onChanged: (m) {
            setState(() {
              _month = m;
              _totals = null;
            });
            _load();
          },
        ),
        const Divider(),
        Expanded(
          child: _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : totals == null
                  ? const Center(child: CircularProgressIndicator())
                  : totals.isEmpty
                      ? const Center(child: Text('Nessuna spesa in questo mese.'))
                      : RefreshIndicator(onRefresh: _load, child: _list(context, state, totals)),
        ),
      ]),
    );
  }

  Widget _list(BuildContext context, AppState state, List<CategoryTotal> totals) {
    final sum = totals.fold<double>(0, (s, t) => s + t.total);
    final max = totals.map((t) => t.total).fold<double>(0, (a, b) => b > a ? b : a);
    return ListView(
      children: [
        ListTile(
          title: const Text('Totale'),
          trailing: Text(money(sum), style: Theme.of(context).textTheme.titleLarge),
        ),
        for (final t in totals)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(backgroundColor: state.category(t.categoryId)?.colorValue ?? Colors.grey, radius: 6),
                const SizedBox(width: 8),
                Expanded(child: Text(state.category(t.categoryId)?.name ?? 'Senza categoria')),
                Text(money(t.total)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  child: Text(sum == 0 ? '' : '${(t.total / sum * 100).round()}%', textAlign: TextAlign.end),
                ),
              ]),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: max <= 0 ? 0 : (t.total / max).clamp(0, 1).toDouble(),
                color: state.category(t.categoryId)?.colorValue,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ]),
          ),
      ],
    );
  }
}
