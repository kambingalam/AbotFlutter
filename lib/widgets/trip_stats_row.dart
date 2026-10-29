import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class TripStatsRow extends StatelessWidget {
  final String distance;
  final String eta;
  final String? label;

  const TripStatsRow({
    super.key,
    required this.distance,
    required this.eta,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            _stat(Icons.route, distance, 'Jarak'),
            const SizedBox(width: 24),
            _stat(Icons.access_time, eta, 'ETA'),
          ],
        ),
      ],
    );
  }

  Widget _stat(IconData icon, String value, String label) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}