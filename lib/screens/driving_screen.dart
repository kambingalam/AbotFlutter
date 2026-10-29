import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';

import 'package:latlong2/latlong.dart';

import 'package:provider/provider.dart';

import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/nav_step.dart';

import '../models/trip.dart';

import '../services/background_service.dart';

import '../services/mock_ble_service.dart';

import '../services/settings_service.dart';

import '../services/simulator_service.dart';

import '../services/tts_service.dart';

import '../services/trip_manager.dart';

import '../theme/app_theme.dart';

import '../widgets/animated_marker.dart';

import '../widgets/debug_overlay.dart';

import '../widgets/nav_instruction_card.dart';

import 'arrived_screen.dart';

class DrivingScreen extends StatefulWidget {
  final bool simulate;

  const DrivingScreen({super.key, this.simulate = false});

  @override
  State<DrivingScreen> createState() => _DrivingScreenState();
}

class _DrivingScreenState extends State<DrivingScreen>
    with TickerProviderStateMixin {
  final MapController _map = MapController();

  final SimulatorService _sim = SimulatorService();

  // ============================================================
  // SMOOTH NAVIGATION CAMERA
  // ============================================================
  late final AnimationController _cameraAnimation;

  LatLng? _pendingCameraTarget;
  LatLng? _lastRequestedCameraTarget;
  LatLng? _cameraStart;
  LatLng? _cameraEnd;

  double? _pendingCameraHeading;
  double? _lastRequestedCameraHeading;
  double _cameraStartRotation = 0.0;
  double _cameraEndRotation = 0.0;

  bool _mapReady = false;
  bool _cameraFrameScheduled = false;

  static const Duration _cameraAnimationDuration = Duration(milliseconds: 240);
  static const double _cameraMinMovementMeters = 1.5;
  static const double _cameraMinHeadingChange = 2.0;

  bool _followUser = true;

  // ============================================================
  // SMOOTH VEHICLE MARKER (separate from raw GPS/navigation data)
  // ============================================================
  late final AnimationController _markerAnimation;
  LatLng? _markerVisualPosition;
  LatLng? _markerStart;
  LatLng? _markerEnd;
  LatLng? _lastMarkerGpsTarget;
  LatLng? _pendingMarkerTarget;
  bool _markerFrameScheduled = false;
  static const Duration _markerAnimationDuration = Duration(milliseconds: 650);

  bool _showDebug = false;

  int _lastAnnouncedBeforeStepIdx = -1;

  int _lastAnnouncedAfterStepIdx = -1;

  bool _arrivalAnnounced = false;

  bool _nearDestAnnounced = false;

  bool _announcing = false;

  bool _navigatedToArrived = false;

  double _simDistance = 0;

  Trip? _cachedTrip;

  List<LatLng> _routePoints = const [];

  List<double> _cumDist = const [];

  int _lastSegIdx = 0;

  DateTime? _offRouteSince;

  bool _lastOffRoute = false;

  Timer? _announceTimer;

  Timer? _offRouteTimer;

  bool _bgStarted = false;

  DateTime? _lastBgUpdate;

  // ============================================================

  // KONFIGURASI

  // ============================================================

  static const double announceDistanceM = 200.0;

  static const double nearDestDistanceM = 500.0; // ← Level 2: 200 → 500

  static const double arrivalDistanceM = 30.0;

  static const double afterMinDistanceM = 400.0;

  static const double stepPassMarginM = 5.0;

  static const double clusterThresholdM = 200.0;

  static const int maxClusterSize = 2;

  static const double offRouteThresholdM = 40.0;

  static const Duration offRouteConfirm = Duration(seconds: 4);

  static const int snapWindowBack = 3;

  static const int snapWindowForward = 20;

  static const double snapFallbackM = 60.0;

  static const Duration announceThrottle = Duration(milliseconds: 500);

  static const Duration offRouteThrottle = Duration(milliseconds: 1000);

  static const Duration bgUpdateThrottle = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();

    _cameraAnimation = AnimationController(
      vsync: this,
      duration: _cameraAnimationDuration,
    )..addListener(_tickCameraAnimation);

    _markerAnimation = AnimationController(
      vsync: this,
      duration: _markerAnimationDuration,
    )..addListener(_tickMarkerAnimation);

    _simDistance = 0; // ← reset

    _sim.onPositionUpdate = (pos, dist) {
      _simDistance = dist;

      if (!mounted) return;

      final manager = context.read<TripManager>();

      manager.setSimulatedPosition(pos, dist);
    };

    _sim.onCompleted = () {
      debugPrint('[SIM] Completed callback');
    };

    _announceTimer = Timer.periodic(
      announceThrottle,

      (_) => _checkAndAnnounce(),
    );

    _offRouteTimer = Timer.periodic(offRouteThrottle, (_) => _checkOffRoute());

    if (widget.simulate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        final manager = context.read<TripManager>();

        final settings = context.read<SettingsService>();

        if (manager.currentTrip != null) {
          // Pastikan flag simulasi bersih sebelum mulai

          manager.clearSimulation();

          _sim.setInitialSpeed(settings.simSpeed);

          _sim.start(manager.currentTrip!);
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        _startBackgroundService();
      });
    }
  }

  @override
  void dispose() {
    _announceTimer?.cancel();

    _offRouteTimer?.cancel();

    WakelockPlus.disable();

    _sim.dispose();

    if (!widget.simulate) {
      BackgroundService.stop();
    }

    _cameraAnimation.dispose();
    _markerAnimation.dispose();

    super.dispose();
  }

  // ============================================================
  // SMOOTH CAMERA HELPERS
  // ============================================================

  static double _normalizeDegrees(double value) {
    return (value % 360.0 + 360.0) % 360.0;
  }

  /// Sudut terpendek, termasuk transisi 359° -> 1°.
  static double _angleDelta(double from, double to) {
    return ((to - from + 540.0) % 360.0) - 180.0;
  }

  /// Mengantrikan posisi dan heading baru untuk kamera.
  /// Perubahan GPS kecil diabaikan untuk mengurangi getaran.
  void _requestCameraFollow(LatLng target, double heading) {
    if (!_mapReady || !_followUser) return;

    final safeHeading = _normalizeDegrees(heading);
    final previousTarget = _lastRequestedCameraTarget;
    final previousHeading = _lastRequestedCameraHeading;

    final movedEnough =
        previousTarget == null ||
        _distM(
              previousTarget.latitude,
              previousTarget.longitude,
              target.latitude,
              target.longitude,
            ) >=
            _cameraMinMovementMeters;

    final turnedEnough =
        previousHeading == null ||
        _angleDelta(previousHeading, safeHeading).abs() >=
            _cameraMinHeadingChange;

    if (!movedEnough && !turnedEnough) return;

    _lastRequestedCameraTarget = target;
    _lastRequestedCameraHeading = safeHeading;
    _pendingCameraTarget = target;
    _pendingCameraHeading = safeHeading;

    // Gabungkan pembaruan yang masuk pada frame yang sama.
    if (_cameraFrameScheduled) return;
    _cameraFrameScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cameraFrameScheduled = false;
      if (!mounted || !_mapReady || !_followUser) return;

      final nextTarget = _pendingCameraTarget;
      final nextHeading = _pendingCameraHeading;
      if (nextTarget == null || nextHeading == null) return;

      try {
        // Mulai dari kamera aktual, bukan dari target animasi lama.
        _cameraStart = _map.camera.center;
        _cameraStartRotation = _normalizeDegrees(_map.camera.rotation);
      } catch (_) {
        _cameraStart = nextTarget;
        _cameraStartRotation = 0.0;
      }

      _cameraEnd = nextTarget;
      // Heading-up: putar peta berlawanan arah heading kendaraan.
      _cameraEndRotation = _normalizeDegrees(-nextHeading);
      _cameraAnimation.forward(from: 0.0);
    });
  }

  /// Dipanggil setiap frame animasi kamera.
  void _tickCameraAnimation() {
    if (!mounted || !_mapReady || !_followUser) return;

    final start = _cameraStart;
    final end = _cameraEnd;
    if (start == null || end == null) return;

    final progress = Curves.linear.transform(_cameraAnimation.value);

    final center = LatLng(
      start.latitude + (end.latitude - start.latitude) * progress,
      start.longitude + (end.longitude - start.longitude) * progress,
    );

    final rotation = _normalizeDegrees(
      _cameraStartRotation +
          _angleDelta(_cameraStartRotation, _cameraEndRotation) * progress,
    );

    try {
      _map.move(center, _map.camera.zoom);
      _map.rotate(rotation);
    } catch (error) {
      debugPrint('[CAMERA] Animation update failed: $error');
    }
  }

  // ============================================================
  // SMOOTH VEHICLE MARKER HELPERS
  // ============================================================

  /// Antrikan target marker setelah build selesai agar controller tidak
  /// memicu setState ketika Flutter sedang membangun widget tree.
  void _requestMarkerPosition(LatLng target) {
    final previous = _lastMarkerGpsTarget;
    if (previous != null &&
        previous.latitude == target.latitude &&
        previous.longitude == target.longitude) {
      return;
    }

    _lastMarkerGpsTarget = target;
    _pendingMarkerTarget = target;
    if (_markerFrameScheduled) return;
    _markerFrameScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markerFrameScheduled = false;
      if (!mounted) return;

      final nextTarget = _pendingMarkerTarget;
      if (nextTarget == null) return;

      final current = _markerVisualPosition;
      if (current == null) {
        setState(() {
          _markerVisualPosition = nextTarget;
        });
        return;
      }

      if (current.latitude == nextTarget.latitude &&
          current.longitude == nextTarget.longitude) {
        return;
      }

      _markerStart = current;
      _markerEnd = nextTarget;
      _markerAnimation.forward(from: 0.0);
    });
  }

  void _tickMarkerAnimation() {
    if (!mounted) return;

    final start = _markerStart;
    final end = _markerEnd;
    if (start == null || end == null) return;

    final progress = Curves.linear.transform(_markerAnimation.value);
    final position = LatLng(
      start.latitude + (end.latitude - start.latitude) * progress,
      start.longitude + (end.longitude - start.longitude) * progress,
    );

    setState(() {
      _markerVisualPosition = _markerAnimation.isCompleted ? end : position;
      if (_markerAnimation.isCompleted) {
        _markerStart = null;
        _markerEnd = null;
      }
    });
  }

  // ============================================================

  // TTS CHECK

  // ============================================================

  void _checkAndAnnounce() {
    if (!mounted) return;

    final manager = context.read<TripManager>();

    final trip = manager.currentTrip;

    if (trip == null) return;

    if (manager.state != TripState.active) return;

    if (_routePoints.isEmpty) return;

    final progress = _computeProgress(manager);

    _scheduleAnnounce(trip, progress.along);
  }

  // ============================================================

  // OFF-ROUTE CHECK

  // ============================================================

  void _checkOffRoute() {
    if (!mounted) return;

    if (widget.simulate) return;

    final manager = context.read<TripManager>();

    final settings = context.read<SettingsService>();

    final trip = manager.currentTrip;

    if (trip == null) return;

    if (manager.state != TripState.active) return;

    final progress = _computeProgress(manager);

    final isOff = _updateOffRoute(progress.offset);

    if (isOff != _lastOffRoute) {
      _lastOffRoute = isOff;

      if (mounted) setState(() {});
    }

    if (isOff && settings.autoReroute && !manager.isRerouting) {
      manager.reroute();
    }
  }

  // ============================================================

  // BACKGROUND SERVICE

  // ============================================================

  Future<void> _startBackgroundService() async {
    if (_bgStarted) return;

    final manager = context.read<TripManager>();

    final settings = context.read<SettingsService>();

    final currentTrip = manager.currentTrip;

    if (currentTrip == null) return;

    if (!settings.backgroundMode) {
      debugPrint('[DRIVING] Background mode disabled di settings');

      return;
    }

    final ok = await BackgroundService.start(
      destinationName: currentTrip.destinationName,

      distanceText:
          '${(currentTrip.totalDistance / 1000).toStringAsFixed(1)} km',

      etaText: '${(currentTrip.totalDuration / 60).toStringAsFixed(0)} menit',
    );

    _bgStarted = ok;

    debugPrint('[DRIVING] BG service start: $ok');
  }

  void _maybeUpdateBackgroundNotification({
    required Trip currentTrip,

    required double remaining,

    required double etaRemaining,
  }) {
    if (!_bgStarted) return;

    final now = DateTime.now();

    if (_lastBgUpdate != null &&
        now.difference(_lastBgUpdate!) < bgUpdateThrottle) {
      return;
    }

    _lastBgUpdate = now;

    BackgroundService.updateNotification(
      destinationName: currentTrip.destinationName,

      distanceText: '${(remaining / 1000).toStringAsFixed(1)} km',

      etaText: '${(etaRemaining / 60).toStringAsFixed(0)} menit',
    );
  }

  // ============================================================

  // ROUTE CACHE & SNAPPING

  // ============================================================

  static double _mPerLon(double lat) =>
      111320.0 * math.cos(lat * math.pi / 180.0);

  static const double _mPerLat = 110540.0;

  double _distM(double lat1, double lon1, double lat2, double lon2) {
    final dx = (lon2 - lon1) * _mPerLon((lat1 + lat2) / 2);

    final dy = (lat2 - lat1) * _mPerLat;

    return math.sqrt(dx * dx + dy * dy);
  }

  void _ensureRouteCache(Trip trip) {
    if (identical(_cachedTrip, trip)) return;

    final isReroute = _cachedTrip != null;

    _cachedTrip = trip;

    _lastSegIdx = 0;

    _offRouteSince = null;

    _lastOffRoute = false;

    _routePoints = trip.coords
        .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
        .toList(growable: false);

    final cum = List<double>.filled(_routePoints.length, 0.0);

    for (var i = 1; i < _routePoints.length; i++) {
      final a = _routePoints[i - 1];

      final b = _routePoints[i];

      cum[i] =
          cum[i - 1] + _distM(a.latitude, a.longitude, b.latitude, b.longitude);
    }

    _cumDist = cum;

    if (isReroute) {
      final manager = mounted ? context.read<TripManager>() : null;

      final distAlong = manager != null ? _computeProgress(manager).along : 0.0;

      final currentIdx = _currentStepIndex(trip, distAlong);

      _lastAnnouncedBeforeStepIdx = currentIdx - 1;

      _lastAnnouncedAfterStepIdx = currentIdx - 1;

      debugPrint('[DRIVING] Reroute cache rebuilt. currentStepIdx=$currentIdx');
    } else {
      _resetAnnouncements();
    }
  }

  _Snap _projectOnSegment(int i, double lat, double lon) {
    final a = _routePoints[i];

    final b = _routePoints[i + 1];

    final mLon = _mPerLon(lat);

    final abx = (b.longitude - a.longitude) * mLon;

    final aby = (b.latitude - a.latitude) * _mPerLat;

    final apx = (lon - a.longitude) * mLon;

    final apy = (lat - a.latitude) * _mPerLat;

    final len2 = abx * abx + aby * aby;

    final t = len2 == 0
        ? 0.0
        : ((apx * abx + apy * aby) / len2).clamp(0.0, 1.0).toDouble();

    final cx = abx * t;

    final cy = aby * t;

    final ox = apx - cx;

    final oy = apy - cy;

    return _Snap(
      along: _cumDist[i] + math.sqrt(len2) * t,

      offset: math.sqrt(ox * ox + oy * oy),

      segIdx: i,
    );
  }

  _Snap _searchRange(int from, int to, double lat, double lon) {
    _Snap? best;

    for (var i = from; i <= to; i++) {
      if (i < 0 || i >= _routePoints.length - 1) continue;

      final s = _projectOnSegment(i, lat, lon);

      if (best == null || s.offset < best.offset) best = s;
    }

    if (best == null) {
      return const _Snap(along: 0, offset: 999999, segIdx: 0);
    }

    return best;
  }

  _Snap? _snapToRoute(double lat, double lon) {
    final segCount = _routePoints.length - 1;

    if (segCount < 1) return null;

    final from = math.max(0, _lastSegIdx - snapWindowBack);

    final to = math.min(segCount - 1, _lastSegIdx + snapWindowForward);

    var snap = _searchRange(from, to, lat, lon);

    if (snap.offset > snapFallbackM) {
      final full = _searchRange(0, segCount - 1, lat, lon);

      if (full.offset < snap.offset) snap = full;
    }

    _lastSegIdx = snap.segIdx;

    return snap;
  }

  // ============================================================

  // LOGIC

  // ============================================================

  _Snap _computeProgress(TripManager m) {
    if (widget.simulate) {
      return _Snap(along: _simDistance, offset: 0, segIdx: 0);
    }

    final pos = m.lastPosition;

    if (pos == null) return const _Snap(along: 0, offset: 0, segIdx: 0);

    return _snapToRoute(pos.latitude, pos.longitude) ??
        const _Snap(along: 0, offset: 0, segIdx: 0);
  }

  int _currentStepIndex(Trip trip, double dist) {
    if (trip.steps.isEmpty) return 0;

    int idx = 0;

    for (var i = 0; i < trip.steps.length; i++) {
      if (trip.steps[i].routeDistance <= dist) idx = i;
    }

    return idx;
  }

  NavStep? _nextImportantStep(Trip trip, double dist) {
    for (final s in trip.steps) {
      if (s.important && s.routeDistance > dist + stepPassMarginM) return s;
    }

    return null;
  }

  NavStep? _nextImportantStepAfter(Trip trip, int afterIndex) {
    for (var i = afterIndex + 1; i < trip.steps.length; i++) {
      if (trip.steps[i].important) return trip.steps[i];
    }

    return null;
  }

  bool _updateOffRoute(double offset) {
    if (widget.simulate) return false;

    if (offset > offRouteThresholdM) {
      _offRouteSince ??= DateTime.now();

      return DateTime.now().difference(_offRouteSince!) >= offRouteConfirm;
    }

    _offRouteSince = null;

    return false;
  }

  void _resetAnnouncements() {
    _lastAnnouncedBeforeStepIdx = -1;

    _lastAnnouncedAfterStepIdx = -1;

    _arrivalAnnounced = false;

    _nearDestAnnounced = false;

    _lastSegIdx = 0;

    _offRouteSince = null;
  }

  List<_ClusterStep> _buildCluster(Trip trip, int startIdx) {
    final result = <_ClusterStep>[];

    for (var i = startIdx; i < trip.steps.length; i++) {
      final step = trip.steps[i];

      if (!step.important) continue;

      if (result.isEmpty) {
        result.add(_ClusterStep(index: i, step: step, distanceFromPrev: 0));
      } else {
        final prev = result.last;

        final distFromPrev =
            step.routeDistance - trip.steps[prev.index].routeDistance;

        if (distFromPrev > clusterThresholdM) break;

        result.add(
          _ClusterStep(index: i, step: step, distanceFromPrev: distFromPrev),
        );
      }

      if (result.length >= maxClusterSize) break;
    }

    return result;
  }

  // ============================================================

  // TTS ANNOUNCE

  // ============================================================

  void _scheduleAnnounce(Trip trip, double distAlong) {
    if (_announcing) return;

    _announcing = true;

    _maybeAnnounce(trip, distAlong).whenComplete(() {
      _announcing = false;
    });
  }

  Future<void> _maybeAnnounce(Trip trip, double distAlong) async {
    if (!mounted) return;

    final tts = context.read<TtsService>();

    if (!tts.enabled) return;

    final remaining = trip.totalDistance - distAlong;

    if (remaining <= arrivalDistanceM && !_arrivalAnnounced) {
      _arrivalAnnounced = true;

      await tts.speakArrived(trip.destinationName);

      return;
    }

    final nextImportant = _nextImportantStep(trip, distAlong);

    if (nextImportant == null &&
        remaining <= nearDestDistanceM &&
        remaining > arrivalDistanceM &&
        !_nearDestAnnounced) {
      _nearDestAnnounced = true;

      await tts.speakNearDestination(
        destinationName: trip.destinationName,

        distanceMeters: remaining,
      );

      return;
    }

    int latestPassed = -1;

    for (var i = 0; i < trip.steps.length; i++) {
      final step = trip.steps[i];

      if (!step.important) continue;

      if (distAlong > step.routeDistance + stepPassMarginM) {
        latestPassed = i;
      }
    }

    if (latestPassed > _lastAnnouncedAfterStepIdx) {
      _lastAnnouncedAfterStepIdx = latestPassed;

      if (latestPassed > _lastAnnouncedBeforeStepIdx) {
        _lastAnnouncedBeforeStepIdx = latestPassed;
      }

      final nextAfter = _nextImportantStepAfter(trip, latestPassed);

      bool speak;

      double distanceToNext = 0;

      if (nextAfter == null) {
        speak = remaining > nearDestDistanceM;
      } else {
        distanceToNext = nextAfter.routeDistance - distAlong;

        final nextIdx = trip.steps.indexOf(nextAfter);

        speak =
            distanceToNext >= afterMinDistanceM &&
            nextIdx > _lastAnnouncedBeforeStepIdx;
      }

      if (speak) {
        if (nextAfter == null) {
          await tts.speakAfterInstruction(isLastStep: true);
        } else {
          await tts.speakAfterInstruction(distanceMeters: distanceToNext);
        }

        return;
      }
    }

    if (nextImportant != null) {
      final stepIdx = trip.steps.indexOf(nextImportant);

      final distanceToStep = nextImportant.routeDistance - distAlong;

      if (stepIdx > _lastAnnouncedBeforeStepIdx &&
          distanceToStep > 0 &&
          distanceToStep <= announceDistanceM) {
        final cluster = _buildCluster(trip, stepIdx);

        if (cluster.isEmpty) return;

        for (final c in cluster) {
          if (c.index > _lastAnnouncedBeforeStepIdx) {
            _lastAnnouncedBeforeStepIdx = c.index;
          }
        }

        final ttsSteps = <TtsStep>[];

        for (var i = 0; i < cluster.length; i++) {
          final c = cluster[i];

          final dist = i == 0 ? distanceToStep : c.distanceFromPrev;

          ttsSteps.add(
            TtsStep(
              instruction: c.step.instruction,

              road: c.step.road.isNotEmpty ? c.step.road : null,

              distanceMeters: dist,
            ),
          );
        }

        await tts.speakBeforeInstruction(steps: ttsSteps);
      }
    }
  }

  // ============================================================

  // STOP

  // ============================================================

  Future<void> _stop() async {
    final manager = context.read<TripManager>();

    final tts = context.read<TtsService>();

    final navigator = Navigator.of(context);

    _announceTimer?.cancel();

    _offRouteTimer?.cancel();

    _sim.clearSimulation();

    manager.clearSimulation();

    await tts.stop();

    if (!widget.simulate) {
      await BackgroundService.stop();
    }

    await manager.stopTrip();

    if (!mounted) return;

    navigator.pop();
  }

  // ============================================================

  // BUILD

  // ============================================================

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<TripManager>();

    final ble = context.watch<MockBleService>();

    final tts = context.watch<TtsService>();

    final settings = context.watch<SettingsService>();

    final trip = manager.currentTrip;

    final pos = manager.lastPosition;

    if (trip == null) {
      return const Scaffold(body: Center(child: Text('Tidak ada trip aktif')));
    }

    if (settings.keepScreenOn) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }

    _ensureRouteCache(trip);

    if (manager.state == TripState.arrived && !_navigatedToArrived) {
      _navigatedToArrived = true;

      if (!widget.simulate && _bgStarted) {
        BackgroundService.stop();

        _bgStarted = false;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ArrivedScreen()),
        );
      });
    }

    final progress = _computeProgress(manager);

    final distAlong = progress.along;

    final offRoute = _lastOffRoute;

    final stepIdx = _currentStepIndex(trip, distAlong);

    final next = _nextImportantStep(trip, distAlong);

    final distanceToStep = next != null
        ? (next.routeDistance - distAlong)
              .clamp(0.0, double.infinity)
              .toDouble()
        : 0.0;

    final LatLng userLatLng;

    if (widget.simulate && _simDistance == 0 && _routePoints.isNotEmpty) {
      // Simulasi baru mulai → paksa pakai titik awal rute,

      // jangan pakai pos lama dari trip sebelumnya.

      userLatLng = _routePoints.first;
    } else if (pos != null) {
      userLatLng = LatLng(pos.latitude, pos.longitude);
    } else if (_routePoints.isNotEmpty) {
      userLatLng = _routePoints.first;
    } else {
      userLatLng = LatLng(trip.destinationLat, trip.destinationLon);
    }

    final remaining = (trip.totalDistance - distAlong)
        .clamp(0.0, double.infinity)
        .toDouble();

    final etaRemaining = trip.totalDuration > 0
        ? trip.totalDuration * (remaining / trip.totalDistance)
        : 0.0;

    if (!widget.simulate) {
      _maybeUpdateBackgroundNotification(
        currentTrip: trip,

        remaining: remaining,

        etaRemaining: etaRemaining,
      );
    }

    final rawHeading = pos?.heading ?? 0;

    final heading = rawHeading.isFinite && rawHeading >= 0 ? rawHeading : 0.0;

    _requestMarkerPosition(userLatLng);
    final markerLatLng = _markerVisualPosition ?? userLatLng;

    _requestCameraFollow(userLatLng, heading);

    final surface = Theme.of(context).colorScheme.surface;

    final onSurface = Theme.of(context).colorScheme.onSurface;

    // ============================================================

    // Tentukan kartu mana yang ditampilkan di atas

    // ============================================================

    Widget? topCard;

    if (!offRoute) {
      if (next != null) {
        // Ada step penting berikutnya → nav card normal

        topCard = NavInstructionCard(
          step: next,

          distanceToStep: distanceToStep,
        );
      } else if (remaining <= nearDestDistanceM) {
        // Tidak ada step penting + sudah dekat tujuan → kartu hijau

        topCard = _nearDestinationCard(trip.destinationName, remaining);
      } else {
        // Tidak ada step penting tapi masih jauh → kartu "LANJUT LURUS"

        topCard = _straightAheadCard(remaining);
      }
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,

            options: MapOptions(
              initialCenter: userLatLng,

              initialZoom: 16,

              onMapReady: () {
                _mapReady = true;
                if (_followUser) {
                  _requestCameraFollow(userLatLng, heading);
                }
              },

              onPositionChanged: (p, hasGesture) {
                if (hasGesture && _followUser) {
                  _cameraAnimation.stop();
                  setState(() => _followUser = false);
                }
              },
            ),

            children: [
              TileLayer(
                urlTemplate:
                    'https://tile-a.openstreetmap.fr/hot/{z}/{x}/{y}.png',

                userAgentPackageName: 'com.example.abot_drivers',

                maxZoom: 19,
              ),

              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,

                    strokeWidth: 6,

                    color: AppColors.primary,
                  ),
                ],
              ),

              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(trip.destinationLat, trip.destinationLon),

                    width: 40,

                    height: 40,

                    child: const Icon(
                      Icons.location_on,

                      color: AppColors.destination,

                      size: 40,
                    ),
                  ),

                  Marker(
                    point: markerLatLng,

                    width: 80,

                    height: 80,

                    child: AnimatedDriverMarker(
                      position: markerLatLng,

                      heading: heading,

                      size: 40,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // TOP CARD
          Positioned(
            top: 0,

            left: 0,

            right: 0,

            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),

                child: Column(
                  mainAxisSize: MainAxisSize.min,

                  crossAxisAlignment: CrossAxisAlignment.stretch,

                  children: [
                    ?topCard,

                    if (offRoute || manager.isRerouting) ...[
                      if (topCard != null) const SizedBox(height: 8),

                      _offRouteBanner(rerouting: manager.isRerouting),
                    ],
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            left: AppSpacing.lg,

            right: AppSpacing.lg,

            bottom: AppSpacing.lg + MediaQuery.of(context).padding.bottom,

            child: Column(
              mainAxisSize: MainAxisSize.min,

              crossAxisAlignment: CrossAxisAlignment.stretch,

              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,

                  children: [
                    if (_showDebug)
                      Flexible(
                        child: DebugOverlay(
                          position: pos,

                          stepIndex: stepIdx,

                          totalSteps: trip.steps.length,

                          progressMeters: distAlong,

                          totalMeters: trip.totalDistance,

                          bleConnected: ble.isConnected,

                          bleSendCount: ble.sendCount,

                          bleBytes: ble.bytesSent,
                        ),
                      ),

                    const Spacer(),

                    Column(
                      mainAxisSize: MainAxisSize.min,

                      children: [
                        _circleButton(
                          context: context,

                          icon: _showDebug
                              ? Icons.bug_report
                              : Icons.bug_report_outlined,

                          onTap: () => setState(() => _showDebug = !_showDebug),

                          highlight: _showDebug,
                        ),

                        const SizedBox(height: 8),

                        _circleButton(
                          context: context,

                          icon: tts.enabled
                              ? Icons.volume_up
                              : Icons.volume_off,

                          onTap: () {
                            final newVal = !tts.enabled;

                            settings.setTtsEnabled(newVal);

                            tts.setEnabled(newVal);
                          },

                          highlight: !tts.enabled,
                        ),

                        const SizedBox(height: 8),

                        _circleButton(
                          context: context,

                          icon: Icons.my_location,

                          onTap: () {
                            _cameraAnimation.stop();
                            _lastRequestedCameraTarget = null;
                            _lastRequestedCameraHeading = null;

                            setState(() => _followUser = true);
                            _requestCameraFollow(userLatLng, heading);
                          },

                          highlight: false,
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                if (widget.simulate) ...[
                  _simToolbar(context),

                  const SizedBox(height: 8),
                ],

                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),

                  decoration: BoxDecoration(
                    color: surface,

                    borderRadius: BorderRadius.circular(AppRadius.lg),

                    boxShadow: AppShadows.floating,
                  ),

                  child: Row(
                    children: [
                      _stat(
                        settings.formatDistanceShort(remaining),

                        'Sisa',

                        onSurface,
                      ),

                      const SizedBox(width: AppSpacing.xl),

                      _stat(
                        '${(etaRemaining / 60).toStringAsFixed(0)} mnt',

                        'Perkiraan',

                        onSurface,
                      ),

                      const Spacer(),

                      TextButton(
                        onPressed: _stop,

                        child: const Text(
                          'Selesai',

                          style: TextStyle(color: AppColors.destination),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================

  // STRAIGHT AHEAD CARD (fallback saat tidak ada step penting)

  // ============================================================

  Widget _straightAheadCard(double remaining) {
    return Container(
      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: AppColors.primary,

        borderRadius: BorderRadius.circular(AppRadius.lg),

        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.4),

            blurRadius: 20,

            offset: const Offset(0, 6),
          ),
        ],
      ),

      child: Row(
        children: [
          const Icon(Icons.straight, color: Colors.white, size: 56),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  remaining >= 1000
                      ? '${(remaining / 1000).toStringAsFixed(1)} km'
                      : '${remaining.round()} m',

                  style: const TextStyle(
                    color: Colors.white,

                    fontSize: 32,

                    fontWeight: FontWeight.bold,

                    height: 1.1,
                  ),
                ),

                const Text(
                  'LANJUT LURUS',

                  style: TextStyle(
                    color: Colors.white,

                    fontSize: 18,

                    fontWeight: FontWeight.w600,
                  ),
                ),

                Text(
                  'Menuju tujuan',

                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),

                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================

  // NEAR DESTINATION CARD (hijau)

  // ============================================================

  Widget _nearDestinationCard(String destinationName, double remaining) {
    return Container(
      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: const Color(0xFF43A047),

        borderRadius: BorderRadius.circular(AppRadius.lg),

        boxShadow: [
          BoxShadow(
            color: const Color(0xFF43A047).withValues(alpha: 0.4),

            blurRadius: 20,

            offset: const Offset(0, 6),
          ),
        ],
      ),

      child: Row(
        children: [
          const Icon(Icons.flag_rounded, color: Colors.white, size: 56),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  remaining >= 1000
                      ? '${(remaining / 1000).toStringAsFixed(1)} km'
                      : '${remaining.round()} m',

                  style: const TextStyle(
                    color: Colors.white,

                    fontSize: 32,

                    fontWeight: FontWeight.bold,

                    height: 1.1,
                  ),
                ),

                const Text(
                  'HAMPIR SAMPAI',

                  style: TextStyle(
                    color: Colors.white,

                    fontSize: 18,

                    fontWeight: FontWeight.w600,
                  ),
                ),

                if (destinationName.isNotEmpty)
                  Text(
                    destinationName,

                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),

                      fontSize: 14,
                    ),

                    maxLines: 1,

                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _offRouteBanner({bool rerouting = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),

      decoration: BoxDecoration(
        color: Colors.orange.shade700,

        borderRadius: BorderRadius.circular(AppRadius.lg),

        boxShadow: AppShadows.card,
      ),

      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,

            color: Colors.white,

            size: 20,
          ),

          const SizedBox(width: 8),

          Expanded(
            child: Text(
              rerouting ? 'Menghitung ulang rute...' : 'Anda keluar dari rute',

              style: const TextStyle(
                color: Colors.white,

                fontWeight: FontWeight.bold,

                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _simToolbar(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),

      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.95),

        borderRadius: BorderRadius.circular(AppRadius.lg),

        boxShadow: AppShadows.floating,
      ),

      child: Column(
        mainAxisSize: MainAxisSize.min,

        children: [
          Row(
            children: [
              const Icon(Icons.smart_toy, color: Colors.orangeAccent, size: 18),

              const SizedBox(width: 6),

              const Text(
                'SIMULASI',

                style: TextStyle(
                  color: Colors.orangeAccent,

                  fontWeight: FontWeight.bold,

                  fontSize: 12,
                ),
              ),

              const Spacer(),

              Text(
                '${_simDistance.toStringAsFixed(0)} m',

                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,

            children: [
              _simButton(
                icon: Icons.restart_alt,

                label: 'Reset',

                onTap: () {
                  _sim.restart();

                  setState(_resetAnnouncements);
                },
              ),

              _simButton(
                icon: _sim.isPlaying ? Icons.pause : Icons.play_arrow,

                label: _sim.isPlaying ? 'Pause' : 'Play',

                onTap: () {
                  if (_sim.isPlaying) {
                    _sim.pause();
                  } else if (_sim.isPaused) {
                    _sim.resume();
                  } else {
                    final manager = context.read<TripManager>();

                    if (manager.currentTrip != null) {
                      _sim.start(manager.currentTrip!);
                    }
                  }

                  setState(() {});
                },
              ),

              _simButton(
                icon: Icons.speed,

                label: '${_sim.speedMultiplier.toStringAsFixed(0)}x',

                onTap: _showSpeedPicker,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _simButton({
    required IconData icon,

    required String label,

    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,

      child: Column(
        mainAxisSize: MainAxisSize.min,

        children: [
          Icon(icon, size: 26),

          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  void _showSpeedPicker() {
    final surface = Theme.of(context).colorScheme.surface;

    showModalBottomSheet(
      context: context,

      backgroundColor: Colors.transparent,

      builder: (_) => Container(
        padding: const EdgeInsets.all(AppSpacing.xl),

        decoration: BoxDecoration(
          color: surface,

          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),

        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            const Text(
              'Kecepatan Simulasi',

              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: AppSpacing.lg),

            Wrap(
              spacing: 12,

              children: [1, 2, 5, 10, 20, 50].map((s) {
                final selected = _sim.speedMultiplier == s.toDouble();

                return ChoiceChip(
                  label: Text('${s}x'),

                  selected: selected,

                  onSelected: (_) {
                    _sim.setSpeed(s.toDouble());

                    setState(() {});

                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleButton({
    required BuildContext context,

    required IconData icon,

    required VoidCallback onTap,

    bool highlight = false,
  }) {
    final surface = Theme.of(context).colorScheme.surface;

    return GestureDetector(
      onTap: onTap,

      child: Container(
        width: 44,

        height: 44,

        decoration: BoxDecoration(
          color: highlight ? AppColors.primary : surface,

          shape: BoxShape.circle,

          boxShadow: AppShadows.card,
        ),

        child: Icon(
          icon,

          color: highlight ? Colors.white : AppColors.primary,

          size: 22,
        ),
      ),
    );
  }

  Widget _stat(String value, String label, Color onSurface) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Text(
          value,

          style: TextStyle(
            fontSize: 20,

            fontWeight: FontWeight.bold,

            color: onSurface,
          ),
        ),

        Text(
          label,

          style: TextStyle(
            fontSize: 11,

            color: onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _ClusterStep {
  final int index;

  final NavStep step;

  final double distanceFromPrev;

  _ClusterStep({
    required this.index,

    required this.step,

    required this.distanceFromPrev,
  });
}

class _Snap {
  final double along;

  final double offset;

  final int segIdx;

  const _Snap({
    required this.along,

    required this.offset,

    required this.segIdx,
  });
}
