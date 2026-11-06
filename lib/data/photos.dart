import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// File delle foto conservate (facoltative), nella cartella privata dell'app:
/// `<supporto applicazione>/photos/`. Esclusa dal backup di sistema come il
/// database (su Android con le regole del manifest, su iOS qui).
class PhotoStore {
  final Directory dir;
  PhotoStore(this.dir);

  static Future<PhotoStore> open() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/photos');
    await dir.create(recursive: true);
    if (!kIsWeb && Platform.isIOS) {
      try {
        await const MethodChannel('scontrini/storage').invokeMethod<void>('excludeFromBackup', dir.path);
      } catch (e) {
        debugPrint('Esclusione delle foto dal backup iCloud non riuscita: $e');
      }
    }
    return PhotoStore(dir);
  }

  /// Nomi accettati: niente percorsi, solo lettere, cifre, trattini e un'estensione.
  static bool validName(String name) => RegExp(r'^[A-Za-z0-9_-]{1,80}\.(jpg|png|webp|heic)$').hasMatch(name);

  File _file(String name) {
    if (!validName(name)) throw ArgumentError('Nome di foto non valido: $name');
    return File('${dir.path}/$name');
  }

  /// Scrive prima in un file temporaneo e poi lo rinomina: niente foto a metà.
  Future<void> write(String name, Uint8List bytes) async {
    final f = _file(name);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
  }

  Future<Uint8List?> read(String name) async {
    final f = _file(name);
    return await f.exists() ? f.readAsBytes() : null;
  }

  Future<void> delete(String name) async {
    try {
      final f = _file(name);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('Foto non eliminata: $e');
    }
  }

  /// Nomi dei file presenti (senza i temporanei).
  Future<List<String>> list() async {
    if (!await dir.exists()) return [];
    return [
      await for (final e in dir.list())
        if (e is File && validName(e.uri.pathSegments.last)) e.uri.pathSegments.last,
    ];
  }

  /// Estensione per il tipo dell'immagine.
  static String extensionFor(String mime) => switch (mime) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        'image/heic' || 'image/heif' => 'heic',
        _ => 'jpg',
      };
}
