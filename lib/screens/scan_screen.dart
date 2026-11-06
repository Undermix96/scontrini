import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ai/ai_client.dart';
import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../scan_controller.dart';
import '../theme/tokens.dart';
import '../widgets/budget_widgets.dart';
import '../widgets/common.dart';
import 'crop_screen.dart';
import 'manual_entry_screen.dart';
import 'receipt_screen.dart';

/// Avvia il flusso: chiede la sorgente (se non indicata), sceglie e
/// ritaglia le foto, mette in coda le letture e apre la schermata "Analisi in
/// corso". Dal pannello si può anche inserire la spesa a mano.
///
/// - Fotocamera: dopo ogni scatto "Altra parte" aggiunge un pezzo dello stesso
///   scontrino lungo; finito uno scontrino si può scattare il prossimo.
/// - Galleria: con più foto si sceglie se sono scontrini diversi o parti dello
///   stesso scontrino.
Future<void> startScanFlow(BuildContext context, [ImageSource? source]) async {
  final state = AppScope.read(context);
  final navigator = Navigator.of(context);
  if (source == null) {
    final choice = await chooseNewReceipt(context);
    if (choice == null || !context.mounted) return;
    if (choice == NewReceipt.manual) {
      await navigator.push(MaterialPageRoute(builder: (_) => const ManualEntryScreen()));
      return;
    }
    source = choice == NewReceipt.camera ? ImageSource.camera : ImageSource.gallery;
  }
  // Le letture partono mentre si scattano le foto successive: i risultati li
  // mostrerà la schermata di analisi, non la shell.
  state.scan.screenAttached = true;
  var queued = 0;
  try {
    queued = source == ImageSource.camera ? await _fromCamera(context, state) : await _fromGallery(context, state);
  } finally {
    if (queued == 0 || !context.mounted) state.scan.detach();
  }
  if (queued == 0 || !context.mounted) return;
  await openScanScreen(context);
}

/// Apre la schermata "Analisi in corso" sulla coda attuale.
Future<void> openScanScreen(BuildContext context) {
  AppScope.read(context).scan.screenAttached = true;
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScanScreen()));
}

/// Ritaglia [first] e, finché l'utente chiede "Altra parte", sceglie e
/// ritaglia le parti successive da [source]. Null se annulla.
Future<List<ScanPart>?> _receiptParts(BuildContext context, AppState state, ScanPart first, ImageSource source) async {
  final parts = <ScanPart>[];
  ScanPart? next = first;
  while (next != null) {
    if (!context.mounted) return null;
    final n = parts.length + 1;
    final cropped = await cropPhoto(
      context,
      next.$1,
      next.$2,
      actionLabel: 'Analizza',
      moreLabel: n < maxScanParts ? 'Altra parte' : null,
      title: n == 1 ? 'Ritaglia lo scontrino' : 'Parte $n dello scontrino',
    );
    if (cropped == null) return null;
    parts.add((cropped.bytes, cropped.mime));
    if (!cropped.addAnother) return parts;
    next = await state.lock.suspendWhile<ScanPart?>(() => ScanController.pick(source));
  }
  // Annullata la scelta della parte successiva: si legge quello che c'è.
  return parts;
}

Future<int> _fromCamera(BuildContext context, AppState state) async {
  var queued = 0;
  while (context.mounted) {
    final first = await state.lock.suspendWhile(() => ScanController.pick(ImageSource.camera));
    if (first == null || !context.mounted) break;
    final parts = await _receiptParts(context, state, first, ImageSource.camera);
    if (parts == null) break;
    state.scan.enqueue(parts);
    queued++;
    if (!context.mounted || await askAnother(context, queued) != true) break;
  }
  return queued;
}

Future<int> _fromGallery(BuildContext context, AppState state) async {
  final picked = await state.lock.suspendWhile(ScanController.pickMany);
  if (picked.isEmpty || !context.mounted) return 0;
  if (picked.length == 1) {
    final parts = await _receiptParts(context, state, picked.single, ImageSource.gallery);
    if (parts == null) return 0;
    state.scan.enqueue(parts);
    return 1;
  }
  final same = await askSameReceipt(context, picked.length);
  if (same == null || !context.mounted) return 0;
  if (same) {
    if (picked.length > maxScanParts) {
      showSnack(context, 'Al massimo $maxScanParts parti per scontrino.');
      return 0;
    }
    final parts = <ScanPart>[];
    for (var i = 0; i < picked.length; i++) {
      if (!context.mounted) return 0;
      final c = await cropPhoto(context, picked[i].$1, picked[i].$2,
          actionLabel: i == picked.length - 1 ? 'Analizza' : 'Avanti',
          title: 'Parte ${i + 1} di ${picked.length}');
      if (c == null) return 0;
      parts.add((c.bytes, c.mime));
    }
    state.scan.enqueue(parts);
    return 1;
  }
  // Scontrini diversi: ognuno entra in coda appena ritagliato.
  var queued = 0;
  for (var i = 0; i < picked.length; i++) {
    if (!context.mounted) break;
    final c = await cropPhoto(context, picked[i].$1, picked[i].$2,
        actionLabel: i == picked.length - 1 ? 'Analizza' : 'Analizza e avanti',
        title: 'Scontrino ${i + 1} di ${picked.length}');
    if (c == null) break;
    state.scan.enqueue([(c.bytes, c.mime)]);
    queued++;
  }
  return queued;
}

/// "Scatta il prossimo" / "Fine" dopo aver messo in coda uno scontrino.
Future<bool?> askAnother(BuildContext context, int queued) => showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(queued == 1 ? 'Scontrino in lettura' : '$queued scontrini in lettura'),
        content: const Text('Vuoi fotografare un altro scontrino? La lettura prosegue intanto.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Fine')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Scatta il prossimo')),
        ],
      ),
    );

/// Più foto dalla galleria: true se sono parti dello stesso scontrino.
Future<bool?> askSameReceipt(BuildContext context, int count) => showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hai scelto $count foto'),
        content: const Text('Sono scontrini diversi o parti dello stesso scontrino lungo, '
            "nell'ordine dall'alto in basso?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stesso scontrino')),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Scontrini diversi')),
        ],
      ),
    );

enum NewReceipt { camera, gallery, manual }

/// Pannello "Scatta foto" / "Scegli dalla galleria" / "Inserisci a mano".
Future<NewReceipt?> chooseNewReceipt(BuildContext context) => showModalBottomSheet<NewReceipt>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final c = ctx.colors;
        Widget tile(IconData icon, String label, NewReceipt s) => ListTile(
              minTileHeight: 56,
              contentPadding: const EdgeInsets.symmetric(horizontal: Gap.gutter),
              leading: Container(
                width: Sizes.avatar,
                height: Sizes.avatar,
                decoration: BoxDecoration(color: c.surfaceHigh, borderRadius: BorderRadius.circular(Radii.chip)),
                child: Icon(icon, color: c.onSurface),
              ),
              title: Text(label, style: AppText.titleSmall.copyWith(color: c.onSurface)),
              onTap: () => Navigator.pop(ctx, s),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              tile(Icons.photo_camera_outlined, 'Scatta foto', NewReceipt.camera),
              tile(Icons.image_outlined, 'Scegli dalla galleria', NewReceipt.gallery),
              tile(Icons.edit_note, 'Inserisci a mano', NewReceipt.manual),
            ]),
          ),
        );
      },
    );

Future<bool?> askDuplicate(BuildContext context) => showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Possibile doppione'),
        content: const Text('Esiste già uno scontrino con lo stesso totale, data e ora. Vuoi tenerlo comunque?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: ctx.colors.error),
            child: const Text('Elimina il nuovo'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tienilo')),
        ],
      ),
    );

/// Schermata "Analisi in corso".
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with SingleTickerProviderStateMixin {
  static const _steps = ['Esercente e data', 'Totale', 'Righe e importi', 'Categorie'];

  late final ScanController _scan = AppScope.read(context).scan;
  late final AnimationController _line =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  Timer? _timer;
  int _step = 0;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _scan.screenAttached = true;
    _scan.addListener(_onScan);
    final started = _scan.job?.startedAt ?? DateTime.now();
    _step = (DateTime.now().difference(started).inMilliseconds ~/ 2000).clamp(0, _steps.length - 1);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_step < _steps.length - 1 && _scan.running) setState(() => _step++);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScan());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _line.stop();
      _line.value = 0.5;
    } else if (!_line.isAnimating) {
      _line.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _scan.removeListener(_onScan);
    _scan.screenAttached = false;
    _timer?.cancel();
    _line.dispose();
    super.dispose();
  }

  int? _shownJob;

  void _onScan() {
    if (!mounted) return;
    final job = _scan.job;
    // Nuova lettura in testa alla coda: si riparte con i passaggi.
    if (job != null && job.id != _shownJob) {
      _shownJob = job.id;
      _handled = false;
      _step = job.status == ScanStatus.running
          ? (DateTime.now().difference(job.startedAt).inMilliseconds ~/ 2000).clamp(0, _steps.length - 1)
          : 0;
    }
    setState(() {});
    if (job == null) {
      if (!_handled) Navigator.maybePop(context);
      _handled = true;
      return;
    }
    if (job.status == ScanStatus.done && !_handled) {
      _handled = true;
      final r = job.result!;
      if (_scan.jobs.length > 1) {
        _next(job, r);
      } else {
        _timer?.cancel();
        _finish(r);
      }
    }
  }

  /// Con altre letture in coda: avviso breve e si passa alla successiva. I
  /// possibili doppioni restano segnalati sullo scontrino.
  Future<void> _next(ScanJob job, Receipt r) async {
    final state = AppScope.read(context);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final alert = await budgetAlertText(state, r);
    if (!mounted) return;
    showSnack(context, 'Scontrino letto: ${r.displayMerchant}${alert == null ? '' : '. $alert'}',
        actionLabel: 'Apri', onAction: () {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReceiptScreen(receiptId: r.id)));
    });
    _scan.clear(job);
  }

  Future<void> _finish(Receipt r) async {
    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    // Un attimo per far vedere i passaggi completati.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    if (r.possibleDuplicateOf != null) {
      final keep = await askDuplicate(context);
      if (!mounted) return;
      if (keep == false) {
        _scan.clear();
        try {
          await state.repo.deleteReceipt(r.id);
          state.dataChanged();
          if (mounted) showSnack(context, 'Doppione eliminato.');
        } catch (e) {
          if (mounted) showSnack(context, 'Eliminazione non riuscita: $e');
        }
        navigator.pop();
        return;
      }
    }
    _scan.clear();
    final alert = await budgetAlertText(state, r);
    if (alert != null && mounted) showSnack(context, '$alert.');
    navigator.pushReplacement(MaterialPageRoute(builder: (_) => ReceiptScreen(receiptId: r.id, initial: r)));
  }

  void _cancel() {
    _scan.cancel();
    if (_scan.jobs.isEmpty) {
      _handled = true;
      Navigator.pop(context);
    }
  }

  void _retry() {
    _handled = false;
    _scan.retry();
    setState(() => _step = 0);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_step < _steps.length - 1 && _scan.running) setState(() => _step++);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final job = _scan.job;
    final failed = job?.status == ScanStatus.error;
    final done = job?.status == ScanStatus.done;
    final r = job?.result;
    final others = _scan.jobs.length - 1;
    final parts = job?.parts.length ?? 1;

    String? meta(int i) {
      if (r == null) return null;
      switch (i) {
        case 0:
          return r.merchant?.trim().isNotEmpty == true ? r.merchant!.trim() : null;
        case 1:
          return money(r.total, r.currency);
        case 2:
          return r.items.length == 1 ? '1 riga' : '${r.items.length} righe';
        default:
          final n = r.items.map((i) => i.categoryId).whereType<int>().toSet().length;
          return n == 1 ? '1 categoria' : '$n categorie';
      }
    }

    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.gutter, Gap.xs, Gap.gutter, Gap.xxl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                RoundIconButton(icon: Icons.chevron_left, tooltip: 'Indietro', onPressed: () => Navigator.maybePop(context)),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('Lettura dello scontrino', style: AppText.title.copyWith(color: c.onSurface)),
                  ),
                ),
              ]),
              const SizedBox(height: Gap.lg),
              Expanded(
                child: ListView(padding: EdgeInsets.zero, children: [
                  _Preview(job: job, line: _line),
                  const SizedBox(height: Gap.lg),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      failed ? 'Non sono riuscito a leggerlo' : (done ? 'Fatto!' : 'Sto leggendo le righe…'),
                      style: AppText.headline.copyWith(fontSize: 24, letterSpacing: -0.4, color: c.onSurface),
                    ),
                  ),
                  const SizedBox(height: Gap.xxs),
                  Text(
                    failed
                        ? (job?.error ?? 'Errore sconosciuto')
                        : [
                            if (parts > 1) 'Scontrino in $parts parti.',
                            'Di solito bastano una decina di secondi.',
                          ].join(' '),
                    style: AppText.body.copyWith(fontSize: 14, height: 1.4, color: c.onSurfaceMuted),
                  ),
                  if (others > 0) ...[
                    const SizedBox(height: Gap.xs),
                    Text(others == 1 ? 'Poi 1 altro scontrino in coda.' : 'Poi altri $others scontrini in coda.',
                        style: AppText.label.copyWith(color: c.primary)),
                  ],
                  const SizedBox(height: Gap.lg),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 4),
                    decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.md)),
                    child: Column(children: [
                      for (var i = 0; i < _steps.length; i++)
                        _StepRow(
                          label: _steps[i],
                          meta: meta(i),
                          state: done
                              ? _StepState.done
                              : i < _step
                                  ? _StepState.done
                                  : i == _step
                                      ? (failed ? _StepState.failed : _StepState.active)
                                      : _StepState.todo,
                        ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: Gap.md),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.verified_user_outlined, size: 16, color: c.onSurfaceMuted),
                const SizedBox(width: Gap.xs),
                Flexible(
                  child: Text(
                      AppScope.of(context).config.keepPhotos
                          ? 'La foto resta solo su questo telefono.'
                          : 'Finita la lettura, la foto viene eliminata.',
                      style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted)),
                ),
              ]),
              const SizedBox(height: Gap.sm),
              if (failed) ...[
                FilledButton(onPressed: _retry, child: const Text('Riprova')),
                const SizedBox(height: Gap.sm),
              ],
              OutlinedButton(onPressed: done ? null : _cancel, child: const Text('Annulla')),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final ScanJob? job;
  final Animation<double> line;
  const _Preview({required this.job, required this.line});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scanning = job?.status == ScanStatus.running || job?.status == ScanStatus.waiting;
    return Semantics(
      label: 'Anteprima della foto',
      image: true,
      child: Container(
        // 340 come nelle tavole, meno sui telefoni bassi perché i passaggi restino visibili.
        height: (MediaQuery.sizeOf(context).height * 0.4).clamp(180.0, 340.0),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.lg)),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (job != null) Image.memory(job!.bytes, fit: BoxFit.cover, gaplessPlayback: true),
          if (job != null && job!.parts.length > 1)
            Positioned(
              right: Gap.sm,
              top: Gap.sm,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.pill)),
                child: Text('${job!.parts.length} parti', style: AppText.label.copyWith(color: c.onSurface)),
              ),
            ),
          if (scanning)
            AnimatedBuilder(
              animation: line,
              builder: (context, _) => LayoutBuilder(builder: (context, box) {
                final y = 24 + (box.maxHeight - 51) * Curves.easeInOut.transform(line.value);
                return Stack(children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: y - 68,
                    height: 68,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [c.primary.withValues(alpha: 0), c.primary.withValues(alpha: 0.22)],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: y,
                    height: 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ]);
              }),
            ),
        ]),
      ),
    );
  }
}

enum _StepState { done, active, todo, failed }

class _StepRow extends StatelessWidget {
  final String label;
  final String? meta;
  final _StepState state;
  const _StepRow({required this.label, required this.meta, required this.state});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Widget icon;
    switch (state) {
      case _StepState.done:
        icon = Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(color: c.success, shape: BoxShape.circle),
          child: Icon(Icons.check_rounded, size: 16, color: c.background),
        );
      case _StepState.failed:
        icon = Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(color: c.error, shape: BoxShape.circle),
          child: Icon(Icons.close_rounded, size: 16, color: c.background),
        );
      case _StepState.active:
        icon = SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 3, color: c.primary, backgroundColor: c.surfaceHigh),
        );
      case _StepState.todo:
        icon = SizedBox.square(dimension: 22, child: CustomPaint(painter: _DashedRing(c.outlineStrong)));
    }
    final todo = state == _StepState.todo;
    final stateLabel = switch (state) {
      _StepState.done => 'fatto',
      _StepState.active => 'in corso',
      _StepState.todo => 'da fare',
      _StepState.failed => 'non riuscito',
    };
    return Semantics(
      label: '$label, $stateLabel${meta == null ? '' : ', $meta'}',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(children: [
          SizedBox(width: 26, child: Center(child: icon)),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(label,
                style: AppText.titleSmall.copyWith(
                    fontWeight: todo ? FontWeight.w500 : FontWeight.w700,
                    color: todo ? c.onSurfaceMuted : c.onSurface)),
          ),
          if (meta != null)
            Flexible(
              child: Text(meta!,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted)),
            ),
        ]),
      ),
    );
  }
}

class _DashedRing extends CustomPainter {
  final Color color;
  _DashedRing(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = Offset.zero & size;
    const n = 12;
    const sweep = 2 * 3.141592653589793 / n;
    for (var i = 0; i < n; i++) {
      canvas.drawArc(rect.deflate(1), i * sweep, sweep * 0.55, false, p);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRing old) => old.color != color;
}
