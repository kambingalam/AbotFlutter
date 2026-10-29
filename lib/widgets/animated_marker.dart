
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';

class AnimatedDriverMarker extends StatefulWidget {
  final LatLng position;
  final double heading;
  final double size;

  const AnimatedDriverMarker({
    super.key,
    required this.position,
    this.heading = 0,
    this.size = 50,
  });

  @override
  State<AnimatedDriverMarker> createState() =>
      _AnimatedDriverMarkerState();
}

class _AnimatedDriverMarkerState extends State<AnimatedDriverMarker>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;

  late LatLng _currentPosition;

  LatLng? _fromPosition;
  LatLng? _toPosition;

  DateTime? _moveStart;

  double _currentHeading = 0;
  double _fromHeading = 0;
  double _toHeading = 0;

  static const Duration _moveDuration =
      Duration(milliseconds: 300);

  Timer? _animationTimer;

  @override
  void initState() {
    super.initState();

    _currentPosition = widget.position;
    _currentHeading = _normalizeHeading(widget.heading);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void didUpdateWidget(AnimatedDriverMarker oldWidget) {
    super.didUpdateWidget(oldWidget);

    final positionChanged =
        widget.position.latitude != oldWidget.position.latitude ||
        widget.position.longitude != oldWidget.position.longitude;

    final headingChanged = widget.heading != oldWidget.heading;

    if (!positionChanged && !headingChanged) return;

    // Hitung animasi dari posisi dan heading yang sedang tampil.
    _updateAnimation();
  }

  double _normalizeHeading(double heading) {
    if (!heading.isFinite || heading < 0) return 0;
    return heading % 360;
  }

  double _shortestHeading(double from, double to) {
    var difference = (to - from) % 360;

    if (difference > 180) difference -= 360;
    if (difference < -180) difference += 360;

    return from + difference;
  }

  void _updateAnimation() {
    // Batalkan timer lama agar animasi tidak berjalan bersamaan.
    _animationTimer?.cancel();

    _fromPosition = _currentPosition;
    _toPosition = widget.position;
    _moveStart = DateTime.now();

    _fromHeading = _currentHeading;
    _toHeading = _shortestHeading(
      _currentHeading,
      _normalizeHeading(widget.heading),
    );

    _tick();
  }

  void _tick() {
    if (!mounted) return;

    final start = _moveStart;
    final from = _fromPosition;
    final to = _toPosition;

    if (start == null || from == null || to == null) return;

    final elapsed = DateTime.now().difference(start);
    final progress = (elapsed.inMilliseconds /
            _moveDuration.inMilliseconds)
        .clamp(0.0, 1.0);

    // Ease-in-out supaya gerakan lebih halus.
    final t = progress * progress * (3 - 2 * progress);

    setState(() {
      _currentPosition = LatLng(
        from.latitude + (to.latitude - from.latitude) * t,
        from.longitude + (to.longitude - from.longitude) * t,
      );

      _currentHeading =
          _fromHeading + (_toHeading - _fromHeading) * t;

      if (progress >= 1.0) {
        _currentPosition = to;
        _currentHeading = _toHeading % 360;

        _fromPosition = null;
        _toPosition = null;
        _moveStart = null;
      }
    });

    if (progress < 1.0) {
      _animationTimer = Timer(
        const Duration(milliseconds: 16),
        _tick,
      );
    }
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 1.6,
      height: widget.size * 1.6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) {
              final scale = 0.6 + _pulseController.value * 0.6;
              final opacity = (1 - _pulseController.value) * 0.4;

              return Transform.scale(
                scale: scale,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(
                      alpha: opacity,
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          ),
          Transform.rotate(
            // Ikon navigation bawaan mengarah ke atas.
            // Heading 0° = utara, 90° = timur.
            angle: _currentHeading * math.pi / 180,
            child: Icon(
              Icons.navigation,
              color: AppColors.primary,
              size: widget.size,
              shadows: [
                Shadow(
                  color: Colors.black.withOpacity( 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
