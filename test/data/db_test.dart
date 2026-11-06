import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scontrini/data/db.dart';
import 'package:scontrini/data/repository.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('scontrini_db_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('i dati restano su file tra una apertura e l\'altra', () async {
    final file = File('${dir.path}/${AppDatabase.fileName}');
    var db = AppDatabase.file(file);
    await Repository(db).saveScan({'merchant': 'Coop', 'total': 1.5, 'items': []}, model: 'm');
    await db.close();

    db = AppDatabase.file(file);
    final repo = Repository(db);
    expect((await repo.allReceipts()).single.merchant, 'Coop');
    // Il seed delle categorie avviene solo alla creazione.
    expect((await repo.categories()).length, 10);
    expect(await db.customSelect('PRAGMA foreign_keys').getSingle().then((r) => r.data.values.first), 1);
    await db.close();
    // Nessuna migrazione: nessuna copia.
    expect(File('${dir.path}/${AppDatabase.preUpgradeFileName}').existsSync(), isFalse);
  });

  test('copia di sicurezza prima di una migrazione', () {
    final path = '${dir.path}/vecchio.sqlite';
    final copy = '${dir.path}/${AppDatabase.preUpgradeFileName}';
    final db = sqlite3.sqlite3.open(path)
      ..execute('CREATE TABLE t (x TEXT)')
      ..execute("INSERT INTO t VALUES ('dato')")
      ..userVersion = 1;
    // Stessa versione: niente copia.
    AppDatabase.copyBeforeUpgrade(db, copy, latest: 1);
    expect(File(copy).existsSync(), isFalse);
    // Versione più vecchia dello schema dell'app: copia completa.
    AppDatabase.copyBeforeUpgrade(db, copy, latest: 2);
    db.close();
    final saved = sqlite3.sqlite3.open(copy);
    expect(saved.select('SELECT x FROM t').single['x'], 'dato');
    saved.close();
  });

  test('schema salvato in drift_schemas per la versione corrente', () {
    expect(File('drift_schemas/app/drift_schema_v${AppDatabase.latestSchemaVersion}.json').existsSync(), isTrue);
  });
}
