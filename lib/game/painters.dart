import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'logic.dart';

const Color _ink = Color(0xFF0B0B0B);

class BoardPainter extends CustomPainter {
  const BoardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 3;
    final inset = cell * 0.14;
    Paint line(Offset a, Offset b) => Paint()
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..shader = ui.Gradient.linear(
        a,
        b,
        const [Color(0x00000000), Color(0xFF151515), Color(0xFF151515), Color(0x00000000)],
        const [0.0, 0.14, 0.86, 1.0],
      );
    for (var i = 1; i < 3; i++) {
      final x = cell * i;
      final v0 = Offset(x, inset);
      final v1 = Offset(x, size.height - inset);
      canvas.drawLine(v0, v1, line(v0, v1));
      final y = cell * i;
      final h0 = Offset(inset, y);
      final h1 = Offset(size.width - inset, y);
      canvas.drawLine(h0, h1, line(h0, h1));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void _tube(Canvas c, Offset a, Offset b, double w) {
  // soft drop shadow
  c.drawLine(
    a + Offset(0, w * 0.45),
    b + Offset(0, w * 0.45),
    Paint()
      ..color = const Color(0x38000000)
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.55),
  );
  // body
  c.drawLine(
    a,
    b,
    Paint()
      ..color = _ink
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round,
  );
  // specular highlight (top-left) for the subtle 3D feel
  final h = Offset(-w * 0.14, -w * 0.16);
  c.drawLine(
    a + h,
    b + h,
    Paint()
      ..color = const Color(0x3DFFFFFF)
      ..strokeWidth = w * 0.2
      ..strokeCap = StrokeCap.round,
  );
}

/// Draws an X or O that "writes itself" as [t] goes 0 → 1.
class MarkPainter extends CustomPainter {
  const MarkPainter(this.mark, this.t);

  final Mark mark;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final w = s * 0.075;
    if (mark == Mark.x) {
      final i = s * 0.27;
      final f1 = (t * 2).clamp(0.0, 1.0).toDouble();
      _tube(canvas, Offset(i, i), Offset.lerp(Offset(i, i), Offset(s - i, s - i), f1)!, w);
      if (t > 0.5) {
        final f2 = ((t - 0.5) * 2).clamp(0.0, 1.0).toDouble();
        _tube(canvas, Offset(s - i, i), Offset.lerp(Offset(s - i, i), Offset(i, s - i), f2)!, w);
      }
    } else if (mark == Mark.o) {
      final c = Offset(s / 2, s / 2);
      final r = s * 0.255;
      final sweep = 2 * pi * t;
      final rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawArc(
        rect.shift(Offset(0, w * 0.45)),
        -pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0x38000000)
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.55),
      );
      canvas.drawArc(
        rect,
        -pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _ink
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawArc(
        rect.shift(Offset(-w * 0.14, -w * 0.16)),
        -pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0x3DFFFFFF)
          ..strokeWidth = w * 0.2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant MarkPainter old) => old.t != t || old.mark != mark;
}

class WinLinePainter extends CustomPainter {
  const WinLinePainter(this.line, this.t);

  final List<int> line;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 3;
    Offset center(int i) => Offset((i % 3 + 0.5) * cell, (i ~/ 3 + 0.5) * cell);
    final a = center(line.first);
    final b = center(line.last);
    final dir = (b - a) / (b - a).distance;
    final start = a - dir * (cell * 0.3);
    final end = b + dir * (cell * 0.3);
    _tube(canvas, start, Offset.lerp(start, end, Curves.easeOutCubic.transform(t))!, 4.5);
  }

  @override
  bool shouldRepaint(covariant WinLinePainter old) => old.t != t || old.line != line;
}
