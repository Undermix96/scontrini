import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../theme/tokens.dart';
import '../widgets/category_widgets.dart';
import '../widgets/common.dart';
import '../widgets/floating_nav_bar.dart';
import '../widgets/month_selector.dart';
import '../widgets/receipt_tile.dart';
import '../widgets/summary_card.dart';
import 'receipt_screen.dart';
import 'scan_screen.dart';

/// Movimenti: un mese alla volta, con card di riepilogo e gruppi per giorno.
class MovementsScreen extends StatefulWidget {
  const MovementsScreen({super.key});

  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends State<MovementsScreen> {
  /// Tutti gli scontrini del mese (per la card di riepilogo).
  List<Receipt>? _month;

  /// Scontrini mostrati (filtrati da ricerca e categoria).
  List<Receipt>? _list;
  String? _error;
  String _loadedKey = '';
  DateTime? _loadedMonth;
  int _request = 0;

  bool _searching = false;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    final key = '${s.dataVersion}|${s.movementsMonth}|${s.movementsCategory}|${s.movementsQuery}';
    if (key != _loadedKey) {
      final monthChanged = _loadedMonth != s.movementsMonth;
      _loadedMonth = s.movementsMonth;
      _loadedKey = key;
      if (s.movementsQuery.isNotEmpty && !_searching) {
        _searching = true;
        _search.text = s.movementsQuery;
      }
      _load(reset: monthChanged);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Budget totale del mese mostrato.
  double? _budget;

  Future<void> _load({bool reset = false}) async {
    final s = AppScope.read(context);
    if (!s.config.isConfigured) return;
    final id = ++_request;
    if (reset) {
      setState(() {
        _month = null;
        _list = null;
      });
    }
    setState(() => _error = null);
    final from = monthStart(s.movementsMonth), to = monthEnd(s.movementsMonth);
    final filtered = s.movementsCategory != null || s.movementsQuery.trim().isNotEmpty;
    try {
      final results = await Future.wait([
        s.repo.receipts(from: from, to: to),
        if (filtered) s.repo.receipts(from: from, to: to, q: s.movementsQuery, categoryId: s.movementsCategory),
      ]);
      final budget = await s.repo.budgetFor(from);
      if (!mounted || id != _request) return;
      setState(() {
        _month = results[0];
        _list = filtered ? results[1] : results[0];
        _budget = budget.total;
      });
    } catch (e) {
      if (mounted && id == _request) setState(() => _error = '$e');
    }
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      AppScope.read(context).setMovementsFilter(categoryId: AppScope.read(context).movementsCategory, query: q.trim());
    });
  }

  void _closeSearch() {
    _debounce?.cancel();
    _search.clear();
    setState(() => _searching = false);
    final s = AppScope.read(context);
    s.setMovementsFilter(categoryId: s.movementsCategory, query: '');
  }

  Future<void> _openReceipt(Receipt r) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReceiptScreen(receiptId: r.id)));
  }

  Future<void> _chooseFilter() async {
    final s = AppScope.read(context);
    final chosen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final c = ctx.colors;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.xl),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Filtra per categoria', style: AppText.title.copyWith(fontSize: 20, color: c.onSurface)),
              const SizedBox(height: Gap.md),
              Wrap(spacing: 6, runSpacing: 6, children: [
                CategoryChip(
                  name: 'Tutte',
                  color: c.onSurfaceMuted,
                  selected: s.movementsCategory == null,
                  onTap: () => Navigator.pop(ctx, -1),
                ),
                for (final cat in s.categories)
                  CategoryChip(
                    name: cat.name,
                    color: cat.colorValue,
                    selected: s.movementsCategory == cat.id,
                    onTap: () => Navigator.pop(ctx, cat.id),
                  ),
              ]),
            ]),
          ),
        );
      },
    );
    if (chosen == null) return;
    s.setMovementsFilter(categoryId: chosen == -1 ? null : chosen);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = context.colors;
    final month = s.movementsMonth;
    final monthList = _month;
    final total = monthList?.fold<double>(0, (t, r) => t + r.total);
    final toCheck = monthList?.where((r) => r.warnings.isNotEmpty).length ?? 0;
    final count = monthList?.length ?? 0;
    final subtitle = monthList == null
        ? ' '
        : count == 0
            ? 'Nessuno scontrino'
            : [count == 1 ? '1 scontrino' : '$count scontrini', if (toCheck > 0) '$toCheck da controllare'].join(' · ');
    final filterCat = s.category(s.movementsCategory);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Gap.gutter, Gap.xs, Gap.gutter, 0),
            sliver: SliverToBoxAdapter(
              child: ContentWidth(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _searching ? _searchBar(c) : _header(month, s),
                  const SizedBox(height: Gap.md),
                  SummaryCard(
                    label: 'Speso a ${monthName(month)}',
                    total: total == null ? '—' : money(total),
                    subtitle: subtitle,
                    budget: monthList == null ? null : _budget,
                    spent: total ?? 0,
                    onCamera: () => startScanFlow(context, ImageSource.camera),
                    onGallery: () => startScanFlow(context, ImageSource.gallery),
                  ),
                  const SizedBox(height: Gap.md),
                  Row(children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text('Movimenti', style: AppText.title.copyWith(color: c.onSurface)),
                      ),
                    ),
                    TextButton(
                      onPressed: s.categories.isEmpty ? null : _chooseFilter,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        textStyle: AppText.label.copyWith(fontSize: 14),
                      ),
                      child: const Text('Filtra'),
                    ),
                  ]),
                  if (filterCat != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Gap.xs),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _ActiveFilter(
                          category: filterCat,
                          onClear: () => s.setMovementsFilter(categoryId: null),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ),
          ..._content(s, c),
          SliverToBoxAdapter(child: SizedBox(height: navBarSpace(context))),
        ]),
      ),
    );
  }

  Widget _header(DateTime month, AppState s) => Row(children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: MonthNav(month: month, onChanged: s.setMovementsMonth),
          ),
        ),
        RoundIconButton(
          icon: Icons.search,
          tooltip: 'Cerca',
          onPressed: () {
            setState(() => _searching = true);
            WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
          },
        ),
      ]);

  Widget _searchBar(ScontriniColors c) => Row(children: [
        Expanded(
          child: SizedBox(
            height: Sizes.touch,
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              style: AppText.body.copyWith(color: c.onSurface, height: 1.2),
              decoration: InputDecoration(
                hintText: 'Cerca esercente o prodotto',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: Gap.md),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.pill), borderSide: BorderSide(color: c.outline)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.pill), borderSide: BorderSide(color: c.outline)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.pill), borderSide: BorderSide(color: c.primary, width: 1.5)),
              ),
            ),
          ),
        ),
        const SizedBox(width: Gap.xs),
        RoundIconButton(icon: Icons.close, tooltip: 'Chiudi ricerca', onPressed: _closeSearch),
      ]);

  List<Widget> _content(AppState s, ScontriniColors c) {
    Widget boxed(Widget w) => SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.gutter),
          sliver: SliverToBoxAdapter(child: ContentWidth(child: w)),
        );
    if (_error != null && _list == null) {
      return [
        boxed(Container(
          padding: const EdgeInsets.all(Gap.lg),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.md)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_error!, style: AppText.body.copyWith(color: c.onSurfaceMuted), textAlign: TextAlign.center),
            const SizedBox(height: Gap.md),
            OutlinedButton(onPressed: _load, child: const Text('Riprova')),
          ]),
        )),
      ];
    }
    final list = _list;
    final pending = s.scan.running && isCurrentMonth(s.movementsMonth);
    if (list == null) {
      return [
        boxed(Column(children: [for (var i = 0; i < 3; i++) const _SkeletonGroup()])),
      ];
    }
    final filtered = s.movementsCategory != null || s.movementsQuery.isNotEmpty;
    if (list.isEmpty && !pending) {
      return [
        boxed(Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.xxl, horizontal: Gap.md),
          child: Text(
            filtered
                ? 'Nessuno scontrino corrisponde alla ricerca a ${monthName(s.movementsMonth)}.'
                : 'Nessuno scontrino a ${monthName(s.movementsMonth)}. Fotografane uno per iniziare.',
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: c.onSurfaceMuted),
          ),
        )),
      ];
    }

    // Raggruppa per giorno (l'elenco arriva già dal più recente).
    final groups = <DateTime, List<Receipt>>{};
    for (final r in list) {
      final d = r.purchasedAt ?? DateTime(1970);
      groups.putIfAbsent(DateTime(d.year, d.month, d.day), () => []).add(r);
    }
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    if (pending) groups.putIfAbsent(todayKey, () => []);
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return [
      boxed(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final day in days) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Semantics(
              header: true,
              child: Text(dayHeader(day), style: AppText.label.copyWith(color: c.onSurfaceMuted)),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.md)),
            child: Column(children: [
              if (pending && day == todayKey) PendingScanTile(onTap: () => startScanFlow(context)),
              for (final r in groups[day]!)
                ReceiptTile(receipt: r, category: s.category(r.dominantCategoryId), onTap: () => _openReceipt(r)),
            ]),
          ),
          const SizedBox(height: 10),
        ],
      ])),
    ];
  }
}

class _ActiveFilter extends StatelessWidget {
  final Category category;
  final VoidCallback onClear;
  const _ActiveFilter({required this.category, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Filtro: ${category.name}. Rimuovi filtro',
      excludeSemantics: true,
      child: Material(
        color: c.cta,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onClear,
          child: Container(
            height: Sizes.chip,
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              CategoryDot(color: category.colorValue),
              const SizedBox(width: 6),
              Text(category.name, style: AppText.label.copyWith(color: c.onCta)),
              const SizedBox(width: 4),
              Icon(Icons.close, size: 16, color: c.onCta),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SkeletonGroup extends StatelessWidget {
  const _SkeletonGroup();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget bar(double w, double h) =>
        Container(width: w, height: h, decoration: BoxDecoration(color: c.surfaceHigh, borderRadius: BorderRadius.circular(h / 2)));
    return Semantics(
      label: 'Caricamento',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: bar(110, 10)),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.md)),
            child: Column(children: [
              for (var i = 0; i < 2; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    Container(
                      width: Sizes.avatar,
                      height: Sizes.avatar,
                      decoration: BoxDecoration(color: c.surfaceHigh, borderRadius: BorderRadius.circular(Radii.chip)),
                    ),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        bar(120, 12),
                        const SizedBox(height: 8),
                        bar(80, 10),
                      ]),
                    ),
                    bar(56, 12),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
