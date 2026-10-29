import 'dart:async';

import 'package:flutter/material.dart';

import '../services/haptic_service.dart';

class VoiceSearchButton extends StatelessWidget {
  final bool listening;
  final VoidCallback onTap;

  const VoiceSearchButton({
    super.key,
    required this.listening,
    required this.onTap,
  });

  static const double _size = 44;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.primary;
    final onSurface = scheme.onSurface;

    return Semantics(
      button: true,
      label: listening ? 'Berhenti mendengarkan' : 'Cari dengan suara',
      child: Tooltip(
        message: listening ? 'Berhenti mendengarkan' : 'Cari dengan suara',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            // Fire and forget: haptic lambat/error tidak boleh menunda aksi utama.
            unawaited(HapticService.tap());
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              color: listening
                  ? primary.withValues(alpha: 0.15)
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Stack(
              clipBehavior: Clip.none, // ring boleh melebihi 44px
              alignment: Alignment.center,
              children: [
                // Pulse ring saat listening
                if (listening)
                  RepaintBoundary(
                    child: _PulsingRing(color: primary, size: _size),
                  ),
                Icon(
                  listening ? Icons.mic : Icons.mic_none,
                  color: listening ? primary : onSurface.withValues(alpha: 0.6),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingRing extends StatefulWidget {
  final Color color;
  final double size;

  const _PulsingRing({required this.color, required this.size});

  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final scale = 0.6 + _controller.value * 0.6;
          final opacity = (1 - _controller.value) * 0.5;

          return Transform.scale(
            scale: scale,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: opacity),
              ),
            ),
          );
        },
      ),
    );
  }
}
