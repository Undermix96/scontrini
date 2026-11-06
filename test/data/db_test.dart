import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scontrini/data/db.dart';
import 'package:scontrini/data/repository.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('scontrini_db_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test("i dati restano su file tra un'apertura e l'altra", () async {
    final file = File('${dir.path}/${AppDatabase.fileName}');
    var db = AppDatabase(NativeDatabase(file));
    await Repository(db).saveScan({'merchant': 'Coop', 'total': 1.5, 'items': []}, model: 'm');
    await db.close();
    expect(await AppDatabase.fileUserVersion(file), AppDatabase.latestSchemaVersion);

    db = AppDatabase(NativeDatabase(file));
    final repo = Repository(db);
    expect((await repo.allReceipts()).single.merchant, 'Coop');
    // Il seed delle categorie avviene solo alla creazione.
    expect((await repo.categories()).length, 10);
    expect((await db.customSelect('PRAGMA foreign_keys').getSingle()).data.values.first, 1);
    await db.close();
  });

  File sqliteFile(String name, int userVersion) {
    final path = '${dir.path}/$name';
    sqlite3.sqlite3.open(path)
      ..execute('CREATE TABLE t (x TEXT)')
      ..execute("INSERT INTO t VALUES ('dato')")
      ..userVersion = userVersion
      ..close();
    return File(path);
  }

  test('versione dello schema letta dal file', () async {
    expect(await AppDatabase.fileUserVersion(sqliteFile('a.sqlite', 7)), 7);
    final other = File('${dir.path}/testo.txt')..writeAsStringSync('non è un database' * 10);
    expect(await AppDatabase.fileUserVersion(other), isNull);
  });

  test('copia di sicurezza solo prima di una migrazione', () async {
    final file = sqliteFile(AppDatabase.fileName, 1);
    final copy = File('${dir.path}/${AppDatabase.preUpgradeFileName}');

    await AppDatabase.copyBeforeUpgrade(file, latest: 1);
    expect(copy.existsSync(), isFalse);
    await AppDatabase.copyBeforeUpgrade(File('${dir.path}/manca.sqlite'), latest: 2);
    expect(copy.existsSync(), isFalse);

    await AppDatabase.copyBeforeUpgrade(file, latest: 2);
    final saved = sqlite3.sqlite3.open(copy.path);
    expect(saved.select('SELECT x FROM t').single['x'], 'dato');
    expect(saved.userVersion, 1);
    saved.close();
  });

  test('schema salvato in drift_schemas per la versione corrente', () {
    expect(File('drift_schemas/app/drift_schema_v${AppDatabase.latestSchemaVersion}.json').existsSync(), isTrue);
  });
}
