import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../models.dart';

/// CSV per Excel/LibreOffice in italiano: separatore `;`, virgola decimale,
/// date gg/mm/aaaa, UTF-8 con BOM (così Excel riconosce gli accenti) e
/// righe terminate da CRLF.
class CsvWriter {
  final _buf = StringBuffer('﻿');

  static String escape(String v) {
    if (v.contains(RegExp(r'[;"\r\n]')) || v.startsWith(' ') || v.endsWith(' ')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  void row(List<String?> cells) {
    _buf.write(cells.map((c) => escape(c ?? '')).join(';'));
    _buf.write('\r\n');
  }

  Uint8List bytes() => Uint8List.fromList(utf8.encode(_buf.toString()));
}

final _date = DateFormat('dd/MM/yyyy');
final _time = DateFormat('HH:mm');

String csvDate(DateTime? d) => d == null ? '' : _date.format(d);
String csvTime(DateTime? d) => d == null ? '' : _time.format(d);

/// 12.5 → "12,50" (niente separatore delle migliaia: lo interpreterebbe male).
String csvAmount(double? v) => v == null ? '' : v.toStringAsFixed(2).replaceAll('.', ',');

String csvQuantity(double? v) {
  if (v == null) return '';
  var s = v.toStringAsFixed(3);
  s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return s.replaceAll('.', ',');
}

/// Una riga per articolo. [receipts] devono avere le righe caricate.
Uint8List itemsCsv(List<Receipt> receipts, List<Category> categories) {
  final names = {for (final c in categories) c.id: c.name};
  final w = CsvWriter()
    ..row([
      'Data',
      'Ora',
      'Esercente',
      'Descrizione',
      'Categoria',
      'Quantità',
      'Prezzo unitario',
      'Importo',
      'Valuta',
      'ID scontrino',
    ]);
  for (final r in receipts) {
    for (final i in r.items) {
      w.row([
        csvDate(r.purchasedAt),
        csvTime(r.purchasedAt),
        r.merchant,
        i.description,
        i.categoryId == null ? '' : names[i.categoryId],
        csvQuantity(i.quantity),
        csvAmount(i.unitPrice),
        csvAmount(i.total),
        r.currency,
        r.id,
      ]);
    }
  }
  return w.bytes();
}

/// Una riga per scontrino.
Uint8List receiptsCsv(List<Receipt> receipts) {
  final w = CsvWriter()
    ..row([
      'Data',
      'Ora',
      'Esercente',
      'Totale',
      'Somma righe',
      'Righe',
      'Valuta',
      'Pagamento',
      'Note',
      'Avvisi',
      'ID scontrino',
    ]);
  for (final r in receipts) {
    w.row([
      csvDate(r.purchasedAt),
      csvTime(r.purchasedAt),
      r.merchant,
      csvAmount(r.total),
      csvAmount(r.itemsSum),
      '${r.itemCount}',
      r.currency,
      r.paymentMethod,
      r.notes,
      r.warnings.map((w) => w.label).join(', '),
      r.id,
    ]);
  }
  return w.bytes();
}
