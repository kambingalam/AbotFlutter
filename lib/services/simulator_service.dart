import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/trip.dart';

enum SimulatorState { stopped, playing, paused }

class SimulatorService {
  Timer? _timer;
  Trip? _trip;

  SimulatorState _state = SimulatorState.stopped;
  double _distanceMeters = 0;
  double _speedMultiplier = 5.0;

  static const double _baseSpeedMps = 8.0;
  static const Duration _tickInterval = Duration(milliseconds: 100);

  Function(Position pos, double distanceAlongRoute)? onPositionUpdate;
  VoidCallback? onCompleted;

  SimulatorState get state => _state;
  bool get isPlaying => _state == SimulatorState.playing;
  bool get isPaused => _state == SimulatorState.paused;
  bool get isStopped => _state == SimulatorState.stopped;
  double get speedMultiplier => _speedMultiplier;
  double get distanceMeters => _distanceMeters;

  /// Set kecepatan awal dari settings sebelum start
  void setInitialSpeed(double multiplier) {
    _speedMultiplier = multiplier.clamp(1.0, 100.0);
  }

  void start(Trip trip, {double fromDistanceMeters = 0}) {
    _trip = trip;
    _distanceMeters = fromDistanceMeters;
    _state = SimulatorState.playing;

    _timer?.cancel();

    // Emit posisi pertama segera supaya marker langsung
    // pindah ke titik awal rute baru (tidak menunggu tick).
    _emitPosition();

    _timer = Timer.periodic(_tickInterval, _tick);

    debugPrint('[SIM] Started | speed: ${_speedMultiplier}x');
  }

  void pause() {
    if (_state != SimulatorState.playing) return;
    _state = SimulatorState.paused;
    _timer?.cancel();
    debugPrint('[SIM] Paused');
  }

  void resume() {
    if (_state != SimulatorState.paused) return;
    if (_trip == null) return;
    _state = SimulatorState.playing;
    _timer?.cancel();
    _timer = Timer.periodic(_tickInterval, _tick);
    debugPrint('[SIM] Resumed');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _state = SimulatorState.stopped;
    _distanceMeters = 0;
    _trip = null;
    debugPrint('[SIM] Stopped');
  }

  /// Reset state tanpa membuang trip.
  /// Dipakai saat trip dihentikan lewat tombol "Selesai"
  /// supaya GPS asli bisa dipakai lagi tanpa restart app.
  void clearSimulation() {
    _timer?.cancel();
    _timer = null;
    _state = SimulatorState.stopped;
    _distanceMeters = 0;
    // _trip tetap disimpan supaya bisa di-restart kalau perlu.
    debugPrint('[SIM] Cleared (trip preserved)');
  }

  void restart() {
    if (_trip == null) return;
    start(_trip!, fromDistanceMeters: 0);
    debugPrint('[SIM] Restarted');
  }

  void setSpeed(double multiplier) {
    _speedMultiplier = multiplier.clamp(1.0, 100.0);
    debugPrint('[SIM] Speed = ${_speedMultiplier}x');
  }

  void _tick(Timer _) {
    if (_trip == null) return;
    if (_state != SimulatorState.playing) return;

    final deltaMeters =
        _baseSpeedMps *
        _speedMultiplier *
        _tickInterval.inMilliseconds /
        1000.0;

    _distanceMeters += deltaMeters;

    if (_distanceMeters >= _trip!.totalDistance) {
      _distanceMeters = _trip!.totalDistance;
      _emitPosition();
      _timer?.cancel();
      _state = SimulatorState.stopped;
      debugPrint('[SIM] Completed');
      onCompleted?.call();
      return;
    }

    _emitPosition();
  }

  void _emitPosition() {
    final trip = _trip;
    if (trip == null || trip.coords.length < 2) return;

    final coords = trip.coords;
    double cumul = 0;
    int idx = 0;

    for (var i = 1; i < coords.length; i++) {
      final seg = _haversine(
        coords[i - 1][1],
        coords[i - 1][0],
        coords[i][1],
        coords[i][0],
      );
      if (cumul + seg >= _distanceMeters) {
        idx = i;
        break;
      }
      cumul += seg;
      idx = i;
    }

    final lat1 = coords[idx - 1][1];
    final lon1 = coords[idx - 1][0];
    final lat2 = coords[idx][1];
    final lon2 = coords[idx][0];

    final segLen = _haversine(lat1, lon1, lat2, lon2);
    final t = segLen > 0
        ? ((_distanceMeters - cumul) / segLen).clamp(0.0, 1.0)
        : 0.0;

    final lat = lat1 + (lat2 - lat1) * t;
    final lon = lon1 + (lon2 - lon1) * t;
    final heading = _bearing(lat1, lon1, lat2, lon2);

    final pos = Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: heading,
      headingAccuracy: 0,
      speed: _baseSpeedMps * _speedMultiplier,
      speedAccuracy: 0,
    );

    onPositionUpdate?.call(pos, _distanceMeters);
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _bearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2 * math.pi / 180);
    final x =
        math.cos(lat1 * math.pi / 180) * math.sin(lat2 * math.pi / 180) -
        math.sin(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.cos(dLon);
    final brng = math.atan2(y, x) * 180 / math.pi;
    return (brng + 360) % 360;
  }

  void dispose() {
    _timer?.cancel();
  }
}
