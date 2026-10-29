import 'dart:async';
import 'package:flutter/foundation.dart';

class MockBleService extends ChangeNotifier {
  final _connectionController = StreamController<bool>.broadcast();
  final _incomingController = StreamController<String>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<String> get incomingStream => _incomingController.stream;

  bool _connected = false;
  bool get isConnected => _connected;
  String? get deviceName => _connected ? 'ABOT-MOCK' : null;

  int _sendCount = 0;
  int get sendCount => _sendCount;

  int _bytesSent = 0;
  int get bytesSent => _bytesSent;

  Future<bool> connectMock() async {
    await Future.delayed(const Duration(milliseconds: 600));
    _connected = true;
    _connectionController.add(true);
    debugPrint('[MOCK-BLE] >>> Connected (mock)');
    notifyListeners();
    return true;
  }

  Future<void> disconnect() async {
    _connected = false;
    _connectionController.add(false);
    debugPrint('[MOCK-BLE] <<< Disconnected');
    notifyListeners();
  }

  Future<void> send(String json) async {
    if (!_connected) {
      debugPrint('[MOCK-BLE] (offline) $json');
      return;
    }

    _sendCount++;
    _bytesSent += json.length;
    notifyListeners();

    debugPrint('[MOCK-BLE → ABOT] #$_sendCount '
        '(${json.length} bytes)');
  }

  void injectIncoming(String json) {
    _incomingController.add(json);
    debugPrint('[MOCK-BLE ← ABOT] $json');
  }

  @override
  void dispose() {
    _connectionController.close();
    _incomingController.close();
    super.dispose();
  }
}