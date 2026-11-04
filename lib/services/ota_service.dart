import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'ota_link.dart';
import 'ota_protocol.dart';

/// Fase OTA di sisi aplikasi.
enum OtaPhase {
  idle,
  checking,
  upToDate,
  available,
  starting,
  connectingWifi,
  fetchingManifest,
  downloading,
  verifying,
  installing,
  rebooting,
  verifyingVersion,
  success,
  failed,
}

class OtaFailure {
  const OtaFailure(this.code, [this.detail]);

  final OtaErrorCode code;
  final String? detail;

  String get message {
    final d = detail;
    if (d == null || d.isEmpty) return code.message;
    return '${code.message} ($d)';
  }
}

class OtaConfig {
  const OtaConfig({
    this.manifestUrl,
    this.useSimulatedManifest = true,
    this.deviceModel = 'abot-esp32s3',
    this.acceptTimeout = const Duration(seconds: 10),
    this.stageTimeout = const Duration(seconds: 45),
    this.rebootTimeout = const Duration(seconds: 120),
    this.versionTimeout = const Duration(seconds: 20),
  });

  /// URL manifest (HTTPS). Kosong = pakai manifest simulasi.
  final Uri? manifestUrl;

  /// true: tidak mengunduh manifest, buat manifest tiruan (untuk Wokwi).
  final bool useSimulatedManifest;

  final String deviceModel;
  final Duration acceptTimeout;
  final Duration stageTimeout;
  final Duration rebootTimeout;
  final Duration versionTimeout;
}

/// State machine OTA. Satu instance untuk seluruh aplikasi (via Provider),
/// supaya progres tidak hilang saat pengguna keluar dari layar Pengaturan.
class OtaService extends ChangeNotifier {
  OtaService({required OtaLink link, this.config = const OtaConfig()})
      : _link = link {
    _messageSub = _link.messages.listen(_onMessage);
    _readySub = _link.readyChanges.listen(_onReadyChanged);
  }

  static const Set<OtaPhase> _runningPhases = {
    OtaPhase.starting,
    OtaPhase.connectingWifi,
    OtaPhase.fetchingManifest,
    OtaPhase.downloading,
    OtaPhase.verifying,
    OtaPhase.installing,
    OtaPhase.rebooting,
    OtaPhase.verifyingVersion,
  };

  static const Set<OtaPhase> _cancellablePhases = {
    OtaPhase.starting,
    OtaPhase.connectingWifi,
    OtaPhase.fetchingManifest,
    OtaPhase.downloading,
  };

  final OtaLink _link;
  final OtaConfig config;

  StreamSubscription<Map<String, dynamic>>? _messageSub;
  StreamSubscription<bool>? _readySub;
  Timer? _timer;

  bool _disposed = false;

  OtaPhase _phase = OtaPhase.idle;
  double _progress = 0;
  OtaFailure? _failure;
  OtaManifest? _manifest;

  String? _currentVersion;
  String? _targetVersion;
  String? _requestId;
  bool _linkDropped = false;
  bool _simulatedResult = false;

  int? _battery;
  bool? _charging;
  bool? _tripActive;
  bool? _routeActive;

  // ============================================================
  // GETTERS
  // ============================================================
  OtaPhase get phase => _phase;

  /// 0.0 - 1.0 (progres tahap unduhan).
  double get progress => _progress;
  OtaFailure? get failure => _failure;
  OtaManifest? get manifest => _manifest;

  String? get currentVersion => _currentVersion;
  String? get targetVersion => _targetVersion;
  int? get battery => _battery;

  bool get isRunning => _runningPhases.contains(_phase);
  bool get isChecking => _phase == OtaPhase.checking;
  bool get canCancel => _cancellablePhases.contains(_phase);
  bool get isSimulated => config.useSimulatedManifest || config.manifestUrl == null;

  /// True jika sukses lewat jalur simulasi lama (firmware V3.45).
  bool get succeededInSimulation => _simulatedResult;

  // ============================================================
  // PUBLIC API
  // ============================================================
  Future<void> checkForUpdate() async {
    if (isRunning || isChecking) return;

    _failure = null;
    _manifest = null;
    _progress = 0;
    _simulatedResult = false;
    _setPhase(OtaPhase.checking);

    final String current;

    try {
      current = await _requireVersion();
    } catch (error) {
      _fail(OtaErrorCode.linkLost, _clean(error));
      return;
    }

    if (_disposed) return;

    final OtaManifest manifest;

    try {
      final url = config.manifestUrl;

      if (config.useSimulatedManifest || url == null) {
        manifest = OtaManifest.simulated(
          from: current,
          device: config.deviceModel,
        );
      } else {
        manifest = await _fetchManifest(url);
      }

      if (manifest.device != config.deviceModel) {
        throw OtaManifestException(
          'Firmware untuk perangkat lain (${manifest.device}).',
        );
      }
    } on OtaManifestException catch (error) {
      _fail(OtaErrorCode.manifestFailed, error.message);
      return;
    } catch (error) {
      _fail(OtaErrorCode.manifestFailed, _clean(error));
      return;
    }

    if (_disposed) return;

    _manifest = manifest;

    final minVersion = manifest.minVersion;
    if (minVersion != null && compareVersions(current, minVersion) < 0) {
      _fail(
        OtaErrorCode.noUpdate,
        'versi $current terlalu lama, perlu minimal $minVersion',
      );
      return;
    }

    if (compareVersions(manifest.version, current) <= 0) {
      _setPhase(OtaPhase.upToDate);
    } else {
      _setPhase(OtaPhase.available);
    }
  }

  Future<void> startUpdate() async {
    final manifest = _manifest;

    if (isRunning || _phase != OtaPhase.available || manifest == null) {
      return;
    }

    // Pengecekan awal di aplikasi (firmware tetap mengecek ulang).
    if (_tripActive == true || _routeActive == true) {
      _fail(OtaErrorCode.tripActive);
      return;
    }

    final battery = _battery;
    if (battery != null && _charging != true && battery < manifest.minBattery) {
      _fail(
        OtaErrorCode.lowBattery,
        'baterai $battery%, minimal ${manifest.minBattery}%',
      );
      return;
    }

    _failure = null;
    _progress = 0;
    _targetVersion = manifest.version;
    _requestId = _newId();
    _linkDropped = false;
    _simulatedResult = false;
    _setPhase(OtaPhase.starting);

    try {
      await _link.ensureReady(timeout: const Duration(seconds: 20));

      if (_disposed || _phase != OtaPhase.starting) return;

      _link.send({
        't': OtaMsg.start,
        'id': _requestId,
        'ver': manifest.version,
      });

      _arm(config.acceptTimeout, () {
        _fail(OtaErrorCode.appTimeout, 'ABOT tidak menjawab perintah update');
      });
    } catch (error) {
      _fail(OtaErrorCode.linkLost, _clean(error));
    }
  }

  /// Batalkan update (hanya sebelum tahap verifikasi).
  void cancelUpdate() {
    if (!canCancel) return;

    try {
      _link.send({
        't': OtaMsg.cancel,
        if (_requestId != null) 'id': _requestId,
      });
    } catch (_) {
      // Tidak terkirim; timer di bawah tetap menutup proses.
    }

    _arm(const Duration(seconds: 8), () {
      _fail(
        OtaErrorCode.cancelled,
        'perintah batal dikirim, ABOT belum mengonfirmasi',
      );
    });
  }

  /// Kembali ke keadaan awal (setelah sukses/gagal).
  void reset() {
    if (isRunning) return;

    _cancelTimer();
    _failure = null;
    _manifest = null;
    _progress = 0;
    _simulatedResult = false;
    _setPhase(OtaPhase.idle);
  }

  // ============================================================
  // PESAN MASUK
  // ============================================================
  void _onMessage(Map<String, dynamic> m) {
    final type = m['t']?.toString();

    switch (type) {
      case 'hb':
      case 'status':
      case 'device':
        _readDeviceInfo(m);
        return;

      case OtaMsg.accepted:
        if (_forCurrentRequest(m)) _onAccepted(m);
        return;

      case OtaMsg.progress:
        if (_forCurrentRequest(m)) _onProgress(m);
        return;

      case OtaMsg.done:
        if (_forCurrentRequest(m)) _onDone(m);
        return;

      case OtaMsg.error:
        if (_forCurrentRequest(m)) _onError(m);
        return;

      case OtaMsg.result:
        if (_forCurrentRequest(m)) _onResult(m);
        return;

      case OtaMsg.simulated:
        if (isRunning) _onSimulated();
        return;
    }
  }

  bool _forCurrentRequest(Map<String, dynamic> m) {
    if (!isRunning) return false;

    final id = m['id']?.toString();
    final mine = _requestId;

    return id == null || mine == null || id == mine;
  }

  void _onAccepted(Map<String, dynamic> m) {
    if (_phase != OtaPhase.starting) return;

    final to = m['to']?.toString();
    if (to != null && to.isNotEmpty) _targetVersion = to;

    _progress = 0;
    _setPhase(OtaPhase.connectingWifi);
    _armStageTimer();
  }

  void _onProgress(Map<String, dynamic> m) {
    if (_phase == OtaPhase.rebooting || _phase == OtaPhase.verifyingVersion) {
      return;
    }

    final raw = m['progress'];
    final percent = (raw is num ? raw.toDouble() : 0.0).clamp(0.0, 100.0);

    final next = switch (m['stage']?.toString()) {
      OtaStage.wifi => OtaPhase.connectingWifi,
      OtaStage.manifest => OtaPhase.fetchingManifest,
      OtaStage.verify => OtaPhase.verifying,
      OtaStage.install => OtaPhase.installing,
      _ => OtaPhase.downloading, // termasuk firmware lama tanpa "stage"
    };

    _progress = percent / 100;
    _setPhase(next);
    _armStageTimer();
  }

  void _onDone(Map<String, dynamic> m) {
    final to = m['to']?.toString();
    if (to != null && to.isNotEmpty) _targetVersion = to;

    _progress = 1;
    _linkDropped = false;
    _setPhase(OtaPhase.rebooting);

    _arm(config.rebootTimeout, () {
      _fail(OtaErrorCode.appTimeout, 'ABOT tidak kembali online setelah update');
    });
  }

  void _onError(Map<String, dynamic> m) {
    _fail(
      OtaErrorCode.parse(m['code']?.toString()),
      m['message']?.toString(),
    );
  }

  void _onResult(Map<String, dynamic> m) {
    final ok = _toBool(m['ok']);
    final ver = m['ver']?.toString();
    final rolledBack = _toBool(m['rolled_back']) == true;

    if (ver != null && ver.isNotEmpty) _currentVersion = ver;

    final target = _targetVersion;

    if (ok == true && (target == null || ver == null || _sameVersion(ver, target))) {
      _succeed();
    } else {
      _fail(
        OtaErrorCode.bootFailed,
        rolledBack ? null : 'versi ${ver ?? '?'} tidak sesuai target',
      );
    }
  }

  void _onSimulated() {
    _simulatedResult = true;
    _succeed();
  }

  void _readDeviceInfo(Map<String, dynamic> m) {
    var changed = false;

    final ver = m['ver']?.toString();
    if (ver != null && ver.isNotEmpty && ver != _currentVersion) {
      _currentVersion = ver;
      changed = true;
    }

    final batt = _toInt(m['batt']);
    if (batt != null && batt != _battery) {
      _battery = batt;
      changed = true;
    }

    final chg = _toBool(m['chg']);
    if (chg != null && chg != _charging) {
      _charging = chg;
      changed = true;
    }

    final trip = _toBool(m['trip']);
    if (trip != null && trip != _tripActive) {
      _tripActive = trip;
      changed = true;
    }

    final route = _toBool(m['route']);
    if (route != null && route != _routeActive) {
      _routeActive = route;
      changed = true;
    }

    if (ver != null &&
        ver.isNotEmpty &&
        (_phase == OtaPhase.rebooting || _phase == OtaPhase.verifyingVersion)) {
      _evaluateVersion(ver);
      return; // _succeed/_fail sudah memanggil notify bila perlu
    }

    if (changed) _notify();
  }

  // ============================================================
  // KONEKSI
  // ============================================================
  void _onReadyChanged(bool ready) {
    if (_phase != OtaPhase.rebooting) return;

    if (!ready) {
      _linkDropped = true;
    } else if (_linkDropped) {
      _setPhase(OtaPhase.verifyingVersion);

      _arm(config.versionTimeout, () {
        _fail(OtaErrorCode.appTimeout, 'versi baru belum bisa diverifikasi');
      });
    }
  }

  /// Dipanggil saat ABOT melaporkan versi setelah ota_done.
  void _evaluateVersion(String reported) {
    final target = _targetVersion;
    if (target == null) return;

    if (_sameVersion(reported, target)) {
      _succeed();
      return;
    }

    // ABOT sudah kembali online tapi versinya masih yang lama.
    if (_phase == OtaPhase.verifyingVersion) {
      _fail(
        OtaErrorCode.bootFailed,
        'ABOT kembali dengan versi $reported, target $target',
      );
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================
  Future<String> _requireVersion() async {
    String? version = _currentVersion;
    if (version != null) return version;

    await _link.ensureReady(timeout: const Duration(seconds: 15));

    for (var i = 0; i < 20 && !_disposed; i++) {
      version = _currentVersion;
      if (version != null) return version;

      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    throw TimeoutException('Versi firmware ABOT belum diterima');
  }

  Future<OtaManifest> _fetchManifest(Uri url) async {
    if (url.scheme != 'https') {
      throw OtaManifestException('URL manifest harus HTTPS.');
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);

    try {
      final request =
          await client.getUrl(url).timeout(const Duration(seconds: 10));
      final response =
          await request.close().timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw OtaManifestException(
          'Server menjawab HTTP ${response.statusCode}.',
        );
      }

      if (response.contentLength > 65536) {
        throw OtaManifestException('Manifest terlalu besar.');
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));

      final decoded = jsonDecode(body);

      if (decoded is! Map<String, dynamic>) {
        throw OtaManifestException('Format manifest salah.');
      }

      return OtaManifest.fromJson(decoded);
    } finally {
      client.close(force: true);
    }
  }

  bool _sameVersion(String a, String b) => compareVersions(a, b) == 0;

  void _succeed() {
    _cancelTimer();
    _progress = 1;
    _failure = null;

    final target = _targetVersion;
    if (target != null) _currentVersion = target;

    _setPhase(OtaPhase.success);
  }

  void _fail(OtaErrorCode code, [String? detail]) {
    _cancelTimer();
    _failure = OtaFailure(code, detail);

    developer.log(
      'OTA gagal: ${code.wire} ${detail ?? ''}',
      name: 'ABOT OTA',
    );

    _setPhase(OtaPhase.failed);
  }

  void _armStageTimer() {
    _arm(config.stageTimeout, () {
      _fail(OtaErrorCode.appTimeout, 'tidak ada progres selama update');
    });
  }

  void _arm(Duration duration, VoidCallback onTimeout) {
    _timer?.cancel();
    _timer = Timer(duration, () {
      if (_disposed) return;
      onTimeout();
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _setPhase(OtaPhase next) {
    _phase = next;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String _newId() => DateTime.now().millisecondsSinceEpoch.toRadixString(36);

  String _clean(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('Bad state: ', '');

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  bool? _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;

    final text = value?.toString().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;

    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimer();
    _messageSub?.cancel();
    _readySub?.cancel();
    super.dispose();
  }
}