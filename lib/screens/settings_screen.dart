import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/abot_mqtt_service.dart';
import '../services/haptic_service.dart';
import '../services/ota_service.dart';
import '../services/settings_service.dart';
import '../services/trip_manager.dart';
import '../services/tts_service.dart';
import '../widgets/firmware_ota_card.dart';

import 'ble_diagnostic_screen.dart';

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

  Future<void> _editMqttToken(
    BuildContext context,
    SettingsService settings,
  ) async {
    final formKey = GlobalKey<FormState>();
    var draft = settings.mqttToken;

    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Token MQTT'),
        content: Form(
          key: formKey,
          child: TextFormField(
            initialValue: draft,
            autofocus: true,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (v) => draft = v,
            decoration: const InputDecoration(
              labelText: 'Token',
              helperText: 'Minimal 16 karakter, tanpa spasi. Samakan dengan SET auth=...',
            ),
            validator: (input) {
              final token = (input ?? '').trim();
              if (token.length < 16) return 'Minimal 16 karakter';
              if (token.length > 200) return 'Maksimal 200 karakter';
              if (RegExp(r'\s').hasMatch(token)) {
                return 'Tidak boleh ada spasi';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, draft.trim());
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (value == null) return;

    if (!context.mounted) return;

    final saved = await settings.setMqttToken(value);

    if (!context.mounted) return;

    _showMqttResult(context, saved, 'Token MQTT');
  }

  Future<void> _editMqttTopic(
    BuildContext context,
    SettingsService settings,
  ) async {
    final formKey = GlobalKey<FormState>();
    var draft = settings.mqttTopic;

    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Topik MQTT'),
        content: Form(
          key: formKey,
          child: TextFormField(
            initialValue: draft,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (v) => draft = v,
            decoration: const InputDecoration(
              labelText: 'Basis topik',
              helperText: '8-80 karakter: huruf, angka, _ - /',
            ),
            validator: (input) {
              final topic = (input ?? '').trim();
              if (topic.length < 8 || topic.length > 80) {
                return 'Harus 8-80 karakter';
              }
              if (topic.startsWith('/') || topic.endsWith('/')) {
                return 'Jangan diawali atau diakhiri /';
              }
              if (!RegExp(r'^[A-Za-z0-9_/-]+$').hasMatch(topic)) {
                return 'Hanya huruf, angka, _ - /';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, draft.trim());
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (value == null) return;

    if (!context.mounted) return;

    final saved = await settings.setMqttTopic(value);

    if (!context.mounted) return;

    _showMqttResult(context, saved, 'Topik MQTT');
  }

  void _showMqttResult(BuildContext context, bool saved, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? '$label disimpan. Tutup lalu buka ulang app.'
              : 'Gagal menyimpan $label.',
        ),
      ),
    );
  }

  Future<void> _playFromLink(BuildContext context) async {
    final trip = context.read<TripManager>();
    var draft = '';

    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Putar dari link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (v) => draft = v,
              decoration: const InputDecoration(
                labelText: 'URL audio',
                helperText: 'Link langsung ke file mp3/aac',
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Device mengunduh audio sendiri lewat WiFi, jadi link harus publik.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, draft.trim()),
            child: const Text('Putar'),
          ),
        ],
      ),
    );

    if (!context.mounted) return;

    if (url == null || url.isEmpty) return;

    _sendLinkCommand(context, trip, {
      't': 'play',
      'url': url,
    }, 'Perintah putar terkirim');
  }

  void _sendLinkCommand(
    BuildContext context,
    TripManager trip,
    Map<String, dynamic> payload,
    String okText,
  ) {
    final messenger = ScaffoldMessenger.of(context);

    try {
      trip.mqtt.publishJson(payload, requireAuthentication: true);
      messenger.showSnackBar(SnackBar(content: Text(okText)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Gagal kirim: $e')));
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
          // KEAMANAN MQTT
          // ============================================================
          const _SectionHeader(
            icon: Icons.lock_rounded,
            title: 'Keamanan MQTT',
          ),
          ListTile(
            leading: const Icon(Icons.vpn_key_rounded),
            title: const Text('Token MQTT'),
            subtitle: Text(
              settings.hasMqttToken
                  ? 'Tersimpan (${settings.mqttToken.length} karakter)'
                  : 'Belum diatur',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              await HapticService.select();
              if (!context.mounted) return;
              await _editMqttToken(context, settings);
            },
          ),
          ListTile(
            leading: const Icon(Icons.tag_rounded),
            title: const Text('Topik MQTT'),
            subtitle: Text(settings.mqttTopic),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              await HapticService.select();
              if (!context.mounted) return;
              await _editMqttTopic(context, settings);
            },
          ),
          ListTile(
            leading: const Icon(Icons.cloud_rounded),
            title: const Text('Broker'),
            subtitle: Text(
              '${AbotMqttService.host}:${AbotMqttService.port} (TLS)',
            ),
          ),

          // ============================================================
          // KONEKSI PERANGKAT (BLE DIAGNOSTIC)
          // ============================================================
          const _SectionHeader(
            icon: Icons.bluetooth_rounded,
            title: 'Koneksi Perangkat',
          ),
          ListTile(
            leading: const Icon(Icons.bluetooth_searching_rounded),
            title: const Text('BLE Diagnostic'),
            subtitle: const Text(
              'Scan, hubungkan, dan tes komunikasi ESP32-S3',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              await HapticService.select();

              if (!context.mounted) return;

              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BleDiagnosticScreen()),
              );
            },
          ),

          // ============================================================
          // MUSIK DARI LINK
          // ============================================================
          const _SectionHeader(icon: Icons.music_note_rounded, title: 'Musik'),
          ListTile(
            leading: const Icon(Icons.link_rounded),
            title: const Text('Putar dari link'),
            subtitle: const Text('URL langsung ke file audio'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              await HapticService.select();
              if (!context.mounted) return;
              await _playFromLink(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.stop_circle_outlined),
            title: const Text('Hentikan musik'),
            onTap: () async {
              await HapticService.select();
              if (!context.mounted) return;
              _sendLinkCommand(context, context.read<TripManager>(), {
                't': 'music_stop',
              }, 'Perintah stop terkirim');
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
