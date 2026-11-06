import 'package:flutter_test/flutter_test.dart';
import 'package:scontrini/data/repository.dart';
import 'package:scontrini/models.dart';

import '../support/fake_app.dart';

void main() {
  late FakeApp app;
  late Repository repo;
  final month = DateTime(2026, 11);
  final next = DateTime(2026, 12);

  setUp(() async {
    app = FakeApp(now: DateTime(2026, 11, 20, 12));
    await app.seed();
    repo = app.repo;
  });
  tearDown(() => app.db.close());

  test('categorie del seed con il numero di righe', () async {
    final cats = await repo.categories();
    expect(cats.map((c) => c.name).take(3), ['Alimentari', 'Bevande', 'Casa']);
    expect(cats.firstWhere((c) => c.name == 'Alimentari').itemCount, 5);
    expect(cats.firstWhere((c) => c.name == 'Altro').itemCount, 0);
  });

  test('categoria con nome già usato (senza distinguere maiuscole)', () async {
    expect(() => repo.addCategory(' casa ', '#000000'), throwsA(isA<DataException>()));
    await repo.addCategory('Animali', '#123456');
    final id = (await repo.categories()).firstWhere((c) => c.name == 'Animali').id;
    expect(() => repo.updateCategory(id, name: 'Svago'), throwsA(isA<DataException>()));
    await repo.updateCategory(id, name: 'Animali domestici', color: '#654321');
    final c = (await repo.categories()).firstWhere((c) => c.id == id);
    expect((c.name, c.color), ('Animali domestici', '#654321'));
  });

  test('eliminare una categoria lascia le righe senza categoria', () async {
    await repo.deleteCategory(3); // Casa
    final r = await repo.receipt('r1');
    expect(r.items.firstWhere((i) => i.description == 'Detersivo piatti').categoryId, isNull);
  });

  test('elenco del mese: ordine, somma righe, prevalente e avvisi', () async {
    final list = await repo.receipts(from: month, to: next);
    expect(list.map((r) => r.id), ['r1', 'r2', 'r3', 'r4']);
    final r1 = list.first;
    expect(r1.total, 64.2);
    expect(r1.itemsSum, 62.7);
    expect(r1.itemCount, 6);
    expect(r1.dominantCategoryId, 4); // Spazzolino 50,40 in Igiene
    expect(r1.warnings, [ReceiptWarning.totalMismatch]);
    expect(list[2].warnings, [ReceiptWarning.duplicate]);
    expect(list[3].warnings, isEmpty);
  });

  test('ricerca per esercente o descrizione, senza distinguere maiuscole', () async {
    expect((await repo.receipts(q: 'esselunga')).map((r) => r.id), ['r1']);
    expect((await repo.receipts(q: 'CAPPUCC')).map((r) => r.id), ['r4']);
    expect((await repo.receipts(q: 'coop')).map((r) => r.id), ['r3', 'r9']);
    expect((await repo.receipts(q: 'coop', from: month, to: next)).map((r) => r.id), ['r3']);
    expect(await repo.receipts(q: '%'), isEmpty);
  });

  test('filtro per categoria di almeno una riga', () async {
    expect((await repo.receipts(categoryId: 5)).map((r) => r.id), ['r2']);
    expect((await repo.receipts(categoryId: 1, from: month, to: next)).map((r) => r.id), ['r1', 'r3']);
  });

  test('statistiche per categoria nel periodo', () async {
    final stats = {for (final s in await repo.stats(from: month, to: next)) s.categoryId: s.total};
    expect(stats[1], closeTo(1.3 + 2.1 + 2.47 + 37.85, 1e-9));
    expect(stats[null], 2.8);
    expect(stats[5], 18.9);
  });

  test('dettaglio con riferimento al doppione', () async {
    final r = await repo.receipt('r3');
    expect(r.duplicate?.id, 'r9');
    expect(r.duplicate?.merchant, 'Coop');
    expect(() => repo.receipt('nessuno'), throwsA(isA<DataException>()));
  });

  test('ignorare un avviso lo toglie dagli avvisi aperti', () async {
    final r = await repo.setDismissedWarnings('r1', ['total_mismatch']);
    expect(r.warnings, isEmpty);
    expect(r.dismissedWarnings, ['total_mismatch']);
    expect(() => repo.setDismissedWarnings('r1', ['boh']), throwsA(isA<DataException>()));
  });

  test('modifica dell\'intestazione', () async {
    final at = DateTime(2026, 11, 3, 9, 30);
    final r = await repo.updateReceipt('r4', {
      'merchant': 'Bar Sport',
      'total': 4.5,
      'payment_method': null,
      'purchased_at': at.toUtc().toIso8601String(),
    });
    expect((r.merchant, r.total, r.paymentMethod, r.purchasedAt), ('Bar Sport', 4.5, null, at));
  });

  test('righe: aggiunta in coda, modifica, eliminazione', () async {
    final added = await repo.addItem('r4', {'description': 'Succo', 'total': 2.2, 'category_id': 2});
    expect(added.position, 2);
    await repo.updateItem(added.id, {'total': '2,5', 'quantity': 2, 'unit_price': 1.25});
    var r = await repo.receipt('r4');
    final item = r.items.last;
    expect((item.description, item.total, item.quantity, item.unitPrice), ('Succo', 2.5, 2.0, 1.25));
    await repo.deleteItem(added.id);
    r = await repo.receipt('r4');
    expect(r.items.length, 2);
  });

  test('eliminare lo scontrino originale toglie il doppione', () async {
    await repo.deleteReceipt('r9');
    final r3 = await repo.receipt('r3');
    expect(r3.duplicateOf, isNull);
    expect(r3.warnings, isEmpty);
  });

  test('salvataggio di una lettura AI', () async {
    final r = await repo.saveScan({
      'merchant': '  Conad ',
      'purchased_at': '2026-11-19T18:30:00',
      'total': 10,
      'currency': 'eur',
      'payment_method': null,
      'items': [
        {'description': 'Pasta', 'quantity': 2, 'unit_price': 1.5, 'total': 3, 'category': 'alimentari'},
        {'description': '', 'quantity': null, 'unit_price': null, 'total': 7, 'category': 'Inventata'},
      ],
    }, model: 'm');
    expect(r.merchant, 'Conad');
    expect(r.currency, 'EUR');
    expect(r.purchasedAt, DateTime(2026, 11, 19, 18, 30));
    expect(r.items.map((i) => i.categoryId), [1, 10]);
    expect(r.items[1].description, '(senza descrizione)');
    expect(r.aiModel, 'm');
    expect(r.possibleDuplicateOf, isNull);
  });

  test('lettura AI: doppione, data futura e totale mancante', () async {
    final at = DateTime.fromMillisecondsSinceEpoch(
        (await repo.receipt('r4')).purchasedAt!.millisecondsSinceEpoch + 30000);
    final dup = await repo.saveScan({'purchased_at': at.toIso8601String(), 'total': 4.3, 'items': []}, model: 'm');
    expect(dup.possibleDuplicateOf, 'r4');
    expect(dup.warnings, contains(ReceiptWarning.duplicate));

    final future = await repo.saveScan({
      'purchased_at': '2030-01-01T10:00:00',
      'total': null,
      'items': [
        {'description': 'a', 'total': 1.25, 'category': 'Altro'},
        {'description': 'b', 'total': 2, 'category': 'Altro'},
      ],
    }, model: 'm');
    expect(future.purchasedAt, app.now);
    expect(future.total, 3.25);
  });

  test('date lette dagli scontrini', () {
    expect(parseReceiptDate('2026-11-04T18:30:00'), DateTime(2026, 11, 4, 18, 30));
    expect(parseReceiptDate('2026-11-04'), DateTime(2026, 11, 4, 12));
    expect(parseReceiptDate('2026-11-04T17:30:00Z'), DateTime.utc(2026, 11, 4, 17, 30).toLocal());
    expect(parseReceiptDate('2026-13-40'), isNull);
    expect(parseReceiptDate('ieri'), isNull);
    expect(parseReceiptDate(null), isNull);
  });

  test('impostazioni', () async {
    expect(await repo.setting('x'), isNull);
    await repo.setSetting('x', '1');
    await repo.setSetting('x', '2');
    expect(await repo.setting('x'), '2');
    await repo.setSetting('x', null);
    expect(await repo.setting('x'), isNull);
  });
}
