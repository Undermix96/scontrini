import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'ai/ai_client.dart';
import 'app_state.dart';
import 'models.dart';

enum ScanStatus { waiting, running, done, error }

/// Una foto (o una parte di uno scontrino lungo).
typedef ScanPart = (Uint8List bytes, String mime);

/// Una lettura di scontrino, con una o più parti (dall'alto in basso). Le
/// foto vivono solo in memoria, salvo l'opzione "Conserva le foto".
class ScanJob {
  static int _next = 0;
  final int id = _next++;
  final List<ScanPart> parts;
  DateTime startedAt = DateTime.now();
  ScanStatus status = ScanStatus.waiting;
  Receipt? result;
  String? error;

  ScanJob(this.parts);

  Uint8List get bytes => parts.first.$1;
  String get mime => parts.first.$2;
  bool get finished => status == ScanStatus.done || status == ScanStatus.error;
}

/// Coda delle letture: una alla volta, in ordine, anche quando l'utente
/// lascia la schermata "Analisi in corso" (la lettura prosegue in sottofondo).
class ScanController extends ChangeNotifier {
  final AppState app;
  ScanController(this.app);

  /// Letture in coda, in corso o finite ma non ancora mostrate.
  final List<ScanJob> jobs = [];

  /// La lettura mostrata dalla schermata di analisi: la prima della coda.
  ScanJob? get job => jobs.isEmpty ? null : jobs.first;

  /// Vero se la schermata di analisi è aperta (o sta per aprirsi, mentre si
  /// scattano e ritagliano le foto) e gestirà lei i risultati.
  bool screenAttached = false;

  /// Nessuna schermata gestirà i risultati: se ne occupa la shell.
  void detach() {
    screenAttached = false;
    _changed();
  }

  /// Qualche lettura in attesa o in corso.
  bool get running => jobs.any((j) => !j.finished);

  /// Letture ancora da fare (in attesa o in corso).
  int get pending => jobs.where((j) => !j.finished).length;

  void _changed() {
    notifyListeners();
    app.scanChanged();
  }

  /// Sceglie la foto e la legge in memoria, cancellando subito il file
  /// temporaneo creato dal selettore. Restituisce null se l'utente annulla.
  static Future<ScanPart?> pick(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
    if (picked == null) return null;
    return _read(picked);
  }

  /// Più foto dalla galleria (nell'ordine scelto). Lista vuota se annulla.
  static Future<List<ScanPart>> pickMany() async {
    final picked = await ImagePicker().pickMultiImage(maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
    return [for (final p in picked) await _read(p)];
  }

  static Future<ScanPart> _read(XFile picked) async {
    final bytes = await picked.readAsBytes();
    if (!kIsWeb) {
      try {
        await File(picked.path).delete();
      } catch (_) {
        // Il file potrebbe non essere nostro (es. galleria su alcune versioni): va bene così.
      }
    }
    return (bytes, mimeFor(picked.name));
  }

  /// Foto scattata mentre Android ha chiuso l'app per mancanza di memoria
  /// (la fotocamera è un'altra app): al riavvio la si recupera.
  static Future<ScanPart?> recoverLost() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final lost = await ImagePicker().retrieveLostData();
      final f = lost.file;
      if (lost.isEmpty || f == null) return null;
      return await _read(f);
    } catch (_) {
      return null;
    }
  }

  static String mimeFor(String fileName) {
    final name = fileName.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.heic') || name.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  /// Mette in coda la lettura di uno scontrino con una sola foto.
  void start(Uint8List bytes, String mime) => enqueue([(bytes, mime)]);

  /// Mette in coda la lettura di uno scontrino (una o più parti).
  ScanJob enqueue(List<ScanPart> parts) {
    assert(parts.isNotEmpty && parts.length <= maxScanParts);
    final j = ScanJob(List.unmodifiable(parts));
    jobs.add(j);
    _changed();
    _pump();
    return j;
  }

  /// Avvia la prossima lettura in attesa, se nessuna è in corso.
  void _pump() {
    if (jobs.any((j) => j.status == ScanStatus.running)) return;
    for (final j in jobs) {
      if (j.status == ScanStatus.waiting) {
        j.status = ScanStatus.running;
        j.startedAt = DateTime.now();
        _changed();
        _run(j);
        return;
      }
    }
  }

  /// Riprova la lettura fallita [j] (di default la prima della coda).
  void retry([ScanJob? j]) {
    j ??= job;
    if (j == null || j.status != ScanStatus.error) return;
    j.status = ScanStatus.waiting;
    j.error = null;
    _changed();
    _pump();
  }

  Future<void> _run(ScanJob j) async {
    try {
      if (app.categories.isEmpty) await app.reloadCategories();
      final names = app.categories.map((c) => c.name).toList();
      final res = await app.ai.scanParts(app.config.endpoint, j.parts, names);
      // Annullata mentre l'AI lavorava: il risultato non viene salvato.
      if (!jobs.contains(j)) return;
      final r = await app.repo.saveScan(res.parsed, model: res.model);
      if (!jobs.contains(j)) {
        await app.repo.deleteReceipt(r.id);
        return;
      }
      if (app.config.keepPhotos) {
        try {
          for (final (bytes, mime) in j.parts) {
            await app.repo.addPhoto(r.id, bytes, mime: mime);
          }
        } catch (e) {
          // Lo scontrino è salvato comunque: le foto si possono aggiungere dopo.
          debugPrint('Foto non salvata: $e');
        }
      }
      j.status = ScanStatus.done;
      j.result = r;
      app.dataChanged();
    } catch (e) {
      if (!jobs.contains(j)) return;
      j.status = ScanStatus.error;
      j.error = '$e';
    } finally {
      _changed();
      _pump();
    }
  }

  /// Annulla [j] (di default la prima della coda): se è in corso la
  /// richiesta all'AI prosegue, ma il risultato verrà scartato.
  void cancel([ScanJob? j]) {
    j ??= job;
    if (j == null) return;
    jobs.remove(j);
    _changed();
    _pump();
  }

  /// Il risultato (o l'errore) di [j] è stato mostrato all'utente.
  void clear([ScanJob? j]) {
    j ??= job;
    if (j == null || !j.finished) return;
    jobs.remove(j);
    _changed();
  }
}
