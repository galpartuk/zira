import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Pips of a d6 face (1-6), drawn on a rounded square.
class DieFace extends StatelessWidget {
  final int value;
  final double size;
  final Color color;
  final Color pip;
  const DieFace({super.key, required this.value, this.size = 120, this.color = Z.text, this.pip = Z.ink});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _DiePainter(value, color, pip));
}

class _DiePainter extends CustomPainter {
  final int v;
  final Color color, pip;
  _DiePainter(this.v, this.color, this.pip);

  static const _layout = {
    1: [(1, 1)],
    2: [(0, 0), (2, 2)],
    3: [(0, 0), (1, 1), (2, 2)],
    4: [(0, 0), (2, 0), (0, 2), (2, 2)],
    5: [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)],
    6: [(0, 0), (2, 0), (0, 1), (2, 1), (0, 2), (2, 2)],
  };

  @override
  void paint(Canvas canvas, Size s) {
    final r = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.width * .2));
    canvas.drawRRect(r, Paint()..color = color);
    final p = Paint()..color = pip;
    // Grid columns/rows at 25% / 50% / 75% of the face, symmetric about the centre.
    for (final (x, y) in _layout[v] ?? const <(int, int)>[]) {
      canvas.drawCircle(Offset(s.width * (.5 + (x - 1) * .25), s.height * (.5 + (y - 1) * .25)), s.width * .085, p);
    }
  }

  @override
  bool shouldRepaint(_DiePainter o) => o.v != v || o.color != color;
}

class DieIcon extends StatelessWidget {
  const DieIcon({super.key});
  @override
  Widget build(BuildContext context) => Transform.rotate(angle: -.2, child: const DieFace(value: 5, size: 42, color: Z.gold));
}

class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [Color(0xFFFFE08A), Color(0xFFC8962E)]),
          border: Border.all(color: const Color(0xFF8F6A1C), width: 2),
        ),
        alignment: Alignment.center,
        child: const Text('₪', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: Color(0xFF6B4D10))),
      );
}

/// A miniature memory gauge.
class GaugeIcon extends StatelessWidget {
  const GaugeIcon({super.key});
  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(34, 84), painter: _GaugeIconPainter());
}

class _GaugeIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    const n = 9;
    final h = s.height / n;
    for (var i = 0; i < n; i++) {
      final c = i < n ~/ 2 ? Z.coral : (i == n ~/ 2 ? Z.text : Z.blue);
      final active = i == 6;
      final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(active ? 0 : 6, i * h + 1, s.width - (active ? 0 : 12), h - 2), const Radius.circular(3));
      canvas.drawRRect(rect, Paint()..color = c.withValues(alpha: active ? 1 : (i == n ~/ 2 ? .6 : .3)));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Polygon outline for non-d6 dice with the number inside.
class PolyDie extends StatelessWidget {
  final int sides;
  final int value;
  final double size;
  final Color color;
  const PolyDie({super.key, required this.sides, required this.value, this.size = 120, this.color = Z.gold});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _PolyPainter(sides, color),
        child: Center(
          child: Text('$value',
              style: TextStyle(
                  fontSize: size * .34, fontWeight: FontWeight.w800, color: Z.ink, fontFeatures: Z.tabular)),
        ),
      ),
    );
  }
}

class _PolyPainter extends CustomPainter {
  final int sides;
  final Color color;
  _PolyPainter(this.sides, this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final corners = switch (sides) { 4 => 3, 8 => 4, 10 => 5, 12 => 5, 20 => 6, _ => 6 };
    final c = s.center(Offset.zero);
    final r = s.width / 2;
    final path = Path();
    for (var i = 0; i < corners; i++) {
      final a = -pi / 2 + 2 * pi * i / corners;
      final pt = c + Offset(cos(a), sin(a)) * r;
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withValues(alpha: .25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_PolyPainter o) => o.sides != sides || o.color != color;
}
