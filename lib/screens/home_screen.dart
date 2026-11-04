import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/place.dart';
import '../services/abot_mqtt_service.dart';
import '../services/gps_service.dart';
import '../services/mock_ble_service.dart';
import '../services/settings_service.dart';
import '../services/tile_cache_service.dart';
import '../services/trip_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/abot_status_chip.dart';
import '../widgets/onboarding_overlay.dart';
import '../widgets/search_bar_button.dart';
import 'preview_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Duration _pongTimeout = Duration(seconds: 5);

  final MapController _map = MapController();

  bool _connecting = false;
  bool _followUser = true;
  bool _showOnboarding = false;
  LatLng? _lastFollowed;

  StreamSubscription<Map<String, dynamic>>? _mqttSubscription;
  Timer? _pongTimer;

  String _mqttStatus = 'Belum diuji';
  bool _mqttBusy = false;
  bool _mqttResponded = false;
  DateTime? _mqttLastResponse;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final settingsService = context.read<SettingsService>();

      if (!settingsService.onboardingDone) {
        setState(() => _showOnboarding = true);
      }

      _listenToMqtt();
    });
  }

  // ============================================================
  // MQTT
  // ============================================================
  void _listenToMqtt() {
    if (_mqttSubscription != null) return;

    final mqtt = context.read<AbotMqttService>();

    _mqttSubscription = mqtt.messages.listen(
      (message) {
        if (!mounted) return;

        final type = message['t']?.toString() ?? 'unknown';

        setState(() {
          _mqttLastResponse = DateTime.now();

          switch (type) {
            case 'pong':
              _pongTimer?.cancel();
              _mqttResponded = true;
              _mqttStatus = 'PONG diterima — ESP32 merespons';
              break;

            case 'hb':
              _mqttStatus = 'Heartbeat ESP32 diterima';
              break;

            case 'status':
              _mqttStatus = 'Status ESP32 diterima';
              break;

            default:
              _mqttStatus = 'Pesan diterima: $type';
          }
        });
      },
      onError: (Object error) {
        if (!mounted) return;

        setState(() => _mqttStatus = 'Stream MQTT error: $error');
      },
    );
  }

  Future<void> _testMqtt() async {
    if (_mqttBusy) return;

    final mqtt = context.read<AbotMqttService>();

    setState(() {
      _mqttBusy = true;
      _mqttResponded = false;
      _mqttStatus = 'Menghubungkan ke broker MQTT...';
    });

    try {
      // Connect + authentication + retry jika autentikasi sebelumnya gagal.
      setState(() => _mqttStatus = 'Menunggu autentikasi ESP32...');

      await mqtt.connectAndAuthenticate(
        timeout: const Duration(seconds: 15),
      );

      if (!mounted) return;

      if (!mqtt.isReady) {
        throw StateError('ESP32 belum terautentikasi');
      }

      mqtt.ping();

      setState(() => _mqttStatus = 'PING terkirim — menunggu PONG...');

      // Hindari status menggantung jika PONG tidak diterima.
      _pongTimer?.cancel();

      _pongTimer = Timer(_pongTimeout, () {
        if (!mounted || _mqttResponded) return;

        setState(() => _mqttStatus = 'Tidak ada PONG (timeout)');
      });
    } catch (error) {
      if (!mounted) return;

      setState(() => _mqttStatus = 'Gagal MQTT: $error');
    } finally {
      if (mounted) {
        setState(() => _mqttBusy = false);
      }
    }
  }

  // ============================================================
  // MAP / GPS
  // ============================================================
  LatLng _userLatLng(TripManager manager) {
    final pos = manager.lastPosition;

    if (pos != null) {
      return LatLng(pos.latitude, pos.longitude);
    }

    return const LatLng(
      AppConfig.defaultLat,
      AppConfig.defaultLon,
    );
  }

  void _moveToUser(LatLng userPos) {
    if (!_followUser) return;

    try {
      _map.move(userPos, _map.camera.zoom);
    } catch (_) {
      // Map belum siap; onMapReady akan menanganinya.
    }
  }

  // ============================================================
  // ACTIONS
  // ============================================================
  Future<void> _connectMock() async {
    if (_connecting) return;

    setState(() => _connecting = true);

    final ble = context.read<MockBleService>();

    try {
      if (ble.isConnected) {
        await ble.disconnect();
        _showSnack('ABOT terputus');
      } else {
        final ok = await ble.connectMock();

        _showSnack(ok ? 'ABOT terhubung (mock)' : 'Gagal');
      }
    } catch (error) {
      _showSnack('Koneksi mock gagal: $error');
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openSearch() async {
    final manager = context.read<TripManager>();

    final result = await Navigator.of(context).push<Place>(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          currentPosition: manager.lastPosition,
        ),
      ),
    );

    if (result == null || !mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PreviewScreen(destination: result),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SettingsScreen(),
      ),
    );
  }

  Future<void> _finishOnboarding() async {
    final settingsService = context.read<SettingsService>();

    await settingsService.setOnboardingDone(true);

    if (!mounted) return;

    setState(() => _showOnboarding = false);
  }

  @override
  void dispose() {
    _pongTimer?.cancel();
    _mqttSubscription?.cancel();
    _map.dispose();

    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final manager = context.watch<TripManager>();
    final ble = context.watch<MockBleService>();

    final userPos = _userLatLng(manager);
    final surface = Theme.of(context).colorScheme.surface;
    final padding = MediaQuery.of(context).padding;

    // Kamera mengikuti posisi pengguna setiap posisi berubah.
    if (_followUser && _lastFollowed != userPos) {
      _lastFollowed = userPos;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moveToUser(userPos);
      });
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: userPos,
              initialZoom: 15,
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture && _followUser) {
                  setState(() => _followUser = false);
                }
              },
              onMapReady: () {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _moveToUser(userPos);
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile-a.openstreetmap.fr/hot/{z}/{x}/{y}.png',
                // TODO: ganti dengan application ID asli sebelum rilis.
                userAgentPackageName: 'com.example.abot_drivers',
                maxZoom: 19,
                tileProvider: TileCacheService.tileProvider,
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: userPos,
                    width: 60,
                    height: 60,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.my_location,
                          color: AppColors.primary,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ======================================================
          // TOP BAR
          // ======================================================
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  AbotStatusChip(
                    connected: ble.isConnected,
                    deviceName: ble.deviceName,
                    onTap: _connectMock,
                  ),
                  const Spacer(),
                  if (_connecting)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                      ),
                    ),
                  const SizedBox(width: 8),
                  _circleButton(
                    surface: surface,
                    icon: Icons.settings,
                    onTap: _openSettings,
                  ),
                ],
              ),
            ),
          ),

          // ======================================================
          // GPS BANNER
          // ======================================================
          if (manager.gpsStatus != GpsStatus.ready)
            Positioned(
              top: 80 + padding.top,
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              child: _gpsBanner(manager),
            ),

          // ======================================================
          // MQTT TEST PANEL
          // ======================================================
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: 150 + padding.bottom,
            child: Material(
              color: surface,
              elevation: 3,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.developer_board,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'ESP32-S3 · MQTT Test',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Icon(
                          _mqttResponded
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: _mqttResponded ? Colors.green : Colors.grey,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _mqttStatus,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_mqttLastResponse != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Respons terakhir: '
                        '${_formatTime(_mqttLastResponse!)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _mqttBusy ? null : _testMqtt,
                        icon: _mqttBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send),
                        label: Text(
                          _mqttBusy ? 'Memproses...' : 'Kirim PING ke ESP32',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ======================================================
          // RECENTER BUTTON
          // ======================================================
          Positioned(
            right: AppSpacing.lg,
            bottom: 85,
            child: FloatingActionButton.small(
              backgroundColor: surface,
              foregroundColor: AppColors.primary,
              elevation: 2,
              onPressed: () {
                setState(() {
                  _followUser = true;
                  _lastFollowed = userPos;
                });

                try {
                  _map.move(userPos, 15);
                } catch (_) {}
              },
              child: const Icon(Icons.my_location),
            ),
          ),

          // ======================================================
          // SEARCH BAR
          // ======================================================
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: AppSpacing.lg + padding.bottom,
            child: SearchBarButton(onTap: _openSearch),
          ),

          // ======================================================
          // ONBOARDING
          // ======================================================
          if (_showOnboarding)
            Positioned.fill(
              child: OnboardingOverlay(
                onFinished: _finishOnboarding,
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================
  String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');

    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  Widget _gpsBanner(TripManager manager) {
    final status = manager.gpsStatus;

    String message;
    IconData icon;
    Color color;

    switch (status) {
      case GpsStatus.ready:
        return const SizedBox.shrink();

      case GpsStatus.permissionDenied:
        message = 'Izin lokasi ditolak';
        icon = Icons.location_disabled;
        color = Colors.orange.shade700;
        break;

      case GpsStatus.permissionDeniedForever:
        message = 'Izin lokasi ditolak permanen — buka Pengaturan';
        icon = Icons.location_disabled;
        color = Colors.red.shade700;
        break;

      case GpsStatus.serviceDisabled:
        message = 'Layanan lokasi HP dimatikan';
        icon = Icons.gps_off;
        color = Colors.orange.shade700;
        break;

      case GpsStatus.error:
        final err = manager.gpsError;
        message = err.isEmpty ? 'GPS error' : 'GPS: $err';
        icon = Icons.error_outline;
        color = Colors.red.shade700;
        break;

      case GpsStatus.initializing:
        message = 'Menyalakan GPS...';
        icon = Icons.gps_not_fixed;
        color = Colors.blueGrey;
        break;

      default:
        message = 'Menunggu sinyal GPS...';
        icon = Icons.gps_not_fixed;
        color = Colors.grey.shade700;
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleButton({
    required Color surface,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: surface,
          shape: BoxShape.circle,
          boxShadow: AppShadows.card,
        ),
        child: Icon(
          icon,
          color: AppColors.primary,
          size: 22,
        ),
      ),
    );
  }
}
