import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum GpsStatus {
  idle,
  initializing,
  permissionDenied,
  permissionDeniedForever,
  serviceDisabled,
  ready,
  error,
}

class GpsService {
  final _positionController = StreamController<Position>.broadcast();
  final _statusController = StreamController<GpsStatus>.broadcast();

  Stream<Position> get positionStream => _positionController.stream;
  Stream<GpsStatus> get statusStream => _statusController.stream;

  StreamSubscription<Position>? _sub;
  Position? _last;
  Position? get last => _last;

  GpsStatus _status = GpsStatus.idle;
  GpsStatus get status => _status;

  String _lastError = '';
  String get lastError => _lastError;

  DateTime? _lastEmitAt;
  Position? _lastEmitted;

  bool _gotFirstFix = false;

  static const Duration _minEmitInterval = Duration(milliseconds: 800);
  static const double _minDistanceM = 3.0;
  static const double _maxAccuracyM = 50.0;
  static const Duration _oneShotTimeout = Duration(seconds: 15);

  void _setStatus(GpsStatus s, {String error = ''}) {
    _status = s;
    _lastError = error;
    if (!_statusController.isClosed) {
      _statusController.add(s);
    }
    debugPrint('[GPS] status: ${s.name} ${error.isNotEmpty ? '($error)' : ''}');
  }

  Future<bool> ensurePermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setStatus(GpsStatus.serviceDisabled, error: 'Location service off');
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _setStatus(GpsStatus.permissionDenied);
        return false;
      }

      if (permission == LocationPermission.deniedForever) {
        _setStatus(GpsStatus.permissionDeniedForever);
        return false;
      }

      return true;
    } catch (e) {
      _setStatus(GpsStatus.error, error: 'permission check: $e');
      return false;
    }
  }

  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  Future<bool> start() async {
    _gotFirstFix = false;
    _setStatus(GpsStatus.initializing);

    if (!await ensurePermission()) {
      return false;
    }

    await _sub?.cancel();

    try {
      final settings = LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 3,
      );

      _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
        _onPosition,
        onError: (e) {
          _setStatus(GpsStatus.error, error: 'stream: $e');
        },
        onDone: () {
          if (_status == GpsStatus.ready) {
            _setStatus(GpsStatus.error, error: 'stream closed');
          }
        },
        cancelOnError: false,
      );

      debugPrint('[GPS] Stream started, waiting for first fix...');
      return true;
    } catch (e) {
      _setStatus(GpsStatus.error, error: 'start: $e');
      return false;
    }
  }

  void _onPosition(Position pos) {
    if (pos.accuracy > _maxAccuracyM) {
      debugPrint('[GPS] Skip — acc ${pos.accuracy.toStringAsFixed(1)}m');
      return;
    }

    final now = DateTime.now();
    if (_lastEmitAt != null &&
        now.difference(_lastEmitAt!) < _minEmitInterval) {
      return;
    }

    if (_lastEmitted != null) {
      final d = _distanceM(
        _lastEmitted!.latitude,
        _lastEmitted!.longitude,
        pos.latitude,
        pos.longitude,
      );
      if (d < _minDistanceM) return;
    }

    _lastEmitAt = now;
    _lastEmitted = pos;
    _last = pos;

    if (!_gotFirstFix) {
      _gotFirstFix = true;
      _setStatus(GpsStatus.ready);
      debugPrint('[GPS] First fix — status ready');
    }

    debugPrint(
      '[GPS] ${pos.latitude.toStringAsFixed(5)}, '
      '${pos.longitude.toStringAsFixed(5)} '
      '| acc: ${pos.accuracy.toStringAsFixed(1)}m',
    );

    if (!_positionController.isClosed) {
      _positionController.add(pos);
    }
  }

  double _distanceM(double lat1, double lon1, double lat2, double lon2) {
    const mPerLat = 110540.0;
    final mPerLon = 111320.0 * math.cos(lat1 * math.pi / 180);
    final dx = (lon2 - lon1) * mPerLon;
    final dy = (lat2 - lat1) * mPerLat;
    return math.sqrt(dx * dx + dy * dy);
  }

  Future<Position?> getOneShot({double maxAccuracyM = _maxAccuracyM}) async {
    if (!await ensurePermission()) return null;

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: _oneShotTimeout,
      );

      if (pos.accuracy > maxAccuracyM) {
        debugPrint(
          '[GPS] getOneShot skip — acc '
          '${pos.accuracy.toStringAsFixed(1)}m',
        );
        return null;
      }

      if (!_gotFirstFix) {
        _gotFirstFix = true;
        _setStatus(GpsStatus.ready);
      }

      _last = pos;
      _lastEmitted = pos;
      _lastEmitAt = DateTime.now();
      return pos;
    } on TimeoutException {
      _setStatus(GpsStatus.error, error: 'getOneShot timeout');
      return null;
    } catch (e) {
      _setStatus(GpsStatus.error, error: 'getOneShot: $e');
      return null;
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _setStatus(GpsStatus.idle);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;

    if (!_positionController.isClosed) {
      await _positionController.close();
    }
    if (!_statusController.isClosed) {
      await _statusController.close();
    }
  }
}
