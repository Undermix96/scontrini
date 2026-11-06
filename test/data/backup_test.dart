import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scontrini/config.dart';
import 'package:scontrini/data/backup.dart';
import 'package:scontrini/data/repository.dart';

import '../support/fake_app.dart';

Uint8List _bytes(Object json) => Uint8List.fromList(utf8.encode(jsonEncode(json)));

void main() {
  late FakeApp source;
  late Uint8List backup;

  setUp(() async {
    source = FakeApp(now: DateTime(2026, 11, 20, 12));
    await source.state(); // dati di esempio + chiave e impostazioni salvate
    await source.repo.setDismissedWarnings('r1', ['total_mismatch']);
    await source.repo.addCategory('Animali', '#123456');
    backup = await Backup.create(source.repo, appVersion: '2026.11.20');
  });
  tearDown(() => source.db.close());

  test('il backup contiene dati e impostazioni ma non la chiave', () {
    final text = utf8.decode(backup);
    final json = jsonDecode(text) as Map<String, dynamic>;
    expect(json['format'], 'scontrini-backup');
    expect(json['version'], 1);
    expect(json['settings'], {'ai_provider': 'openrouter', 'ai_base_url': '', 'ai_model': 'google/gemini-2.5-flash'});
    expect((json['receipts'] as List).length, 5);
    expect((json['categories'] as List).length, 11);
    expect(text, isNot(contains('sk-or-test-key')));
    expect(text, isNot(contains('setup_done')));
  });

  test('ripristino completo in un\'app nuova', () async {
    final app = FakeApp(now: DateTime(2026, 12, 1));
    addTearDown(app.db.close);
    final summary = await Backup.restore(app.repo, backup);
    expect(summary.receipts, 5);
    expect(summary.categories, 11);

    final before = await source.repo.allReceipts();
    final after = await app.repo.allReceipts();
    String dump(List list) => jsonEncode([
          for (final r in list)
            [
              r.id, r.merchant, r.purchasedAt?.toIso8601String(), r.total, r.currency, r.paymentMethod, r.notes,
              r.aiModel, r.dismissedWarnings, r.duplicateOf, r.createdAt?.toIso8601String(),
              [for (final i in r.items) [i.id, i.position, i.description, i.quantity, i.unitPrice, i.total, i.categoryId]],
            ],
        ]);
    expect(dump(after), dump(before));
    expect((await app.repo.categories()).map((c) => (c.id, c.name, c.color)),
        (await source.repo.categories()).map((c) => (c.id, c.name, c.color)));

    // Impostazioni ripristinate, setup non completato: la chiave va reinserita.
    final config = AppConfig(app.repo, keys: MemoryKeyStore());
    await config.load();
    expect(config.model, 'google/gemini-2.5-flash');
    expect(config.setupDone, isFalse);
    expect(config.isConfigured, isFalse);

    // Le nuove categorie continuano la numerazione.
    await app.repo.addCategory('Nuova', '#000000');
    expect((await app.repo.categories()).firstWhere((c) => c.name == 'Nuova').id, greaterThan(11));
  });

  test('ripristino rifiutato dopo il primo avvio', () async {
    expect(() => Backup.restore(source.repo, backup), throwsA(isA<DataException>()));
    final app = FakeApp();
    addTearDown(app.db.close);
    await app.repo.setSetting(AppConfig.kSetupDone, 'true');
    expect(() => Backup.restore(app.repo, backup), throwsA(isA<DataException>()));
  });

  Future<void> expectRejected(Uint8List bytes, String message) async {
    final app = FakeApp();
    addTearDown(app.db.close);
    await expectLater(
      Backup.restore(app.repo, bytes),
      throwsA(isA<DataException>().having((e) => e.message, 'message', contains(message))),
    );
    // Il database resta com'era: solo le categorie iniziali.
    expect(await app.repo.hasReceipts(), isFalse);
    expect((await app.repo.categories()).length, 10);
  }

  test('file non validi', () async {
    await expectRejected(Uint8List.fromList([0xff, 0x00, 0x12]), 'non è un backup');
    await expectRejected(_bytes({'hello': 1}), 'non è un backup');
    await expectRejected(_bytes({'format': 'scontrini-export', 'version': 1}), "un'esportazione");
    await expectRejected(_bytes({'format': 'scontrini-backup', 'version': 99}), 'versione più recente');
  });

  test('backup danneggiati: nessun dato parziale', () async {
    final json = jsonDecode(utf8.decode(backup)) as Map<String, dynamic>;
    Map<String, dynamic> copy() => jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

    final badCat = copy();
    (((badCat['receipts'] as List)[1] as Map)['items'] as List).first['category_id'] = 999;
    await expectRejected(_bytes(badCat), 'categoria inesistente');

    final badDup = copy();
    ((badDup['receipts'] as List).last as Map)['duplicate_of'] = 'manca';
    await expectRejected(_bytes(badDup), 'doppione inesistente');

    final badTotal = copy();
    ((badTotal['receipts'] as List).last as Map)['total_cents'] = '12,50';
    await expectRejected(_bytes(badTotal), 'total_cents');

    final dupIds = copy();
    (dupIds['receipts'] as List).add((dupIds['receipts'] as List).first);
    await expectRejected(_bytes(dupIds), 'ripetuti');
  });

  test('esportazione JSON filtrata per periodo', () async {
    final bytes = await Backup.export(source.repo,
        from: DateTime(2026, 11), to: DateTime(2026, 12), appVersion: 'x');
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(json['format'], 'scontrini-export');
    expect(json.containsKey('settings'), isFalse);
    expect((json['receipts'] as List).map((r) => r['id']), unorderedEquals(['r1', 'r2', 'r3', 'r4']));
  });

  test('nome del file', () {
    expect(Backup.fileName(DateTime(2026, 3, 7)), 'scontrini-backup-2026-03-07.json');
  });
}
