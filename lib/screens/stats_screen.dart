import 'package:flutter/material.dart';

import '../app_state.dart';
import '../budget.dart';
import '../format.dart';
import '../models.dart';
import '../theme/tokens.dart';
import '../widgets/budget_widgets.dart';
import '../widgets/common.dart';
import '../widgets/donut_chart.dart';
import '../widgets/floating_nav_bar.dart';
import '../widgets/month_selector.dart';
import '../widgets/trend_charts.dart';

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
  MonthBudget _budget = const MonthBudget();

  // Andamento: 12 mesi fino a quello selezionato (eventualmente di una sola
  // categoria), giorni del mese e del precedente, esercenti.
  static const _months = 12;
  int? _focus;
  List<double>? _monthly;
  List<double?> _monthlyBudgets = const [];
  List<double>? _daily;
  List<double>? _prevDaily;
  List<MerchantTotal> _merchants = const [];

  DateTime get _firstMonth => DateTime(_month.year, _month.month - _months + 1);
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
      final budget = await s.repo.budgetFor(_month);
      final focus = _focus;
      final monthly = await s.repo.monthlyTotals(_firstMonth, _months, categoryId: focus);
      final entries = await s.repo.budgetEntries();
      final daily = await s.repo.dailyTotals(_month);
      final prevDaily = await s.repo.dailyTotals(prev);
      final merchants = await s.repo.merchantTotals(monthStart(_month), monthEnd(_month));
      if (!mounted || id != _request) return;
      final t = res[0]..sort((a, b) => b.total.compareTo(a.total));
      setState(() {
        _totals = t;
        _previous = res[1].fold<double>(0, (sum, x) => sum + x.total);
        _budget = budget;
        _monthly = monthly;
        _monthlyBudgets = [
          for (var i = 0; i < _months; i++)
            resolveBudget(entries, DateTime(_firstMonth.year, _firstMonth.month + i)).of(focus),
        ];
        _daily = daily;
        _prevDaily = prevDaily;
        _merchants = merchants;
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
      _monthly = null;
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
                else ...[
                  if (_budget.total != null || _editable) ...[
                    BudgetCard(
                      month: _month,
                      spent: totals.fold<double>(0, (t, x) => t + x.total),
                      budget: _budget.total,
                      onEdit: _editable ? () => showBudgetSheet(context, _month) : null,
                    ),
                    const SizedBox(height: Gap.md),
                  ],
                  if (totals.isEmpty)
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
                  if (_monthly != null) ...[
                    const SizedBox(height: Gap.md),
                    _barsCard(s, c),
                  ],
                  if (totals.isNotEmpty && _daily != null && _prevDaily != null) ...[
                    const SizedBox(height: Gap.md),
                    _cumulativeCard(c),
                  ],
                  if (_merchants.isNotEmpty) ...[
                    const SizedBox(height: Gap.md),
                    _merchantsCard(s, c),
                  ],
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(ScontriniColors c, String title, Widget child, {Widget? trailing}) => Container(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.lg),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.lg)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: AppText.titleSmall.copyWith(color: c.onSurface)),
              ),
            ),
            if (trailing != null) trailing,
          ]),
          const SizedBox(height: Gap.sm),
          child,
        ]),
      );

  Future<void> _chooseFocus(AppState s) async {
    final c = context.colors;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final (id, name, color) in [
            (-1, 'Tutte le categorie', c.primary),
            for (final cat in s.categories) (cat.id, cat.name, cat.colorValue),
          ])
            ListTile(
              minTileHeight: 52,
              contentPadding: const EdgeInsets.symmetric(horizontal: Gap.gutter),
              leading: CategoryDot(color: color, size: 12),
              title: Text(name, style: AppText.titleSmall.copyWith(color: c.onSurface)),
              trailing: (id == -1 ? _focus == null : _focus == id) ? Icon(Icons.check, color: c.primary) : null,
              onTap: () => Navigator.pop(ctx, id),
            ),
        ]),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _focus = chosen == -1 ? null : chosen;
      _monthly = null;
    });
    _load();
  }

  Widget _barsCard(AppState s, ScontriniColors c) {
    final focus = s.category(_focus);
    final months = [for (var i = 0; i < _months; i++) DateTime(_firstMonth.year, _firstMonth.month + i)];
    return _card(
      c,
      'Ultimi 12 mesi',
      trailing: Semantics(
        button: true,
        label: 'Categoria del grafico: ${focus?.name ?? 'tutte'}. Cambia',
        excludeSemantics: true,
        child: InkWell(
          onTap: () => _chooseFocus(s),
          borderRadius: BorderRadius.circular(Radii.pill),
          child: Container(
            constraints: const BoxConstraints(minHeight: Sizes.touch),
            padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (focus != null) ...[CategoryDot(color: focus.colorValue, size: 10), const SizedBox(width: 6)],
              Text(focus?.name ?? 'Tutte', style: AppText.label.copyWith(color: c.primary)),
              Icon(Icons.expand_more, size: 18, color: c.primary),
            ]),
          ),
        ),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MonthlyBarsChart(
          months: months,
          values: _monthly!,
          budgets: _monthlyBudgets,
          selected: _months - 1,
          color: focus?.colorValue ?? c.primary,
          onSelect: (i) {
            if (i != _months - 1) _setMonth(months[i]);
          },
        ),
        const SizedBox(height: Gap.xs),
        Text(
          'Tratteggio: media dei mesi${_monthlyBudgets.any((b) => b != null) ? '. Trattino: budget del mese' : ''}. '
          'Tocca una barra per vedere quel mese.',
          style: AppText.badge.copyWith(color: c.onSurfaceMuted, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }

  Widget _cumulativeCard(ScontriniColors c) {
    final now = DateTime.now();
    final current = monthStart(now);
    final days = _daily!.length;
    final shown = _month == current ? now.day.clamp(1, days) : (_month.isAfter(current) ? 0 : days);
    final prev = DateTime(_month.year, _month.month - 1);
    String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
    return _card(
      c,
      'Andamento del mese',
      CumulativeChart(
        current: _daily!,
        previous: _prevDaily!,
        currentDays: shown,
        budget: _budget.total,
        color: c.primary,
        currentLabel: cap(monthName(_month)),
        previousLabel: cap(monthName(prev)),
      ),
    );
  }

  Widget _merchantsCard(AppState s, ScontriniColors c) => _card(
        c,
        'Dove spendi di più',
        Column(children: [
          for (final m in _merchants)
            Semantics(
              button: true,
              label: '${m.name}, ${moneySpoken(m.total)}, ${m.receipts == 1 ? '1 scontrino' : '${m.receipts} scontrini'}. '
                  'Mostra i movimenti',
              excludeSemantics: true,
              child: InkWell(
                onTap: () => s.openMovements(month: _month, query: m.name),
                borderRadius: BorderRadius.circular(Radii.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.titleSmall.copyWith(color: c.onSurface)),
                        Text(m.receipts == 1 ? '1 scontrino' : '${m.receipts} scontrini',
                            style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted)),
                      ]),
                    ),
                    Text(money(m.total), style: AppText.amountSmall.copyWith(color: c.onSurface)),
                  ]),
                ),
              ),
            ),
        ]),
      );

  /// Il budget si modifica dal mese corrente in poi: quelli passati restano com'erano.
  bool get _editable => !_month.isBefore(monthStart(DateTime.now()));

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
            spent: t.total,
            budget: t.categoryId == null ? null : _budget.categories[t.categoryId],
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
  final double spent;

  /// Budget della categoria nel mese: la barra mostra la spesa rispetto a esso.
  final double? budget;
  final VoidCallback? onTap;

  const _CategoryBar({
    required this.name,
    required this.color,
    required this.percent,
    required this.amount,
    required this.fraction,
    required this.spent,
    required this.budget,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = budget;
    final level = budgetLevel(spent, b);
    return Semantics(
      button: onTap != null,
      label: '$name, $percent, $amount${b == null ? '' : ' su un budget di ${money(b)}'}'
          '${onTap == null ? '' : '. Mostra i movimenti'}',
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
              child: b == null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Stack(children: [
                        Container(height: 6, color: c.surfaceHigh),
                        FractionallySizedBox(widthFactor: fraction, child: Container(height: 6, color: color)),
                      ]),
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      BudgetBar(spent: spent, budget: b, height: 6, color: level == BudgetLevel.ok ? color : null),
                      const SizedBox(height: 3),
                      Text('${budgetRemaining(spent, b)} su ${money(b)}',
                          style: AppText.badge.copyWith(
                              color: level == BudgetLevel.ok ? c.onSurfaceMuted : budgetColor(c, level))),
                    ]),
            ),
          ]),
        ),
      ),
    );
  }
}
