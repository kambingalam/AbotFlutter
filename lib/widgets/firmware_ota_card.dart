import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/haptic_service.dart';
import '../services/ota_service.dart';

/// Kartu update firmware. Seluruh logika ada di [OtaService]; widget ini
/// hanya menampilkan state dan meneruskan aksi pengguna.
class FirmwareOtaCard extends StatelessWidget {
  const FirmwareOtaCard({super.key});

  Future<void> _check(BuildContext context, OtaService ota) async {
    await HapticService.select();

    if (ota.phase == OtaPhase.failed || ota.phase == OtaPhase.success) {
      ota.reset();
    }

    await ota.checkForUpdate();
  }

  Future<void> _confirmAndStart(BuildContext context, OtaService ota) async {
    final manifest = ota.manifest;
    if (manifest == null) return;

    await HapticService.select();
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Update ke v${manifest.version}?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (manifest.notes.isNotEmpty) ...[
                const Text(
                  'Yang baru:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                for (final note in manifest.notes) Text('• $note'),
                const SizedBox(height: 12),
              ],
              const Text(
                'ABOT akan restart setelah update. Jangan matikan ABOT dan '
                'pastikan tidak sedang dalam perjalanan.',
              ),
              if (ota.isSimulated) ...[
                const SizedBox(height: 12),
                const Text(
                  'Mode simulasi: tidak ada firmware yang diunduh.',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ota.startUpdate();
    }
  }

  String _statusText(OtaService ota) {
    final percent = (ota.progress * 100).round();

    switch (ota.phase) {
      case OtaPhase.idle:
        final v = ota.currentVersion;
        return v == null
            ? 'Hubungkan ABOT lalu cek pembaruan'
            : 'Versi ABOT saat ini: v$v';
      case OtaPhase.checking:
        return 'Memeriksa pembaruan...';
      case OtaPhase.upToDate:
        return 'Firmware sudah yang terbaru (v${ota.currentVersion ?? '?'})';
      case OtaPhase.available:
        return 'Tersedia versi v${ota.manifest?.version ?? '?'}';
      case OtaPhase.starting:
        return 'Mengirim perintah update...';
      case OtaPhase.connectingWifi:
        return 'ABOT menyambung ke WiFi...';
      case OtaPhase.fetchingManifest:
        return 'ABOT mengambil info update...';
      case OtaPhase.downloading:
        return 'Mengunduh firmware: $percent%';
      case OtaPhase.verifying:
        return 'Memverifikasi firmware...';
      case OtaPhase.installing:
        return 'Memasang firmware...';
      case OtaPhase.rebooting:
        return 'ABOT restart. Mohon tunggu...';
      case OtaPhase.verifyingVersion:
        return 'Memverifikasi versi baru...';
      case OtaPhase.success:
        final base = 'Update berhasil — sekarang v${ota.currentVersion ?? '?'}';
        return ota.succeededInSimulation ? '$base (simulasi)' : base;
      case OtaPhase.failed:
        return ota.failure?.message ?? 'Update gagal';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ota = context.watch<OtaService>();
    final colorScheme = Theme.of(context).colorScheme;
    final phase = ota.phase;

    final IconData icon;
    final Color iconColor;

    switch (phase) {
      case OtaPhase.success:
        icon = Icons.check_circle_rounded;
        iconColor = Colors.green;
        break;
      case OtaPhase.failed:
        icon = Icons.error_outline_rounded;
        iconColor = colorScheme.error;
        break;
      case OtaPhase.upToDate:
        icon = Icons.verified_rounded;
        iconColor = Colors.green;
        break;
      case OtaPhase.available:
        icon = Icons.system_update_alt_rounded;
        iconColor = colorScheme.primary;
        break;
      case OtaPhase.idle:
        icon = Icons.info_outline_rounded;
        iconColor = colorScheme.onSurfaceVariant;
        break;
      default:
        icon = Icons.sync_rounded;
        iconColor = colorScheme.primary;
    }

    final showProgress = ota.isRunning || ota.isChecking;
    final determinate = phase == OtaPhase.downloading && ota.progress > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Update firmware',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                ota.isSimulated
                    ? 'Mode simulasi: alur update diuji tanpa mengunduh '
                        'firmware, menulis flash, atau me-restart ESP32.'
                    : 'ABOT mengunduh firmware sendiri lewat WiFi. Pastikan '
                        'ABOT sudah tersambung ke WiFi dan baterai cukup.',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(icon, color: iconColor),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_statusText(ota))),
                ],
              ),
              if (showProgress) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: determinate ? ota.progress : null,
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: _buildAction(context, ota),
              ),
              if (ota.canCancel) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: ota.cancelUpdate,
                    child: const Text('Batalkan'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAction(BuildContext context, OtaService ota) {
    switch (ota.phase) {
      case OtaPhase.available:
        return FilledButton.icon(
          onPressed: () => _confirmAndStart(context, ota),
          icon: const Icon(Icons.system_update_alt_rounded),
          label: Text('Update ke v${ota.manifest?.version ?? '?'}'),
        );

      case OtaPhase.checking:
        return const FilledButton(
          onPressed: null,
          child: Text('Memeriksa...'),
        );

      case OtaPhase.failed:
        return FilledButton.icon(
          onPressed: () => _check(context, ota),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Coba lagi'),
        );

      case OtaPhase.idle:
      case OtaPhase.upToDate:
      case OtaPhase.success:
        return FilledButton.tonalIcon(
          onPressed: () => _check(context, ota),
          icon: const Icon(Icons.search_rounded),
          label: const Text('Cek pembaruan'),
        );

      default:
        return const FilledButton(
          onPressed: null,
          child: Text('Update berjalan — jangan matikan ABOT'),
        );
    }
  }
}