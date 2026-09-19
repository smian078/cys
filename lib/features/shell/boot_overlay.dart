import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

class BootOverlay extends StatefulWidget {
  const BootOverlay({super.key});

  @override
  State<BootOverlay> createState() => _BootOverlayState();
}

class _BootOverlayState extends State<BootOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: Container(
          color: Theme.of(context).scaffoldBackgroundColor.withOpacity(.96),
          child: AnimatedBuilder(
            animation: controller,
            builder: (_, __) => CustomPaint(
              painter: _BootPainter(controller.value),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'CYSTEM',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'INITIALIZING PERSONAL OS',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: 180,
                      child: LinearProgressIndicator(value: controller.value),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${(controller.value * 100).round()}%',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BootPainter extends CustomPainter {
  const _BootPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withOpacity(.18);
    for (var i = 0; i < 7; i++) {
      final radius = 50 + i * 34 + t * 16;
      canvas.drawCircle(center, radius, ringPaint);
    }

    final rayPaint = Paint()..color = Colors.white.withOpacity(.20);
    for (var i = 0; i < 12; i++) {
      final angle = i * pi / 6 + t * pi;
      final radius = 50 + i * 22;
      canvas.drawLine(
        center,
        center + Offset(cos(angle), sin(angle)) * radius,
        rayPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BootPainter oldDelegate) => oldDelegate.t != t;
}
