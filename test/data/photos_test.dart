import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scontrini/config.dart';
import 'package:scontrini/data/backup.dart';
import 'package:scontrini/data/photos.dart';
import 'package:scontrini/data/repository.dart';

import '../support/fake_app.dart';

Uint8List _jpeg(int seed) => Uint8List.fromList([0xFF, 0xD8, 0xFF, seed, 1, 2, 3, 0xFF, 0xD9]);

void main() {
  late FakeApp app;
  setUp(() async {
    app = FakeApp(now: DateTime(2026, 11, 20, 12));
    await app.seed();
  });
  tearDown(() async {
    await app.db.close();
    await app.photos.dir.delete(recursive: true);
  });

  test('aggiunta in coda, lettura ed eliminazione', () async {
    final a = await app.repo.addPhoto('r1', _jpeg(1));
    final b = await app.repo.addPhoto('r1', _jpeg(2), mime: 'image/png');
    expect(b.fileName, endsWith('.png'));
    final list = await app.repo.photosOf('r1');
    expect(list.map((p) => p.position), [0, 1]);
    expect(await app.repo.photoBytes(list.first), _jpeg(1));
    expect(await app.repo.photoCount(), 2);

    await app.repo.deletePhoto(a.id);
    expect((await app.repo.photosOf('r1')).single.id, b.id);
    expect(await app.photos.list(), [b.fileName]);
  });

  test("eliminando lo scontrino se ne vanno anche i file", () async {
    await app.repo.addPhoto('r1', _jpeg(1));
    await app.repo.addPhoto('r2', _jpeg(2));
    await app.repo.deleteReceipt('r1');
    expect(await app.repo.photoCount(), 1);
    expect((await app.photos.list()).length, 1);
    await app.repo.deleteAllPhotos();
    expect(await app.photos.list(), isEmpty);
  });

  test('pulizia: file senza riga e righe senza file', () async {
    final kept = await app.repo.addPhoto('r1', _jpeg(1));
    final lost = await app.repo.addPhoto('r2', _jpeg(2));
    await app.photos.write('orfana.jpg', _jpeg(3));
    await app.photos.delete(lost.fileName);
    await app.repo.cleanPhotos();
    expect(await app.photos.list(), [kept.fileName]);
    expect((await app.repo.photosOf('r2')), isEmpty);
  });

  test('nomi di file pericolosi rifiutati', () {
    expect(PhotoStore.validName('abc-123.jpg'), isTrue);
    expect(PhotoStore.validName('../db/scontrini.sqlite'), isFalse);
    expect(PhotoStore.validName('a/b.jpg'), isFalse);
    expect(PhotoStore.validName('x.exe'), isFalse);
  });

  test('backup ZIP con le foto e ripristino', () async {
    await AppConfig(app.repo, keys: MemoryKeyStore()).setKeepPhotos(true);
    final p1 = await app.repo.addPhoto('r1', _jpeg(1));
    await app.repo.addPhoto('r1', _jpeg(2));
    final file = await Backup.createFile(app.repo, appVersion: 'test');
    expect(file.fileName, endsWith('.zip'));
    expect(file.mimeType, 'application/zip');
    final zip = ZipDecoder().decodeBytes(file.bytes);
    expect(zip.findFile('photos/${p1.fileName}')!.content, _jpeg(1));
    final json = jsonDecode(utf8.decode(zip.findFile(Backup.jsonName)!.content)) as Map;
    expect((json['photos'] as List).length, 2);

    final fresh = FakeApp();
    addTearDown(() async {
      await fresh.db.close();
      await fresh.photos.dir.delete(recursive: true);
    });
    final summary = await Backup.restore(fresh.repo, file.bytes);
    expect(summary.receipts, 5);
    final restored = await fresh.repo.photosOf('r1');
    expect(restored.length, 2);
    expect(await fresh.repo.photoBytes(restored.first), _jpeg(1));
  });

  test('senza foto il backup resta JSON', () async {
    final file = await Backup.createFile(app.repo, appVersion: 'test');
    expect(file.fileName, endsWith('.json'));
    expect(utf8.decode(file.bytes), startsWith('{'));
  });

  test('ZIP con una foto mancante: rifiutato senza toccare nulla', () async {
    await app.repo.addPhoto('r1', _jpeg(1));
    final file = await Backup.createFile(app.repo, appVersion: 'test');
    final zip = ZipDecoder().decodeBytes(file.bytes);
    final broken = Archive();
    for (final f in zip.files) {
      if (!f.name.startsWith('photos/')) broken.add(ArchiveFile.bytes(f.name, f.content));
    }
    final fresh = FakeApp();
    addTearDown(() async {
      await fresh.db.close();
      await fresh.photos.dir.delete(recursive: true);
    });
    expect(() => Backup.restore(fresh.repo, Uint8List.fromList(ZipEncoder().encode(broken))),
        throwsA(isA<DataException>()));
    expect(await fresh.repo.hasReceipts(), isFalse);
  });
}
