import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../services/haptic_service.dart';
import '../theme/app_theme.dart';

class TripRouteCard extends StatefulWidget {
  final Trip trip;
  final bool selected;
  final VoidCallback onTap;

  const TripRouteCard({
    super.key,
    required this.trip,
    required this.selected,
    required this.onTap,
  });

  @override
  State<TripRouteCard> createState() => _TripRouteCardState();
}

class _TripRouteCardState extends State<TripRouteCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(
        parent: _scaleController,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeOutBack,
      ),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  Future<void> _handleTapDown(_) async {
    await _scaleController.forward();
  }

  Future<void> _handleTapUp(_) async {
    await _scaleController.reverse();
    await HapticService.select();
    widget.onTap();
  }

  Future<void> _handleTapCancel() async {
    await _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final surface = cs.surface;
    final onSurface = cs.onSurface;
    final primary = cs.primary;

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: widget.selected ? primary.withValues(alpha: 0.12) : surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: widget.selected
                  ? primary
                  : onSurface.withValues(alpha: 0.15),
              width: widget.selected ? 2 : 1,
            ),
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              // Radio button animated
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Icon(
                  widget.selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  key: ValueKey(widget.selected),
                  color: widget.selected
                      ? primary
                      : onSurface.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.trip.summary,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: widget.selected ? primary : onSurface,
                          ),
                        ),
                        if (widget.selected) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'DIPILIH',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: primary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.trip.distanceKm.toStringAsFixed(1)} km · '
                      '${widget.trip.durationMin.toStringAsFixed(0)} menit',
                      style: TextStyle(
                        fontSize: 12,
                        color: onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    if (widget.trip.viaRoads.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.trip.viaRoads,
                        style: TextStyle(
                          fontSize: 11,
                          color: onSurface.withValues(alpha: 0.5),
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
