import 'package:flutter/material.dart';

import '../app_state.dart';
import '../export/exporter.dart';
import '../format.dart';
import '../theme/tokens.dart';
import '../version.dart';
import '../widgets/category_widgets.dart';
import '../widgets/common.dart';
import '../widgets/month_selector.dart';

enum _PeriodKind { month, year, range, all }

/// Esporta gli scontrini di un periodo in CSV, JSON o PDF, salvando il file
/// dove sceglie l'utente.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  _PeriodKind _kind = _PeriodKind.month;
  DateTime _month = monthStart(DateTime.now());
  int _year = DateTime.now().year;
  DateTimeRange? _range;
  ExportFormat _format = ExportFormat.itemsCsv;
  bool _busy = false;
  int? _count;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateCount());
  }

  ExportPeriod? get _period => switch (_kind) {
        _PeriodKind.month => ExportPeriod.month(_month),
        _PeriodKind.year => ExportPeriod.year(_year),
        _PeriodKind.range => _range == null ? null : ExportPeriod.range(_range!.start, _range!.end),
        _PeriodKind.all => ExportPeriod.all,
      };

  Future<void> _updateCount() async {
    final p = _period;
    final id = ++_request;
    setState(() => _count = null);
    if (p == null) return;
    final list = await AppScope.read(context).repo.receipts(from: p.from, to: p.to);
    if (mounted && id == _request) setState(() => _count = list.length);
  }

  void _setKind(_PeriodKind k) {
    setState(() => _kind = k);
    if (k == _PeriodKind.range && _range == null) {
      _pickRange();
    } else {
      _updateCount();
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: _range ?? DateTimeRange(start: DateTime(now.year, now.month), end: now),
    );
    if (r != null) setState(() => _range = r);
    _updateCount();
  }

  Future<void> _export() async {
    final p = _period;
    if (p == null) return;
    final s = AppScope.read(context);
    setState(() => _busy = true);
    try {
      final f = await buildExport(s.repo, _format, p, appVersion: versionLabel());
      final saved = await s.files.save(f.fileName, f.bytes, f.mimeType);
      if (saved && mounted) showSnack(context, 'File salvato: ${f.fileName}');
    } catch (e) {
      if (mounted) showSnack(context, 'Esportazione non riuscita: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget section(String t) => Padding(
          padding: const EdgeInsets.only(top: Gap.lg, bottom: Gap.sm),
          child: Semantics(header: true, child: Text(t, style: AppText.titleSmall.copyWith(color: c.onSurface))),
        );
    final thisYear = DateTime.now().year;
    final count = _count;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.gutter, Gap.xs, Gap.gutter, Gap.xxl),
          children: [
            ContentWidth(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  RoundIconButton(icon: Icons.arrow_back, tooltip: 'Indietro', onPressed: () => Navigator.pop(context)),
                  const SizedBox(width: Gap.sm),
                  Semantics(
                      header: true, child: Text('Esporta', style: AppText.headline.copyWith(color: c.onSurface))),
                ]),
                section('Periodo'),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final (k, label) in [
                    (_PeriodKind.month, 'Mese'),
                    (_PeriodKind.year, 'Anno'),
                    (_PeriodKind.range, 'Intervallo'),
                    (_PeriodKind.all, 'Tutto'),
                  ])
                    CategoryChip(name: label, selected: _kind == k, onTap: () => _setKind(k)),
                ]),
                const SizedBox(height: Gap.md),
                if (_kind == _PeriodKind.month)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CompactMonthSelector(
                      month: _month,
                      onChanged: (m) {
                        setState(() => _month = m);
                        _updateCount();
                      },
                    ),
                  ),
                if (_kind == _PeriodKind.year)
                  Row(children: [
                    RoundIconButton(
                      icon: Icons.chevron_left,
                      tooltip: 'Anno precedente',
                      onPressed: () {
                        setState(() => _year--);
                        _updateCount();
                      },
                    ),
                    const SizedBox(width: Gap.sm),
                    Text('$_year', style: AppText.title.copyWith(color: c.onSurface)),
                    const SizedBox(width: Gap.sm),
                    RoundIconButton(
                      icon: Icons.chevron_right,
                      tooltip: 'Anno successivo',
                      onPressed: _year >= thisYear
                          ? null
                          : () {
                              setState(() => _year++);
                              _updateCount();
                            },
                    ),
                  ]),
                if (_kind == _PeriodKind.range)
                  OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range),
                    label: Text(_range == null
                        ? 'Scegli le date'
                        : '${longDate(_range!.start)} – ${longDate(_range!.end)}'),
                  ),
                const SizedBox(height: Gap.xs),
                Text(
                  _period == null
                      ? 'Scegli un intervallo di date.'
                      : count == null
                          ? ' '
                          : count == 0
                              ? 'Nessuno scontrino nel periodo.'
                              : count == 1
                                  ? '1 scontrino nel periodo.'
                                  : '$count scontrini nel periodo.',
                  style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted),
                ),
                section('Formato'),
                Material(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(Radii.md),
                  clipBehavior: Clip.antiAlias,
                  child: RadioGroup<ExportFormat>(
                    groupValue: _format,
                    onChanged: (f) => setState(() => _format = f ?? _format),
                    child: Column(children: [
                      for (final f in ExportFormat.values)
                        RadioListTile<ExportFormat>(
                          value: f,
                          title: Text(f.label, style: AppText.titleSmall.copyWith(color: c.onSurface)),
                          subtitle: Text(f.description, style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted)),
                        ),
                    ]),
                  ),
                ),
                if (_format == ExportFormat.itemsCsv || _format == ExportFormat.receiptsCsv) ...[
                  const SizedBox(height: Gap.xs),
                  Text('Separatore punto e virgola e virgola decimale, come Excel in italiano.',
                      style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted)),
                ],
                const SizedBox(height: Gap.lg),
                FilledButton(
                  onPressed: _busy || _period == null ? null : _export,
                  child: _busy ? const SmallSpinner() : const Text('Esporta e salva'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
