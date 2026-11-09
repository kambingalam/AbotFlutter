import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../config/app_config.dart';


enum AbotMqttState {
  disconnected,
  connecting,
  connected,
  authenticating,
  ready,
  authFailed,
  deviceOffline,
}

class AbotMqttService {
  static const String host = 'broker.emqx.io';

  static const int port =
      AppConfig.mqttUseTls ? AppConfig.mqttTlsPort : 1883;

  static const String commandTopic =
      'abot/wokwi/477375325542330369/v337/command';

  static const String statusTopic =
      'abot/wokwi/477375325542330369/v337/status';

  static const String authToken = 'abot-secret-2025';

  static const Duration authTimeout = Duration(seconds: 15);
  static const Duration subscribeTimeout = Duration(seconds: 10);
  static const Duration heartbeatTimeout = Duration(seconds: 30);

  /// Jeda minimum antar percobaan auth otomatis (dipicu heartbeat).
  static const Duration _autoReauthInterval = Duration(seconds: 10);

  static const int _maxConnectRetries = 5;
  static const Duration _initialBackoff = Duration(seconds: 2);
  static const int _maxOutboxSize = 100;

  final Queue<Map<String, dynamic>> _outbox = Queue<>();


  MqttServerClient? _client;

  final StreamController<Map<String, dynamic>> _messages =
      StreamController<Map<String, dynamic>>.broadcast();

  final StreamController<AbotMqttState> _stateController =
      StreamController<AbotMqttState>.broadcast();

  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>?
      _updatesSubscription;

  Timer? _authTimer;
  Timer? _heartbeatMonitor;

  Future<void>? _connectFuture;

  /// Semua pemanggil connectAndAuthenticate yang sedang menunggu.
  final List<Completer<void>> _authWaiters = <Completer<void>>[];

  bool _disposed = false;
  bool _authenticated = false;
  bool _subscribed = false;
  bool _subscribing = false;
  bool _authInProgress = false;

  DateTime? _lastHeartbeat;
  DateTime? _lastAuthAttempt;

  AbotMqttState _state = AbotMqttState.disconnected;

  String? _firmwareVersion;
  int? _uptimeSeconds;
  int? _freeHeap;
  bool? _routeActive;
  bool? _tripActive;

  Stream<Map<String, dynamic>> get messages => _messages.stream;
  Stream<AbotMqttState> get states => _stateController.stream;

  AbotMqttState get state => _state;
  bool get isAuthenticated => _authenticated;
  bool get isReady => isConnected && _authenticated;

  DateTime? get lastHeartbeat => _lastHeartbeat;
  String? get firmwareVersion => _firmwareVersion;
  int? get uptimeSeconds => _uptimeSeconds;
  int? get freeHeap => _freeHeap;
  bool? get routeActive => _routeActive;
  bool? get tripActive => _tripActive;

  bool get isConnected =>
      !_disposed &&
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  // ============================================================
  // STATE
  // ============================================================
  void _setState(AbotMqttState nextState) {
    if (_state == nextState) return;

    _state = nextState;

    if (!_stateController.isClosed) {
      _stateController.add(nextState);
    }

    _log('State changed: $nextState', name: 'ABOT MQTT');

    _resolveAuthWaiters(nextState);
  }

  void _resolveAuthWaiters(AbotMqttState nextState) {
    if (_authWaiters.isEmpty) return;

    final StateError? error = switch (nextState) {
      AbotMqttState.authFailed => StateError('ESP32 gagal autentikasi'),
      AbotMqttState.deviceOffline => StateError('ESP32 sedang offline'),
      AbotMqttState.disconnected => StateError('MQTT terputus'),
      _ => null,
    };

    if (nextState != AbotMqttState.ready && error == null) return;

    final waiters = List<Completer<void>>.of(_authWaiters);
    _authWaiters.clear();

    for (final waiter in waiters) {
      if (waiter.isCompleted) continue;

      if (error == null) {
        waiter.complete();
      } else {
        waiter.completeError(error);
      }
    }
  }

  // ============================================================
  // CONNECT
  // ============================================================
  Future<void> connect() {
    if (_disposed) {
      return Future<void>.error(StateError('MQTT service sudah ditutup'));
    }

    if (isConnected) {
      return Future<void>.value();
    }

    final ongoing = _connectFuture;
    if (ongoing != null) return ongoing;

    final future = _connectWithRetry();
    _connectFuture = future;

    return future.whenComplete(() {
      if (identical(_connectFuture, future)) {
        _connectFuture = null;
      }
    });
  }

  /// Hubungkan lalu tunggu ESP32 terautentikasi.
  ///
  /// Jika sebelumnya auth gagal / ESP32 offline tapi koneksi MQTT masih
  /// hidup, method ini akan mencoba autentikasi ulang (bukan langsung
  /// melempar error dengan state lama).
  Future<void> connectAndAuthenticate({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await connect();

    if (_disposed) {
      throw StateError('MQTT service sudah ditutup');
    }

    if (isReady) return;

    final completer = Completer<void>();
    _authWaiters.add(completer);

    try {
      final client = _client;

      // Coba ulang kalau state sebelumnya gagal.
      if (client != null &&
          (_state == AbotMqttState.authFailed ||
              _state == AbotMqttState.deviceOffline)) {
        unawaited(_subscribeAndAuthenticate(client, force: true));
      }

      // Periksa lagi setelah waiter terpasang agar event tidak terlewat.
      if (isReady && !completer.isCompleted) {
        completer.complete();
      }

      await completer.future.timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException('Timeout menunggu ESP32 terautentikasi');
        },
      );
    } finally {
      _authWaiters.remove(completer);
    }
  }

  /// Bersihkan client lama agar tidak ada dua client (dan dua auto-reconnect)
  /// yang hidup bersamaan.
  Future<void> _teardownClient() async {
    final old = _client;
    _client = null;

    await _updatesSubscription?.cancel();
    _updatesSubscription = null;

    if (old == null) return;

    old
      ..autoReconnect = false
      ..onConnected = null
      ..onAutoReconnect = null
      ..onAutoReconnected = null
      ..onDisconnected = null
      ..onSubscribed = null
      ..onSubscribeFail = null;

    try {
      old.disconnect();
    } catch (_) {}
  }

  Future<void> _connectWithRetry() async {
    Duration delay = _initialBackoff;
    for (var attempt = 1; attempt <= _maxConnectRetries; attempt++) {
      if (_disposed) {
        throw StateError('MQTT service sudah ditutup');
      }

      try {
        await _connectInternal();
        _flushOutbox();
        return;
      } catch (error, stackTrace) {
        _log(
          'MQTT connect attempt $attempt/$_maxConnectRetries gagal: $error',
          name: 'ABOT MQTT',
          error: error,
          stackTrace: stackTrace,
        );

        if (attempt == _maxConnectRetries || _disposed) {
          rethrow;
        }

        await Future.delayed(delay);
        delay = Duration(seconds: delay.inSeconds * 2);
      }
    }
  }

  Future<void> _connectInternal() async {
    await _teardownClient();

    _resetAuthentication();
    _setState(AbotMqttState.connecting);

    final clientId = 'ABOT-FLUTTER-${DateTime.now().millisecondsSinceEpoch}';

    final client = MqttServerClient.withPort(host, clientId, port);

    _client = client;

    client
      ..logging(on: false)
      ..keepAlivePeriod = 30
      ..connectTimeoutPeriod = 10000
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = false
      ..onConnected = () {
        _log('MQTT connected', name: 'ABOT MQTT');

        _attachUpdates(client);
        _resetAuthentication();
        _setState(AbotMqttState.connected);

        unawaited(_subscribeAndAuthenticate(client));
      }
      ..onAutoReconnect = () {
        _log('MQTT reconnecting', name: 'ABOT MQTT');

        _resetAuthentication();
        _setState(AbotMqttState.connecting);
      }
      ..onAutoReconnected = () {
        _log('MQTT reconnected', name: 'ABOT MQTT');

        _attachUpdates(client);
        _resetAuthentication();
        _setState(AbotMqttState.connected);

        unawaited(_subscribeAndAuthenticate(client));
      }
      ..onDisconnected = () {
        _log('MQTT disconnected', name: 'ABOT MQTT');

        _resetAuthentication();
        _setState(AbotMqttState.disconnected);
      };

    client.connectionMessage =
        MqttConnectMessage().withClientIdentifier(clientId).startClean();

    try {
      _log('Connecting to $host:$port', name: 'ABOT MQTT');

      await client.connect();

      if (_disposed) {
        client.disconnect();
        throw StateError('MQTT service sudah ditutup');
      }

      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        throw Exception(
          'MQTT gagal terhubung: ${client.connectionStatus?.state}',
        );
      }

      // Jaga-jaga jika onConnected belum sempat memasang listener.
      if (_updatesSubscription == null) {
        _attachUpdates(client);
      }

      // Callback onConnected biasanya sudah memulai subscribe.
      // Fallback hanya jika belum ada yang memulai (state masih "connected",
      // bukan authFailed dsb.), supaya tidak memicu percobaan ganda.
      if (_state == AbotMqttState.connected &&
          !_subscribed &&
          !_subscribing) {
        unawaited(_subscribeAndAuthenticate(client));
      }
    } catch (error, stackTrace) {
      _log(
        'MQTT connection failed',
        name: 'ABOT MQTT',
        error: error,
        stackTrace: stackTrace,
      );

      if (identical(_client, client)) {
        _client = null;
      }

      await _updatesSubscription?.cancel();
      _updatesSubscription = null;

      client.disconnect();

      _resetAuthentication();
      _setState(AbotMqttState.disconnected);

      rethrow;
    }
  }

  /// Pasang listener pesan masuk.
  ///
  /// PENTING: di mqtt_client, `client.updates` baru tersedia SETELAH
  /// `connect()` dipanggil (sebelumnya null). Karena itu listener dipasang
  /// dari callback onConnected / onAutoReconnected, bukan sebelum connect.
  void _attachUpdates(MqttServerClient client) {
    if (_disposed || !identical(_client, client)) return;

    final updates = client.updates;

    if (updates == null) {
      _log('client.updates belum tersedia', name: 'ABOT MQTT');
      return;
    }

    // Cancel dulu agar tidak ada listener ganda pada stream yang sama.
    final old = _updatesSubscription;
    if (old != null) unawaited(old.cancel());

    _updatesSubscription = updates.listen(
      _handleMessages,
      onError: (Object error, StackTrace stackTrace) {
        _log(
          'MQTT updates stream error',
          name: 'ABOT MQTT',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );

    _log('Listener status topic terpasang', name: 'ABOT MQTT');
  }

  void _resetAuthentication() {
    _authenticated = false;
    _subscribed = false;
    _subscribing = false;
    _authInProgress = false;

    _cancelAuthTimer();
    _cancelHeartbeatMonitor();
  }

  // ============================================================
  // SUBSCRIBE + AUTH
  // ============================================================
  /// Subscribe ke topic status (jika belum), lalu kirim AUTH.
  /// [force] = true: kirim ulang AUTH walau sudah subscribe.
  Future<void> _subscribeAndAuthenticate(
    MqttServerClient client, {
    bool force = false,
  }) async {
    if (_disposed ||
        !identical(_client, client) ||
        client.connectionStatus?.state != MqttConnectionState.connected ||
        _subscribing ||
        _authInProgress) {
      return;
    }

    if (_subscribed) {
      if (force) _sendAuth(client);
      return;
    }

    _subscribing = true;
    _authInProgress = true;
    _authenticated = false;

    _setState(AbotMqttState.authenticating);

    final completer = Completer<void>();

    client.onSubscribed = (topic) {
      _log('SUBACK received: $topic', name: 'ABOT MQTT');

      if (topic == statusTopic && !completer.isCompleted) {
        completer.complete();
      }
    };

    client.onSubscribeFail = (topic) {
      _log('Subscribe failed: $topic', name: 'ABOT MQTT');

      if (!completer.isCompleted) {
        completer.completeError(StateError('Gagal subscribe ke topic status'));
      }
    };

    try {
      _log('Subscribing: $statusTopic', name: 'ABOT MQTT');

      client.subscribe(statusTopic, MqttQos.atLeastOnce);

      await completer.future.timeout(
        subscribeTimeout,
        onTimeout: () {
          throw TimeoutException('Timeout menunggu SUBACK topic status');
        },
      );

      if (_disposed ||
          !identical(_client, client) ||
          client.connectionStatus?.state != MqttConnectionState.connected) {
        throw StateError('MQTT terputus sebelum AUTH');
      }

      _subscribed = true;

      _sendAuth(client);
    } catch (error, stackTrace) {
      _subscribed = false;

      _log(
        'Subscribe/auth setup failed',
        name: 'ABOT MQTT',
        error: error,
        stackTrace: stackTrace,
      );

      _cancelAuthTimer();
      _setState(AbotMqttState.authFailed);
    } finally {
      _subscribing = false;
      _authInProgress = false;
    }
  }

  /// Kirim pesan AUTH dan jalankan timer menunggu auth_ok.
  void _sendAuth(MqttServerClient client) {
    _authenticated = false;
    _lastAuthAttempt = DateTime.now();

    _setState(AbotMqttState.authenticating);

    try {
      _publishRaw({'t': 'auth', 'token': authToken});

      _log(
        'AUTH published to $commandTopic',
        name: 'ABOT MQTT',
      );
    } catch (error) {
      _log('Gagal kirim AUTH: $error', name: 'ABOT MQTT');

      _cancelAuthTimer();
      _setState(AbotMqttState.authFailed);
      return;
    }

    _cancelAuthTimer();

    _authTimer = Timer(authTimeout, () {
      if (!_authenticated && !_disposed && identical(_client, client)) {
        _log(
          'Timeout menunggu auth_ok dari ESP32',
          name: 'ABOT MQTT',
        );

        _setState(AbotMqttState.authFailed);
      }
    });
  }

  // ============================================================
  // INCOMING MESSAGES
  // ============================================================
  void _handleMessages(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      if (event.topic != statusTopic) continue;

      try {
        final publishMessage = event.payload;

        if (publishMessage is! MqttPublishMessage) continue;

        final payload = MqttPublishPayload.bytesToStringAsString(
          publishMessage.payload.message,
        );

        final decoded = jsonDecode(payload);

        if (decoded is! Map<String, dynamic>) continue;

        final data = decoded;
        final type = data['t']?.toString();

        _log(
          'Received on status topic: $payload',
          name: 'ABOT MQTT',
        );

        switch (type) {
          case 'auth_ok':
            _authenticated = true;

            _cancelAuthTimer();
            _setState(AbotMqttState.ready);
            _startHeartbeatMonitor();

            _log(
              'ESP32 authenticated successfully',
              name: 'ABOT MQTT',
            );
            break;

          case 'auth_fail':
            _authenticated = false;

            _cancelAuthTimer();
            _cancelHeartbeatMonitor();

            _setState(AbotMqttState.authFailed);
            break;

          case 'device':
            _handleDevice(data);
            break;

          case 'hb':
            _handleHeartbeat(data);
            break;

          case 'status':
            _handleStatus(data);
            break;

          case 'pong':
            _lastHeartbeat = DateTime.now();
            break;
        }

        if (!_messages.isClosed) {
          _messages.add(data);
        }
      } catch (error, stackTrace) {
        _log(
          'Invalid MQTT message',
          name: 'ABOT MQTT',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  void _handleDevice(Map<String, dynamic> data) {
    final online = _toBool(data['online']);

    if (online == false) {
      _authenticated = false;

      _cancelAuthTimer();
      _cancelHeartbeatMonitor();

      _setState(AbotMqttState.deviceOffline);
    } else if (online == true) {
      _log(
        'ESP32 online: ${data['ver'] ?? 'unknown version'}',
        name: 'ABOT MQTT',
      );

      // ESP32 kembali online setelah kita menandainya offline / gagal auth:
      // otentikasi ulang otomatis.
      // ESP32 baru (re)boot atau reconnect: sesi auth di sisinya bisa sudah
      // hilang (mis. setelah OTA), jadi otentikasi ulang. Jangan menumpuk
      // kalau proses auth sedang berjalan.
      final client = _client;

      if (client != null &&
          _subscribed &&
          _state != AbotMqttState.authenticating) {
        _sendAuth(client);
      }
    }
  }

  void _handleHeartbeat(Map<String, dynamic> data) {
    _lastHeartbeat = DateTime.now();

    final version = data['ver'];
    if (version != null) {
      _firmwareVersion = version.toString();
    }

    _uptimeSeconds = _toInt(data['up']);
    _freeHeap = _toInt(data['heap']);

    _routeActive = _toBool(data['route']);
    _tripActive = _toBool(data['trip']);

    if (_authenticated) {
      _setState(AbotMqttState.ready);
      return;
    }

    // Heartbeat masuk padahal kita menandai ESP32 offline (mis. heartbeat
    // sempat telat > 30 dtk). Coba auth ulang, dibatasi supaya tidak spam.
    final client = _client;
    final last = _lastAuthAttempt;

    if (client != null &&
        _subscribed &&
        !_authInProgress &&
        _state == AbotMqttState.deviceOffline &&
        (last == null ||
            DateTime.now().difference(last) > _autoReauthInterval)) {
      _sendAuth(client);
    }
  }

  void _handleStatus(Map<String, dynamic> data) {
    final heap = data['heap'];
    if (heap != null) {
      _freeHeap = _toInt(heap);
    }

    if (data['route'] != null) {
      _routeActive = _toBool(data['route']);
    }

    if (data['trip'] != null) {
      _tripActive = _toBool(data['trip']);
    }

    // Pesan status dari ESP32 menandakan perangkat masih hidup.
    if (_authenticated) {
      _lastHeartbeat = DateTime.now();
    }
  }

  void _startHeartbeatMonitor() {
    _cancelHeartbeatMonitor();

    _lastHeartbeat = DateTime.now();

    _heartbeatMonitor = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (_disposed || !_authenticated) return;

        final last = _lastHeartbeat;
        if (last == null) return;

        if (DateTime.now().difference(last) > heartbeatTimeout) {
          _log(
            'Heartbeat timeout: ESP32 offline',
            name: 'ABOT MQTT',
          );

          _authenticated = false;

          _cancelHeartbeatMonitor();
          _setState(AbotMqttState.deviceOffline);
        }
      },
    );
  }

  // ============================================================
  // PUBLISH
  // ============================================================
  void _publishRaw(Map<String, dynamic> data) {
    final client = _client;

    if (client == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      throw StateError('MQTT belum terhubung');
    }

    final builder = MqttClientPayloadBuilder()
      ..addUTF8String(jsonEncode(data));

    final payload = builder.payload;

    if (payload == null) {
      throw StateError('Gagal membuat payload MQTT');
    }

    client.publishMessage(
      commandTopic,
      MqttQos.atLeastOnce,
      payload,
      retain: false,
    );
  }

  void publishJson(
    Map<String, dynamic> data, {
    int qos = 1,
    bool requireAuthentication = false,
  }) {
    if (requireAuthentication && !isReady) {
      throw StateError('ESP32 belum terautentikasi');
    }

    // Validasi skema sebelum simpan ke antrian offline.
    if (!_validateMqttPayload(data)) {
      throw StateError('Payload MQTT tidak valid: type=${data['t']}');
    }

    final client = _client;

    if (!isConnected || client == null) {
      if (_outbox.length >= _maxOutboxSize) {
        _outbox.removeFirst();
        _log('Antrian offline penuh, buang pesan terlama');
      }
      _outbox.add(data);
      _log(
        'Pesan ditantrikan (offline): ${jsonEncode(data)}',
        name: 'ABOT MQTT',
      );
      return;
    }

    final builder = MqttClientPayloadBuilder()
      ..addUTF8String(jsonEncode(data));

    final selectedQos = switch (qos) {
      0 => MqttQos.atMostOnce,
      2 => MqttQos.exactlyOnce,
      _ => MqttQos.atLeastOnce,
    };

    final payload = builder.payload;

    if (payload == null) {
      throw StateError('Gagal membuat payload MQTT');
    }

    client.publishMessage(
      commandTopic,
      selectedQos,
      payload,
      retain: false,
    );

    // Jangan log token ke console.
    final safe = Map<String, dynamic>.of(data);
    if (safe.containsKey('token')) safe['token'] = '***';

    _log('Command sent: ${jsonEncode(safe)}', name: 'ABOT MQTT');
  }

  void _flushOutbox() {
    while (_outbox.isNotEmpty) {
      if (!isConnected) break;
      final data = _outbox.removeFirst();
      try {
        _publishRaw(data);
      } catch (e) {
        _outbox.addFirst(data);
        _log(
          'Gagal flush outbox, dikembalikan ke antrian: $e',
          name: 'ABOT MQTT',
        );
        break;
      }
    }
  }

  void ping() {
    publishJson({'t': 'ping'}, requireAuthentication: true);
  }

  void requestStatus() {
    publishJson({'t': 'get_status'}, requireAuthentication: true);
  }

  // ============================================================
  // HELPERS
  // ============================================================
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

  void _log(String message, {String name = 'ABOT MQTT'}) {
    if (kReleaseMode) return;
    developer.log(message, name: name);
  }

  /// Validasi skema payload MQTT sebelum dikirim.
  /// Payload yang gagal validasi ditolak agar tidak menumpuk antrian offline
  /// atau menyebabkan crash di sisi penerima.
  bool _validateMqttPayload(Map<String, dynamic> data) {
    final type = data['t'] as String?;
    if (type == null || type.isEmpty) return false;

    switch (type) {
      case 'route':
        return data['dist'] is num &&
            data['dur'] is num &&
            data['coords'] is List &&
            (data['coords'] as List).isNotEmpty;
      case 'gps':
        return (data['progress'] is num) ||
            (data['lat'] is num && data['lon'] is num);
      case 'trip_start':
      case 'trip_end':
      case 'reset':
      case 'ping':
      case 'get_status':
        return true;
      default:
        return false;
    }
  }

  void _cancelAuthTimer() {
    _authTimer?.cancel();
    _authTimer = null;
  }

  void _cancelHeartbeatMonitor() {
    _heartbeatMonitor?.cancel();
    _heartbeatMonitor = null;
  }

  void dispose() {
    if (_disposed) return;

    _disposed = true;

    _cancelAuthTimer();
    _cancelHeartbeatMonitor();

    // Bangunkan semua yang masih menunggu auth supaya tidak menggantung.
    final waiters = List<Completer<void>>.of(_authWaiters);
    _authWaiters.clear();

    for (final waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.completeError(StateError('MQTT service sudah ditutup'));
      }
    }

    _updatesSubscription?.cancel();
    _updatesSubscription = null;

    final client = _client;
    _client = null;

    if (!_messages.isClosed) {
      _messages.close();
    }

    if (!_stateController.isClosed) {
      _stateController.close();
    }

    client?.disconnect();
  }
}