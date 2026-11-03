import 'dart:async';

import 'package:flutter/material.dart';

import '../services/abot_mqtt_service.dart';
import '../services/haptic_service.dart';

class FirmwareOtaCard extends StatefulWidget {
  const FirmwareOtaCard({super.key});

  @override
  State<FirmwareOtaCard> createState() => _FirmwareOtaCardState();
}

class _FirmwareOtaCardState extends State<FirmwareOtaCard> {
  late final AbotMqttService _mqtt;

  StreamSubscription<Map<String, dynamic>>? _subscription;

  bool _busy = false;
  bool _completed = false;
  double _progress = 0;
  String _status = 'Siap diuji melalui MQTT';

  @override
  void initState() {
    super.initState();

    _mqtt = AbotMqttService();
    _subscription = _mqtt.messages.listen(_handleMessage);
  }

  void _handleMessage(Map<String, dynamic> message) {
    if (!mounted) return;

    final type = message['t']?.toString();

    if (type == 'ota_progress') {
      final value = message['progress'];
      final progress = value is num ? value.toDouble() : 0.0;

      setState(() {
        _busy = true;
        _progress = (progress / 100).clamp(0.0, 1.0);
        _status = 'Proses update: ${progress.toStringAsFixed(0)}%';
      });
    } else if (type == 'ota_simulated') {
      setState(() {
        _busy = false;
        _completed = true;
        _progress = 1;
        _status = 'Simulasi OTA berhasil';
      });
    } else if (type == 'ota_error') {
      setState(() {
        _busy = false;
        _completed = false;
        _status = message['message']?.toString() ?? 'OTA gagal';
      });
    }
  }

  Future<void> _startOta() async {
    if (_busy) return;

    await HapticService.select();

    setState(() {
      _busy = true;
      _completed = false;
      _progress = 0;
      _status = 'Menghubungkan ke MQTT...';
    });

    try {
      await _mqtt.connect();

      if (!mounted) return;

      _mqtt.publishJson({'t': 'ota_start', 'token': 'abot-secret-2025'});

      setState(() {
        _status = 'Perintah OTA terkirim. Menunggu ESP32...';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _busy = false;
        _status = 'Gagal terhubung ke MQTT';
      });

      debugPrint('OTA MQTT error: $error');
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _mqtt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'OTA melalui MQTT',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Uji alur update firmware di Wokwi. Mode simulasi '
                'tidak mengunduh firmware, menulis flash, '
                'atau me-restart ESP32.',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    _completed
                        ? Icons.check_circle_rounded
                        : _busy
                        ? Icons.sync_rounded
                        : Icons.info_outline_rounded,
                    color: _completed
                        ? Colors.green
                        : _busy
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_status)),
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _startOta,
                  icon: Icon(
                    _busy
                        ? Icons.sync_rounded
                        : Icons.system_update_alt_rounded,
                  ),
                  label: Text(
                    _busy ? 'OTA sedang berjalan...' : 'Mulai Simulasi OTA',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
