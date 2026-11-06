import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:scontrini/export/csv_export.dart';
import 'package:scontrini/export/exporter.dart';
import 'package:scontrini/export/pdf_report.dart';

import '../support/fake_app.dart';

Future<PdfFonts> _fonts() async {
  pw.Font font(String w) =>
      pw.Font.ttf(ByteData.sublistView(File('assets/fonts/Manrope-$w.ttf').readAsBytesSync()));
  return PdfFonts(font('Medium'), font('Bold'));
}

void main() {
  late FakeApp app;
  setUpAll(() => initializeDateFormatting('it_IT'));
  setUp(() async {
    app = FakeApp(now: DateTime(2026, 11, 20, 12));
    await app.seed();
  });
  tearDown(() => app.db.close());

  test('CSV: escape, BOM e CRLF', () {
    final w = CsvWriter()
      ..row(['a;b', 'virgolette "qui"', 'a capo\nqui', null, ' spazio', 'semplice'])
      ..row(['x']);
    final bytes = w.bytes();
    // BOM UTF-8 (utf8.decode lo toglie).
    expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    expect(utf8.decode(bytes), '"a;b";"virgolette ""qui""";"a capo\nqui";;" spazio";semplice\r\nx\r\n');
  });

  test('CSV: numeri e date all\'italiana', () {
    expect(csvAmount(1234.5), '1234,50');
    expect(csvAmount(-0.4), '-0,40');
    expect(csvAmount(null), '');
    expect(csvQuantity(2), '2');
    expect(csvQuantity(1.24), '1,24');
    expect(csvQuantity(0.1255), '0,126');
    expect(csvDate(DateTime(2026, 3, 7, 9, 5)), '07/03/2026');
    expect(csvTime(DateTime(2026, 3, 7, 9, 5)), '09:05');
  });

  test('CSV righe del mese, dal più vecchio', () async {
    final f = await buildExport(app.repo, ExportFormat.itemsCsv, ExportPeriod.month(DateTime(2026, 11)),
        appVersion: 'x');
    expect(f.fileName, 'scontrini-righe-2026-11.csv');
    expect(f.mimeType, 'text/csv');
    final lines = utf8.decode(f.bytes).split('\r\n')..removeLast();
    expect(lines.first, 'Data;Ora;Esercente;Descrizione;Categoria;Quantità;Prezzo unitario;Importo;Valuta;ID scontrino');
    expect(lines.length, 1 + 11);
    expect(lines[1], '19/11/2026;08:15;Bar Centrale;Cappuccino;Bevande;;;1,50;EUR;r4');
    expect(lines[2], '19/11/2026;08:15;Bar Centrale;Brioche;;;;2,80;EUR;r4');
    expect(lines, contains('20/11/2026;18:42;Esselunga;Mele Golden;Alimentari;1,24;1,99;2,47;EUR;r1'));
  });

  test('CSV scontrini con avvisi', () async {
    final f = await buildExport(app.repo, ExportFormat.receiptsCsv, ExportPeriod.all, appVersion: 'x');
    expect(f.fileName, 'scontrini-elenco-tutto.csv');
    final lines = utf8.decode(f.bytes).split('\r\n');
    expect(lines.length, 1 + 5 + 1);
    expect(lines.last, isEmpty);
    expect(lines[5], '20/11/2026;18:42;Esselunga;64,20;62,70;6;EUR;carta;;Totale da verificare;r1');
  });

  test('periodi', () {
    final y = ExportPeriod.year(2025);
    expect((y.from, y.to, y.slug), (DateTime(2025), DateTime(2026), '2025'));
    final r = ExportPeriod.range(DateTime(2026, 1, 5, 15), DateTime(2026, 1, 31, 8));
    expect((r.from, r.to, r.slug), (DateTime(2026, 1, 5), DateTime(2026, 2, 1), '2026-01-05_2026-01-31'));
    expect(ExportPeriod.all.from, isNull);
  });

  test('PDF riepilogo', () async {
    final f = await buildExport(app.repo, ExportFormat.pdf, ExportPeriod.year(2026), appVersion: 'x', fonts: _fonts);
    expect(f.fileName, 'scontrini-riepilogo-2026.pdf');
    expect(ascii.decode(f.bytes.sublist(0, 5)), '%PDF-');
    expect(f.bytes.length, greaterThan(2000));
  });

  test('PDF di un periodo vuoto', () async {
    final f = await buildExport(app.repo, ExportFormat.pdf, ExportPeriod.year(2020), appVersion: 'x', fonts: _fonts);
    expect(ascii.decode(f.bytes.sublist(0, 5)), '%PDF-');
  });
}
