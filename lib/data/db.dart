import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_sqflite/drift_sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

part 'db.g.dart';

// Importi in centesimi interi, date in millisecondi UTC (drift salva i
// DateTime come secondi Unix: qui usiamo interi espliciti per non perdere
// precisione e per avere lo stesso formato nel backup).

@DataClassName('CategoryRow')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  TextColumn get color => text().withDefault(const Constant('#8E8C9C'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
}

@DataClassName('ReceiptRow')
class Receipts extends Table {
  TextColumn get id => text()();
  TextColumn get merchant => text().nullable()();
  IntColumn get purchasedAt => integer().nullable()();
  IntColumn get totalCents => integer().withDefault(const Constant(0))();
  TextColumn get currency => text().withDefault(const Constant('EUR'))();
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get aiModel => text().nullable()();

  /// Risposta dell'AI così com'è (JSON), per eventuali correzioni future.
  TextColumn get aiRaw => text().nullable()();

  /// Codici degli avvisi ignorati, come array JSON.
  TextColumn get dismissedWarnings => text().withDefault(const Constant('[]'))();
  TextColumn get duplicateOf => text().nullable().references(Receipts, #id, onDelete: KeyAction.setNull)();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ItemRow')
class ReceiptItems extends Table {
  TextColumn get id => text()();
  TextColumn get receiptId => text().references(Receipts, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get description => text()();
  RealColumn get quantity => real().nullable()();
  IntColumn get unitPriceCents => integer().nullable()();
  IntColumn get totalCents => integer().withDefault(const Constant(0))();
  IntColumn get categoryId => integer().nullable().references(Categories, #id, onDelete: KeyAction.setNull)();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Impostazioni non segrete (la chiave API sta nel Keystore/Keychain).
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Categorie iniziali, con la palette del design.
const defaultCategories = [
  ('Alimentari', '#4CC38A', 10),
  ('Bevande', '#F0A35A', 20),
  ('Casa', '#5AA9F0', 30),
  ('Igiene', '#E67AC4', 40),
  ('Salute', '#F26D6D', 50),
  ('Trasporti', '#6FD3D3', 60),
  ('Ristorazione', '#E8D45A', 70),
  ('Abbigliamento', '#7C8CF8', 80),
  ('Svago', '#A99CFF', 90),
  ('Altro', '#8E8C9C', 100),
];

@DriftDatabase(tables: [Categories, Receipts, ReceiptItems, Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Apre il database dell'app nella cartella dati privata.
  ///
  /// Il file si trova in `<supporto applicazione>/db/scontrini.sqlite`: resta
  /// tra un aggiornamento e l'altro e si perde solo disinstallando l'app.
  ///
  /// Usa il SQLite del sistema tramite sqflite (Java su Android, C su iOS):
  /// niente FFI nell'app, quindi nessuna callback creata a runtime in
  /// memoria eseguibile (GrapheneOS la segnala come "DCL via memory").
  /// I test usano invece un database in memoria via FFI.
  static Future<AppDatabase> open() async {
    final dir = await databaseDirectory();
    final file = File('${dir.path}/$fileName');
    await copyBeforeUpgrade(file);
    return AppDatabase(SqfliteQueryExecutor(path: file.path));
  }

  static const preUpgradeFileName = 'scontrini.pre-upgrade.sqlite';

  /// Prima di una migrazione di schema salva una copia del database accanto
  /// all'originale (con gli eventuali file -wal e -journal, così la copia è
  /// coerente). Se l'aggiornamento andasse storto i dati restano
  /// recuperabili. Si tiene solo l'ultima copia. Va chiamata con il database
  /// chiuso.
  static Future<void> copyBeforeUpgrade(File db, {int latest = latestSchemaVersion}) async {
    try {
      if (!await db.exists()) return;
      final version = await fileUserVersion(db);
      if (version == null || version == 0 || version >= latest) return;
      final target = '${db.parent.path}/$preUpgradeFileName';
      for (final suffix in ['', '-wal', '-journal']) {
        final old = File('$target$suffix');
        if (await old.exists()) await old.delete();
        final src = File('${db.path}$suffix');
        if (await src.exists()) await src.copy('$target$suffix');
      }
    } catch (e) {
      debugPrint("Copia prima dell'aggiornamento non riuscita: $e");
    }
  }

  /// `user_version` (la versione dello schema) letta dall'intestazione del
  /// file SQLite: 4 byte big-endian all'offset 60. Null se il file non è un
  /// database SQLite. Con un WAL non ancora riportato può essere più vecchia
  /// di quella reale: al massimo si fa una copia in più.
  static Future<int?> fileUserVersion(File db) async {
    final raf = await db.open();
    try {
      final header = await raf.read(64);
      if (header.length < 64 || String.fromCharCodes(header.sublist(0, 15)) != 'SQLite format 3') return null;
      return ByteData.sublistView(Uint8List.fromList(header)).getUint32(60);
    } finally {
      await raf.close();
    }
  }

  static const fileName = 'scontrini.sqlite';

  static Future<Directory> databaseDirectory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/db');
    await dir.create(recursive: true);
    await _excludeFromSystemBackup(dir);
    return dir;
  }

  /// Su iOS i dati delle app finiscono nel backup iCloud/iTunes per default:
  /// la cartella del database ne viene esclusa. Su Android ci pensano
  /// `allowBackup="false"` e le regole di estrazione nel manifest.
  static Future<void> _excludeFromSystemBackup(Directory dir) async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      await const MethodChannel('scontrini/storage').invokeMethod<void>('excludeFromBackup', dir.path);
    } catch (e) {
      debugPrint('Esclusione dal backup iCloud non riuscita: $e');
    }
  }

  // Ogni modifica allo schema: incrementare latestSchemaVersion, aggiungere
  // un passo in `migration`, poi `dart run drift_dev make-migrations` per
  // salvare lo schema in drift_schemas/ e generare i test di migrazione.
  static const latestSchemaVersion = 1;

  @override
  int get schemaVersion => latestSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await seedCategories();
        },
        onUpgrade: (m, from, to) async {
          // Nessuna migrazione ancora: la versione 1 è la prima.
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> seedCategories() async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await batch((b) {
      b.insertAll(categories, [
        for (final (name, color, order) in defaultCategories)
          CategoriesCompanion.insert(name: name, color: Value(color), sortOrder: Value(order), createdAt: now),
      ]);
    });
  }
}
