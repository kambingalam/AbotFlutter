
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/app_config.dart';

class BleDiagnosticService extends ChangeNotifier {
  BleDiagnosticService() {
    _scanSubscription = FlutterBluePlus.scanResults.listen(
      _handleScanResults,
      onError: (Object error) {
        _setError('Scan BLE gagal: $error');
      },
    );
  }

  final List<ScanResult> _devices = [];
  final List<String> _logs = [];

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  final List<int> _incomingBytes = [];

  static const int _maxIncomingLineBytes = 4096;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _notificationSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _rxCharacteristic;
  BluetoothCharacteristic? _txCharacteristic;

  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isReady = false;

  String _status = 'Belum terhubung';
  String? _error;

  List<ScanResult> get devices => List.unmodifiable(_devices);
  List<String> get logs => List.unmodifiable(_logs);

  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  bool get isScanning => _isScanning;
  bool get isConnecting => _isConnecting;
  bool get isConnected => _isConnected;
  bool get isReady => _isReady;

  String get status => _status;
  String? get error => _error;

  String get connectedDeviceName {
    final device = _connectedDevice;

    if (device == null) return '-';

    if (device.platformName.isNotEmpty) {
      return device.platformName;
    }

    return device.remoteId.toString();
  }

  String? get connectedDeviceId => _connectedDevice?.remoteId.toString();

  String get rxStatus {
    return _rxCharacteristic == null ? 'Belum ditemukan' : 'Ditemukan';
  }

  String get txStatus {
    return _txCharacteristic == null ? 'Belum ditemukan' : 'Ditemukan';
  }

  void _addLog(String message) {
    final time = DateTime.now().toLocal().toString().substring(11, 19);

    _logs.insert(0, '[$time] $message');

    if (_logs.length > 100) {
      _logs.removeLast();
    }

    notifyListeners();
  }

  void _setError(String message) {
    _error = message;
    _status = message;
    _addLog('ERROR: $message');
  }

  void _handleScanResults(List<ScanResult> results) {
    for (final result in results) {
      final index = _devices.indexWhere(
        (item) => item.device.remoteId == result.device.remoteId,
      );

      if (index == -1) {
        _devices.add(result);
      } else {
        _devices[index] = result;
      }
    }

    _devices.sort((a, b) => b.rssi.compareTo(a.rssi));
    notifyListeners();
  }

  Future<void> _requestBlePermissions() async {
    final scanStatus = await Permission.bluetoothScan.request();
    final connectStatus = await Permission.bluetoothConnect.request();

    if (!scanStatus.isGranted || !connectStatus.isGranted) {
      throw Exception(
        'Izin Bluetooth ditolak. Izinkan Bluetooth Scan dan Connect '
        'melalui pengaturan aplikasi.',
      );
    }
  }

  Future<void> startScan() async {
    try {
      _error = null;

      if (_isScanning) {
        await stopScan();
      }

      await _requestBlePermissions();

      final supported = await FlutterBluePlus.isSupported;

      if (!supported) {
        throw Exception('HP tidak mendukung Bluetooth Low Energy.');
      }

      final adapterState = await FlutterBluePlus.adapterState.first;

      if (adapterState != BluetoothAdapterState.on) {
        throw Exception(
          'Bluetooth HP belum aktif. Aktifkan Bluetooth lalu coba lagi.',
        );
      }

      _devices.clear();
      _isScanning = true;
      _status = 'Sedang mencari perangkat BLE...';

      _addLog('Memulai scan BLE selama 12 detik');

      notifyListeners();

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 12),
      );

      _isScanning = false;

      if (_devices.isEmpty) {
        _status = 'Scan selesai. Belum ada perangkat ditemukan.';
      } else {
        _status = 'Scan selesai. ${_devices.length} perangkat ditemukan.';
      }

      _addLog(_status);
      notifyListeners();
    } catch (e) {
      _isScanning = false;

      _setError(
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {
      // Scan mungkin sudah berhenti.
    }

    _isScanning = false;
    notifyListeners();
  }

  Future<void> connectTo(BluetoothDevice device) async {
    if (_isConnecting) return;

    try {
      _error = null;
      _isConnecting = true;
      _status = 'Menghubungkan ke perangkat...';

      _addLog('Menghubungkan ke ${device.remoteId}');
      notifyListeners();

      await _requestBlePermissions();

      if (_isScanning) {
        await stopScan();
      }

      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      _connectedDevice = device;
      _isConnected = true;

      await _connectionSubscription?.cancel();

      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _isConnected = false;
          _isReady = false;
          _rxCharacteristic = null;
          _txCharacteristic = null;
          _status = 'Perangkat terputus';

          _addLog('Koneksi BLE terputus');
          notifyListeners();
        }
      });

      _addLog('Terhubung. Memeriksa GATT service...');

      final services = await device.discoverServices();

      BluetoothService? targetService;

      for (final service in services) {
        if (service.uuid.toString().toLowerCase() ==
            AppConfig.abotServiceUuid.toLowerCase()) {
          targetService = service;
          break;
        }
      }

      if (targetService == null) {
        throw Exception(
          'ABOT UART Service tidak ditemukan. Periksa UUID firmware.',
        );
      }

      BluetoothCharacteristic? rx;
      BluetoothCharacteristic? tx;

      for (final characteristic in targetService.characteristics) {
        final uuid = characteristic.uuid.toString().toLowerCase();

        if (uuid == AppConfig.abotRxCharUuid.toLowerCase()) {
          rx = characteristic;
        }

        if (uuid == AppConfig.abotTxCharUuid.toLowerCase()) {
          tx = characteristic;
        }
      }

      if (rx == null ||
          (!rx.properties.write && !rx.properties.writeWithoutResponse)) {
        throw Exception(
          'RX Characteristic tidak memiliki properti Write.',
        );
      }

      if (tx == null ||
          (!tx.properties.notify && !tx.properties.indicate)) {
        throw Exception(
          'TX Characteristic tidak mendukung Notify atau Indicate.',
        );
      }

      _rxCharacteristic = rx;
      _txCharacteristic = tx;

      await _notificationSubscription?.cancel();

      _incomingBytes.clear();

      _notificationSubscription = tx.onValueReceived.listen(
        _handleNotification,
        onError: (Object error) {
          _setError('BLE notification gagal: $error');
        },
      );

      await tx.setNotifyValue(true);

      _isReady = true;
      _status = 'BLE siap. RX Write dan TX Notify aktif.';

      _addLog('GATT berhasil ditemukan');
      _addLog('RX Characteristic siap untuk Write');
      _addLog('TX Notification aktif');
      _addLog('BLE Diagnostic siap');
    } catch (e) {
      _isReady = false;
      _status = 'Gagal menghubungkan';

      _setError(
        e.toString().replaceFirst('Exception: ', ''),
      );

      try {
        await device.disconnect();
      } catch (_) {
        // Abaikan jika perangkat sudah terputus.
      }

      _isConnected = false;
      _connectedDevice = null;
      _rxCharacteristic = null;
      _txCharacteristic = null;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  void _handleNotification(List<int> value) {
    if (value.isEmpty) return;

    for (final byte in value) {
      if (byte == 13) continue;

      if (byte == 10) {
        if (_incomingBytes.isNotEmpty) {
          final line = utf8.decode(
            _incomingBytes,
            allowMalformed: true,
          ).trim();

          _incomingBytes.clear();

          if (line.isNotEmpty) {
            _handleIncomingLine(line);
          }
        }

        continue;
      }

      if (_incomingBytes.length >= _maxIncomingLineBytes) {
        _incomingBytes.clear();
        _addLog('ERROR: Pesan BLE terlalu panjang, baris dibuang');
        continue;
      }

      _incomingBytes.add(byte);
    }
  }

  void _handleIncomingLine(String line) {
    try {
      final decoded = jsonDecode(line);

      if (decoded is! Map) {
        _addLog('ESP32 → HP: Format JSON bukan object');
        return;
      }

      final message = Map<String, dynamic>.from(decoded);
      final type = message['t']?.toString() ?? 'unknown';

      _addLog('ESP32 → HP [$type]: $line');
      _messageController.add(message);
    } on FormatException {
      _addLog('ESP32 → HP [teks]: $line');
    } catch (e) {
      _addLog('Gagal membaca pesan BLE: $e');
    }
  }

  Future<void> sendJson(Map<String, dynamic> payload) async {
    final rx = _rxCharacteristic;

    if (!_isReady || rx == null) {
      _setError(
        'BLE belum siap. Hubungkan perangkat terlebih dahulu.',
      );
      return;
    }

    try {
      final message = '${jsonEncode(payload)}\n';
      final bytes = utf8.encode(message);

      await rx.write(
        bytes,
        withoutResponse: !rx.properties.write,
      );

      _addLog(
        'HP → ESP32 [${payload['t'] ?? 'unknown'}]: ${message.trim()}',
      );
    } catch (e) {
      _setError('Gagal mengirim pesan BLE: $e');
    }
  }

  Future<void> sendPing() async {
    await sendJson({'t': 'ping'});
  }

  Future<void> disconnect() async {
    final device = _connectedDevice;

    try {
      await _notificationSubscription?.cancel();
      _notificationSubscription = null;

      await _connectionSubscription?.cancel();
      _connectionSubscription = null;

      if (device != null) {
        await device.disconnect();
      }

      _addLog('Disconnect BLE');
    } catch (e) {
      _setError('Gagal disconnect: $e');
    } finally {
      _connectedDevice = null;
      _rxCharacteristic = null;
      _txCharacteristic = null;
      _incomingBytes.clear();

      _isConnected = false;
      _isReady = false;
      _isConnecting = false;
      _status = 'Belum terhubung';

      notifyListeners();
    }
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _notificationSubscription?.cancel();
    _connectionSubscription?.cancel();
    _messageController.close();

    super.dispose();
  }
}
