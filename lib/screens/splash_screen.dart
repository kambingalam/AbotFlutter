import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/trip_manager.dart';
import '../widgets/abot_face.dart';
import 'home_screen.dart';

enum _GpsState { loading, ready, failed }

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _routeController;
  late final AnimationController _pulseController;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _contentFade;
  late final Animation<Offset> _contentSlide;

  _GpsState _gpsState = _GpsState.loading;

  static const Color _background = Color(0xFF101A2C);
  static const Color _surface = Color(0xFF18253A);
  static const Color _accent = Color(0xFF8DB8FF);
  static const Color _accentDeep = Color(0xFF416DAA);
  static const Color _muted = Color(0xFF9AAAC1);
  static const Color _mutedDim = Color(0xFF63738C);
  static const Color _success = Color(0xFF7ED6A5);
  static const Color _error = Color(0xFFE57373);

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _routeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _logoScale = Tween<double>(begin: 0.78, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.72, curve: Curves.easeOutBack),
      ),
    );

    _logoFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    );

    _contentFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.28, 1.0, curve: Curves.easeOut),
    );

    _contentSlide =
        Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
          ),
        );

    _boot();
  }

  Future<void> _boot() async {
    final manager = context.read<TripManager>();
    final startedAt = DateTime.now();

    unawaited(_initializeGps(manager));

    await _entranceController.forward();

    const minDisplayMs = 2400;
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
    final remaining = minDisplayMs - elapsed;

    if (remaining > 0) {
      await Future.delayed(Duration(milliseconds: remaining));
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<void> _initializeGps(TripManager manager) async {
    try {
      final ok = await manager.initGps();
      if (!mounted) return;
      setState(() => _gpsState = ok ? _GpsState.ready : _GpsState.failed);
    } catch (_) {
      if (!mounted) return;
      setState(() => _gpsState = _GpsState.failed);
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _routeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  String get _statusText {
    switch (_gpsState) {
      case _GpsState.loading:
        return 'Abot bangun dulu...';
      case _GpsState.ready:
        return 'Abot siap, gass!';
      case _GpsState.failed:
        return 'Abot gak dapat GPS nih';
    }
  }

  Color get _statusColor {
    switch (_gpsState) {
      case _GpsState.loading:
        return _accent.withOpacity( 0.45 + _pulseController.value * 0.55);
      case _GpsState.ready:
        return _success;
      case _GpsState.failed:
        return _error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Stack(
        children: [
          // Background glow kanan atas.
          Positioned(
            top: -150,
            right: -110,
            child: IgnorePointer(
              child: Container(
                width: 310,
                height: 310,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _accent.withOpacity( 0.10),
                      _accent.withOpacity( 0.025),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Background glow kiri bawah.
          Positioned(
            bottom: -190,
            left: -130,
            child: IgnorePointer(
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _accentDeep.withOpacity( 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
              child: Column(
                children: [
                  // Brand label.
                  FadeTransition(
                    opacity: _contentFade,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: _accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 9),
                        const Text(
                          'ABOT MOBILITY',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 3.2,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 3),

                  // Logo ABOT dengan mata.
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final pulse = _pulseController.value;

                          return Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _surface,
                              border: Border.all(
                                color: _accent.withValues(
                                  alpha: 0.12 + pulse * 0.12,
                                ),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _accent.withValues(
                                    alpha: 0.035 + pulse * 0.035,
                                  ),
                                  blurRadius: 30 + pulse * 10,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: child,
                          );
                        },
                        child: const Center(
                          child: AbotFace(
                            size: 84,
                            color: _accent,
                            blinkInterval: Duration(seconds: 4),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 35),

                  // Brand name and tagline.
                  SlideTransition(
                    position: _contentSlide,
                    child: FadeTransition(
                      opacity: _contentFade,
                      child: Column(
                        children: [
                          const Text(
                            'ABOT Driver',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1.1,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 13),
                          Text(
                            'Abot siap nemenin perjalananmu.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _muted.withOpacity( 0.95),
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 45),

                  // Animated route illustration.
                  FadeTransition(
                    opacity: _contentFade,
                    child: SizedBox(
                      width: 230,
                      height: 48,
                      child: AnimatedBuilder(
                        animation: _routeController,
                        builder: (context, child) {
                          return CustomPaint(
                            painter: _RoutePainter(
                              progress: _routeController.value,
                              accent: _accent,
                              muted: _muted,
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  const Spacer(flex: 3),

                  // Loading indicator.
                  FadeTransition(
                    opacity: _contentFade,
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, child) {
                                return Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: _statusColor,
                                    shape: BoxShape.circle,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _statusText,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                                letterSpacing: 0.25,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        const Text(
                          'MADE FOR THE JOURNEY',
                          style: TextStyle(
                            color: _mutedDim,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final double progress;
  final Color accent;
  final Color muted;

  const _RoutePainter({
    required this.progress,
    required this.accent,
    required this.muted,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;

    final path = Path()
      ..moveTo(12, centerY)
      ..cubicTo(
        size.width * 0.22,
        centerY,
        size.width * 0.24,
        centerY - 20,
        size.width * 0.43,
        centerY - 10,
      )
      ..cubicTo(
        size.width * 0.60,
        centerY,
        size.width * 0.62,
        centerY + 19,
        size.width * 0.80,
        centerY + 8,
      )
      ..quadraticBezierTo(
        size.width * 0.90,
        centerY + 2,
        size.width - 12,
        centerY,
      );

    final basePaint = Paint()
      ..color = muted.withOpacity( 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, basePaint);

    final metrics = path.computeMetrics().toList();

    if (metrics.isNotEmpty) {
      final metric = metrics.first;
      final segmentLength = metric.length * 0.22;
      final start = (metric.length * progress) % metric.length;
      final end = start + segmentLength;

      final activePaint = Paint()
        ..color = accent.withOpacity( 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;

      if (end <= metric.length) {
        canvas.drawPath(metric.extractPath(start, end), activePaint);
      } else {
        canvas.drawPath(metric.extractPath(start, metric.length), activePaint);
        canvas.drawPath(
          metric.extractPath(0, end - metric.length),
          activePaint,
        );
      }

      final point = metric.getTangentForOffset(metric.length * progress);

      if (point != null) {
        final pointPaint = Paint()
          ..color = accent
          ..style = PaintingStyle.fill;

        canvas.drawCircle(point.position, 3, pointPaint);
      }
    }

    final endpointPaint = Paint()
      ..color = accent.withOpacity( 0.7)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(12, centerY), 3, endpointPaint);
    canvas.drawCircle(Offset(size.width - 12, centerY), 3, endpointPaint);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.accent != accent ||
        oldDelegate.muted != muted;
  }
}
