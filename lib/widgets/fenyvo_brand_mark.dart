import 'dart:math' as math;

import 'package:flutter/material.dart';

class FenyvoBrandMark extends StatefulWidget {
  const FenyvoBrandMark({required this.size});
  final double size;

  @override
  State<FenyvoBrandMark> createState() => FenyvoBrandMarkState();
}

class FenyvoBrandMarkState extends State<FenyvoBrandMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation;
  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final reducedMotion = media.disableAnimations || media.accessibleNavigation;
    if (reducedMotion) {
      _rotation.stop();
    } else if (!_rotation.isAnimating) {
      _rotation.repeat();
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _rotation,
              builder: (context, child) => CustomPaint(
                painter: _FenyvoBrandPainter(
                  reducedMotion ? 0 : _rotation.value,
                ),
              ),
            ),
          ),
          Container(
            width: widget.size * .70,
            height: widget.size * .70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE6BE69).withValues(alpha: .13),
                  blurRadius: 32,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Image.asset(
              'assets/images/spartan_brand.png',
              fit: BoxFit.contain,
              semanticLabel: 'FENYVO',
            ),
          ),
        ],
      ),
    );
  }
}

class _FenyvoBrandPainter extends CustomPainter {
  const _FenyvoBrandPainter(this.phase);
  final double phase;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * .455;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final track = Paint()
      ..color = const Color(0xFF7194B5).withValues(alpha: .28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, radius, track);
    final arcPaint = Paint()
      ..color = const Color(0xFFE6BE69)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.3
      ..strokeCap = StrokeCap.round;
    final a = phase * 2 * math.pi;
    canvas.drawArc(rect, a, math.pi * .55, false, arcPaint);
    final dot = Offset(
      center.dx + radius * math.cos(a),
      center.dy + radius * math.sin(a),
    );
    canvas.drawCircle(dot, 4, Paint()..color = const Color(0xFFF4DA9E));
  }

  @override
  bool shouldRepaint(covariant _FenyvoBrandPainter oldDelegate) =>
      oldDelegate.phase != phase;
}
