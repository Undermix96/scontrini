import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Salvataggio e apertura di file tramite il selettore di sistema (Storage
/// Access Framework su Android, documenti su iOS): l'utente sceglie dove.
/// Sostituibile nei test.
abstract class FileGateway {
  /// Vero se il file è stato salvato, falso se l'utente ha annullato.
  Future<bool> save(String fileName, Uint8List bytes, String mimeType);

  /// Contenuto del file scelto, o null se l'utente ha annullato.
  Future<Uint8List?> open();
}

class SystemFiles implements FileGateway {
  const SystemFiles();

  @override
  Future<bool> save(String fileName, Uint8List bytes, String mimeType) async =>
      await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mimeType) != null;

  @override
  Future<Uint8List?> open() async {
    final f = await FilePicker.pickFile(type: FileType.any);
    return f == null ? null : await f.readAsBytes();
  }
}
