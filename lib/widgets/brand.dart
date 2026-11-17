import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';

/// The app's mark: a four-player bracket (the same drawing as the launcher icon).
class BrandMark extends StatelessWidget {
  final double size;

  /// Draws the rounded dark tile behind the bracket, like the launcher icon.
  final bool tile;
  const BrandMark({super.key, this.size = 28, this.tile = false});

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _BracketPainter()),
    );
    if (!tile) return mark;
    return Container(
      padding: EdgeInsets.all(size * .22),
      decoration: BoxDecoration(
        color: Z.surface,
        borderRadius: BorderRadius.circular(size * .36),
        border: Border.all(color: Z.line),
      ),
      child: mark,
    );
  }
}

class _BracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    Offset p(double x, double y) => Offset(x * s, y * s);
    final line = Paint()
      ..color = Z.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * .075
      ..strokeJoin = StrokeJoin.miter;
    // Four entrants on the left, at these heights.
    const ys = [.14, .38, .62, .86];
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(p(.1, ys[i]), s * .085, Paint()..color = i.isEven ? Z.blue : Z.coral);
    }
    // Two semi-finals, then the final.
    for (final (a, b) in [(ys[0], ys[1]), (ys[2], ys[3])]) {
      canvas.drawPath(
        Path()
          ..moveTo(.1 * s, a * s)
          ..lineTo(.36 * s, a * s)
          ..lineTo(.36 * s, b * s)
          ..lineTo(.1 * s, b * s),
        line,
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(.36 * s, .26 * s)
        ..lineTo(.6 * s, .26 * s)
        ..lineTo(.6 * s, .74 * s)
        ..lineTo(.36 * s, .74 * s),
      line,
    );
    canvas.drawLine(p(.6, .5), p(.8, .5), line);
    canvas.drawCircle(p(.86, .5), s * .12, Paint()..color = Z.gold);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// App bar title: the mark next to the app name.
class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const BrandMark(size: 26),
      const SizedBox(width: 10),
      Flexible(child: Text(S.t.appName, overflow: TextOverflow.ellipsis)),
    ],
  );
}
