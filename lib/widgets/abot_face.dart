import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Wajah RoboEyes sederhana untuk app UI.
/// Bukan versi OLED — versi warna untuk layar HP.
class AbotFace extends StatefulWidget {
  final double size;
  final Color color;

  /// true = happy (mata melengkung)
  /// false = netral (mata bulat)
  final bool happy;

  /// Kecepatan auto-blink. Duration.zero = tidak pernah kedip.
  final Duration blinkInterval;

  const AbotFace({
    super.key,
    this.size = 100,
    this.color = Colors.white,
    this.happy = false,
    this.blinkInterval = const Duration(seconds: 4),
  });

  @override
  State<AbotFace> createState() => _AbotFaceState();
}

class _AbotFaceState extends State<AbotFace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blinkController;
  Timer? _blinkTimer;

  @override
  void initState() {
    super.initState();

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );

    _scheduleBlink();
  }

  void _scheduleBlink() {
    if (widget.blinkInterval == Duration.zero) return;

    final jitter = math.Random().nextInt(1500);
    _blinkTimer = Timer(
      widget.blinkInterval + Duration(milliseconds: jitter),
      () async {
        if (!mounted) return;
        await _blinkController.forward();
        await _blinkController.reverse();
        _scheduleBlink();
      },
    );
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _blinkController,
        builder: (_, _) {
          return CustomPaint(
            painter: _AbotFacePainter(
              color: widget.color,
              blink: _blinkController.value,
              happy: widget.happy,
            ),
          );
        },
      ),
    );
  }
}

class _AbotFacePainter extends CustomPainter {
  final Color color;
  final double blink; // 0 = mata terbuka, 1 = mata tertutup
  final bool happy;

  _AbotFacePainter({
    required this.color,
    required this.blink,
    required this.happy,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final eyeWidth = w * 0.26;
    final eyeHeight = h * 0.40 * (1 - blink);
    final eyeRadius = eyeWidth * 0.5;

    final leftCx = w * 0.32;
    final rightCx = w * 0.68;
    final cy = h * 0.5;

    if (happy) {
      // Mode happy: mata melengkung seperti ^ ^
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.055
        ..strokeCap = StrokeCap.round;

      final leftPath = Path()
        ..moveTo(leftCx - eyeWidth * 0.6, cy + eyeHeight * 0.15)
        ..quadraticBezierTo(
          leftCx,
          cy - eyeHeight * 0.5,
          leftCx + eyeWidth * 0.6,
          cy + eyeHeight * 0.15,
        );
      canvas.drawPath(leftPath, paint);

      final rightPath = Path()
        ..moveTo(rightCx - eyeWidth * 0.6, cy + eyeHeight * 0.15)
        ..quadraticBezierTo(
          rightCx,
          cy - eyeHeight * 0.5,
          rightCx + eyeWidth * 0.6,
          cy + eyeHeight * 0.15,
        );
      canvas.drawPath(rightPath, paint);
    } else {
      if (blink >= 0.95) {
        // Mata tertutup -> garis horizontal
        final paint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.055
          ..strokeCap = StrokeCap.round;

        canvas.drawLine(
          Offset(leftCx - eyeWidth * 0.5, cy),
          Offset(leftCx + eyeWidth * 0.5, cy),
          paint,
        );
        canvas.drawLine(
          Offset(rightCx - eyeWidth * 0.5, cy),
          Offset(rightCx + eyeWidth * 0.5, cy),
          paint,
        );
      } else {
        // Mata oval
        final paint = Paint()..color = color;

        final leftRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(leftCx, cy),
            width: eyeWidth,
            height: eyeHeight,
          ),
          Radius.circular(eyeRadius),
        );
        canvas.drawRRect(leftRect, paint);

        final rightRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(rightCx, cy),
            width: eyeWidth,
            height: eyeHeight,
          ),
          Radius.circular(eyeRadius),
        );
        canvas.drawRRect(rightRect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AbotFacePainter oldDelegate) {
    return oldDelegate.blink != blink ||
        oldDelegate.color != color ||
        oldDelegate.happy != happy;
  }
}
