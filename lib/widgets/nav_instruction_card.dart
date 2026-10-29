import 'package:flutter/material.dart';
import '../models/nav_step.dart';
import '../theme/app_theme.dart';

class NavInstructionCard extends StatefulWidget {
  final NavStep step;
  final double distanceToStep;

  const NavInstructionCard({
    super.key,
    required this.step,
    required this.distanceToStep,
  });

  @override
  State<NavInstructionCard> createState() => _NavInstructionCardState();
}

class _NavInstructionCardState extends State<NavInstructionCard>
    with TickerProviderStateMixin {
  late final AnimationController _slideController;
  late final AnimationController _distanceController;
  late final AnimationController _pulseController;

  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  late double _displayedDistance;
  double _fromDistance = 0;
  double _toDistance = 0;

  late String _lastInstruction;
  late String _lastRoad;
  late int _lastRouteIndex;

  bool get _isUrgent => widget.distanceToStep < 100;

  @override
  void initState() {
    super.initState();

    _displayedDistance = _safeDistance(widget.distanceToStep);
    _fromDistance = _displayedDistance;
    _toDistance = _displayedDistance;

    _lastInstruction = widget.step.instruction;
    _lastRoad = widget.step.road;
    _lastRouteIndex = widget.step.routeIndex;

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _distanceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0.12, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _fadeAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    );

    _slideController.forward();

    if (_isUrgent) {
      _pulseController.repeat(reverse: true);
    }
  }

  double _safeDistance(double distance) {
    if (!distance.isFinite) return 0;
    return distance.clamp(0.0, double.infinity).toDouble();
  }

  @override
  void didUpdateWidget(covariant NavInstructionCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final instructionChanged =
        widget.step.instruction != _lastInstruction ||
        widget.step.road != _lastRoad ||
        widget.step.routeIndex != _lastRouteIndex;

    if (instructionChanged) {
      _lastInstruction = widget.step.instruction;
      _lastRoad = widget.step.road;
      _lastRouteIndex = widget.step.routeIndex;

      _slideController.forward(from: 0);
    }

    final nextDistance = _safeDistance(widget.distanceToStep);
    final currentTarget = _toDistance;

    // Abaikan perubahan GPS yang terlalu kecil agar angka tidak bergetar.
    if ((nextDistance - currentTarget).abs() >= 3) {
      // Mulai dari angka yang sedang terlihat, bukan nilai animasi lama.
      final progress = Curves.easeOutCubic.transform(_distanceController.value);

      _displayedDistance =
          _fromDistance + (_toDistance - _fromDistance) * progress;

      _fromDistance = _displayedDistance;
      _toDistance = nextDistance;

      _distanceController.forward(from: 0);
    }

    // Pulse hanya berjalan saat mendekati belokan.
    if (_isUrgent && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!_isUrgent && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    _distanceController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  IconData _icon() {
    final instruction = widget.step.instruction.toUpperCase();

    // Periksa PUTARAN terlebih dahulu agar tidak tertukar dengan U-turn.
    if (instruction.contains('PUTARAN')) {
      return Icons.roundabout_left;
    }

    if (instruction.contains('PUTAR BALIK')) {
      return Icons.u_turn_left;
    }

    if (instruction.contains('KIRI')) {
      return Icons.turn_left;
    }

    if (instruction.contains('KANAN')) {
      return Icons.turn_right;
    }

    if (instruction.contains('GABUNG')) {
      return Icons.merge;
    }

    return Icons.straight;
  }

  Color _cardColor() {
    return _isUrgent ? const Color(0xFFFB8C00) : AppColors.primary;
  }

  String _formatDistance(double meters) {
    final safeMeters = _safeDistance(meters);

    if (safeMeters >= 1000) {
      return '${(safeMeters / 1000).toStringAsFixed(1)} km';
    }

    return '${safeMeters.round()} m';
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = _cardColor();

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: [
              BoxShadow(
                color: cardColor.withValues(alpha: 0.30),
                blurRadius: _isUrgent ? 20 : 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                child: Icon(_icon(), color: Colors.white, size: 56),
                builder: (context, child) {
                  final scale = _isUrgent
                      ? 1.0 + (_pulseController.value * 0.07)
                      : 1.0;

                  return Transform.scale(scale: scale, child: child);
                },
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedBuilder(
                      animation: _distanceController,
                      builder: (context, child) {
                        final progress = Curves.easeOutCubic.transform(
                          _distanceController.value,
                        );

                        final currentDistance =
                            _fromDistance +
                            (_toDistance - _fromDistance) * progress;

                        if (_distanceController.isCompleted) {
                          _displayedDistance = _toDistance;
                        }

                        return Text(
                          _formatDistance(currentDistance),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.step.instruction,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.step.road.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.step.road,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
