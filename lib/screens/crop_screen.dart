import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../scan/crop.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Foto ritagliata pronta per l'AI (o da conservare).
class CropResult {
  final Uint8List bytes;
  final String mime;

  /// L'utente vuole aggiungere un'altra parte dello stesso scontrino.
  final bool addAnother;

  const CropResult(this.bytes, this.mime, {this.addAnother = false});
}

/// Apre la schermata di ritaglio. Se la foto non è leggibile dal nostro
/// decoder (es. HEIC), la restituisce così com'è senza mostrare nulla.
/// Null se l'utente annulla.
Future<CropResult?> cropPhoto(
  BuildContext context,
  Uint8List bytes,
  String mime, {
  required String actionLabel,
  String? moreLabel,
  String title = 'Ritaglia lo scontrino',
}) async {
  final preview = await makePreview(bytes);
  if (preview == null) return CropResult(bytes, mime);
  if (!context.mounted) return null;
  return Navigator.of(context).push<CropResult>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => CropScreen(
      original: bytes,
      initial: preview,
      actionLabel: actionLabel,
      moreLabel: moreLabel,
      title: title,
    ),
  ));
}

class CropScreen extends StatefulWidget {
  final Uint8List original;
  final CropPreview initial;
  final String actionLabel;
  final String? moreLabel;
  final String title;

  const CropScreen({
    super.key,
    required this.original,
    required this.initial,
    required this.actionLabel,
    this.moreLabel,
    this.title = 'Ritaglia lo scontrino',
  });

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  late CropPreview _preview = widget.initial;
  late List<Offset> _quad = List.of(widget.initial.detected);
  int _turns = 0;
  int? _dragging;
  bool _busy = false;

  Future<void> _rotate() async {
    setState(() => _busy = true);
    final turns = (_turns + 1) % 4;
    final p = await makePreview(widget.original, quarterTurns: turns);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (p == null) return;
      _turns = turns;
      _preview = p;
      _quad = List.of(p.detected);
    });
  }

  Future<void> _done({bool more = false}) async {
    setState(() => _busy = true);
    final out = await cropToJpeg(widget.original, _quad, quarterTurns: _turns);
    if (!mounted) return;
    setState(() => _busy = false);
    if (out == null) {
      showSnack(context, 'Non è stato possibile ritagliare la foto.');
      return;
    }
    Navigator.pop(context, CropResult(out, 'image/jpeg', addAnother: more));
  }

  /// Rettangolo occupato dall'immagine dentro lo spazio disponibile.
  Rect _imageRect(Size box) {
    final ar = _preview.width / _preview.height;
    var w = box.width, h = box.width / ar;
    if (h > box.height) {
      h = box.height;
      w = h * ar;
    }
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  void _start(Offset local, Rect r) {
    var best = -1;
    var bestD = 56.0;
    for (var i = 0; i < 4; i++) {
      final p = Offset(r.left + _quad[i].dx * r.width, r.top + _quad[i].dy * r.height);
      final d = (p - local).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    setState(() => _dragging = best < 0 ? null : best);
  }

  void _move(Offset local, Rect r) {
    final i = _dragging;
    if (i == null) return;
    final p = Offset(((local.dx - r.left) / r.width).clamp(0.0, 1.0), ((local.dy - r.top) / r.height).clamp(0.0, 1.0));
    setState(() => _quad[i] = p);
  }

  void _nudge(int i, Offset d) => setState(() {
        final p = _quad[i] + d;
        _quad[i] = Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0));
      });

  Widget _magnifier(Rect r, ScontriniColors c) {
    final q = _quad[_dragging!];
    final p = Offset(r.left + q.dx * r.width, r.top + q.dy * r.height);
    const size = 96.0;
    final above = p.dy - r.top > size + 40;
    final center = Offset(p.dx.clamp(size / 2, r.right + Gap.gutter - size / 2), above ? p.dy - 80 : p.dy + 80);
    return Positioned(
      left: center.dx - size / 2,
      top: center.dy - size / 2,
      child: RawMagnifier(
        size: const Size(size, size),
        magnificationScale: 2,
        focalPointOffset: p - center,
        decoration: MagnifierDecoration(shape: CircleBorder(side: BorderSide(color: c.primary, width: 3))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const names = ['alto a sinistra', 'alto a destra', 'basso a destra', 'basso a sinistra'];
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.gutter, Gap.xs, Gap.gutter, Gap.sm),
            child: Row(children: [
              RoundIconButton(icon: Icons.close, tooltip: 'Annulla', onPressed: () => Navigator.pop(context)),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(widget.title,
                      textAlign: TextAlign.center, style: AppText.title.copyWith(fontSize: 17, color: c.onSurface)),
                ),
              ),
              const SizedBox(width: Sizes.iconButton),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.gutter),
              child: LayoutBuilder(builder: (context, box) {
                final r = _imageRect(box.biggest);
                return GestureDetector(
                  onPanStart: (d) => _start(d.localPosition, r),
                  onPanUpdate: (d) => _move(d.localPosition, r),
                  onPanEnd: (_) => setState(() => _dragging = null),
                  child: Stack(children: [
                    Positioned.fromRect(
                      rect: r,
                      child: Image.memory(_preview.jpeg, fit: BoxFit.fill, gaplessPlayback: true),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _QuadPainter(
                          rect: r,
                          quad: _quad,
                          active: _dragging,
                          line: c.primary,
                          handle: Colors.white,
                          scrim: Colors.black.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    // Maniglie accessibili: azioni per spostare ogni angolo.
                    for (var i = 0; i < 4; i++)
                      Positioned(
                        left: r.left + _quad[i].dx * r.width - 22,
                        top: r.top + _quad[i].dy * r.height - 22,
                        width: 44,
                        height: 44,
                        child: Semantics(
                          label: 'Angolo ${names[i]}',
                          customSemanticsActions: {
                            const CustomSemanticsAction(label: 'Sposta in alto'): () => _nudge(i, const Offset(0, -0.02)),
                            const CustomSemanticsAction(label: 'Sposta in basso'): () => _nudge(i, const Offset(0, 0.02)),
                            const CustomSemanticsAction(label: 'Sposta a sinistra'): () =>
                                _nudge(i, const Offset(-0.02, 0)),
                            const CustomSemanticsAction(label: 'Sposta a destra'): () => _nudge(i, const Offset(0.02, 0)),
                          },
                          child: const SizedBox.expand(),
                        ),
                      ),
                    // Lente sull'angolo trascinato: mostra il bordo sotto il dito.
                    if (_dragging != null) _magnifier(r, c),
                    if (_busy) const Center(child: CircularProgressIndicator()),
                  ]),
                );
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.gutter, Gap.sm, Gap.gutter, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _Tool(icon: Icons.rotate_right, label: 'Ruota', onTap: _busy ? null : _rotate),
              _Tool(
                icon: Icons.auto_fix_high,
                label: 'Automatico',
                onTap: _busy ? null : () => setState(() => _quad = List.of(_preview.detected)),
              ),
              _Tool(
                icon: Icons.crop_free,
                label: 'Tutta',
                onTap: _busy ? null : () => setState(() => _quad = List.of(fullQuad)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.gutter, Gap.sm, Gap.gutter, Gap.md),
            child: Row(children: [
              if (widget.moreLabel != null) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _done(more: true),
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: Text(widget.moreLabel!, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _done,
                  child: Text(widget.actionLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _Tool({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = onTap == null ? c.onSurfaceMuted.withValues(alpha: 0.5) : c.onSurface;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color),
            const SizedBox(height: 2),
            Text(label, style: AppText.badge.copyWith(color: color)),
          ]),
        ),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  final Rect rect;
  final List<Offset> quad;
  final int? active;
  final Color line, handle, scrim;

  _QuadPainter({
    required this.rect,
    required this.quad,
    required this.active,
    required this.line,
    required this.handle,
    required this.scrim,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pts = [for (final p in quad) Offset(rect.left + p.dx * rect.width, rect.top + p.dy * rect.height)];
    final path = Path()..addPolygon(pts, true);
    // Fuori dal ritaglio, l'immagine si scurisce.
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(rect), path),
      Paint()..color = scrim,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    for (var i = 0; i < 4; i++) {
      final r = i == active ? 14.0 : 11.0;
      canvas.drawCircle(pts[i], r + 2.5, Paint()..color = line);
      canvas.drawCircle(pts[i], r, Paint()..color = handle);
    }
  }

  @override
  bool shouldRepaint(_QuadPainter old) => true;
}
