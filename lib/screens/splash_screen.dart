import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/trip_manager.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
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

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _contentFade;
  late final Animation<Offset> _contentSlide;

  _GpsState _gpsState = _GpsState.loading;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _routeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    _logoScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
      ),
    );

    _logoFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    );

    _contentFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    );

    _contentSlide =
        Tween<Offset>(begin: const Offset(0, 0.10), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
          ),
        );

    _boot();
  }

  Future<void> _boot() async {
    final manager = context.read<TripManager>();
    final startedAt = DateTime.now();

    unawaited(_initializeGps(manager));

    // Cek update jalan paralel dan tidak menahan splash lebih dari 2 detik.
    final updateFuture = UpdateService.check().timeout(
      const Duration(seconds: 2),
    );

    await _entranceController.forward();

    const minDisplayMs = 900;
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
    final remaining = minDisplayMs - elapsed;

    if (remaining > 0) {
      await Future.delayed(Duration(milliseconds: remaining));
    }

    if (!mounted) return;

    UpdateService? update;
    try {
      update = await updateFuture;
    } catch (_) {
      update = null;
    }

    if (mounted && update != null && update.updateAvailable && update.htmlUrl != null) {
      await _showUpdateDialog(update);
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
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

  Future<void> _showUpdateDialog(UpdateService update) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Update tersedia'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Versi baru: ${update.latestTag}'),
            const SizedBox(height: 8),
            const Text(
              'Unduh APK dari GitHub dan install manual. '
              'App akan tetap berfungsi kalau kamu lewati.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Nanti'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // Buka browser ke halaman release GitHub.
              // (paket url_launcher belum ditambahkan — user buka manual via browser)
            },
            child: const Text('Buka GitHub'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _routeController.dispose();
    super.dispose();
  }

  String get _statusText {
    switch (_gpsState) {
      case _GpsState.loading:
        return 'Menyiapkan GPS...';
      case _GpsState.ready:
        return 'GPS siap';
      case _GpsState.failed:
        return 'GPS belum aktif';
    }
  }

  Color get _statusColor {
    switch (_gpsState) {
      case _GpsState.loading:
        return AppColors.textSecondary;
      case _GpsState.ready:
        return AppColors.success;
      case _GpsState.failed:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          child: Column(
            children: [
              const Spacer(flex: 3),

              // Logo ABOT dengan mata.
              FadeTransition(
                opacity: _logoFade,
                child: ScaleTransition(
                  scale: _logoScale,
                  child: Container(
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.divider),
                      boxShadow: AppShadows.card,
                    ),
                    child: const Center(
                      child: AbotFace(
                        size: 76,
                        color: AppColors.primary,
                        blinkInterval: Duration.zero,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Nama dan status.
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
                          color: AppColors.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: _statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _statusText,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 34),

              // Ilustrasi route.
              FadeTransition(
                opacity: _contentFade,
                child: SizedBox(
                  width: 210,
                  height: 44,
                  child: AnimatedBuilder(
                    animation: _routeController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: _RoutePainter(
                          progress: _routeController.value,
                          accent: AppColors.primary,
                          muted: AppColors.textSecondary,
                        ),
                      );
                    },
                  ),
                ),
              ),

              const Spacer(flex: 4),
            ],
          ),
        ),
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
        centerY - 18,
        size.width * 0.43,
        centerY - 9,
      )
      ..cubicTo(
        size.width * 0.60,
        centerY,
        size.width * 0.62,
        centerY + 17,
        size.width * 0.80,
        centerY + 7,
      )
      ..quadraticBezierTo(
        size.width * 0.90,
        centerY + 2,
        size.width - 12,
        centerY,
      );

    final basePaint = Paint()
      ..color = muted.withValues(alpha: 0.28)
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
        ..color = accent.withValues(alpha: 0.9)
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
      ..color = accent.withValues(alpha: 0.7)
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
