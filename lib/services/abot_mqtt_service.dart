import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class AbotMqttService {
  static const String host = 'broker.emqx.io';
  static const int port = 1883;

  static const String commandTopic =
      'abot/wokwi/477375325542330369/v337/command';

  static const String statusTopic = 'abot/wokwi/477375325542330369/v337/status';

  MqttServerClient? _client;

  final StreamController<Map<String, dynamic>> _messages =
      StreamController<Map<String, dynamic>>.broadcast();

  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>?
  _updatesSubscription;

  Future<void>? _connectFuture;
  bool _disposed = false;

  Stream<Map<String, dynamic>> get messages => _messages.stream;

  bool get isConnected =>
      !_disposed &&
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect() {
    if (_disposed) {
      return Future<void>.error(StateError('MQTT service sudah ditutup'));
    }

    if (isConnected) {
      return Future<void>.value();
    }

    // Jika koneksi sedang berlangsung, tunggu proses yang sama.
    final ongoing = _connectFuture;
    if (ongoing != null) {
      return ongoing;
    }

    final future = _connectInternal();
    _connectFuture = future;

    return future.whenComplete(() {
      if (identical(_connectFuture, future)) {
        _connectFuture = null;
      }
    });
  }

  Future<void> _connectInternal() async {
    final clientId = 'ABOT-FLUTTER-${DateTime.now().millisecondsSinceEpoch}';

    final client = MqttServerClient.withPort(host, clientId, port);

    _client = client;

    client
      ..logging(on: false)
      ..keepAlivePeriod = 30
      ..connectTimeoutPeriod = 10000
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      ..onConnected = () {
        developer.log('MQTT terhubung', name: 'ABOT MQTT');

        client.subscribe(statusTopic, MqttQos.atLeastOnce);
      }
      ..onDisconnected = () {
        developer.log('MQTT terputus', name: 'ABOT MQTT');
      };

    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean();

    try {
      developer.log('Menghubungkan ke $host:$port ...', name: 'ABOT MQTT');

      await client.connect();

      if (_disposed) {
        client.disconnect();
        throw StateError('MQTT service sudah ditutup');
      }

      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        throw Exception(
          'MQTT gagal terhubung. Status: '
          '${client.connectionStatus?.state}',
        );
      }

      _updatesSubscription ??= client.updates?.listen((events) {
        for (final event in events) {
          if (event.topic != statusTopic) continue;

          final message = event.payload as MqttPublishMessage;

          final payload = MqttPublishPayload.bytesToStringAsString(
            message.payload.message,
          );

          try {
            final decoded = jsonDecode(payload);

            if (decoded is Map<String, dynamic>) {
              if (!_messages.isClosed) {
                _messages.add(decoded);
              }

              developer.log('Pesan diterima: $payload', name: 'ABOT MQTT');
            }
          } catch (error, stackTrace) {
            developer.log(
              'Payload MQTT bukan JSON valid',
              name: 'ABOT MQTT',
              error: error,
              stackTrace: stackTrace,
            );
          }
        }
      });

      developer.log('Siap mengirim perintah MQTT', name: 'ABOT MQTT');
    } catch (error, stackTrace) {
      developer.log(
        'Gagal menghubungkan MQTT',
        name: 'ABOT MQTT',
        error: error,
        stackTrace: stackTrace,
      );

      if (identical(_client, client)) {
        _client = null;
      }

      client.disconnect();
      rethrow;
    }
  }

  void publishJson(Map<String, dynamic> data, {int qos = 1}) {
    final client = _client;

    if (!isConnected || client == null) {
      throw StateError('MQTT belum terhubung');
    }

    final builder = MqttClientPayloadBuilder()..addUTF8String(jsonEncode(data));

    final selectedQos = switch (qos) {
      0 => MqttQos.atMostOnce,
      2 => MqttQos.exactlyOnce,
      _ => MqttQos.atLeastOnce,
    };

    final payload = builder.payload;

    if (payload == null) {
      throw StateError('Gagal membuat payload MQTT');
    }

    client.publishMessage(commandTopic, selectedQos, payload, retain: false);

    developer.log('Perintah terkirim: ${jsonEncode(data)}', name: 'ABOT MQTT');
  }

  void ping() {
    publishJson({'t': 'ping'});
  }

  void requestStatus() {
    publishJson({'t': 'get_status'});
  }

  void dispose() {
    if (_disposed) return;

    _disposed = true;

    _updatesSubscription?.cancel();
    _updatesSubscription = null;

    final client = _client;
    _client = null;

    if (!_messages.isClosed) {
      _messages.close();
    }

    client?.disconnect();
  }
}
