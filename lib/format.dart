import 'package:intl/intl.dart';

String money(double v, [String currency = 'EUR']) =>
    NumberFormat.currency(locale: 'it_IT', name: currency, symbol: currency == 'EUR' ? '€' : currency).format(v);

String dateTime(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy, HH:mm', 'it_IT').format(d);

String dayLabel(DateTime d) => DateFormat('EEEE d MMMM', 'it_IT').format(d);

String monthLabel(DateTime d) {
  final s = DateFormat('MMMM yyyy', 'it_IT').format(d);
  return s[0].toUpperCase() + s.substring(1);
}
