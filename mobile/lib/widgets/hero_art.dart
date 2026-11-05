import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

// Геометрическая иллюстрация (круги, полукруги, четверти и волнистые линии)
class HeroArt extends CustomPainter {
  static const _cols = [kAccent, Color(0xFF4B3FBF), Color(0xFF2A2560), Color(0xFF7AB8FF), Color(0xFF1F1B45), Color(0xFFB7A9FF)];

  @override
  void paint(Canvas c, Size s) {
    final u = s.width / 3;
    final p = Paint();
    for (var r = 0; r < (s.height / u).ceil(); r++) {
      for (var q = 0; q < 3; q++) {
        final i = r * 3 + q;
        final rect = Rect.fromLTWH(q * u, r * u, u, u).deflate(3);
        p.color = _cols[(i * 5) % 6];
        switch (i % 4) {
          case 0:
            c.drawCircle(rect.center, rect.width / 2, p);
          case 1:
            c.drawArc(rect, 0, math.pi, true, p);
          case 2:
            c.drawArc(rect, math.pi, math.pi, true, p);
          default:
            c.drawRRect(RRect.fromRectAndCorners(rect, topRight: Radius.circular(rect.width)), p);
        }
      }
    }
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0x88EDEDF2);
    for (var i = 0; i < 5; i++) {
      final dx = i * 9.0;
      c.drawPath(
        Path()
          ..moveTo(u * 0.9 + dx, 0)
          ..cubicTo(u * 0.9 + dx, u * 1.2, u * 2.0 + dx, u * 1.0, u * 2.0 + dx, u * 2.0)
          ..cubicTo(u * 2.0 + dx, u * 2.6, u * 1.2 + dx, u * 2.5, u * 1.2 + dx, s.height),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
