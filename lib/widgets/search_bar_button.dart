import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SearchBarButton extends StatelessWidget {
  final String? text;
  final VoidCallback onTap;

  const SearchBarButton({super.key, this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: AppShadows.floating,
        ),
        child: Row(
          children: [
            Icon(Icons.search, color: onSurface.withOpacity( 0.6)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text ?? 'Mau ke mana hari ini?',
                style: TextStyle(
                  color: text == null
                      ? onSurface.withOpacity( 0.6)
                      : onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.mic, color: onSurface.withOpacity( 0.6)),
          ],
        ),
      ),
    );
  }
}
