import 'dart:async';

import 'package:flutter/material.dart';

import '../services/background_service.dart';
import '../services/haptic_service.dart';
import '../theme/app_theme.dart';

class BatteryOptimizationDialog extends StatelessWidget {
  const BatteryOptimizationDialog({super.key});

  static bool _shownThisSession = false;

  static Future<void> showIfNeeded(BuildContext context) async {
    if (_shownThisSession) return;
    if (await BackgroundService.isIgnoringBatteryOptimizations()) return;
    if (!context.mounted) return;

    _shownThisSession = true;
    await showDialog<void>(
      context: context,
      builder: (_) => const BatteryOptimizationDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      title: const Row(
        children: [
          Icon(Icons.battery_alert, color: AppColors.warning),
          SizedBox(width: 8),
          Expanded(child: Text('Optimasi Baterai')),
        ],
      ),
      content: const Text(
        'Supaya GPS dan navigasi tetap akurat saat layar mati, '
        'ABOT Driver perlu dikecualikan dari optimasi baterai.\n\n'
        'Tap "Lanjutkan", lalu pilih "Izinkan" pada dialog sistem.\n\n'
        'Di beberapa HP (Xiaomi, Oppo, Vivo, Samsung) kamu mungkin juga perlu '
        'mengaktifkan Autostart atau memilih "Tidak dibatasi" di Pengaturan '
        'baterai aplikasi.',
        style: TextStyle(height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () {
            unawaited(HapticService.tap());
            Navigator.pop(context);
          },
          child: const Text('Nanti'),
        ),
        ElevatedButton(
          onPressed: () async {
            unawaited(HapticService.tap());
            final navigator = Navigator.of(context);
            await BackgroundService.requestIgnoreBatteryOptimizations();
            if (!context.mounted) return;
            navigator.pop();
          },
          child: const Text('Lanjutkan'),
        ),
      ],
    );
  }
}
