import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/fenyvo_theme.dart';

/// Converts real audio measurements into a stable visual intensity.
///
/// Input is normalized audio amplitude in the interval [0, 1].
/// No artificial timer or random blinking is used.
class FenyvoHexAudioLevel {
  static const double speakingThreshold = 0.015;

  static double normalize(double value) {
    if (!value.isFinite || value <= 0) return 0;
    return value.clamp(0.0, 1.0).toDouble();
  }

  static double smooth(double previous, double incoming) {
    final oldValue = normalize(previous);
    final nextValue = normalize(incoming);
    final factor = nextValue > oldValue ? 0.65 : 0.22;
    return normalize(oldValue + (nextValue - oldValue) * factor);
  }

  static double glow(double level) {
    final safe = normalize(level);
    if (safe < speakingThreshold) return 0;
    return math.sqrt(safe).clamp(0.0, 1.0).toDouble();
  }
}

/// Gold hexagonal outline driven by a real audio-level value.
///
/// Parent supplies [level]. At zero the border remains visible but calm.
/// The drawing does not cover or intercept the video content.
class FenyvoHexAudioBorder extends StatelessWidget {
  const FenyvoHexAudioBorder({
    super.key,
    required this.level,
    this.color = FenyvoPalette.gold,
  });

  final double level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _FenyvoHexAudioBorderPainter(
          level: FenyvoHexAudioLevel.glow(level),
          color: color,
        ),
      ),
    );
  }
}

class _FenyvoHexAudioBorderPainter extends CustomPainter {
  const _FenyvoHexAudioBorderPainter({
    required this.level,
    required this.color,
  });

  final double level;
  final Color color;

  Path _hexagon(Size size) {
    final width = size.width;
    final height = size.height;

    return Path()
      ..moveTo(width * 0.5, 2)
      ..lineTo(width - 2, height * 0.25)
      ..lineTo(width - 2, height * 0.75)
      ..lineTo(width * 0.5, height - 2)
      ..lineTo(2, height * 0.75)
      ..lineTo(2, height * 0.25)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final path = _hexagon(size);
    final intensity = level.clamp(0.0, 1.0).toDouble();

    if (intensity > 0) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.25 + 0.70 * intensity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0 + 6.0 * intensity
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          4.0 + 12.0 * intensity,
        );

      canvas.drawPath(path, glowPaint);
    }

    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.90 + 0.10 * intensity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 + 1.8 * intensity
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _FenyvoHexAudioBorderPainter oldDelegate) {
    return oldDelegate.level != level || oldDelegate.color != color;
  }
}
