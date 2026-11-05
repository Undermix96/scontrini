import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class DonutSegment {
  final double value;
  final Color color;
  const DonutSegment(this.value, this.color);
}

/// Grafico a ciambella: segmenti da ore 12 in senso orario, con 3 di spazio.
class DonutChart extends StatelessWidget {
  final List<DonutSegment> segments;
  final String centerLabel;
  final String centerValue;
  final String semanticLabel;
  final double size;

  const DonutChart({
    super.key,
    required this.segments,
    required this.centerLabel,
    required this.centerValue,
    required this.semanticLabel,
    this.size = 168,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: semanticLabel,
      image: true,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _DonutPainter(segments, c.surfaceHigh),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(centerLabel, style: AppText.badge.copyWith(color: c.onSurfaceMuted)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(centerValue,
                      style: AppText.amountLarge.copyWith(fontSize: 22, letterSpacing: -0.5, color: c.onSurface)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<DonutSegment> segments;
  final Color track;
  _DonutPainter(this.segments, this.track);

  static const stroke = 18.0;
  static const gap = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2 * (70 / 84);
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: radius);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawCircle(rect.center, radius, p..color = track);
    final positive = segments.where((s) => s.value > 0).toList();
    final total = positive.fold<double>(0, (t, s) => t + s.value);
    if (total <= 0) return;
    final gapAngle = positive.length > 1 ? gap / radius : 0.0;
    var start = -math.pi / 2;
    for (final s in positive) {
      final sweep = s.value / total * 2 * math.pi;
      final drawn = sweep - gapAngle;
      if (drawn > 0) canvas.drawArc(rect, start + gapAngle / 2, drawn, false, p..color = s.color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.segments != segments || old.track != track;
}
