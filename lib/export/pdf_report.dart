import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../format.dart';
import '../models.dart';
import '../warnings.dart';

/// Font Manrope inclusi nell'app (servono per €, accenti e grassetto).
class PdfFonts {
  final pw.Font regular;
  final pw.Font bold;
  PdfFonts(this.regular, this.bold);

  static Future<PdfFonts> fromAssets() async => PdfFonts(
        pw.Font.ttf(await rootBundle.load('assets/fonts/Manrope-Medium.ttf')),
        pw.Font.ttf(await rootBundle.load('assets/fonts/Manrope-Bold.ttf')),
      );
}

/// Riepilogo stampabile del periodo: totale, spese per categoria, per mese
/// (se il periodo ne copre più di uno) ed elenco degli scontrini.
Future<Uint8List> pdfReport({
  required List<Receipt> receipts,
  required List<Category> categories,
  required String periodLabel,
  required PdfFonts fonts,
  DateTime? generatedAt,
}) {
  final muted = PdfColor.fromInt(0xFF6B6878);
  final line = PdfColor.fromInt(0xFFDDDBE3);
  final doc = pw.Document(
    title: 'Scontrini · $periodLabel',
    creator: 'Scontrini',
    theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
  );

  // Totali: per scontrino (quanto pagato) e per categoria (somma delle righe).
  final totalCents = receipts.fold<int>(0, (s, r) => s + cents(r.total));
  final byCat = <int?, int>{};
  for (final r in receipts) {
    for (final i in r.items) {
      byCat[i.categoryId] = (byCat[i.categoryId] ?? 0) + cents(i.total);
    }
  }
  final itemsCents = byCat.values.fold<int>(0, (s, v) => s + v);
  final names = {for (final c in categories) c.id: c.name};
  final catRows = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  final byMonth = <DateTime, (int, int)>{};
  for (final r in receipts) {
    final d = r.purchasedAt;
    if (d == null) continue;
    final m = DateTime(d.year, d.month);
    final (n, t) = byMonth[m] ?? (0, 0);
    byMonth[m] = (n + 1, t + cents(r.total));
  }
  final months = byMonth.keys.toList()..sort();

  final sorted = [...receipts]..sort((a, b) => (a.purchasedAt ?? DateTime(0)).compareTo(b.purchasedAt ?? DateTime(0)));
  String eur(int c) => money(c / 100);
  String pct(int c) => itemsCents == 0 ? '' : '${(c * 100 / itemsCents).toStringAsFixed(1).replaceAll('.', ',')} %';

  pw.Widget heading(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget table(List<String> headers, List<List<String>> rows, {Set<int> right = const {}}) => pw.TableHelper.fromTextArray(
        headers: headers,
        data: rows,
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: line, width: 0.5)),
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: muted),
        cellStyle: const pw.TextStyle(fontSize: 9.5),
        headerDecoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: line))),
        headerAlignment: pw.Alignment.centerLeft,
        cellAlignment: pw.Alignment.centerLeft,
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        cellAlignments: {for (final i in right) i: pw.Alignment.centerRight},
        headerAlignments: {for (final i in right) i: pw.Alignment.centerRight},
      );

  final now = generatedAt ?? DateTime.now();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 36),
    footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('Scontrini · creato il ${DateFormat('d MMMM yyyy, HH:mm', 'it_IT').format(now)}',
          style: pw.TextStyle(fontSize: 8, color: muted)),
      pw.Text('Pagina ${ctx.pageNumber} di ${ctx.pagesCount}', style: pw.TextStyle(fontSize: 8, color: muted)),
    ]),
    build: (ctx) => [
      pw.Text('Riepilogo spese', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 2),
      pw.Text(periodLabel, style: pw.TextStyle(fontSize: 12, color: muted)),
      pw.SizedBox(height: 14),
      pw.Row(children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Totale speso', style: pw.TextStyle(fontSize: 9, color: muted)),
            pw.Text(eur(totalCents), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Scontrini', style: pw.TextStyle(fontSize: 9, color: muted)),
            pw.Text('${receipts.length}', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
      ]),
      if (receipts.isEmpty) ...[
        pw.SizedBox(height: 24),
        pw.Text('Nessuno scontrino in questo periodo.', style: pw.TextStyle(color: muted)),
      ] else ...[
        heading('Per categoria'),
        table(
          ['Categoria', 'Importo', '%'],
          [
            for (final e in catRows) [e.key == null ? 'Senza categoria' : (names[e.key] ?? 'Categoria eliminata'), eur(e.value), pct(e.value)],
          ],
          right: {1, 2},
        ),
        if (itemsCents != totalCents)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
              'Le righe sommano ${eur(itemsCents)}: la differenza con il totale viene da scontrini da verificare.',
              style: pw.TextStyle(fontSize: 8, color: muted),
            ),
          ),
        if (months.length > 1) ...[
          heading('Per mese'),
          table(
            ['Mese', 'Scontrini', 'Totale'],
            [
              for (final m in months) [monthLabel(m), '${byMonth[m]!.$1}', eur(byMonth[m]!.$2)],
            ],
            right: {1, 2},
          ),
        ],
        heading('Scontrini'),
        table(
          ['Data', 'Esercente', 'Pagamento', 'Totale'],
          [
            for (final r in sorted)
              [
                r.purchasedAt == null ? '—' : DateFormat('dd/MM/yyyy HH:mm').format(r.purchasedAt!),
                r.displayMerchant,
                r.paymentMethod ?? '',
                money(r.total, r.currency),
              ],
          ],
          right: {3},
        ),
      ],
    ],
  ));
  return doc.save();
}
