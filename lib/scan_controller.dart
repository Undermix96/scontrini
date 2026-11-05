import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'app_state.dart';
import 'models.dart';

enum ScanStatus { running, done, error }

/// Una lettura di scontrino. La foto vive solo in memoria ([bytes]).
class ScanJob {
  final Uint8List bytes;
  final String mime;
  final DateTime startedAt = DateTime.now();
  ScanStatus status = ScanStatus.running;
  Receipt? result;
  String? error;

  ScanJob(this.bytes, this.mime);
}

/// Gestisce l'analisi in corso, anche quando l'utente lascia la schermata
/// "Analisi in corso" (la lettura prosegue in sottofondo).
class ScanController extends ChangeNotifier {
  final AppState app;
  ScanController(this.app);

  ScanJob? job;

  /// Vero se la schermata di analisi è aperta e gestirà lei il risultato.
  bool screenAttached = false;

  bool get running => job?.status == ScanStatus.running;

  void _changed() {
    notifyListeners();
    app.scanChanged();
  }

  /// Sceglie la foto e la legge in memoria, cancellando subito il file
  /// temporaneo creato dal selettore. Restituisce null se l'utente annulla.
  static Future<(Uint8List, String)?> pick(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
    if (picked == null) return null;
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

  static String mimeFor(String fileName) {
    final name = fileName.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.heic') || name.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  /// Avvia una nuova lettura. Se ce n'è già una in corso non fa nulla.
  void start(Uint8List bytes, String mime) {
    if (running) return;
    final j = ScanJob(bytes, mime);
    job = j;
    _changed();
    _run(j);
  }

  /// Riprova l'ultima lettura fallita con la stessa foto.
  void retry() {
    final j = job;
    if (j == null || j.status != ScanStatus.error) return;
    job = null;
    start(j.bytes, j.mime);
  }

  Future<void> _run(ScanJob j) async {
    try {
      if (app.categories.isEmpty) await app.reloadCategories();
      final r = await app.api.scan(j.bytes, j.mime);
      if (!identical(job, j)) {
        // Annullata mentre il server lavorava: lo scontrino è stato salvato
        // comunque, quindi lo eliminiamo.
        try {
          await app.api.deleteReceipt(r.id);
        } catch (_) {}
        return;
      }
      j.status = ScanStatus.done;
      j.result = r;
      app.dataChanged();
    } catch (e) {
      if (!identical(job, j)) return;
      j.status = ScanStatus.error;
      j.error = '$e';
    }
    _changed();
  }

  /// Annulla: la richiesta prosegue sul server, ma il risultato verrà eliminato.
  void cancel() {
    job = null;
    _changed();
  }

  /// Il risultato (o l'errore) è stato mostrato all'utente.
  void clear() {
    if (job?.status != ScanStatus.running) {
      job = null;
      _changed();
    }
  }
}
