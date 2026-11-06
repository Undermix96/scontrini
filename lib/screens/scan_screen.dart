import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../scan_controller.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'receipt_screen.dart';

/// Avvia il flusso di lettura: se c'è già un'analisi in corso la riapre,
/// altrimenti chiede la sorgente (se non indicata), sceglie la foto e apre
/// la schermata "Analisi in corso".
Future<void> startScanFlow(BuildContext context, [ImageSource? source]) async {
  final state = AppScope.read(context);
  final navigator = Navigator.of(context);
  if (state.scan.running) {
    await navigator.push(MaterialPageRoute(builder: (_) => const ScanScreen()));
    return;
  }
  source ??= await chooseImageSource(context);
  if (source == null) return;
  final picked = await state.lock.suspendWhile(() => ScanController.pick(source!));
  if (picked == null) return;
  state.scan.start(picked.$1, picked.$2);
  await navigator.push(MaterialPageRoute(builder: (_) => const ScanScreen()));
}

/// Pannello "Scatta foto" / "Scegli dalla galleria".
Future<ImageSource?> chooseImageSource(BuildContext context) => showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final c = ctx.colors;
        Widget tile(IconData icon, String label, ImageSource s) => ListTile(
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
              tile(Icons.photo_camera_outlined, 'Scatta foto', ImageSource.camera),
              tile(Icons.image_outlined, 'Scegli dalla galleria', ImageSource.gallery),
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

  void _onScan() {
    if (!mounted) return;
    setState(() {});
    final job = _scan.job;
    if (job?.status == ScanStatus.done && !_handled) {
      _handled = true;
      _timer?.cancel();
      _finish(job!.result!);
    }
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
    navigator.pushReplacement(MaterialPageRoute(builder: (_) => ReceiptScreen(receiptId: r.id, initial: r)));
  }

  void _cancel() {
    _scan.cancel();
    Navigator.pop(context);
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
                    failed ? (job?.error ?? 'Errore sconosciuto') : 'Di solito bastano una decina di secondi.',
                    style: AppText.body.copyWith(fontSize: 14, height: 1.4, color: c.onSurfaceMuted),
                  ),
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
                  child: Text('Finita la lettura, la foto viene eliminata.',
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
    final scanning = job?.status == ScanStatus.running;
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
