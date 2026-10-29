
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import '../models/abot_message.dart';
import '../models/trip.dart';
import 'abot_mqtt_service.dart';
import 'gps_service.dart';
import 'mock_ble_service.dart';
import 'osrm_service.dart';

enum TripState { idle, calculating, ready, active, arrived, error }

class TripManager extends ChangeNotifier {
  final MockBleService ble;
  final AbotMqttService mqtt;
  final GpsService gps;
  final OsrmService osrm;

  TripManager({
    required this.ble,
    required this.mqtt,
    required this.gps,
    required this.osrm,
  }) {
    _bleSub = ble.incomingStream.listen(_onBleMessage);
    _mqttSub = mqtt.messages.listen(_onMqttMessage);
    _gpsSub = gps.positionStream.listen(_onGpsUpdate);

    _connSub = ble.connectionStream.listen((connected) {
      isBleConnected = connected;
      notifyListeners();
    });

    // Mempertahankan callback background yang sudah ada.
    FlutterForegroundTask.addTaskDataCallback(_onBackgroundData);
  }

  late final StreamSubscription _bleSub;
  late final StreamSubscription<Map<String, dynamic>> _mqttSub;
  late final StreamSubscription _gpsSub;
  late final StreamSubscription _connSub;

  static const double arrivalRadiusM = 20.0;
  static const int rerouteCooldownSec = 15;
  static const Duration _mqttGpsInterval = Duration(seconds: 2);

  // ============================================================
  // STATE
  // ============================================================

  bool isBleConnected = false;

  bool get isMqttConnected => mqtt.isConnected;

  /// Minimal satu transport aktif agar perintah dapat dikirim.
  bool get isAbotConnected => isBleConnected || isMqttConnected;

  TripState state = TripState.idle;
  Trip? currentTrip;
  Position? lastPosition;
  String? errorMessage;

  bool _isRerouting = false;
  bool get isRerouting => _isRerouting;

  DateTime? _lastRerouteAt;
  DateTime? _lastMqttGpsAt;

  /// True jika posisi berasal dari simulator.
  bool _simulating = false;
  bool get simulating => _simulating;

  // ============================================================
  // GPS STATUS PROXY
  // ============================================================

  GpsStatus get gpsStatus => gps.status;
  String get gpsError => gps.lastError;

  // ============================================================
  // INIT GPS
  // ============================================================

  Future<bool> initGps() async {
    return gps.start();
  }

  // ============================================================
  // START TRIP
  // ============================================================

  Future<bool> startTrip({
    required String destinationName,
    required double toLat,
    required double toLon,
  }) async {
    state = TripState.calculating;
    errorMessage = null;
    _simulating = false;
    _lastRerouteAt = null;
    _lastMqttGpsAt = null;
    notifyListeners();

    debugPrint('[TRIP] === Mulai ke $destinationName ===');

    Position? pos = gps.last;
    pos ??= await gps.getOneShot();

    if (pos == null) {
      state = TripState.error;
      errorMessage = 'GPS belum dapat posisi. Coba di luar ruangan.';
      notifyListeners();
      return false;
    }

    lastPosition = pos;

    debugPrint(
      '[TRIP] GPS: ${pos.latitude}, ${pos.longitude} '
      '| acc: ${pos.accuracy.toStringAsFixed(1)}m',
    );

    final straightDist = _straightLine(
      pos.latitude,
      pos.longitude,
      toLat,
      toLon,
    );

    debugPrint(
      '[TRIP] Jarak lurus: '
      '${(straightDist / 1000).toStringAsFixed(2)} km',
    );

    if (straightDist > 200000) {
      state = TripState.error;
      errorMessage =
          'Tujuan ${(straightDist / 1000).toStringAsFixed(0)} km dari kamu. '
          'Pilih tujuan yang lebih dekat.';
      notifyListeners();
      return false;
    }

    final sw = Stopwatch()..start();
    Trip? trip;

    try {
      trip = await osrm.getRoute(
        fromLat: pos.latitude,
        fromLon: pos.longitude,
        toLat: toLat,
        toLon: toLon,
        destinationName: destinationName,
      );
    } catch (e) {
      debugPrint('[TRIP] OSRM exception: $e');
      trip = null;
    }

    sw.stop();
    debugPrint('[TRIP] OSRM ${sw.elapsedMilliseconds} ms');

    if (trip == null || !trip.isReady) {
      state = TripState.error;
      errorMessage = 'Gagal hitung rute. Coba lagi.';
      notifyListeners();
      return false;
    }

    debugPrint(
      '[TRIP] OK: ${trip.distanceKm.toStringAsFixed(2)} km, '
      '${trip.durationMin.toStringAsFixed(0)} min, '
      '${trip.steps.length} steps',
    );

    currentTrip = trip;

    if (isAbotConnected) {
      debugPrint('[TRIP] Mengirim perjalanan ke ABOT...');
      await _sendTripStart();
      await _sendRoute(trip);
      debugPrint('[TRIP] Pengiriman perintah selesai');
    } else {
      debugPrint(
        '[TRIP] BLE dan MQTT belum terhubung. '
        'Rute tetap tersedia di aplikasi.',
      );
    }

    state = TripState.ready;
    notifyListeners();
    return true;
  }

  // ============================================================
  // START TRIP DENGAN PLAN DARI PREVIEW SCREEN
  // ============================================================

  Future<bool> startTripWithPlan(Trip trip) async {
    state = TripState.calculating;
    errorMessage = null;
    _simulating = false;
    _lastRerouteAt = null;
    _lastMqttGpsAt = null;
    notifyListeners();

    debugPrint('[TRIP] === Mulai dengan rute terpilih ===');
    debugPrint('[TRIP] Destination: ${trip.destinationName}');
    debugPrint('[TRIP] Distance: ${trip.distanceKm.toStringAsFixed(2)} km');
    debugPrint('[TRIP] Duration: ${trip.durationMin.toStringAsFixed(0)} min');
    debugPrint('[TRIP] Steps: ${trip.steps.length}');

    if (!trip.isReady) {
      state = TripState.error;
      errorMessage = 'Rute tidak valid';
      notifyListeners();
      return false;
    }

    currentTrip = trip;
    lastPosition = gps.last;

    if (isAbotConnected) {
      await _sendTripStart();
      await _sendRoute(trip);
    } else {
      debugPrint(
        '[TRIP] BLE dan MQTT belum terhubung. '
        'Rute hanya disimpan di aplikasi.',
      );
    }

    state = TripState.ready;
    notifyListeners();
    return true;
  }

  // ============================================================
  // START DRIVING
  // ============================================================

  Future<void> startDriving() async {
    if (currentTrip == null) return;

    state = TripState.active;
    _lastMqttGpsAt = null;

    debugPrint('[TRIP] Perjalanan aktif');
    notifyListeners();
  }

  // ============================================================
  // REROUTE
  // ============================================================

  Future<bool> reroute() async {
    if (_simulating) return false;
    if (_isRerouting) return false;
    if (state != TripState.active) return false;

    final trip = currentTrip;
    final pos = lastPosition;

    if (trip == null || pos == null) return false;

    final now = DateTime.now();

    if (_lastRerouteAt != null &&
        now.difference(_lastRerouteAt!).inSeconds <
            rerouteCooldownSec) {
      return false;
    }

    _isRerouting = true;
    _lastRerouteAt = now;
    notifyListeners();

    debugPrint('[TRIP] Reroute dari ${pos.latitude}, ${pos.longitude}');

    try {
      final newTrip = await osrm.getRoute(
        fromLat: pos.latitude,
        fromLon: pos.longitude,
        toLat: trip.destinationLat,
        toLon: trip.destinationLon,
        destinationName: trip.destinationName,
      );

      if (state != TripState.active ||
          !identical(currentTrip, trip)) {
        return false;
      }

      if (newTrip == null || !newTrip.isReady) {
        debugPrint('[TRIP] Reroute gagal');
        return false;
      }

      currentTrip = newTrip;

      if (isAbotConnected) {
        await _sendRoute(newTrip);
      }

      debugPrint(
        '[TRIP] Reroute OK: '
        '${newTrip.distanceKm.toStringAsFixed(2)} km, '
        '${newTrip.steps.length} steps',
      );

      return true;
    } catch (e) {
      debugPrint('[TRIP] Reroute error: $e');
      return false;
    } finally {
      _isRerouting = false;
      notifyListeners();
    }
  }

  // ============================================================
  // STOP TRIP
  // ============================================================

  Future<void> stopTrip() async {
    state = TripState.idle;
    currentTrip = null;
    _simulating = false;
    _isRerouting = false;
    _lastRerouteAt = null;
    _lastMqttGpsAt = null;

    final message = AbotMessage.tripEnd();

    if (isBleConnected) {
      try {
        await ble.send(message.toJsonString());
        debugPrint('[TRIP] trip_end terkirim lewat BLE');
      } catch (e) {
        debugPrint('[TRIP] Gagal mengirim trip_end lewat BLE: $e');
      }
    }

    await _sendMqttMessage(message);

    notifyListeners();
  }

  // ============================================================
  // BLE -> HP
  // ============================================================

  void _onBleMessage(String raw) {
    try {
      final msg = AbotMessage.fromJson(raw.trim());

      debugPrint('[ABOT BLE] ${msg.type}');

      if (msg.type == 'arrived') {
        _triggerArrival();
      } else if (msg.type == 'pong') {
        debugPrint('[ABOT BLE] PONG diterima');
      }
    } catch (e) {
      debugPrint('[ABOT BLE] Parse error: $e');
    }
  }

  // ============================================================
  // MQTT -> HP
  // ============================================================

  void _onMqttMessage(Map<String, dynamic> message) {
    final type = message['t']?.toString() ?? 'unknown';

    debugPrint('[ABOT MQTT] Pesan diterima: $type');

    switch (type) {
      case 'arrived':
        _triggerArrival();
        break;

      case 'pong':
        debugPrint('[ABOT MQTT] PONG diterima');
        break;

      case 'ack':
        debugPrint('[ABOT MQTT] ACK: $message');
        break;

      case 'nack':
        debugPrint('[ABOT MQTT] NACK: $message');
        break;

      case 'offroute':
        debugPrint('[ABOT MQTT] Peringatan keluar rute: $message');
        break;

      case 'status':
      case 'hb':
        debugPrint('[ABOT MQTT] Status ESP32: $message');
        break;

      default:
        debugPrint('[ABOT MQTT] Tipe pesan belum ditangani: $type');
    }
  }

  // ============================================================
  // GPS -> ABOT
  // ============================================================

  void _onGpsUpdate(Position pos) {
    if (_simulating) return;

    lastPosition = pos;
    notifyListeners();

    if (state != TripState.active) return;

    final message = AbotMessage.gpsLatLon(
      pos.latitude,
      pos.longitude,
    );

    // Jalur BLE tetap dipertahankan.
    if (isBleConnected) {
      unawaited(_sendBleMessage(message));
    }

    // MQTT dibatasi maksimal satu pengiriman setiap 2 detik.
    final now = DateTime.now();

    if (isMqttConnected &&
        (_lastMqttGpsAt == null ||
            now.difference(_lastMqttGpsAt!) >= _mqttGpsInterval)) {
      _lastMqttGpsAt = now;
      unawaited(_sendMqttMessage(message));
    }

    // Deteksi tiba di tujuan tetap menggunakan GPS aplikasi.
    final trip = currentTrip;

    if (trip != null) {
      final distance = _straightLine(
        pos.latitude,
        pos.longitude,
        trip.destinationLat,
        trip.destinationLon,
      );

      if (distance <= arrivalRadiusM) {
        _triggerArrival();
      }
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

  double _straightLine(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dx =
        (lon2 - lon1) *
        111320.0 *
        math.cos(lat1 * math.pi / 180);

    final dy = (lat2 - lat1) * 110540.0;

    return math.sqrt(dx * dx + dy * dy);
  }

  Future<void> _sendBleMessage(AbotMessage message) async {
    if (!isBleConnected) return;

    try {
      await ble.send(message.toJsonString());
      debugPrint('[ABOT BLE] Mengirim: ${message.type}');
    } catch (e) {
      debugPrint('[ABOT BLE] Gagal mengirim ${message.type}: $e');
    }
  }

  Future<void> _sendMqttMessage(AbotMessage message) async {
    if (!mqtt.isConnected) {
      debugPrint(
        '[ABOT MQTT] Belum terhubung, '
        'pesan dilewati: ${message.type}',
      );
      return;
    }

    final payload = <String, dynamic>{
      't': message.type,
      ...message.data,
    };

    try {
      // publishJson pada AbotMqttService merupakan pemanggilan sinkron.
      mqtt.publishJson(payload);
      debugPrint('[ABOT MQTT] Mengirim: ${message.type}');
    } catch (e) {
      debugPrint('[ABOT MQTT] Gagal mengirim ${message.type}: $e');
    }
  }

  Future<void> _sendTripStart() async {
    final message = AbotMessage.tripStart();

    if (isBleConnected) {
      await _sendBleMessage(message);
    }

    if (isMqttConnected) {
      await _sendMqttMessage(message);
    }

    await Future.delayed(const Duration(milliseconds: 200));
  }

  Future<void> _sendRoute(Trip trip) async {
    final steps = trip.steps.map((step) => step.toJson()).toList();

    final message = AbotMessage.route(
      distance: trip.totalDistance,
      duration: trip.totalDuration,
      coords: trip.coords,
      steps: steps,
    );

    if (isBleConnected) {
      await _sendBleMessage(message);
    }

    if (isMqttConnected) {
      await _sendMqttMessage(message);
    }
  }

  // ============================================================
  // BACKGROUND TASK CALLBACK
  // ============================================================

  void _onBackgroundData(Object data) {
    debugPrint('[TRIP] Background data: $data');

    if (data == 'stop_trip') {
      unawaited(stopTrip());
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onBackgroundData);

    _bleSub.cancel();
    _mqttSub.cancel();
    _gpsSub.cancel();
    _connSub.cancel();

    super.dispose();
  }

  // ============================================================
  // SIMULATOR SUPPORT
  // ============================================================

  void setSimulatedPosition(
    Position pos,
    double distanceAlongRoute,
  ) {
    _simulating = true;
    lastPosition = pos;
    notifyListeners();

    if (state == TripState.active) {
      final message = AbotMessage.gpsLatLon(
        pos.latitude,
        pos.longitude,
      );

      if (isBleConnected) {
        unawaited(_sendBleMessage(message));
      }

      final now = DateTime.now();

      if (isMqttConnected &&
          (_lastMqttGpsAt == null ||
              now.difference(_lastMqttGpsAt!) >= _mqttGpsInterval)) {
        _lastMqttGpsAt = now;
        unawaited(_sendMqttMessage(message));
      }
    }

    final trip = currentTrip;

    if (trip != null &&
        distanceAlongRoute >= trip.totalDistance - 5 &&
        state == TripState.active) {
      _triggerArrival();
    }
  }

  /// Dipanggil saat simulator dihentikan agar GPS asli kembali digunakan.
  void clearSimulation() {
    if (!_simulating) return;

    _simulating = false;
    notifyListeners();
  }

  void _triggerArrival() {
    if (state == TripState.arrived) return;
    if (state != TripState.active) return;

    state = TripState.arrived;
    debugPrint('[TRIP] Arrived');
    notifyListeners();
  }
}
