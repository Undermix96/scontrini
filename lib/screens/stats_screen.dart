import 'package:flutter/material.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/donut_chart.dart';
import '../widgets/floating_nav_bar.dart';
import '../widgets/month_selector.dart';

/// Scheda Spese: spese del mese per categoria.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  DateTime _month = monthStart(DateTime.now());
  List<CategoryTotal>? _totals;
  double? _previous;
  String? _error;
  int _seen = -1;
  int _request = 0;

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
    final id = ++_request;
    setState(() => _error = null);
    final prev = DateTime(_month.year, _month.month - 1);
    try {
      final res = await Future.wait([
        s.repo.stats(from: monthStart(_month), to: monthEnd(_month)),
        s.repo.stats(from: monthStart(prev), to: monthEnd(prev)),
      ]);
      if (!mounted || id != _request) return;
      final t = res[0]..sort((a, b) => b.total.compareTo(a.total));
      setState(() {
        _totals = t;
        _previous = res[1].fold<double>(0, (sum, x) => sum + x.total);
      });
    } catch (e) {
      if (mounted && id == _request) setState(() => _error = '$e');
    }
  }

  void _setMonth(DateTime m) {
    setState(() {
      _month = m;
      _totals = null;
      _previous = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = AppScope.of(context);
    final totals = _totals;
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
                        header: true, child: Text('Spese', style: AppText.headline.copyWith(color: c.onSurface))),
                  ),
                  CompactMonthSelector(month: _month, onChanged: _setMonth),
                ]),
                const SizedBox(height: Gap.md),
                if (_error != null && totals == null)
                  _box(c, Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(_error!, textAlign: TextAlign.center, style: AppText.body.copyWith(color: c.onSurfaceMuted)),
                    const SizedBox(height: Gap.md),
                    OutlinedButton(onPressed: _load, child: const Text('Riprova')),
                  ]))
                else if (totals == null)
                  const Padding(padding: EdgeInsets.all(Gap.xxxl), child: Center(child: CircularProgressIndicator()))
                else if (totals.isEmpty)
                  _box(
                    c,
                    Text('Nessuna spesa a ${monthName(_month)}.',
                        textAlign: TextAlign.center, style: AppText.body.copyWith(color: c.onSurfaceMuted)),
                  )
                else ...[
                  _chartCard(s, c, totals),
                  const SizedBox(height: Gap.md),
                  _list(s, c, totals),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _box(ScontriniColors c, Widget child) => Container(
        padding: const EdgeInsets.all(Gap.xl),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.lg)),
        child: child,
      );

  Color _color(AppState s, int? id) => s.category(id)?.colorValue ?? ScontriniColors.uncategorized;
  String _name(AppState s, int? id) => s.category(id)?.name ?? 'Senza categoria';

  Widget _chartCard(AppState s, ScontriniColors c, List<CategoryTotal> totals) {
    final sum = totals.fold<double>(0, (t, x) => t + x.total);
    final prev = _previous;
    final diff = prev == null ? null : sum - prev;
    int pct(double v) => sum == 0 ? 0 : (v / sum * 100).round();
    final semantic = 'Spese di ${monthName(_month)}: '
        '${totals.map((t) => '${_name(s, t.categoryId)} ${pct(t.total)}%').join(', ')}';
    Widget stat(String label, String value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppText.badge.copyWith(color: c.onSurfaceMuted)),
          const SizedBox(height: 2),
          Text(value, style: AppText.title.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()])),
        ]);
    final prevMonth = DateTime(_month.year, _month.month - 1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 22),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.lg)),
      child: LayoutBuilder(builder: (context, box) {
        final size = box.maxWidth < 300 ? box.maxWidth * 0.5 : 168.0;
        return Row(children: [
          DonutChart(
            size: size,
            segments: [for (final t in totals) DonutSegment(t.total, _color(s, t.categoryId))],
            centerLabel: 'Totale',
            centerValue: money(sum),
            semanticLabel: semantic,
          ),
          const SizedBox(width: Gap.lg),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (diff != null)
                stat(
                  'Rispetto a ${monthName(prevMonth)}',
                  prev == 0 ? '—' : '${diff < 0 ? '−' : '+'} ${money(diff.abs())}',
                  diff < 0 ? c.success : c.onSurface,
                ),
              const SizedBox(height: Gap.sm),
              stat('Categoria principale', _name(s, totals.first.categoryId), c.onSurface),
            ]),
          ),
        ]);
      }),
    );
  }

  Widget _list(AppState s, ScontriniColors c, List<CategoryTotal> totals) {
    final sum = totals.fold<double>(0, (t, x) => t + x.total);
    final max = totals.map((t) => t.total).fold<double>(0, (a, b) => b > a ? b : a);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.card)),
      child: Column(children: [
        for (final t in totals)
          _CategoryBar(
            name: _name(s, t.categoryId),
            color: _color(s, t.categoryId),
            percent: sum == 0 ? '' : '${(t.total / sum * 100).round()}%',
            amount: money(t.total),
            fraction: max <= 0 ? 0 : (t.total / max).clamp(0, 1).toDouble(),
            onTap: t.categoryId == null ? null : () => s.openMovements(month: _month, categoryId: t.categoryId),
          ),
      ]),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  final String name;
  final Color color;
  final String percent;
  final String amount;
  final double fraction;
  final VoidCallback? onTap;

  const _CategoryBar({
    required this.name,
    required this.color,
    required this.percent,
    required this.amount,
    required this.fraction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: onTap != null,
      label: '$name, $percent, $amount${onTap == null ? '' : '. Mostra i movimenti'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              CategoryDot(color: color, size: 12),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.titleSmall.copyWith(color: c.onSurface)),
              ),
              Text(percent,
                  style: AppText.label.copyWith(color: c.onSurfaceMuted, fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: Gap.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 78),
                child: Text(amount, textAlign: TextAlign.end, style: AppText.amountSmall.copyWith(color: c.onSurface)),
              ),
            ]),
            const SizedBox(height: Gap.xs),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Stack(children: [
                  Container(height: 6, color: c.surfaceHigh),
                  FractionallySizedBox(widthFactor: fraction, child: Container(height: 6, color: color)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
