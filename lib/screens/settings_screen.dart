import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/haptic_service.dart';
import '../services/ota_service.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart';
import '../widgets/firmware_ota_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  String _themeLabel(AppTheme theme) {
    switch (theme) {
      case AppTheme.light:
        return 'Terang';
      case AppTheme.dark:
        return 'Gelap';
      case AppTheme.system:
        return 'Ikuti sistem';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final tts = context.watch<TtsService>();
    final ota = context.watch<OtaService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ============================================================
          // SUARA
          // ============================================================
          const _SectionHeader(icon: Icons.volume_up_rounded, title: 'Suara'),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_rounded),
            title: const Text('Suara Navigasi'),
            subtitle: const Text('Instruksi suara belokan dan tujuan'),
            value: settings.ttsEnabled,
            onChanged: (v) async {
              await HapticService.select();
              // Tunggu simpan selesai, lalu sinkronkan TTS dengan nilai
              // yang benar-benar tersimpan (jika gagal simpan, tidak beda).
              await settings.setTtsEnabled(v);
              tts.setEnabled(settings.ttsEnabled);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.record_voice_over_rounded),
            title: const Text('Ucapkan "sekarang"'),
            subtitle: const Text('Ucapkan "Belok sekarang" saat jarak < 50m'),
            value: settings.speakNearNow,
            onChanged: settings.ttsEnabled
                ? (v) async {
                    await HapticService.select();
                    await settings.setSpeakNearNow(v);
                    tts.setSpeakNearNow(settings.speakNearNow);
                  }
                : null,
          ),

          // ============================================================
          // TAMPILAN
          // ============================================================
          const _SectionHeader(icon: Icons.palette_rounded, title: 'Tampilan'),
          ListTile(
            leading: const Icon(Icons.straighten_rounded),
            title: const Text('Unit Jarak'),
            subtitle: Text(
              settings.distanceUnit == DistanceUnit.km
                  ? 'Kilometer (km)'
                  : 'Mil (mi)',
            ),
            trailing: SegmentedButton<DistanceUnit>(
              segments: const [
                ButtonSegment(value: DistanceUnit.km, label: Text('km')),
                ButtonSegment(value: DistanceUnit.miles, label: Text('mi')),
              ],
              selected: {settings.distanceUnit},
              onSelectionChanged: (s) async {
                await HapticService.select();
                settings.setDistanceUnit(s.first);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6_rounded),
            title: const Text('Tema'),
            subtitle: Text(_themeLabel(settings.theme)),
            trailing: DropdownButton<AppTheme>(
              value: settings.theme,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: AppTheme.light, child: Text('Terang')),
                DropdownMenuItem(value: AppTheme.dark, child: Text('Gelap')),
                DropdownMenuItem(value: AppTheme.system, child: Text('Sistem')),
              ],
              onChanged: (t) async {
                if (t == null) return;
                await HapticService.select();
                settings.setTheme(t);
              },
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.screen_lock_portrait_rounded),
            title: const Text('Layar Tetap Aktif'),
            subtitle: const Text('Cegah layar mati saat navigasi aktif'),
            value: settings.keepScreenOn,
            onChanged: (v) async {
              await HapticService.select();
              settings.setKeepScreenOn(v);
            },
          ),

          // ============================================================
          // NAVIGASI
          // ============================================================
          const _SectionHeader(
            icon: Icons.navigation_rounded,
            title: 'Navigasi',
          ),
          SwitchListTile(
            secondary: const Icon(Icons.alt_route_rounded),
            title: const Text('Reroute Otomatis'),
            subtitle: const Text('Hitung ulang rute saat keluar jalur'),
            value: settings.autoReroute,
            onChanged: (v) async {
              await HapticService.select();
              settings.setAutoReroute(v);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_rounded),
            title: const Text('Background Mode'),
            subtitle: const Text(
              'App tetap jalan saat layar mati atau pindah aplikasi',
            ),
            value: settings.backgroundMode,
            onChanged: (v) async {
              await HapticService.select();
              settings.setBackgroundMode(v);
            },
          ),

          // ============================================================
          // FIRMWARE UPDATE (OTA)
          // ============================================================
          const _SectionHeader(
            icon: Icons.system_update_rounded,
            title: 'Firmware Update',
          ),
          ListTile(
            leading: const Icon(Icons.memory_rounded),
            title: const Text('Firmware ESP32'),
            subtitle: Text(
              ota.currentVersion == null
                  ? 'Versi: belum terhubung'
                  : 'Versi saat ini: ${ota.currentVersion}',
            ),
            trailing: Chip(label: Text(ota.isSimulated ? 'Simulasi' : 'Live')),
          ),
          const FirmwareOtaCard(),

          // ============================================================
          // SIMULATOR
          // ============================================================
          const _SectionHeader(icon: Icons.science_rounded, title: 'Simulator'),
          ListTile(
            leading: const Icon(Icons.speed_rounded),
            title: const Text('Kecepatan Default'),
            subtitle: Text(
              '${settings.simSpeed.toStringAsFixed(0)}x — '
              'Berapa kali kecepatan normal',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 8,
              children: [1, 2, 5, 10, 20, 50].map((s) {
                final selected = settings.simSpeed == s.toDouble();

                return ChoiceChip(
                  label: Text('${s}x'),
                  selected: selected,
                  onSelected: (_) async {
                    await HapticService.select();
                    settings.setSimSpeed(s.toDouble());
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SECTION HEADER
// ============================================================
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: primary),
          ),
          const SizedBox(width: 10),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: primary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(height: 1, color: primary.withValues(alpha: 0.15)),
          ),
        ],
      ),
    );
  }
}