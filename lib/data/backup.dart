import 'dart:convert';

import 'package:drift/drift.dart';

import '../config.dart';
import '../models.dart';
import 'db.dart';
import 'repository.dart';

/// File di backup: un JSON con tutti i dati e le impostazioni AI non segrete.
/// La chiave API non c'è mai.
///
/// ```json
/// {"format": "scontrini-backup", "version": 1, "schema_version": 1,
///  "app_version": "2026.11.6", "created_at": "2026-11-06T10:00:00.000Z",
///  "settings": {"ai_provider": "openrouter", "ai_base_url": "", "ai_model": "..."},
///  "categories": [{"id": 1, "name": "Alimentari", "color": "#4CC38A", "sort_order": 10, "created_at": "..."}],
///  "receipts": [{"id": "...", "merchant": "...", "purchased_at": "...", "total_cents": 1250, ...,
///                "items": [{"id": "...", "position": 0, "description": "...", "total_cents": 250, ...}]}]}
/// ```
class Backup {
  static const format = 'scontrini-backup';
  static const exportFormat = 'scontrini-export';
  static const version = 1;

  /// Impostazioni salvate nel backup (mai la chiave API).
  static const settingKeys = [AppConfig.kProvider, AppConfig.kBaseUrl, AppConfig.kModel];

  static String fileName(DateTime d) =>
      'scontrini-backup-${d.year}-${_two(d.month)}-${_two(d.day)}.json';
  static String _two(int n) => n.toString().padLeft(2, '0');

  static String? _iso(int? ms) =>
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

  static Map<String, dynamic> _categoryJson(CategoryRow c) => {
        'id': c.id,
        'name': c.name,
        'color': c.color,
        'sort_order': c.sortOrder,
        'created_at': _iso(c.createdAt),
      };

  static dynamic _decode(String? s) {
    if (s == null) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return s;
    }
  }

  static Map<String, dynamic> _receiptJson(ReceiptRow r, List<ItemRow> items) => {
        'id': r.id,
        'merchant': r.merchant,
        'purchased_at': _iso(r.purchasedAt),
        'total_cents': r.totalCents,
        'currency': r.currency,
        'payment_method': r.paymentMethod,
        'notes': r.notes,
        'ai_model': r.aiModel,
        'ai_raw': _decode(r.aiRaw),
        'dismissed_warnings': _decode(r.dismissedWarnings) ?? [],
        'duplicate_of': r.duplicateOf,
        'created_at': _iso(r.createdAt),
        'updated_at': _iso(r.updatedAt),
        'items': [
          for (final i in items)
            {
              'id': i.id,
              'position': i.position,
              'description': i.description,
              'quantity': i.quantity,
              'unit_price_cents': i.unitPriceCents,
              'total_cents': i.totalCents,
              'category_id': i.categoryId,
              'created_at': _iso(i.createdAt),
            },
        ],
      };

  /// Categorie e scontrini (con data d'acquisto in [from, to) se indicati).
  static Future<Map<String, dynamic>> _data(AppDatabase db, {DateTime? from, DateTime? to}) async {
    final cats = await (db.select(db.categories)..orderBy([(c) => OrderingTerm(expression: c.sortOrder)])).get();
    final q = db.select(db.receipts)..orderBy([(r) => OrderingTerm(expression: r.purchasedAt)]);
    if (from != null) q.where((r) => r.purchasedAt.isBiggerOrEqualValue(from.toUtc().millisecondsSinceEpoch));
    if (to != null) q.where((r) => r.purchasedAt.isSmallerThanValue(to.toUtc().millisecondsSinceEpoch));
    final receipts = await q.get();
    final items = await (db.select(db.receiptItems)..orderBy([(i) => OrderingTerm(expression: i.position)])).get();
    final byReceipt = <String, List<ItemRow>>{};
    for (final i in items) {
      (byReceipt[i.receiptId] ??= []).add(i);
    }
    return {
      'categories': cats.map(_categoryJson).toList(),
      'receipts': [for (final r in receipts) _receiptJson(r, byReceipt[r.id] ?? const [])],
    };
  }

  /// Contenuto del file di backup.
  static Future<Uint8List> create(Repository repo, {required String appVersion, DateTime? now}) async {
    final settings = <String, String>{};
    for (final k in settingKeys) {
      final v = await repo.setting(k);
      if (v != null) settings[k] = v;
    }
    final json = {
      'format': format,
      'version': version,
      'schema_version': repo.db.schemaVersion,
      'app_version': appVersion,
      'created_at': (now ?? repo.now()).toUtc().toIso8601String(),
      'settings': settings,
      ...await _data(repo.db),
    };
    return Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert(json)));
  }

  /// Esportazione JSON: stessa struttura del backup, senza impostazioni.
  static Future<Uint8List> export(Repository repo, {DateTime? from, DateTime? to, required String appVersion}) async {
    final json = {
      'format': exportFormat,
      'version': version,
      'app_version': appVersion,
      'created_at': repo.now().toUtc().toIso8601String(),
      'from': from?.toUtc().toIso8601String(),
      'to': to?.toUtc().toIso8601String(),
      ...await _data(repo.db, from: from, to: to),
    };
    return Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert(json)));
  }

  /// Ripristina un backup in un'app appena installata. Tutto o niente: se il
  /// file non è valido il database resta com'era.
  static Future<RestoreSummary> restore(Repository repo, Uint8List bytes) async {
    final parsed = _parse(bytes);
    final db = repo.db;
    if (await repo.hasReceipts() || await repo.setting(AppConfig.kSetupDone) == 'true') {
      throw DataException("Il ripristino è possibile solo al primo avvio, prima di usare l'app.");
    }
    await db.transaction(() async {
      await db.delete(db.receiptItems).go();
      await db.delete(db.receipts).go();
      await db.delete(db.categories).go();
      await db.batch((b) {
        b.insertAll(db.categories, parsed.categories);
        // Prima senza doppioni, poi i riferimenti: l'ordine non conta.
        b.insertAll(db.receipts, [for (final r in parsed.receipts) r.copyWith(duplicateOf: const Value(null))]);
        b.insertAll(db.receiptItems, parsed.items);
        for (final r in parsed.receipts.where((r) => r.duplicateOf != null)) {
          b.update(db.receipts, ReceiptsCompanion(duplicateOf: Value(r.duplicateOf)),
              where: (x) => x.id.equals(r.id));
        }
        for (final e in parsed.settings.entries) {
          b.insert(db.settings, SettingsCompanion.insert(key: e.key, value: e.value), mode: InsertMode.insertOrReplace);
        }
      });
      final fk = await db.customSelect('PRAGMA foreign_key_check').get();
      if (fk.isNotEmpty) throw DataException('Il backup contiene riferimenti non validi.');
    });
    return RestoreSummary(parsed.receipts.length, parsed.categories.length, parsed.createdAt);
  }

  static _Parsed _parse(Uint8List bytes) {
    dynamic json;
    try {
      var text = utf8.decode(bytes);
      if (text.startsWith('﻿')) text = text.substring(1);
      json = jsonDecode(text);
    } catch (_) {
      throw DataException('Il file non è un backup di Scontrini.');
    }
    if (json is! Map || json['format'] != format) {
      throw DataException(json is Map && json['format'] == exportFormat
          ? "Questo file è un'esportazione, non un backup: non si può ripristinare."
          : 'Il file non è un backup di Scontrini.');
    }
    final v = json['version'];
    if (v is! int || v < 1) throw DataException('Il file non è un backup di Scontrini.');
    if (v > version) throw DataException("Il backup è stato creato da una versione più recente: aggiorna l'app.");

    T req<T>(Map m, String k) {
      final x = m[k];
      if (x is! T) throw DataException('Backup danneggiato: campo "$k" non valido.');
      return x;
    }

    int? ms(Map m, String k, {bool required = false}) {
      final x = m[k];
      if (x == null && !required) return null;
      final d = x is String ? DateTime.tryParse(x) : null;
      if (d == null) throw DataException('Backup danneggiato: data "$k" non valida.');
      return d.toUtc().millisecondsSinceEpoch;
    }

    String? str(Map m, String k) {
      final x = m[k];
      if (x == null) return null;
      if (x is! String) throw DataException('Backup danneggiato: campo "$k" non valido.');
      return x;
    }

    final categories = <CategoryRow>[];
    final catIds = <int>{};
    for (final c in req<List>(json, 'categories')) {
      if (c is! Map) throw DataException('Backup danneggiato: categoria non valida.');
      final row = CategoryRow(
        id: req<int>(c, 'id'),
        name: req<String>(c, 'name'),
        color: str(c, 'color') ?? '#8E8C9C',
        sortOrder: (c['sort_order'] as num?)?.toInt() ?? 0,
        createdAt: ms(c, 'created_at') ?? 0,
      );
      if (!catIds.add(row.id)) throw DataException('Backup danneggiato: categorie ripetute.');
      categories.add(row);
    }

    final receipts = <ReceiptRow>[];
    final items = <ItemRow>[];
    final receiptIds = <String>{};
    final itemIds = <String>{};
    for (final r in req<List>(json, 'receipts')) {
      if (r is! Map) throw DataException('Backup danneggiato: scontrino non valido.');
      final dismissed = r['dismissed_warnings'] ?? [];
      if (dismissed is! List || !dismissed.every((w) => ReceiptWarning.fromCode('$w') != null)) {
        throw DataException('Backup danneggiato: avvisi non validi.');
      }
      final created = ms(r, 'created_at', required: true)!;
      final row = ReceiptRow(
        id: req<String>(r, 'id'),
        merchant: str(r, 'merchant'),
        purchasedAt: ms(r, 'purchased_at'),
        totalCents: req<int>(r, 'total_cents'),
        currency: str(r, 'currency') ?? 'EUR',
        paymentMethod: str(r, 'payment_method'),
        notes: str(r, 'notes'),
        aiModel: str(r, 'ai_model'),
        aiRaw: r['ai_raw'] == null ? null : jsonEncode(r['ai_raw']),
        dismissedWarnings: jsonEncode(dismissed),
        duplicateOf: str(r, 'duplicate_of'),
        createdAt: created,
        updatedAt: ms(r, 'updated_at') ?? created,
      );
      if (!receiptIds.add(row.id)) throw DataException('Backup danneggiato: scontrini ripetuti.');
      receipts.add(row);
      for (final i in req<List>(r, 'items')) {
        if (i is! Map) throw DataException('Backup danneggiato: riga non valida.');
        final cat = (i['category_id'] as num?)?.toInt();
        if (cat != null && !catIds.contains(cat)) throw DataException('Backup danneggiato: categoria inesistente.');
        final item = ItemRow(
          id: req<String>(i, 'id'),
          receiptId: row.id,
          position: (i['position'] as num?)?.toInt() ?? 0,
          description: req<String>(i, 'description'),
          quantity: (i['quantity'] as num?)?.toDouble(),
          unitPriceCents: (i['unit_price_cents'] as num?)?.toInt(),
          totalCents: req<int>(i, 'total_cents'),
          categoryId: cat,
          createdAt: ms(i, 'created_at') ?? created,
        );
        if (!itemIds.add(item.id)) throw DataException('Backup danneggiato: righe ripetute.');
        items.add(item);
      }
    }
    for (final r in receipts) {
      if (r.duplicateOf != null && !receiptIds.contains(r.duplicateOf)) {
        throw DataException('Backup danneggiato: doppione inesistente.');
      }
    }

    final settings = <String, String>{};
    final s = json['settings'];
    if (s is Map) {
      for (final k in settingKeys) {
        if (s[k] is String) settings[k] = s[k] as String;
      }
    }
    return _Parsed(categories, receipts, items, settings, DateTime.tryParse('${json['created_at']}')?.toLocal());
  }
}

class _Parsed {
  final List<CategoryRow> categories;
  final List<ReceiptRow> receipts;
  final List<ItemRow> items;
  final Map<String, String> settings;
  final DateTime? createdAt;
  _Parsed(this.categories, this.receipts, this.items, this.settings, this.createdAt);
}

class RestoreSummary {
  final int receipts;
  final int categories;
  final DateTime? createdAt;
  RestoreSummary(this.receipts, this.categories, this.createdAt);
}
