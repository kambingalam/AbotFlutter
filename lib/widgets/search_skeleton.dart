import 'package:flutter/material.dart';

class SearchSkeleton extends StatefulWidget {
  final int itemCount;

  const SearchSkeleton({super.key, this.itemCount = 5});

  @override
  State<SearchSkeleton> createState() => _SearchSkeletonState();
}

class _SearchSkeletonState extends State<SearchSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        return ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.itemCount,
          itemBuilder: (_, i) => _skeletonItem(onSurface),
        );
      },
    );
  }

  Widget _skeletonItem(Color onSurface) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _shimmerCircle(onSurface),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _shimmerBar(onSurface, height: 14, widthFactor: 0.6),
                const SizedBox(height: 8),
                _shimmerBar(onSurface, height: 10, widthFactor: 0.9),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shimmerCircle(Color onSurface) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            onSurface.withValues(alpha: 0.08),
            onSurface.withValues(alpha: 0.15),
            onSurface.withValues(alpha: 0.08),
          ],
          stops: [
            (_controller.value - 0.3).clamp(0.0, 1.0),
            _controller.value,
            (_controller.value + 0.3).clamp(0.0, 1.0),
          ],
        ),
      ),
    );
  }

  Widget _shimmerBar(
    Color onSurface, {
    required double height,
    required double widthFactor,
  }) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          gradient: LinearGradient(
            colors: [
              onSurface.withValues(alpha: 0.08),
              onSurface.withValues(alpha: 0.15),
              onSurface.withValues(alpha: 0.08),
            ],
            stops: [
              (_controller.value - 0.3).clamp(0.0, 1.0),
              _controller.value,
              (_controller.value + 0.3).clamp(0.0, 1.0),
            ],
          ),
        ),
      ),
    );
  }
}
