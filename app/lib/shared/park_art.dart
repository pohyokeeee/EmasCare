import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A quiet, code-native illustration; no remote image or network dependency.
class ParkArt extends StatelessWidget {
  const ParkArt({super.key, this.garden = false, this.dark = false});
  final bool garden, dark;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      painter: _ParkPainter(garden, dark),
      size: Size.infinite,
    ),
  );
}

class _ParkPainter extends CustomPainter {
  _ParkPainter(this.garden, this.dark);
  final bool garden, dark;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final scale = math.max(size.width / 420, size.height / 240);
    canvas.clipRect(Offset.zero & size);
    canvas.translate(
      (size.width - 420 * scale) / 2,
      (size.height - 240 * scale) / 2,
    );
    canvas.scale(scale);
    final paint = Paint();
    void rect(Rect r, Color c) {
      paint.color = c;
      canvas.drawRect(r, paint);
    }

    void circle(Offset p, double r, Color c) {
      paint.color = c;
      canvas.drawCircle(p, r, paint);
    }

    void path(Path p, Color c) {
      paint.color = c;
      canvas.drawPath(p, paint);
    }

    rect(
      const Rect.fromLTWH(0, 0, 420, 240),
      dark ? const Color(0xFF315D4B) : const Color(0xFFE8EEE0),
    );
    circle(const Offset(331, 45), 24, const Color(0xFFE4C98E));
    path(
      Path()
        ..moveTo(0, 141)
        ..quadraticBezierTo(80, 80, 215, 145)
        ..quadraticBezierTo(330, 85, 420, 130)
        ..lineTo(420, 240)
        ..lineTo(0, 240)
        ..close(),
      dark ? const Color(0xFF48705A) : const Color(0xFFB7C9AA),
    );
    path(
      Path()
        ..moveTo(0, 192)
        ..quadraticBezierTo(145, 115, 285, 178)
        ..quadraticBezierTo(350, 150, 420, 174)
        ..lineTo(420, 240)
        ..lineTo(0, 240)
        ..close(),
      dark ? const Color(0xFF5E8065) : const Color(0xFF94B088),
    );
    path(
      Path()
        ..moveTo(226, 137)
        ..quadraticBezierTo(165, 178, 278, 204)
        ..quadraticBezierTo(305, 218, 268, 240)
        ..lineTo(383, 240)
        ..quadraticBezierTo(388, 198, 296, 185)
        ..quadraticBezierTo(202, 163, 243, 137)
        ..close(),
      const Color(0xFFDAD5B6),
    );
    for (final data in [
      (50.0, 113.0, 42.0),
      (114.0, 105.0, 28.0),
      (368.0, 131.0, 32.0),
    ]) {
      rect(Rect.fromLTWH(data.$1 - 2, data.$2, 4, 53), const Color(0xFF57705A));
      circle(
        Offset(data.$1, data.$2 - 10),
        data.$3,
        dark ? const Color(0xFF7B9775) : const Color(0xFF718F68),
      );
      circle(
        Offset(data.$1 - 8, data.$2 - 18),
        data.$3 * .7,
        dark ? const Color(0xFF8FA784) : const Color(0xFF8FA97D),
      );
    }
    if (garden) {
      for (var i = 0; i < 3; i++) {
        final x = 82.0 + i * 62;
        canvas.save();
        canvas.translate(x, 190);
        canvas.rotate(-.12);
        rect(const Rect.fromLTWH(0, 0, 46, 20), const Color(0xFFAD9771));
        rect(const Rect.fromLTWH(3, 0, 40, 10), const Color(0xFF687D52));
        for (var j = 0; j < 3; j++) {
          circle(Offset(10 + j * 12, -2), 5, const Color(0xFF435F42));
        }
        canvas.restore();
      }
    } else {
      void person(double x, double y, Color coat) {
        circle(Offset(x, y - 29), 6, const Color(0xFFE0BA90));
        paint
          ..color = coat
          ..strokeWidth = 11
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(x, y - 18), Offset(x, y), paint);
        paint
          ..color = const Color(0xFF344F43)
          ..strokeWidth = 4;
        canvas.drawLine(Offset(x - 2, y + 4), Offset(x - 5, y + 20), paint);
        canvas.drawLine(Offset(x + 3, y + 4), Offset(x + 8, y + 19), paint);
        paint.strokeWidth = 3;
        canvas.drawLine(Offset(x - 2, y - 17), Offset(x - 10, y - 5), paint);
      }

      person(234, 177, const Color(0xFFF0E8CF));
      person(261, 179, const Color(0xFFC39762));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ParkPainter old) =>
      old.garden != garden || old.dark != dark;
}
