import 'package:flutter/material.dart';

double _d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
double? _dn(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
DateTime? _date(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

/// Avvisi su uno scontrino, in ordine di priorità (il primo è quello del badge).
enum ReceiptWarning {
  totalMismatch('total_mismatch', 'Totale da verificare'),
  duplicate('duplicate', 'Possibile doppione'),
  date('date', 'Data da verificare');

  final String code;
  final String label;
  const ReceiptWarning(this.code, this.label);

  static ReceiptWarning? fromCode(String code) {
    for (final w in values) {
      if (w.code == code) return w;
    }
    return null;
  }

  static List<ReceiptWarning> parse(dynamic v) => v is List
      ? (v.map((e) => fromCode('$e')).whereType<ReceiptWarning>().toList()..sort((a, b) => a.index - b.index))
      : <ReceiptWarning>[];
}

class Category {
  final int id;
  final String name;
  final String color;
  final int sortOrder;

  /// Numero di righe assegnate (null se l'API non lo fornisce).
  final int? itemCount;

  Category({required this.id, required this.name, required this.color, required this.sortOrder, this.itemCount});

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String,
        color: (j['color'] as String?) ?? '#8E8C9C',
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
        itemCount: (j['item_count'] as num?)?.toInt(),
      );

  Color get colorValue => hexColor(color);
}

Color hexColor(String hex, [Color fallback = const Color(0xFF8E8C9C)]) {
  final h = hex.replaceAll('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v == null ? fallback : Color(v);
}

class ReceiptItem {
  final String id;
  final int position;
  String description;
  double? quantity;
  double? unitPrice;
  double total;
  int? categoryId;

  ReceiptItem({
    required this.id,
    required this.position,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    required this.categoryId,
  });

  factory ReceiptItem.fromJson(Map<String, dynamic> j) => ReceiptItem(
        id: j['id'] as String,
        position: (j['position'] as num?)?.toInt() ?? 0,
        description: (j['description'] as String?) ?? '',
        quantity: _dn(j['quantity']),
        unitPrice: _dn(j['unit_price']),
        total: _d(j['total']),
        categoryId: (j['category_id'] as num?)?.toInt(),
      );
}

/// Riferimento all'altro scontrino di un possibile doppione.
class ReceiptRef {
  final String id;
  final String? merchant;
  final DateTime? purchasedAt;
  ReceiptRef(this.id, this.merchant, this.purchasedAt);

  static ReceiptRef? fromJson(dynamic j) =>
      j is Map ? ReceiptRef(j['id'] as String, j['merchant'] as String?, _date(j['purchased_at'])) : null;
}

class Receipt {
  final String id;
  String? merchant;
  DateTime? purchasedAt;
  DateTime? createdAt;
  double total;
  String currency;
  String? paymentMethod;
  String? notes;
  String? aiModel;
  int itemCount;
  List<ReceiptItem> items;

  /// Solo nell'elenco: somma delle righe e categoria con l'importo più alto.
  double? itemsSum;
  int? dominantCategoryId;

  /// Avvisi aperti (già esclusi quelli ignorati).
  List<ReceiptWarning> warnings;
  List<String> dismissedWarnings;
  String? duplicateOf;
  ReceiptRef? duplicate;

  /// Valorizzato solo dalla risposta di /scan se esiste già uno scontrino simile.
  String? possibleDuplicateOf;

  Receipt({
    this.possibleDuplicateOf,
    required this.id,
    this.merchant,
    this.purchasedAt,
    this.createdAt,
    required this.total,
    required this.currency,
    this.paymentMethod,
    this.notes,
    this.aiModel,
    this.itemCount = 0,
    this.items = const [],
    this.itemsSum,
    this.dominantCategoryId,
    this.warnings = const [],
    this.dismissedWarnings = const [],
    this.duplicateOf,
    this.duplicate,
  });

  factory Receipt.fromJson(Map<String, dynamic> j) {
    final rawItems = j['items'];
    var items = <ReceiptItem>[];
    var count = 0;
    if (rawItems is List) {
      if (rawItems.isNotEmpty && rawItems.first is Map && (rawItems.first as Map).containsKey('count')) {
        count = ((rawItems.first as Map)['count'] as num).toInt();
      } else {
        items = rawItems.map((e) => ReceiptItem.fromJson(e as Map<String, dynamic>)).toList();
        count = items.length;
      }
    }
    final dismissed = j['dismissed_warnings'];
    return Receipt(
      id: j['id'] as String,
      merchant: j['merchant'] as String?,
      purchasedAt: _date(j['purchased_at']),
      createdAt: _date(j['created_at']),
      total: _d(j['total']),
      currency: (j['currency'] as String?) ?? 'EUR',
      paymentMethod: j['payment_method'] as String?,
      notes: j['notes'] as String?,
      aiModel: j['ai_model'] as String?,
      itemCount: count,
      items: items,
      itemsSum: _dn(j['items_sum']),
      dominantCategoryId: (j['dominant_category_id'] as num?)?.toInt(),
      warnings: ReceiptWarning.parse(j['warnings']),
      dismissedWarnings: dismissed is List ? dismissed.map((e) => '$e').toList() : <String>[],
      duplicateOf: j['duplicate_of'] as String?,
      duplicate: ReceiptRef.fromJson(j['duplicate']),
      possibleDuplicateOf: j['possible_duplicate_of'] as String?,
    );
  }

  String get displayMerchant => merchant?.trim().isNotEmpty == true ? merchant!.trim() : 'Esercente sconosciuto';
}

class CategoryTotal {
  final int? categoryId;
  final double total;
  CategoryTotal(this.categoryId, this.total);

  factory CategoryTotal.fromJson(Map<String, dynamic> j) =>
      CategoryTotal((j['category_id'] as num?)?.toInt(), _d(j['total']));
}
