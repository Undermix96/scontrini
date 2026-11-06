// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:scontrini/data/db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = AppDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  // Aggiungere solo tabelle (v2: budget) non deve toccare i dati esistenti.
  test('da v1 a v2 i dati restano intatti', () async {
    const cat = (1, 'Alimentari', '#4CC38A', 10, 1000);
    const rec = ('r1', 'Esselunga', 2000, 640, 'EUR', 'carta', 'nota', 'm', '{}', '[]', 3000, 3001);
    const item = ('i1', 'r1', 0, 'Latte', 2.0, 65, 130, 1, 3000);
    const set = ('ai_model', 'google/gemini-2.5-flash');

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(oldDb.categories,
            v1.CategoriesData(id: cat.$1, name: cat.$2, color: cat.$3, sortOrder: cat.$4, createdAt: cat.$5));
        batch.insert(
            oldDb.receipts,
            v1.ReceiptsData(
                id: rec.$1,
                merchant: rec.$2,
                purchasedAt: rec.$3,
                totalCents: rec.$4,
                currency: rec.$5,
                paymentMethod: rec.$6,
                notes: rec.$7,
                aiModel: rec.$8,
                aiRaw: rec.$9,
                dismissedWarnings: rec.$10,
                createdAt: rec.$11,
                updatedAt: rec.$12));
        batch.insert(
            oldDb.receiptItems,
            v1.ReceiptItemsData(
                id: item.$1,
                receiptId: item.$2,
                position: item.$3,
                description: item.$4,
                quantity: item.$5,
                unitPriceCents: item.$6,
                totalCents: item.$7,
                categoryId: item.$8,
                createdAt: item.$9));
        batch.insert(oldDb.settings, v1.SettingsData(key: set.$1, value: set.$2));
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.categories).get(),
            [v2.CategoriesData(id: cat.$1, name: cat.$2, color: cat.$3, sortOrder: cat.$4, createdAt: cat.$5)]);
        expect(await newDb.select(newDb.receipts).get(), [
          v2.ReceiptsData(
              id: rec.$1,
              merchant: rec.$2,
              purchasedAt: rec.$3,
              totalCents: rec.$4,
              currency: rec.$5,
              paymentMethod: rec.$6,
              notes: rec.$7,
              aiModel: rec.$8,
              aiRaw: rec.$9,
              dismissedWarnings: rec.$10,
              createdAt: rec.$11,
              updatedAt: rec.$12)
        ]);
        expect(await newDb.select(newDb.receiptItems).get(), [
          v2.ReceiptItemsData(
              id: item.$1,
              receiptId: item.$2,
              position: item.$3,
              description: item.$4,
              quantity: item.$5,
              unitPriceCents: item.$6,
              totalCents: item.$7,
              categoryId: item.$8,
              createdAt: item.$9)
        ]);
        expect(await newDb.select(newDb.settings).get(), [v2.SettingsData(key: set.$1, value: set.$2)]);
        expect(await newDb.select(newDb.budgets).get(), isEmpty);
      },
    );
  });
}
