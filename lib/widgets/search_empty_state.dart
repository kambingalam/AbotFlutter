import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'abot_face.dart';

class SearchEmptyState extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final VoidCallback? onRetry;

  const SearchEmptyState({
    super.key,
    this.title,
    this.subtitle,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Mata ABOT
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onSurface.withValues(alpha: 0.05),
              ),
              child: Center(
                child: AbotFace(
                  size: 80,
                  color: AppColors.primary.withValues(alpha: 0.6),
                  blinkInterval: const Duration(seconds: 3),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            Text(
              title ?? 'Abot gak nemu apa-apa',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),

            Text(
              subtitle ?? 'Coba kata kunci lain atau lebih spesifik',
              style: TextStyle(
                fontSize: 13,
                color: onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),

            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Coba lagi'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}