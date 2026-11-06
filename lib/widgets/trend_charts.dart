import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../format.dart';
import '../theme/tokens.dart';

/// Valore "tondo" per l'asse: 1, 2, 2,5 o 5 per una potenza di 10.
double niceCeil(double v) {
  if (v <= 0) return 1;
  final p = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  for (final m in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (v <= m * p) return m * p;
  }
  return 10 * p;
}

/// Importo breve per gli assi: "250 €", "1,2k €".
String shortMoney(double v) {
  if (v >= 1000) {
    final k = v / 1000;
    return '${k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1).replaceAll('.', ',')}k €';
  }
  return '${v.round()} €';
}

/// Etichetta con uno sfondo del colore della card, così resta leggibile
/// sopra linee e tratteggi.
void _paintLabel(Canvas canvas, TextPainter t, Offset at, Color background) {
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(at.dx - 4, at.dy - 1, t.width + 8, t.height + 2), const Radius.circular(4)),
    Paint()..color = background,
  );
  t.paint(canvas, at);
}

/// Barre della spesa mese per mese, con il mese selezionato evidenziato, la
/// media tratteggiata e, se esiste, il budget di ogni mese come trattino.
/// Toccando una barra si seleziona quel mese.
class MonthlyBarsChart extends StatelessWidget {
  final List<DateTime> months;
  final List<double> values;
  final List<double?> budgets;
  final int selected;
  final Color color;
  final ValueChanged<int>? onSelect;

  const MonthlyBarsChart({
    super.key,
    required this.months,
    required this.values,
    required this.budgets,
    required this.selected,
    required this.color,
    this.onSelect,
  });

  /// Media dei mesi con spese (i mesi vuoti all'inizio non contano).
  double get average {
    final first = values.indexWhere((v) => v > 0);
    if (first < 0) return 0;
    final used = values.sublist(first);
    return used.fold<double>(0, (a, b) => a + b) / used.length;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final avg = average;
    final semantic = [
      for (var i = 0; i < months.length; i++) '${monthLabel(months[i])} ${moneySpoken(values[i])}',
    ].join(', ');
    return Semantics(
      label: 'Spesa per mese: $semantic. Media ${moneySpoken(avg)}',
      child: LayoutBuilder(builder: (context, box) {
        const height = 190.0;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: onSelect == null
              ? null
              : (d) {
                  final i = _BarsPainter.indexAt(d.localPosition.dx, box.maxWidth, months.length);
                  if (i != null) onSelect!(i);
                },
          child: CustomPaint(
            size: Size(box.maxWidth, height),
            painter: _BarsPainter(
              months: months,
              values: values,
              budgets: budgets,
              selected: selected,
              average: avg,
              color: color,
              muted: c.outlineStrong,
              grid: c.outline,
              ink: c.onSurface,
              inkMuted: c.onSurfaceMuted,
              budgetColor: c.onSurface,
              surface: c.surface,
              textScale: MediaQuery.textScalerOf(context),
            ),
          ),
        );
      }),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<DateTime> months;
  final List<double> values;
  final List<double?> budgets;
  final int selected;
  final double average;
  final Color color, muted, grid, ink, inkMuted, budgetColor, surface;
  final TextScaler textScale;

  _BarsPainter({
    required this.months,
    required this.values,
    required this.budgets,
    required this.selected,
    required this.average,
    required this.color,
    required this.muted,
    required this.grid,
    required this.ink,
    required this.inkMuted,
    required this.budgetColor,
    required this.surface,
    required this.textScale,
  });

  static const _axisW = 44.0;
  static const _labelH = 22.0;
  static const _topH = 22.0;

  static int? indexAt(double x, double width, int n) {
    if (x < _axisW || n == 0) return null;
    final i = ((x - _axisW) / ((width - _axisW) / n)).floor();
    return i >= 0 && i < n ? i : null;
  }

  TextPainter _text(String s, TextStyle style) =>
      TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr, textScaler: textScale)
        ..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final maxV = niceCeil([...values, ...budgets.whereType<double>(), average].fold<double>(0, math.max));
    final plotTop = _topH, plotBottom = size.height - _labelH;
    final plotH = plotBottom - plotTop;
    double y(double v) => plotBottom - (v / maxV) * plotH;
    final slot = (size.width - _axisW) / n;
    final barW = math.min(18.0, slot * 0.55);

    // Griglia discreta: zero, metà, massimo.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final axisStyle = AppText.badge.copyWith(color: inkMuted, fontWeight: FontWeight.w600, fontSize: 11);
    for (final v in [0.0, maxV / 2, maxV]) {
      final yy = y(v);
      canvas.drawLine(Offset(_axisW, yy), Offset(size.width, yy), gridPaint);
      final t = _text(shortMoney(v), axisStyle);
      t.paint(canvas, Offset(_axisW - 6 - t.width, yy - t.height / 2));
    }

    // Barre: angoli superiori arrotondati, ancorate alla base.
    for (var i = 0; i < n; i++) {
      final cx = _axisW + slot * i + slot / 2;
      final v = values[i];
      if (v > 0) {
        final top = math.min(y(v), plotBottom - 2);
        final r = RRect.fromRectAndCorners(
          Rect.fromLTRB(cx - barW / 2, top, cx + barW / 2, plotBottom),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        );
        canvas.drawRRect(r, Paint()..color = i == selected ? color : muted);
      }
      // Budget del mese: trattino orizzontale.
      final b = budgets[i];
      if (b != null && b > 0) {
        final yy = y(b);
        canvas.drawLine(
          Offset(cx - slot * 0.42, yy),
          Offset(cx + slot * 0.42, yy),
          Paint()
            ..color = budgetColor
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
      }
      // Etichetta del mese: iniziale, quella selezionata in evidenza.
      final label = _text(
        monthName(months[i]).substring(0, 1).toUpperCase(),
        axisStyle.copyWith(color: i == selected ? ink : inkMuted, fontWeight: i == selected ? FontWeight.w800 : null),
      );
      label.paint(canvas, Offset(cx - label.width / 2, plotBottom + 5));
    }

    // Media tratteggiata.
    if (average > 0) {
      final yy = y(average);
      final p = Paint()
        ..color = inkMuted
        ..strokeWidth = 1.5;
      for (var x = _axisW; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, yy), Offset(math.min(x + 4, size.width), yy), p);
      }
    }

    // Valore del mese selezionato sopra la sua barra.
    final sel = selected;
    if (sel >= 0 && sel < n) {
      final cx = _axisW + slot * sel + slot / 2;
      final t = _text(money(values[sel]), AppText.label.copyWith(color: ink));
      final x = (cx - t.width / 2).clamp(_axisW + 4, size.width - t.width - 4);
      var top = values[sel] > 0 ? y(values[sel]) : plotBottom;
      final b = budgets[sel];
      if (b != null && b > 0) top = math.min(top, y(b));
      _paintLabel(canvas, t, Offset(x, math.max(0, top - t.height - 6)), surface);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values || old.selected != selected || old.budgets != budgets || old.color != color;
}

/// Spesa cumulata giorno per giorno: mese selezionato (linea piena, fino a
/// oggi se è il mese in corso) contro il mese precedente (linea tenue), con
/// la linea del budget totale se c'è.
class CumulativeChart extends StatelessWidget {
  final List<double> current;
  final List<double> previous;

  /// Giorni del mese corrente da disegnare (per il mese in corso: fino a oggi).
  final int currentDays;
  final double? budget;
  final Color color;
  final String currentLabel;
  final String previousLabel;

  const CumulativeChart({
    super.key,
    required this.current,
    required this.previous,
    required this.currentDays,
    required this.budget,
    required this.color,
    required this.currentLabel,
    required this.previousLabel,
  });

  static List<double> cumulate(List<double> daily) {
    var sum = 0.0;
    return [for (final d in daily) sum += d];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cur = cumulate(current).take(currentDays).toList();
    final prev = cumulate(previous);
    final curEnd = cur.isEmpty ? 0.0 : cur.last;
    final prevSame = prev.isEmpty ? 0.0 : prev[math.min(currentDays, prev.length) - 1];
    Widget key(Color col, String text, {bool dashed = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 16, height: dashed ? 2 : 3, color: col),
          const SizedBox(width: 6),
          Text(text, style: AppText.badge.copyWith(color: c.onSurfaceMuted)),
        ]);
    return Semantics(
      label: '$currentLabel: ${moneySpoken(curEnd)} al giorno $currentDays. '
          '$previousLabel allo stesso giorno: ${moneySpoken(prevSame)}'
          '${budget == null ? '' : '. Budget ${moneySpoken(budget!)}'}',
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: Gap.md, runSpacing: 4, children: [
          key(color, currentLabel),
          key(c.outlineStrong, previousLabel),
          if (budget != null) key(c.onSurface, 'Budget', dashed: true),
        ]),
        const SizedBox(height: Gap.sm),
        LayoutBuilder(
          builder: (context, box) => CustomPaint(
            size: Size(box.maxWidth, 170),
            painter: _CumulativePainter(
              current: cur,
              previous: prev,
              days: math.max(previous.length, current.length),
              budget: budget,
              color: color,
              previousColor: c.outlineStrong,
              grid: c.outline,
              ink: c.onSurface,
              inkMuted: c.onSurfaceMuted,
              surface: c.surface,
              textScale: MediaQuery.textScalerOf(context),
            ),
          ),
        ),
      ]),
    );
  }
}

class _CumulativePainter extends CustomPainter {
  final List<double> current, previous;
  final int days;
  final double? budget;
  final Color color, previousColor, grid, ink, inkMuted, surface;
  final TextScaler textScale;

  _CumulativePainter({
    required this.current,
    required this.previous,
    required this.days,
    required this.budget,
    required this.color,
    required this.previousColor,
    required this.grid,
    required this.ink,
    required this.inkMuted,
    required this.surface,
    required this.textScale,
  });

  static const _axisW = 44.0;
  static const _labelH = 20.0;

  TextPainter _text(String s, TextStyle style) =>
      TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr, textScaler: textScale)
        ..layout();

  @override
  void paint(Canvas canvas, Size size) {
    if (days <= 0) return;
    final maxV = niceCeil(
        [...current, ...previous, budget ?? 0].fold<double>(0, math.max));
    final top = 8.0, bottom = size.height - _labelH;
    final w = size.width - _axisW - 8;
    double x(int day) => _axisW + (days <= 1 ? 0 : (day - 1) / (days - 1) * w);
    double y(double v) => bottom - (v / maxV) * (bottom - top);

    final axisStyle = AppText.badge.copyWith(color: inkMuted, fontWeight: FontWeight.w600, fontSize: 11);
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final v in [0.0, maxV / 2, maxV]) {
      canvas.drawLine(Offset(_axisW, y(v)), Offset(size.width, y(v)), gridPaint);
      final t = _text(shortMoney(v), axisStyle);
      t.paint(canvas, Offset(_axisW - 6 - t.width, y(v) - t.height / 2));
    }
    for (final d in {1, (days / 2).round(), days}) {
      final t = _text('$d', axisStyle);
      t.paint(canvas, Offset((x(d) - t.width / 2).clamp(_axisW, size.width - t.width), bottom + 4));
    }

    if (budget != null && budget! > 0) {
      final p = Paint()
        ..color = ink
        ..strokeWidth = 1.5;
      for (var xx = _axisW; xx < size.width; xx += 8) {
        canvas.drawLine(Offset(xx, y(budget!)), Offset(math.min(xx + 4, size.width), y(budget!)), p);
      }
    }

    Path line(List<double> v) {
      final path = Path();
      for (var i = 0; i < v.length; i++) {
        final pt = Offset(x(i + 1), y(v[i]));
        i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      return path;
    }

    Paint stroke(Color col) => Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    if (previous.isNotEmpty) canvas.drawPath(line(previous), stroke(previousColor));
    if (current.isNotEmpty) {
      canvas.drawPath(line(current), stroke(color));
      // Punto finale con anello del colore della superficie ed etichetta diretta.
      final end = Offset(x(current.length), y(current.last));
      canvas.drawCircle(end, 6, Paint()..color = surface);
      canvas.drawCircle(end, 4, Paint()..color = color);
      final t = _text(money(current.last), AppText.label.copyWith(color: ink));
      final lx = (end.dx + 10).clamp(_axisW + 4, size.width - t.width - 4);
      final ly = (end.dy - t.height / 2).clamp(0.0, size.height - _labelH - t.height);
      _paintLabel(canvas, t, Offset(lx, ly), surface);
    }
  }

  @override
  bool shouldRepaint(_CumulativePainter old) =>
      old.current != current || old.previous != previous || old.budget != budget || old.color != color;
}
