import 'package:flutter/material.dart';

/// Route transition: fade + scale halus.
/// Cocok untuk transisi antar screen utama.
class FadeScalePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final Duration duration;

  FadeScalePageRoute({
    required this.page,
    this.duration = const Duration(milliseconds: 400),
  }) : super(
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, animation, __, child) {
            final fade = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            );
            final scale = Tween<double>(begin: 0.92, end: 1.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
            );
            return FadeTransition(
              opacity: fade,
              child: ScaleTransition(scale: scale, child: child),
            );
          },
        );
}