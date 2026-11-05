import 'package:intl/intl.dart';

String money(double v, [String currency = 'EUR']) =>
    NumberFormat.currency(locale: 'it_IT', name: currency, symbol: currency == 'EUR' ? '€' : currency).format(v);

/// Importo per il lettore di schermo: "64,20 euro".
String moneySpoken(double v, [String currency = 'EUR']) =>
    '${NumberFormat.decimalPatternDigits(locale: 'it_IT', decimalDigits: 2).format(v)} ${currency == 'EUR' ? 'euro' : currency}';

String dateTime(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy, HH:mm', 'it_IT').format(d);

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String dayLabel(DateTime d) => DateFormat('EEEE d MMMM', 'it_IT').format(d);

/// Intestazione dei gruppi per giorno: "Oggi · giovedì 5", "Ieri · mercoledì 4", "Martedì 3".
/// L'elenco mostra un mese alla volta, quindi il mese non serve.
String dayHeader(DateTime d, {DateTime? now}) {
  now ??= DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  final weekday = DateFormat('EEEE d', 'it_IT').format(d);
  if (diff == 0) return 'Oggi · $weekday';
  if (diff == 1) return 'Ieri · $weekday';
  return _cap(weekday);
}

/// "Gio 5 novembre 2026 · 18:42"
String longDateTime(DateTime? d) {
  if (d == null) return 'Data sconosciuta';
  final wd = DateFormat('EEE', 'it_IT').format(d).replaceAll('.', '');
  return '${_cap(wd)} ${DateFormat('d MMMM yyyy · HH:mm', 'it_IT').format(d)}';
}

/// "5 novembre 2026"
String longDate(DateTime? d) => d == null ? '—' : DateFormat('d MMMM yyyy', 'it_IT').format(d);

String monthLabel(DateTime d) => _cap(DateFormat('MMMM yyyy', 'it_IT').format(d));

/// "novembre"
String monthName(DateTime d) => DateFormat('MMMM', 'it_IT').format(d);

/// "Nov 2026"
String shortMonthLabel(DateTime d) => _cap(DateFormat('MMM yyyy', 'it_IT').format(d).replaceAll('.', ''));

/// Quantità senza decimali inutili: 2 → "2", 1.24 → "1,24".
String quantity(double q) => q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toString().replaceAll('.', ',');

/// Interpreta un importo scritto dall'utente ("12,50", "12.5", "-1,20").
double? parseAmount(String s) {
  final t = s.trim().replaceAll('€', '').replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}
