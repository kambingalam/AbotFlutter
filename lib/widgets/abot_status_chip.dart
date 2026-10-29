import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AbotStatusChip extends StatelessWidget {
  final bool connected;
  final String? deviceName;
  final VoidCallback? onTap;

  const AbotStatusChip({
    super.key,
    required this.connected,
    this.deviceName,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: connected ? AppColors.success : Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              connected ? (deviceName ?? 'Abot') : 'Abot belum nyala',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: onSurface,
              ),
            ),
            if (!connected) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 16, color: onSurface),
            ],
          ],
        ),
      ),
    );
  }
}
