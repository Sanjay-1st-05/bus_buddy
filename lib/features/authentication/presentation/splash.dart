import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:esec_bus/core/services/auth_service.dart';
import 'package:esec_bus/app/entry/app_entry.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    _controller.forward();
    _openApp();
  }

  Future<void> _openApp() async {
    await Future.wait([
      Future.delayed(const Duration(seconds: 3)),
      AuthService.restoreSession(),
    ]);

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AppEntry()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        width: double.infinity,
        color: colorScheme.primary,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SplashRoutePainter(progress: _controller.value),
                  ),
                ),
                SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(),
                      SizedBox(
                        height: 260,
                        width: double.infinity,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Transform.translate(
                              offset: Offset(
                                -84 + (_controller.value * 168),
                                72 -
                                    (math.sin(_controller.value * math.pi) *
                                        20),
                              ),
                              child: Opacity(
                                opacity: 0.18 + (_controller.value * 0.32),
                                child: const Icon(
                                  Icons.directions_bus_filled_rounded,
                                  color: Colors.white,
                                  size: 44,
                                ),
                              ),
                            ),
                            ScaleTransition(
                              scale: _scaleAnimation,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    height: 176,
                                    width: 176,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.white.withValues(
                                        alpha: 0.22,
                                      ),
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.05,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    height: 142,
                                    width: 142,
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(40),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.2,
                                          ),
                                          blurRadius: 34,
                                          offset: const Offset(0, 18),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(34),
                                      child: Image.asset(
                                        "assets/logo.jpeg",
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        "ESEC BUS",
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "College Transport Management System",
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.76),
                        ),
                      ),
                      const SizedBox(height: 84),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 28),
                        child: Text(
                          "Powered by ByZra & CODE INHALERS",
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SplashRoutePainter extends CustomPainter {
  final double progress;

  const _SplashRoutePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final routePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final activeRoutePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final route = Path()
      ..moveTo(size.width * 0.12, size.height * 0.28)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.18,
        size.width * 0.35,
        size.height * 0.42,
        size.width * 0.52,
        size.height * 0.34,
      )
      ..cubicTo(
        size.width * 0.72,
        size.height * 0.24,
        size.width * 0.78,
        size.height * 0.54,
        size.width * 0.9,
        size.height * 0.46,
      );

    canvas.drawPath(route, routePaint);
    _drawPartialPath(canvas, route, activeRoutePaint, progress);

    final lowerRoute = Path()
      ..moveTo(size.width * 0.08, size.height * 0.72)
      ..cubicTo(
        size.width * 0.26,
        size.height * 0.62,
        size.width * 0.42,
        size.height * 0.82,
        size.width * 0.58,
        size.height * 0.7,
      )
      ..cubicTo(
        size.width * 0.76,
        size.height * 0.58,
        size.width * 0.84,
        size.height * 0.82,
        size.width * 0.95,
        size.height * 0.72,
      );

    canvas.drawPath(lowerRoute, routePaint);

    _drawStop(canvas, Offset(size.width * 0.16, size.height * 0.29));
    _drawStop(canvas, Offset(size.width * 0.52, size.height * 0.34));
    _drawStop(canvas, Offset(size.width * 0.88, size.height * 0.46));
    _drawStop(canvas, Offset(size.width * 0.2, size.height * 0.71));
    _drawStop(canvas, Offset(size.width * 0.62, size.height * 0.68));
  }

  void _drawPartialPath(
    Canvas canvas,
    Path path,
    Paint paint,
    double progress,
  ) {
    final metrics = path.computeMetrics().toList(growable: false);
    for (final metric in metrics) {
      final visibleLength = metric.length * progress.clamp(0, 1);
      canvas.drawPath(metric.extractPath(0, visibleLength), paint);
    }
  }

  void _drawStop(Canvas canvas, Offset offset) {
    final outerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    final innerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.68)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(offset, 8, outerPaint);
    canvas.drawCircle(offset, 3.5, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _SplashRoutePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
