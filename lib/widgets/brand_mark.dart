import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Marchio di Scontrini (docs/design/brand/mark.svg) disegnato in vettoriale.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 64});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Scontrini',
        image: true,
        child: SizedBox.square(dimension: size, child: CustomPaint(painter: _MarkPainter())),
      );
}

class _MarkPainter extends CustomPainter {
  static const violet = Color(0xFF6A5AE0);
  static const ink = Color(0xFF14112B);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 108;
    canvas.scale(s);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 108, 108), const Radius.circular(24)),
      Paint()..color = violet,
    );
    canvas.translate(54, 54);
    canvas.rotate(-8 * math.pi / 180);
    canvas.translate(-54, -54);
    final receipt = Path()
      ..moveTo(40, 28)
      ..lineTo(68, 28)
      ..quadraticBezierTo(72, 28, 72, 32)
      ..lineTo(72, 78);
    const teeth = [67.5, 63.0, 58.5, 54.0, 49.5, 45.0, 40.5, 36.0];
    for (var i = 0; i < teeth.length; i++) {
      receipt.lineTo(teeth[i], i.isEven ? 75 : 78);
    }
    receipt
      ..lineTo(36, 32)
      ..quadraticBezierTo(36, 28, 40, 28)
      ..close();
    canvas.drawPath(receipt, Paint()..color = Colors.white);
    final line = Paint()..color = violet;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(42, 38, 24, 4), const Radius.circular(2)), line);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(42, 47, 15, 4), const Radius.circular(2)), line);
    canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(50, 61, 16, 7), const Radius.circular(3.5)), Paint()..color = ink);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
