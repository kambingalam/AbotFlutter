
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../services/abot_mqtt_service.dart';
import '../services/tile_cache_service.dart';
import '../config/app_config.dart';
import '../models/place.dart';
import '../services/gps_service.dart';
import '../services/mock_ble_service.dart';
import '../services/settings_service.dart';
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
  final MapController _map = MapController();

  bool _connecting = false;
  bool _followUser = true;
  bool _showOnboarding = false;

  StreamSubscription<Map<String, dynamic>>? _mqttSubscription;

  String _mqttStatus = 'Belum diuji';
  bool _mqttBusy = false;
  DateTime? _mqttLastResponse;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final settings = context.read<SettingsService>();

      if (!settings.onboardingDone) {
        setState(() => _showOnboarding = true);
      }

      _listenToMqtt();
    });
  }

  void _listenToMqtt() {
    if (_mqttSubscription != null) return;

    final mqtt = context.read<AbotMqttService>();

    _mqttSubscription = mqtt.messages.listen(
      (message) {
        if (!mounted) return;

        final type = message['t']?.toString() ?? 'unknown';

        setState(() {
          switch (type) {
            case 'pong':
              _mqttStatus = 'PONG diterima — ESP32 merespons';
              _mqttLastResponse = DateTime.now();
              break;

            case 'hb':
              _mqttStatus = 'Heartbeat ESP32 diterima';
              _mqttLastResponse = DateTime.now();
              break;

            case 'status':
              _mqttStatus = 'Status ESP32 diterima';
              _mqttLastResponse = DateTime.now();
              break;

            default:
              _mqttStatus = 'Pesan diterima: $type';
              _mqttLastResponse = DateTime.now();
          }
        });
      },
      onError: (Object error) {
        if (!mounted) return;

        setState(() {
          _mqttStatus = 'Stream MQTT error: $error';
        });
      },
    );
  }

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
    } catch (_) {}
  }

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

        _showSnack(
          ok ? 'ABOT terhubung (mock)' : 'Gagal',
        );
      }
    } catch (error) {
      _showSnack('Koneksi mock gagal: $error');
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  Future<void> _testMqtt() async {
    if (_mqttBusy) return;

    setState(() {
      _mqttBusy = true;
      _mqttStatus = 'Menghubungkan ke broker MQTT...';
    });

    try {
      final mqtt = context.read<AbotMqttService>();

      if (!mqtt.isConnected) {
        await mqtt.connect();
      }

      if (!mounted) return;

      mqtt.ping();

      setState(() {
        _mqttStatus = 'PING terkirim — menunggu PONG...';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _mqttStatus = 'Gagal MQTT: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _mqttBusy = false);
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

  Future<void> _openSettings() async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SettingsScreen(),
      ),
    );
  }

  Future<void> _finishOnboarding() async {
    final settings = context.read<SettingsService>();

    await settings.setOnboardingDone(true);

    if (!mounted) return;

    setState(() => _showOnboarding = false);
  }

  @override
  void dispose() {
    _mqttSubscription?.cancel();
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<TripManager>();
    final ble = context.watch<MockBleService>();

    final userPos = _userLatLng(manager);
    final surface = Theme.of(context).colorScheme.surface;

    final mqttResponded =
        _mqttStatus.contains('PONG diterima');

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
                  _moveToUser(userPos);
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile-a.openstreetmap.fr/hot/{z}/{x}/{y}.png',
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
                        color: AppColors.primary.withOpacity( 0.2),
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

          // Top bar: status mock BLE dan tombol pengaturan.
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

          // Banner GPS.
          if (manager.gpsStatus != GpsStatus.ready)
            Positioned(
              top: 80 + MediaQuery.of(context).padding.top,
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              child: _gpsBanner(manager),
            ),

          // Panel pengujian MQTT ESP32-S3.
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom:
                150 + MediaQuery.of(context).padding.bottom,
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
                        Icon(
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
                          mqttResponded
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: mqttResponded
                              ? Colors.green
                              : Colors.grey,
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
                        '${_mqttLastResponse!.hour.toString().padLeft(2, '0')}:'
                        '${_mqttLastResponse!.minute.toString().padLeft(2, '0')}:'
                        '${_mqttLastResponse!.second.toString().padLeft(2, '0')}',
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
                          _mqttBusy
                              ? 'Memproses...'
                              : 'Kirim PING ke ESP32',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Tombol recenter.
          Positioned(
            right: AppSpacing.lg,
            bottom: 85,
            child: FloatingActionButton.small(
              backgroundColor: surface,
              foregroundColor: AppColors.primary,
              elevation: 2,
              onPressed: () {
                setState(() => _followUser = true);

                try {
                  _map.move(userPos, 15);
                } catch (_) {}
              },
              child: const Icon(Icons.my_location),
            ),
          ),

          // Search bar.
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom:
                AppSpacing.lg + MediaQuery.of(context).padding.bottom,
            child: SearchBarButton(onTap: _openSearch),
          ),

          // Onboarding.
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
  // GPS BANNER
  // ============================================================

  Widget _gpsBanner(TripManager manager) {
    final status = manager.gpsStatus;

    if (status == GpsStatus.ready) {
      return const SizedBox.shrink();
    }

    String message;
    IconData icon;
    Color color;

    switch (status) {
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

  // ============================================================
  // CIRCLE BUTTON
  // ============================================================

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
