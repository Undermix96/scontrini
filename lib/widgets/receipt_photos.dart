import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../models.dart';
import '../scan_controller.dart';
import '../screens/crop_screen.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// Foto conservate di uno scontrino: miniature, aggiunta e visualizzatore.
/// Si vede se ci sono foto o se l'opzione "Conserva le foto" è attiva.
class ReceiptPhotos extends StatefulWidget {
  final String receiptId;
  const ReceiptPhotos({super.key, required this.receiptId});

  @override
  State<ReceiptPhotos> createState() => _ReceiptPhotosState();
}

class _ReceiptPhotosState extends State<ReceiptPhotos> {
  late final AppState _s = AppScope.read(context);
  List<ReceiptPhoto>? _photos;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _s.repo.photosOf(widget.receiptId);
      if (mounted) setState(() => _photos = p);
    } catch (_) {
      if (mounted) setState(() => _photos = const []);
    }
  }

  Future<void> _add() async {
    final c = context.colors;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (icon, label, src) in [
            (Icons.photo_camera_outlined, 'Scatta foto', ImageSource.camera),
            (Icons.image_outlined, 'Scegli dalla galleria', ImageSource.gallery),
          ])
            ListTile(
              minTileHeight: 56,
              contentPadding: const EdgeInsets.symmetric(horizontal: Gap.gutter),
              leading: Icon(icon, color: c.onSurface),
              title: Text(label, style: AppText.titleSmall.copyWith(color: c.onSurface)),
              onTap: () => Navigator.pop(ctx, src),
            ),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    final picked = await _s.lock.suspendWhile(() => ScanController.pick(source));
    if (picked == null || !mounted) return;
    final cropped =
        await cropPhoto(context, picked.$1, picked.$2, actionLabel: 'Salva la foto', title: 'Ritaglia la foto');
    if (cropped == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _s.repo.addPhoto(widget.receiptId, cropped.bytes, mime: cropped.mime);
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, 'Foto non salvata: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(int index) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => PhotoViewer(photos: _photos!, initial: index),
    ));
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final photos = _photos;
    if (photos == null || (photos.isEmpty && !_s.config.keepPhotos)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(photos.length == 1 ? '1 foto' : '${photos.length} foto',
              style: AppText.title.copyWith(fontSize: 16, color: c.onSurface)),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 112,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var i = 0; i < photos.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: Gap.xs),
                child: Semantics(
                  button: true,
                  label: 'Foto ${i + 1} di ${photos.length}. Apri',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () => _open(i),
                    borderRadius: BorderRadius.circular(Radii.sm),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      child: SizedBox(width: 84, height: 112, child: _PhotoImage(photo: photos[i], thumbnail: true)),
                    ),
                  ),
                ),
              ),
            Semantics(
              button: true,
              label: 'Aggiungi una foto',
              excludeSemantics: true,
              child: InkWell(
                onTap: _busy ? null : _add,
                borderRadius: BorderRadius.circular(Radii.sm),
                child: Container(
                  width: 84,
                  height: 112,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: c.outline),
                  ),
                  child: _busy
                      ? Center(child: SmallSpinner(color: c.onSurfaceMuted))
                      : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_a_photo_outlined, color: c.primary),
                          const SizedBox(height: 4),
                          Text('Aggiungi', style: AppText.badge.copyWith(color: c.primary)),
                        ]),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _PhotoImage extends StatelessWidget {
  final ReceiptPhoto photo;
  final bool thumbnail;
  const _PhotoImage({required this.photo, this.thumbnail = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FutureBuilder(
      future: AppScope.read(context).repo.photoBytes(photo),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) {
          return Container(
            color: c.surfaceHigh,
            alignment: Alignment.center,
            child: snap.connectionState == ConnectionState.done
                ? Icon(Icons.broken_image_outlined, color: c.onSurfaceMuted)
                : null,
          );
        }
        return Image.memory(
          bytes,
          fit: thumbnail ? BoxFit.cover : BoxFit.contain,
          cacheWidth: thumbnail ? 260 : null,
          gaplessPlayback: true,
        );
      },
    );
  }
}

/// Foto a schermo intero, con zoom e scorrimento tra le parti.
class PhotoViewer extends StatefulWidget {
  final List<ReceiptPhoto> photos;
  final int initial;
  const PhotoViewer({super.key, required this.photos, required this.initial});

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final _page = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare la foto?'),
        content: const Text('Lo scontrino e le sue righe restano.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: ctx.colors.error),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AppScope.read(context).repo.deletePhoto(widget.photos[_index].id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.photos.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(n == 1 ? 'Foto' : 'Foto ${_index + 1} di $n'),
        actions: [IconButton(tooltip: 'Elimina la foto', icon: const Icon(Icons.delete_outline), onPressed: _delete)],
      ),
      body: PageView.builder(
        controller: _page,
        itemCount: n,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 6,
          child: Center(child: _PhotoImage(photo: widget.photos[i])),
        ),
      ),
    );
  }
}
