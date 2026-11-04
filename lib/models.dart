import 'package:flutter/material.dart';

double _d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
double? _dn(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

class Category {
  final int id;
  final String name;
  final String color;
  final int sortOrder;

  Category({required this.id, required this.name, required this.color, required this.sortOrder});

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String,
        color: (j['color'] as String?) ?? '#607D8B',
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );

  Color get colorValue {
    final hex = color.replaceAll('#', '');
    return Color(int.tryParse('FF$hex', radix: 16) ?? 0xFF607D8B);
  }
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

class Receipt {
  final String id;
  String? merchant;
  DateTime? purchasedAt;
  double total;
  String currency;
  String? paymentMethod;
  String? notes;
  String? aiModel;
  int itemCount;
  List<ReceiptItem> items;

  Receipt({
    required this.id,
    this.merchant,
    this.purchasedAt,
    required this.total,
    required this.currency,
    this.paymentMethod,
    this.notes,
    this.aiModel,
    this.itemCount = 0,
    this.items = const [],
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
    return Receipt(
      id: j['id'] as String,
      merchant: j['merchant'] as String?,
      purchasedAt: j['purchased_at'] == null ? null : DateTime.tryParse(j['purchased_at'] as String)?.toLocal(),
      total: _d(j['total']),
      currency: (j['currency'] as String?) ?? 'EUR',
      paymentMethod: j['payment_method'] as String?,
      notes: j['notes'] as String?,
      aiModel: j['ai_model'] as String?,
      itemCount: count,
      items: items,
    );
  }
}

class CategoryTotal {
  final int? categoryId;
  final double total;
  CategoryTotal(this.categoryId, this.total);

  factory CategoryTotal.fromJson(Map<String, dynamic> j) =>
      CategoryTotal((j['category_id'] as num?)?.toInt(), _d(j['total']));
}
