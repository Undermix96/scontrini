import 'dart:convert';

import 'package:drift/drift.dart';

import '../budget.dart';
import '../models.dart';
import '../warnings.dart';
import 'db.dart';
import 'ids.dart';
import 'photos.dart';

/// Errore mostrato all'utente così com'è.
class DataException implements Exception {
  final String message;
  DataException(this.message);
  @override
  String toString() => message;
}

/// Accesso ai dati locali. Stessi metodi del vecchio client della Edge
/// Function, così le schermate non sanno dove stanno i dati.
class Repository {
  final AppDatabase db;

  /// Orologio sostituibile nei test.
  final DateTime Function() now;

  /// Foto conservate (null: nessuna cartella, es. in alcuni test).
  final PhotoStore? photos;

  Repository(this.db, {DateTime Function()? now, this.photos}) : now = now ?? DateTime.now;

  int get _nowMs => now().toUtc().millisecondsSinceEpoch;

  // ------------------------------------------------------------- impostazioni

  Future<String?> setting(String key) async =>
      (await (db.select(db.settings)..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      await (db.delete(db.settings)..where((s) => s.key.equals(key))).go();
    } else {
      // INSERT OR REPLACE e non upsert: il SQLite di sistema di Android 7-10
      // non conosce ON CONFLICT DO UPDATE.
      await db.into(db.settings).insert(SettingsCompanion.insert(key: key, value: value), mode: InsertMode.insertOrReplace);
    }
  }

  Future<bool> hasReceipts() async {
    final n = await db.customSelect('SELECT COUNT(*) AS n FROM receipts').getSingle();
    return n.read<int>('n') > 0;
  }

  // ------------------------------------------------------------- categorie

  Future<List<Category>> categories() async {
    final rows = await db.customSelect(
      'SELECT c.*, (SELECT COUNT(*) FROM receipt_items i WHERE i.category_id = c.id) AS item_count '
      'FROM categories c ORDER BY c.sort_order, c.id',
      readsFrom: {db.categories, db.receiptItems},
    ).get();
    return [
      for (final r in rows) _category(db.categories.map(r.data), itemCount: r.read<int>('item_count')),
    ];
  }

  static Category _category(CategoryRow c, {int? itemCount}) =>
      Category(id: c.id, name: c.name, color: c.color, sortOrder: c.sortOrder, itemCount: itemCount);

  Future<void> _checkName(String name, {int? exceptId}) async {
    if (name.isEmpty) throw DataException('Scrivi un nome');
    final all = await db.select(db.categories).get();
    if (all.any((c) => c.id != exceptId && c.name.toLowerCase() == name.toLowerCase())) {
      throw DataException('Esiste già un elemento con questo nome');
    }
  }

  Future<void> addCategory(String name, String color) async {
    name = name.trim();
    await _checkName(name);
    await db.into(db.categories).insert(CategoriesCompanion.insert(
          name: name,
          color: Value(color),
          sortOrder: const Value(500),
          createdAt: _nowMs,
        ));
  }

  Future<void> updateCategory(int id, {String? name, String? color}) async {
    if (name != null) {
      name = name.trim();
      await _checkName(name, exceptId: id);
    }
    await (db.update(db.categories)..where((c) => c.id.equals(id))).write(CategoriesCompanion(
      name: name == null ? const Value.absent() : Value(name),
      color: color == null ? const Value.absent() : Value(color),
    ));
  }

  /// Le righe della categoria restano, senza categoria.
  Future<void> deleteCategory(int id) => (db.delete(db.categories)..where((c) => c.id.equals(id))).go();

  // ------------------------------------------------------------- scontrini

  static DateTime? _date(int? ms) => ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  static int _ms(DateTime d) => d.toUtc().millisecondsSinceEpoch;
  static double _eur(int cents) => cents / 100;

  static ReceiptItem _item(ItemRow i) => ReceiptItem(
        id: i.id,
        position: i.position,
        description: i.description,
        quantity: i.quantity,
        unitPrice: i.unitPriceCents == null ? null : _eur(i.unitPriceCents!),
        total: _eur(i.totalCents),
        categoryId: i.categoryId,
      );

  static List<String> _codes(String json) {
    try {
      final v = jsonDecode(json);
      return v is List ? v.map((e) => '$e').toList() : <String>[];
    } catch (_) {
      return <String>[];
    }
  }

  /// Costruisce il modello con righe, somma, categoria prevalente e avvisi.
  static Receipt _receipt(ReceiptRow r, List<ItemRow> rows) {
    final items = rows.map(_item).toList()..sort((a, b) => a.position.compareTo(b.position));
    final byCat = <int, int>{};
    var sum = 0;
    for (final i in rows) {
      sum += i.totalCents;
      if (i.categoryId != null) byCat[i.categoryId!] = (byCat[i.categoryId!] ?? 0) + i.totalCents;
    }
    int? dominant;
    for (final e in byCat.entries) {
      if (dominant == null || e.value > byCat[dominant]!) dominant = e.key;
    }
    final receipt = Receipt(
      id: r.id,
      merchant: r.merchant,
      purchasedAt: _date(r.purchasedAt),
      createdAt: _date(r.createdAt),
      total: _eur(r.totalCents),
      currency: r.currency,
      paymentMethod: r.paymentMethod,
      notes: r.notes,
      aiModel: r.aiModel,
      itemCount: items.length,
      items: items,
      itemsSum: _eur(sum),
      dominantCategoryId: dominant,
      dismissedWarnings: _codes(r.dismissedWarnings),
      duplicateOf: r.duplicateOf,
    );
    receipt.warnings = computeWarnings(receipt);
    return receipt;
  }

  /// Scontrini con le righe, dal più recente, con data d'acquisto in [from, to).
  Future<List<Receipt>> _load({DateTime? from, DateTime? to, String? id}) async {
    final where = <String>[];
    final args = <Variable>[];
    if (id != null) {
      where.add('r.id = ?');
      args.add(Variable.withString(id));
    }
    if (from != null) {
      where.add('r.purchased_at >= ?');
      args.add(Variable.withInt(_ms(from)));
    }
    if (to != null) {
      where.add('r.purchased_at < ?');
      args.add(Variable.withInt(_ms(to)));
    }
    final cond = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final receiptRows = await db
        .customSelect('SELECT r.* FROM receipts r $cond', variables: args, readsFrom: {db.receipts})
        .map((row) => db.receipts.map(row.data))
        .get();
    final itemRows = await db
        .customSelect('SELECT i.* FROM receipt_items i JOIN receipts r ON r.id = i.receipt_id $cond',
            variables: args, readsFrom: {db.receipts, db.receiptItems})
        .map((row) => db.receiptItems.map(row.data))
        .get();
    final byReceipt = <String, List<ItemRow>>{};
    for (final i in itemRows) {
      (byReceipt[i.receiptId] ??= []).add(i);
    }
    final out = [for (final r in receiptRows) _receipt(r, byReceipt[r.id] ?? const [])];
    out.sort((a, b) {
      final pa = a.purchasedAt, pb = b.purchasedAt;
      if (pa == null || pb == null) return pa == null ? (pb == null ? 0 : 1) : -1;
      final c = pb.compareTo(pa);
      return c != 0 ? c : (b.createdAt ?? pb).compareTo(a.createdAt ?? pa);
    });
    return out;
  }

  /// Scontrini con data d'acquisto in [from, to), filtrati per testo
  /// (esercente o descrizione di una riga) e per categoria di almeno una riga.
  Future<List<Receipt>> receipts({DateTime? from, DateTime? to, String? q, int? categoryId}) async {
    var list = await _load(from: from, to: to);
    final query = q?.trim().toLowerCase() ?? '';
    if (query.isNotEmpty) {
      list = list
          .where((r) =>
              (r.merchant ?? '').toLowerCase().contains(query) ||
              r.items.any((i) => i.description.toLowerCase().contains(query)))
          .toList();
    }
    if (categoryId != null) list = list.where((r) => r.items.any((i) => i.categoryId == categoryId)).toList();
    return list;
  }

  Future<List<Receipt>> allReceipts() => _load();

  Future<Receipt> receipt(String id) async {
    final found = await _load(id: id);
    if (found.isEmpty) throw DataException('Scontrino non trovato');
    final r = found.single;
    if (r.duplicateOf != null) {
      final other = await (db.select(db.receipts)..where((x) => x.id.equals(r.duplicateOf!))).getSingleOrNull();
      if (other != null) r.duplicate = ReceiptRef(other.id, other.merchant, _date(other.purchasedAt));
    }
    return r;
  }

  static int? _cents(dynamic v) {
    if (v == null || v == '') return null;
    final n = v is num ? v.toDouble() : double.tryParse('$v'.replaceAll(',', '.'));
    return n == null || !n.isFinite ? null : cents(n);
  }

  static double? _real(dynamic v, [int digits = 3]) {
    if (v == null || v == '') return null;
    final n = v is num ? v.toDouble() : double.tryParse('$v'.replaceAll(',', '.'));
    if (n == null || !n.isFinite) return null;
    return double.parse(n.toStringAsFixed(digits));
  }

  static String? _text(dynamic v) => v == null ? null : '$v';

  /// Aggiorna i campi indicati: merchant, purchased_at (DateTime o ISO 8601),
  /// total, currency, notes, payment_method, dismissed_warnings.
  Future<Receipt> updateReceipt(String id, Map<String, dynamic> f) async {
    DateTime? purchased;
    if (f.containsKey('purchased_at')) {
      final v = f['purchased_at'];
      purchased = v is DateTime ? v : DateTime.tryParse('$v');
      if (purchased == null) throw DataException('Data non valida');
    }
    if (f.containsKey('dismissed_warnings')) {
      final v = f['dismissed_warnings'];
      if (v is! List || !v.every((w) => ReceiptWarning.fromCode('$w') != null)) {
        throw DataException('Avvisi non validi');
      }
    }
    final n = await (db.update(db.receipts)..where((r) => r.id.equals(id))).write(ReceiptsCompanion(
      merchant: f.containsKey('merchant') ? Value(_text(f['merchant'])) : const Value.absent(),
      purchasedAt: purchased != null ? Value(_ms(purchased)) : const Value.absent(),
      totalCents: f.containsKey('total') ? Value(_cents(f['total']) ?? 0) : const Value.absent(),
      currency: f.containsKey('currency') ? Value(_currency(f['currency'])) : const Value.absent(),
      notes: f.containsKey('notes') ? Value(_text(f['notes'])) : const Value.absent(),
      paymentMethod: f.containsKey('payment_method') ? Value(_text(f['payment_method'])) : const Value.absent(),
      dismissedWarnings: f.containsKey('dismissed_warnings')
          ? Value(jsonEncode({...(f['dismissed_warnings'] as List).map((e) => '$e')}.toList()))
          : const Value.absent(),
      updatedAt: Value(_nowMs),
    ));
    if (n == 0) throw DataException('Scontrino non trovato');
    return receipt(id);
  }

  static String _currency(dynamic v) {
    final s = '${v ?? ''}'.trim().toUpperCase();
    return s.length >= 3 ? s.substring(0, 3) : 'EUR';
  }

  /// Elimina lo scontrino, le sue righe e le sue foto.
  Future<void> deleteReceipt(String id) async {
    final files = [for (final p in await photosOf(id)) p.fileName];
    await (db.delete(db.receipts)..where((r) => r.id.equals(id))).go();
    for (final f in files) {
      await photos?.delete(f);
    }
  }

  // ------------------------------------------------------------- foto

  Future<List<ReceiptPhoto>> photosOf(String receiptId) async => [
        for (final p in await (db.select(db.receiptPhotos)
              ..where((p) => p.receiptId.equals(receiptId))
              ..orderBy([(p) => OrderingTerm(expression: p.position), (p) => OrderingTerm(expression: p.createdAt)]))
            .get())
          ReceiptPhoto(p.id, p.receiptId, p.position, p.fileName),
      ];

  Future<int> photoCount() async {
    final c = db.receiptPhotos.id.count();
    return (await (db.selectOnly(db.receiptPhotos)..addColumns([c])).getSingle()).read(c) ?? 0;
  }

  Future<Uint8List?> photoBytes(ReceiptPhoto p) async => photos?.read(p.fileName);

  /// Aggiunge una foto in coda a quelle dello scontrino.
  Future<ReceiptPhoto> addPhoto(String receiptId, Uint8List bytes, {String mime = 'image/jpeg'}) async {
    final store = photos;
    if (store == null) throw DataException('Cartella delle foto non disponibile');
    final id = newId();
    final name = '$id.${PhotoStore.extensionFor(mime)}';
    await store.write(name, bytes);
    try {
      return await db.transaction(() async {
        final last = await db.customSelect(
          'SELECT MAX(position) AS p FROM receipt_photos WHERE receipt_id = ?',
          variables: [Variable.withString(receiptId)],
        ).getSingle();
        final pos = (last.read<int?>('p') ?? -1) + 1;
        await db.into(db.receiptPhotos).insert(
            ReceiptPhotosCompanion.insert(id: id, receiptId: receiptId, position: Value(pos), fileName: name, createdAt: _nowMs));
        return ReceiptPhoto(id, receiptId, pos, name);
      });
    } catch (_) {
      await store.delete(name);
      rethrow;
    }
  }

  Future<void> deletePhoto(String id) async {
    final row = await (db.select(db.receiptPhotos)..where((p) => p.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    await (db.delete(db.receiptPhotos)..where((p) => p.id.equals(id))).go();
    await photos?.delete(row.fileName);
  }

  /// Elimina tutte le foto conservate (quando l'utente spegne l'opzione).
  Future<void> deleteAllPhotos() async {
    final rows = await db.select(db.receiptPhotos).get();
    await db.delete(db.receiptPhotos).go();
    for (final r in rows) {
      await photos?.delete(r.fileName);
    }
  }

  /// Allinea file e righe: elimina i file senza riga (es. salvataggio
  /// interrotto) e le righe senza file.
  Future<void> cleanPhotos() async {
    final store = photos;
    if (store == null) return;
    final rows = await db.select(db.receiptPhotos).get();
    final files = (await store.list()).toSet();
    final known = {for (final r in rows) r.fileName};
    for (final f in files.difference(known)) {
      await store.delete(f);
    }
    final missing = [for (final r in rows) if (!files.contains(r.fileName)) r.id];
    if (missing.isNotEmpty) await (db.delete(db.receiptPhotos)..where((p) => p.id.isIn(missing))).go();
  }

  /// Ignora gli avvisi indicati per questo scontrino (sostituisce l'elenco).
  Future<Receipt> setDismissedWarnings(String id, List<String> codes) =>
      updateReceipt(id, {'dismissed_warnings': codes});

  Future<void> _touch(String receiptId) => (db.update(db.receipts)..where((r) => r.id.equals(receiptId)))
      .write(ReceiptsCompanion(updatedAt: Value(_nowMs)));

  /// Campi: category_id, description, total, quantity, unit_price.
  Future<void> updateItem(String id, Map<String, dynamic> f) async {
    final item = await (db.select(db.receiptItems)..where((i) => i.id.equals(id))).getSingleOrNull();
    if (item == null) throw DataException('Riga non trovata');
    await db.transaction(() async {
      await (db.update(db.receiptItems)..where((i) => i.id.equals(id))).write(ReceiptItemsCompanion(
        categoryId: f.containsKey('category_id') ? Value((f['category_id'] as num?)?.toInt()) : const Value.absent(),
        description: f.containsKey('description') ? Value(_desc(f['description'])) : const Value.absent(),
        totalCents: f.containsKey('total') ? Value(_cents(f['total']) ?? 0) : const Value.absent(),
        quantity: f.containsKey('quantity') ? Value(_real(f['quantity'])) : const Value.absent(),
        unitPriceCents: f.containsKey('unit_price') ? Value(_cents(f['unit_price'])) : const Value.absent(),
      ));
      await _touch(item.receiptId);
    });
  }

  static String _desc(dynamic v) {
    final s = '${v ?? ''}';
    return s.length > 300 ? s.substring(0, 300) : s;
  }

  Future<ReceiptItem> addItem(String receiptId, Map<String, dynamic> f) async {
    return db.transaction(() async {
      final exists = await (db.select(db.receipts)..where((r) => r.id.equals(receiptId))).getSingleOrNull();
      if (exists == null) throw DataException('Scontrino non trovato');
      final last = await db.customSelect(
        'SELECT MAX(position) AS p FROM receipt_items WHERE receipt_id = ?',
        variables: [Variable.withString(receiptId)],
      ).getSingle();
      final row = ItemRow(
        id: newId(),
        receiptId: receiptId,
        position: (last.read<int?>('p') ?? -1) + 1,
        description: _desc(f['description']),
        quantity: _real(f['quantity']),
        unitPriceCents: _cents(f['unit_price']),
        totalCents: _cents(f['total']) ?? 0,
        categoryId: (f['category_id'] as num?)?.toInt(),
        createdAt: _nowMs,
      );
      await db.into(db.receiptItems).insert(row);
      await _touch(receiptId);
      return _item(row);
    });
  }

  Future<void> deleteItem(String id) async {
    final item = await (db.select(db.receiptItems)..where((i) => i.id.equals(id))).getSingleOrNull();
    if (item == null) return;
    await db.transaction(() async {
      await (db.delete(db.receiptItems)..where((i) => i.id.equals(id))).go();
      await _touch(item.receiptId);
    });
  }

  /// Totali per categoria delle righe degli scontrini in [from, to).
  Future<List<CategoryTotal>> stats({DateTime? from, DateTime? to}) async {
    final where = <String>[];
    final args = <Variable>[];
    if (from != null) {
      where.add('r.purchased_at >= ?');
      args.add(Variable.withInt(_ms(from)));
    }
    if (to != null) {
      where.add('r.purchased_at < ?');
      args.add(Variable.withInt(_ms(to)));
    }
    final rows = await db.customSelect(
      'SELECT i.category_id AS c, SUM(i.total_cents) AS t FROM receipt_items i '
      'JOIN receipts r ON r.id = i.receipt_id ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} '
      'GROUP BY i.category_id',
      variables: args,
      readsFrom: {db.receipts, db.receiptItems},
    ).get();
    return [for (final r in rows) CategoryTotal(r.read<int?>('c'), _eur(r.read<int>('t')))];
  }

  // ------------------------------------------------------------- andamento

  /// Righe (data d'acquisto locale, importo in centesimi, categoria, scontrino)
  /// degli scontrini con data in [from, to).
  Future<List<({DateTime at, int cents, int? categoryId, String receiptId})>> _itemsIn(DateTime from, DateTime to) async {
    final rows = await db.customSelect(
      'SELECT r.id AS r, r.purchased_at AS p, i.total_cents AS t, i.category_id AS c FROM receipt_items i '
      'JOIN receipts r ON r.id = i.receipt_id WHERE r.purchased_at >= ? AND r.purchased_at < ?',
      variables: [Variable.withInt(_ms(from)), Variable.withInt(_ms(to))],
      readsFrom: {db.receipts, db.receiptItems},
    ).get();
    return [
      for (final r in rows)
        (
          at: DateTime.fromMillisecondsSinceEpoch(r.read<int>('p'), isUtc: true).toLocal(),
          cents: r.read<int>('t'),
          categoryId: r.read<int?>('c'),
          receiptId: r.read<String>('r'),
        ),
    ];
  }

  /// Spesa di [count] mesi a partire da [firstMonth] (somma delle righe, nel
  /// fuso del telefono), eventualmente di una sola categoria.
  Future<List<double>> monthlyTotals(DateTime firstMonth, int count, {int? categoryId}) async {
    final from = DateTime(firstMonth.year, firstMonth.month);
    final to = DateTime(from.year, from.month + count);
    final out = List<int>.filled(count, 0);
    for (final i in await _itemsIn(from, to)) {
      if (categoryId != null && i.categoryId != categoryId) continue;
      final idx = (i.at.year - from.year) * 12 + i.at.month - from.month;
      if (idx >= 0 && idx < count) out[idx] += i.cents;
    }
    return [for (final c in out) _eur(c)];
  }

  /// Spesa giorno per giorno del mese (indice 0 = giorno 1).
  Future<List<double>> dailyTotals(DateTime month, {int? categoryId}) async {
    final from = DateTime(month.year, month.month);
    final to = DateTime(month.year, month.month + 1);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final out = List<int>.filled(days, 0);
    for (final i in await _itemsIn(from, to)) {
      if (categoryId != null && i.categoryId != categoryId) continue;
      final d = i.at.day - 1;
      if (d >= 0 && d < days) out[d] += i.cents;
    }
    return [for (final c in out) _eur(c)];
  }

  /// Esercenti del periodo per spesa (somma delle righe), il più caro per
  /// primo. Nomi raggruppati senza distinguere maiuscole e spazi, mostrati
  /// come nello scontrino più recente.
  Future<List<MerchantTotal>> merchantTotals(DateTime from, DateTime to, {int limit = 5}) async {
    final rows = await db.customSelect(
      'SELECT r.id AS id, r.merchant AS m, COALESCE(SUM(i.total_cents), 0) AS t FROM receipts r '
      'LEFT JOIN receipt_items i ON i.receipt_id = r.id '
      'WHERE r.purchased_at >= ? AND r.purchased_at < ? GROUP BY r.id ORDER BY r.purchased_at DESC',
      variables: [Variable.withInt(_ms(from)), Variable.withInt(_ms(to))],
      readsFrom: {db.receipts, db.receiptItems},
    ).get();
    final groups = <String, ({String name, int cents, int count})>{};
    for (final r in rows) {
      final name = (r.read<String?>('m') ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      final g = groups[key];
      groups[key] = (name: g?.name ?? name, cents: (g?.cents ?? 0) + r.read<int>('t'), count: (g?.count ?? 0) + 1);
    }
    final list = groups.values.toList()..sort((a, b) => b.cents.compareTo(a.cents));
    return [for (final g in list.take(limit)) MerchantTotal(g.name, _eur(g.cents), g.count)];
  }

  // ------------------------------------------------------------- budget

  Future<List<BudgetEntry>> budgetEntries() async => [
        for (final b in await db.select(db.budgets).get())
          BudgetEntry(b.categoryId, b.fromMonth, b.amountCents == null ? null : _eur(b.amountCents!)),
      ];

  Future<MonthBudget> budgetFor(DateTime month) async => resolveBudget(await budgetEntries(), month);

  /// Imposta (o toglie, con [amount] null) il budget da [month] in poi. I
  /// mesi precedenti mantengono il budget che avevano.
  Future<void> setBudget(int? categoryId, DateTime month, double? amount) async {
    final key = monthKey(month);
    final value = amount == null || cents(amount) <= 0 ? null : cents(amount);
    await db.transaction(() async {
      final same = db.delete(db.budgets)
        ..where((b) => b.fromMonth.equals(key) & (categoryId == null ? b.categoryId.isNull() : b.categoryId.equals(categoryId)));
      await same.go();
      final previous = resolveBudget(await budgetEntries(), month).of(categoryId);
      // Uguale a quello già in vigore: nessuna riga in più.
      if ((previous == null ? null : cents(previous)) == value) return;
      await db.into(db.budgets).insert(BudgetsCompanion.insert(
            categoryId: Value(categoryId),
            fromMonth: key,
            amountCents: Value(value),
            createdAt: _nowMs,
          ));
    });
  }

  /// Spesa del mese per categoria (chiave null: righe senza categoria).
  Future<Map<int?, double>> monthSpending(DateTime month) async => {
        for (final t in await stats(from: DateTime(month.year, month.month), to: DateTime(month.year, month.month + 1)))
          t.categoryId: t.total,
      };

  /// Soglia di budget superata per prima dallo scontrino [r] appena
  /// salvato, o null.
  Future<BudgetCrossing?> budgetCrossingFor(Receipt r) async {
    final when = r.purchasedAt ?? now();
    final month = DateTime(when.year, when.month);
    final budget = await budgetFor(month);
    if (budget.isEmpty) return null;
    final after = await monthSpending(month);
    final before = Map<int?, double>.of(after);
    for (final i in r.items) {
      before[i.categoryId] = ((cents(before[i.categoryId] ?? 0) - cents(i.total)) / 100);
    }
    final crossings = budgetCrossings(budget, before, after);
    return crossings.isEmpty ? null : crossings.first;
  }

  // ------------------------------------------------------------- nuovi scontrini

  /// Possibile doppione: stesso totale e stessa data/ora (al minuto).
  Future<String?> _duplicateOf(int totalCents, int purchasedMs) async {
    final dup = await db.customSelect(
      'SELECT id FROM receipts WHERE total_cents = ? AND purchased_at BETWEEN ? AND ? '
      'ORDER BY created_at LIMIT 1',
      variables: [Variable.withInt(totalCents), Variable.withInt(purchasedMs - 60000), Variable.withInt(purchasedMs + 60000)],
    ).getSingleOrNull();
    return dup?.read<String>('id');
  }

  /// Scontrino inserito a mano (senza AI: `aiModel` resta vuoto). Le righe
  /// hanno i campi di [addItem]; il totale è la loro somma.
  Future<Receipt> createReceipt({
    String? merchant,
    required DateTime purchasedAt,
    String? paymentMethod,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) throw DataException('Serve almeno una riga');
    String? str(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    final total = items.fold<int>(0, (s, it) => s + (_cents(it['total']) ?? 0));
    final purchasedMs = _ms(purchasedAt);
    return db.transaction(() async {
      final duplicateOf = await _duplicateOf(total, purchasedMs);
      final id = newId();
      final nowMs = _nowMs;
      await db.into(db.receipts).insert(ReceiptsCompanion.insert(
            id: id,
            merchant: Value(str(merchant)),
            purchasedAt: Value(purchasedMs),
            totalCents: Value(total),
            paymentMethod: Value(str(paymentMethod)),
            notes: Value(str(notes)),
            duplicateOf: Value(duplicateOf),
            createdAt: nowMs,
            updatedAt: nowMs,
          ));
      await db.batch((b) {
        b.insertAll(db.receiptItems, [
          for (var i = 0; i < items.length; i++)
            ReceiptItemsCompanion.insert(
              id: newId(),
              receiptId: id,
              position: Value(i),
              description: _desc(items[i]['description']),
              quantity: Value(_real(items[i]['quantity'])),
              unitPriceCents: Value(_cents(items[i]['unit_price'])),
              totalCents: Value(_cents(items[i]['total']) ?? 0),
              categoryId: Value((items[i]['category_id'] as num?)?.toInt()),
              createdAt: nowMs,
            ),
        ]);
      });
      final r = await receipt(id);
      r.possibleDuplicateOf = duplicateOf;
      return r;
    });
  }

  // ------------------------------------------------------------- lettura AI

  /// Salva lo scontrino letto dall'AI ([parsed] è il JSON dello schema in
  /// lib/ai/ai_client.dart). Le categorie sono abbinate per nome, con
  /// "Altro" come ripiego; una data nel futuro diventa "adesso".
  Future<Receipt> saveScan(Map<String, dynamic> parsed, {required String model}) async {
    final cats = await db.select(db.categories).get();
    final byName = {for (final c in cats) c.name.toLowerCase(): c.id};
    final fallback = byName['altro'];

    final rawItems = parsed['items'] is List ? (parsed['items'] as List).whereType<Map>().toList() : <Map>[];
    final itemsSum = rawItems.fold<int>(0, (s, it) => s + (_cents(it['total']) ?? 0));
    final total = _cents(parsed['total']) ?? itemsSum;

    final current = now();
    var purchased = parseReceiptDate(parsed['purchased_at']);
    if (purchased != null && purchased.isAfter(current.add(const Duration(days: 1)))) purchased = null;
    final purchasedMs = _ms(purchased ?? current);

    return db.transaction(() async {
      final duplicateOf = await _duplicateOf(total, purchasedMs);

      final id = newId();
      final nowMs = _nowMs;
      String? str(dynamic v) => v == null || '$v'.trim().isEmpty ? null : '$v'.trim();
      await db.into(db.receipts).insert(ReceiptsCompanion.insert(
            id: id,
            merchant: Value(str(parsed['merchant'])),
            purchasedAt: Value(purchasedMs),
            totalCents: Value(total),
            currency: Value(_currency(parsed['currency'])),
            paymentMethod: Value(str(parsed['payment_method'])),
            aiModel: Value(model),
            aiRaw: Value(jsonEncode(parsed)),
            duplicateOf: Value(duplicateOf),
            createdAt: nowMs,
            updatedAt: nowMs,
          ));
      await db.batch((b) {
        b.insertAll(db.receiptItems, [
          for (var i = 0; i < rawItems.length; i++)
            ReceiptItemsCompanion.insert(
              id: newId(),
              receiptId: id,
              position: Value(i),
              description: _desc(str(rawItems[i]['description']) ?? '(senza descrizione)'),
              quantity: Value(_real(rawItems[i]['quantity'])),
              unitPriceCents: Value(_cents(rawItems[i]['unit_price'])),
              totalCents: Value(_cents(rawItems[i]['total']) ?? 0),
              categoryId: Value(byName['${rawItems[i]['category'] ?? ''}'.toLowerCase()] ?? fallback),
              createdAt: nowMs,
            ),
        ]);
      });
      final r = await receipt(id);
      r.possibleDuplicateOf = duplicateOf;
      return r;
    });
  }
}

/// Data letta dallo scontrino. Senza fuso orario esplicito è l'ora locale
/// del telefono; senza ora vale mezzogiorno.
DateTime? parseReceiptDate(dynamic value) {
  if (value is! String) return null;
  final s = value.trim();
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}))?)?').firstMatch(s);
  if (m == null) return null;
  if (RegExp(r'([zZ]|[+-]\d{2}:?\d{2})$').hasMatch(s)) return DateTime.tryParse(s)?.toLocal();
  int g(int i, int def) => m.group(i) == null ? def : int.parse(m.group(i)!);
  final d = DateTime(g(1, 0), g(2, 1), g(3, 1), g(4, 12), g(5, 0), g(6, 0));
  // DateTime normalizza i valori fuori intervallo (es. mese 13): li scartiamo.
  if (d.month != g(2, 1) || d.day != g(3, 1)) return null;
  return d;
}
