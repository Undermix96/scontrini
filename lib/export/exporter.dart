import 'dart:typed_data';

import '../data/backup.dart';
import '../data/repository.dart';
import '../format.dart';
import 'csv_export.dart';
import 'pdf_report.dart';

enum ExportFormat {
  itemsCsv('CSV righe articolo', 'Una riga per articolo, per tabelle pivot in Excel o LibreOffice', 'csv', 'text/csv'),
  receiptsCsv('CSV scontrini', 'Una riga per scontrino con totale e pagamento', 'csv', 'text/csv'),
  json('JSON completo', 'Tutti i dati, leggibili da altri programmi', 'json', 'application/json'),
  pdf('PDF riepilogo', 'Totali per categoria e per mese, da stampare', 'pdf', 'application/pdf');

  final String label;
  final String description;
  final String extension;
  final String mimeType;
  const ExportFormat(this.label, this.description, this.extension, this.mimeType);
}

/// Periodo esportato: data d'acquisto in [from, to). Null = senza limite.
class ExportPeriod {
  final DateTime? from;
  final DateTime? to;
  final String label;

  /// Parte del nome del file, es. "2026-11" o "tutto".
  final String slug;

  const ExportPeriod._(this.from, this.to, this.label, this.slug);

  static String _two(int n) => n.toString().padLeft(2, '0');

  factory ExportPeriod.month(DateTime m) =>
      ExportPeriod._(DateTime(m.year, m.month), DateTime(m.year, m.month + 1), monthLabel(m), '${m.year}-${_two(m.month)}');

  factory ExportPeriod.year(int y) => ExportPeriod._(DateTime(y), DateTime(y + 1), 'Anno $y', '$y');

  /// Dal giorno [start] al giorno [end] inclusi.
  factory ExportPeriod.range(DateTime start, DateTime end) {
    final a = DateTime(start.year, start.month, start.day);
    final b = DateTime(end.year, end.month, end.day + 1);
    String slug(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
    return ExportPeriod._(a, b, 'Dal ${longDate(a)} al ${longDate(end)}', '${slug(a)}_${slug(end)}');
  }

  static const all = ExportPeriod._(null, null, 'Tutti gli scontrini', 'tutto');
}

class ExportFile {
  final String fileName;
  final Uint8List bytes;
  final String mimeType;
  ExportFile(this.fileName, this.bytes, this.mimeType);
}

Future<ExportFile> buildExport(
  Repository repo,
  ExportFormat format,
  ExportPeriod period, {
  required String appVersion,
  Future<PdfFonts> Function()? fonts,
}) async {
  final name = switch (format) {
    ExportFormat.itemsCsv => 'scontrini-righe',
    ExportFormat.receiptsCsv => 'scontrini-elenco',
    ExportFormat.json => 'scontrini-dati',
    ExportFormat.pdf => 'scontrini-riepilogo',
  };
  final fileName = '$name-${period.slug}.${format.extension}';
  Future<Uint8List> bytes() async {
    if (format == ExportFormat.json) {
      return Backup.export(repo, from: period.from, to: period.to, appVersion: appVersion);
    }
    // Dal più vecchio al più recente: più naturale in un foglio di calcolo.
    final receipts = (await repo.receipts(from: period.from, to: period.to)).reversed.toList();
    final categories = await repo.categories();
    return switch (format) {
      ExportFormat.itemsCsv => itemsCsv(receipts, categories),
      ExportFormat.receiptsCsv => receiptsCsv(receipts),
      _ => pdfReport(
          receipts: receipts,
          categories: categories,
          periodLabel: period.label,
          fonts: await (fonts ?? PdfFonts.fromAssets)(),
          generatedAt: repo.now(),
        ),
    };
  }

  return ExportFile(fileName, await bytes(), format.mimeType);
}
