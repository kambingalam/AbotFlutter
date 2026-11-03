import 'dart:async';

import 'dart:convert';

import 'dart:developer' as developer;



import 'package:mqtt_client/mqtt_client.dart';

import 'package:mqtt_client/mqtt_server_client.dart';



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

  static const int port = 1883;



  static const String commandTopic =

      'abot/wokwi/477375325542330369/v337/command';



  static const String statusTopic =

      'abot/wokwi/477375325542330369/v337/status';



  static const String authToken = 'abot-secret-2025';



  static const Duration authTimeout = Duration(seconds: 10);

  static const Duration heartbeatTimeout = Duration(seconds: 30);



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



  bool _disposed = false;

  bool _authenticated = false;

  bool _subscribed = false;
  bool _subscribing = false;
  Completer<void>? _subscribeCompleter;



  DateTime? _lastHeartbeat;

  AbotMqttState _state = AbotMqttState.disconnected;



  // Device status dari firmware

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

      _client?.connectionStatus?.state ==

          MqttConnectionState.connected;



  void _setState(AbotMqttState nextState) {

    if (_state == nextState) return;



    _state = nextState;



    if (!_stateController.isClosed) {

      _stateController.add(nextState);

    }



    developer.log('State: $nextState', name: 'ABOT MQTT');

  }



  Future<void> connect() {

    if (_disposed) {

      return Future<void>.error(

        StateError('MQTT service sudah ditutup'),

      );

    }



    if (isConnected) {

      return Future<void>.value();

    }



    final ongoing = _connectFuture;

    if (ongoing != null) return ongoing;



    final future = _connectInternal();

    _connectFuture = future;



    return future.whenComplete(() {

      if (identical(_connectFuture, future)) {

        _connectFuture = null;

      }

    });

  }



  Future<void> _connectInternal() async {

    _setState(AbotMqttState.connecting);



    final clientId =

        'ABOT-FLUTTER-${DateTime.now().millisecondsSinceEpoch}';



    final client = MqttServerClient.withPort(host, clientId, port);

    _client = client;



    client

      ..logging(on: false)

      ..keepAlivePeriod = 30

      ..connectTimeoutPeriod = 10000

      ..autoReconnect = true

      ..resubscribeOnAutoReconnect = false

      ..onConnected = () {

        developer.log('MQTT connected', name: 'ABOT MQTT');

        _authenticated = false;

        _subscribed = false;
        _subscribing = false;
        _subscribeCompleter = null;

        _setState(AbotMqttState.connected);

        unawaited(_subscribeAndAuthenticate(client));

      }

      ..onAutoReconnect = () {

        developer.log('MQTT reconnecting', name: 'ABOT MQTT');

        _authenticated = false;

        _subscribed = false;
        _subscribing = false;
        _subscribeCompleter = null;

        _cancelAuthTimer();

        _cancelHeartbeatMonitor();

        _setState(AbotMqttState.connecting);

      }

      ..onAutoReconnected = () {

        developer.log('MQTT reconnected', name: 'ABOT MQTT');

        _authenticated = false;

        _subscribed = false;
        _subscribing = false;
        _subscribeCompleter = null;

        _setState(AbotMqttState.connected);

        unawaited(_subscribeAndAuthenticate(client));

      }

      ..onDisconnected = () {

        developer.log('MQTT disconnected', name: 'ABOT MQTT');

        _authenticated = false;

        _subscribed = false;
        _subscribing = false;
        _subscribeCompleter = null;

        _cancelAuthTimer();

        _cancelHeartbeatMonitor();

        _setState(AbotMqttState.disconnected);

      };



    client.connectionMessage = MqttConnectMessage()

        .withClientIdentifier(clientId)

        .startClean();



    // Listener dipasang sebelum connect agar auth_ok tidak terlewat.

    _updatesSubscription ??= client.updates?.listen(_handleMessages);



    try {

      developer.log(

        'Connecting to $host:$port',

        name: 'ABOT MQTT',

      );



      await client.connect();



      if (_disposed) {

        client.disconnect();

        throw StateError('MQTT service sudah ditutup');

      }



      if (client.connectionStatus?.state !=

          MqttConnectionState.connected) {

        throw Exception(

          'MQTT gagal terhubung: ${client.connectionStatus?.state}',

        );

      }



      // Fallback jika callback onConnected belum memicu proses.

      if (!_subscribed) {

        unawaited(_subscribeAndAuthenticate(client));

      }

    } catch (error, stackTrace) {

      developer.log(

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

      _setState(AbotMqttState.disconnected);

      rethrow;

    }

  }



  Future<void> _subscribeAndAuthenticate(MqttServerClient client) async {
    if (_disposed ||
        client.connectionStatus?.state != MqttConnectionState.connected ||
        _subscribed ||
        _subscribing) {
      return;
    }

    _subscribing = true;
    _authenticated = false;
    _setState(AbotMqttState.authenticating);

    _cancelAuthTimer();
    _authTimer = Timer(authTimeout, () {
      if (!_authenticated && !_disposed) {
        developer.log('Timeout menunggu auth_ok', name: 'ABOT MQTT');
        _setState(AbotMqttState.authFailed);
      }
    });

    final completer = Completer<void>();
    _subscribeCompleter = completer;

    client.onSubscribed = (topic) {
      developer.log('SUBACK received: $topic', name: 'ABOT MQTT');
      if (topic == statusTopic && !completer.isCompleted) {
        completer.complete();
      }
    };

    client.onSubscribeFail = (topic) {
      developer.log('Subscribe failed: $topic', name: 'ABOT MQTT');
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Gagal subscribe ke topic status'),
        );
      }
    };

    try {
      client.subscribe(statusTopic, MqttQos.atLeastOnce);

      await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          throw TimeoutException('Timeout menunggu SUBACK topic status');
        },
      );

      if (_disposed ||
          client.connectionStatus?.state != MqttConnectionState.connected) {
        throw StateError('MQTT terputus sebelum AUTH');
      }

      _subscribed = true;
      _publishRaw({'t': 'auth', 'token': authToken});
      developer.log('AUTH sent after SUBACK', name: 'ABOT MQTT');
    } catch (error, stackTrace) {
      _subscribed = false;
      developer.log(
        'Subscribe/auth setup failed',
        name: 'ABOT MQTT',
        error: error,
        stackTrace: stackTrace,
      );
      _cancelAuthTimer();
      _setState(AbotMqttState.authFailed);
    } finally {
      _subscribing = false;
      if (identical(_subscribeCompleter, completer)) {
        _subscribeCompleter = null;
      }
    }
  }

  void _handleMessages(

    List<MqttReceivedMessage<MqttMessage>> events,

  ) {

    for (final event in events) {

      if (event.topic != statusTopic) continue;



      final publishMessage = event.payload as MqttPublishMessage;

      final payload = MqttPublishPayload.bytesToStringAsString(

        publishMessage.payload.message,

      );



      try {

        final decoded = jsonDecode(payload);

        if (decoded is! Map<String, dynamic>) continue;



        final data = decoded;

        final type = data['t']?.toString();



        switch (type) {

          case 'auth_ok':

            _authenticated = true;

            _cancelAuthTimer();

            _setState(AbotMqttState.ready);

            _startHeartbeatMonitor();



            developer.log(

              'ESP32 authenticated',

              name: 'ABOT MQTT',

            );

            break;



          case 'auth_fail':

            _authenticated = false;

            _cancelAuthTimer();

            _cancelHeartbeatMonitor();

            _setState(AbotMqttState.authFailed);

            break;



          case 'hb':

            _handleHeartbeat(data);

            break;



          case 'status':

            _handleStatus(data);

            break;



          case 'pong':

            // Respons ping juga menandakan ESP32 masih merespons.

            _lastHeartbeat = DateTime.now();

            break;

        }



        if (!_messages.isClosed) {

          _messages.add(data);

        }



        developer.log(

          'Received: $payload',

          name: 'ABOT MQTT',

        );

      } catch (error, stackTrace) {

        developer.log(

          'Invalid MQTT JSON payload',

          name: 'ABOT MQTT',

          error: error,

          stackTrace: stackTrace,

        );

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

    }

  }



  void _handleStatus(Map<String, dynamic> data) {

    // Firmware status berkala memiliki route/trip/prog/step/heap/auth.

    final heap = data['heap'];

    if (heap != null) _freeHeap = _toInt(heap);



    if (data['route'] != null) {

      _routeActive = _toBool(data['route']);

    }



    if (data['trip'] != null) {

      _tripActive = _toBool(data['trip']);

    }



    if (data['auth'] != null && _toInt(data['auth']) == 1) {

      _lastHeartbeat ??= DateTime.now();

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

          developer.log(

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



  void _publishRaw(Map<String, dynamic> data) {

    final client = _client;



    if (client == null ||

        client.connectionStatus?.state !=

            MqttConnectionState.connected) {

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



    final client = _client;



    if (!isConnected || client == null) {

      throw StateError('MQTT belum terhubung');

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



    developer.log(

      'Command sent: ${jsonEncode(data)}',

      name: 'ABOT MQTT',

    );

  }



  void ping() {

    publishJson(

      {'t': 'ping'},

      requireAuthentication: true,

    );

  }



  void requestStatus() {

    publishJson(

      {'t': 'get_status'},

      requireAuthentication: true,

    );

  }



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