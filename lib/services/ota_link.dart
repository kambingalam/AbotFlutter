import 'dart:async';

import 'abot_mqtt_service.dart';

/// Jalur komunikasi ke ABOT yang dibutuhkan OTA.
///
/// Isi pesannya sama di semua transport. Sekarang: MQTT (simulasi Wokwi).
/// Nanti: BLE (perangkat asli) — cukup buat implementasi baru, OtaService
/// tidak perlu diubah.
abstract class OtaLink {
  /// Semua pesan JSON dari ABOT.
  Stream<Map<String, dynamic>> get messages;

  /// Emit true saat sesi siap (terhubung + terautentikasi), false saat tidak.
  Stream<bool> get readyChanges;

  bool get isReady;

  /// Hubungkan dan tunggu sesi siap. Melempar error jika gagal / timeout.
  Future<void> ensureReady({Duration timeout = const Duration(seconds: 30)});

  /// Kirim satu pesan JSON. Melempar error jika sesi belum siap.
  void send(Map<String, dynamic> message);
}

/// Transport MQTT (Wokwi).
class MqttOtaLink implements OtaLink {
  MqttOtaLink(this._mqtt);

  final AbotMqttService _mqtt;

  @override
  Stream<Map<String, dynamic>> get messages => _mqtt.messages;

  @override
  Stream<bool> get readyChanges =>
      _mqtt.states.map((s) => s == AbotMqttState.ready).distinct();

  @override
  bool get isReady => _mqtt.isReady;

  @override
  Future<void> ensureReady({
    Duration timeout = const Duration(seconds: 30),
  }) {
    return _mqtt.connectAndAuthenticate(timeout: timeout);
  }

  @override
  void send(Map<String, dynamic> message) {
    _mqtt.publishJson(message, requireAuthentication: true);
  }
}