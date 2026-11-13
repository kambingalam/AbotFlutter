import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/splash_screen.dart';

import 'services/abot_mqtt_service.dart';
import 'services/background_service.dart';
import 'services/ble_diagnostic_service.dart';
import 'services/gps_service.dart';
import 'services/mock_ble_service.dart';
import 'services/osrm_service.dart';
import 'services/ota_link.dart';
import 'services/ota_service.dart';
import 'services/settings_service.dart';
import 'services/tile_cache_service.dart';
import 'services/trip_manager.dart';
import 'services/tts_service.dart';

import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init foreground service.
  BackgroundService.init();

  // Load settings.
  final settings = SettingsService();
  await settings.load();

  // Inisialisasi cache peta sebelum layar peta digunakan.
  await TileCacheService.init();

  runApp(
    AbotDriverApp(settings: settings),
  );
}

class AbotDriverApp extends StatelessWidget {
  final SettingsService settings;

  const AbotDriverApp({
    super.key,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // ============================================================
        // SETTINGS
        // ============================================================
        ChangeNotifierProvider<SettingsService>.value(
          value: settings,
        ),

        // ============================================================
        // BLE MOCK
        // ============================================================
        ChangeNotifierProvider<MockBleService>(
          create: (_) => MockBleService(),
        ),

        // ============================================================
        // BLE DIAGNOSTIC
        // ============================================================
        ChangeNotifierProvider<BleDiagnosticService>(
          create: (_) => BleDiagnosticService(),
        ),

        // ============================================================
        // MQTT
        // ============================================================
        Provider<AbotMqttService>(
          create: (_) {
            final mqtt = AbotMqttService();

            unawaited(
              mqtt.connect().catchError(
                (Object error, StackTrace stackTrace) {
                  developer.log(
                    'Gagal menghubungkan MQTT',
                    name: 'ABOT MQTT',
                    error: error,
                    stackTrace: stackTrace,
                  );
                },
              ),
            );

            return mqtt;
          },
          dispose: (_, mqtt) => mqtt.dispose(),
        ),

        // ============================================================
        // OTA FIRMWARE UPDATE
        // FIX: sekarang pakai OTA beneran (useSimulatedManifest: false).
        //
        // ⚠️ PENTING: ganti URL di bawah dengan URL manifest.json yang
        // sudah kamu host. Lihat langkah hosting di panduan terpisah.
        //
        // Contoh URL yang valid setelah hosting:
        //   https://github.com/USERNAME/REPO/releases/download/v3.52.0/manifest.json
        //   https://cdn.contoh.com/abot/manifest.json
        // ============================================================
        ChangeNotifierProvider<OtaService>(
          create: (context) {
            final mqtt = context.read<AbotMqttService>();

            return OtaService(
              link: MqttOtaLink(mqtt),
              config: OtaConfig(
                useSimulatedManifest: false,
                deviceModel: 'abot-esp32s3',
                // ⚠️ GANTI URL INI setelah manifest dihosting:
                manifestUrl: Uri.parse(
                  'https://raw.githubusercontent.com/kambingalam/AbotDevices/refs/heads/main/manifest.json',
                ),
              ),
            );
          },
        ),

        // ============================================================
        // GPS
        // ============================================================
        Provider<GpsService>(
          create: (_) => GpsService(),
          dispose: (_, service) => service.dispose(),
        ),

        // ============================================================
        // OSRM ROUTING
        // ============================================================
        Provider<OsrmService>(
          create: (_) => OsrmService(),
        ),

        // ============================================================
        // TEXT TO SPEECH
        // ============================================================
        ChangeNotifierProvider<TtsService>(
          create: (context) {
            final appSettings = context.read<SettingsService>();
            final tts = TtsService();

            unawaited(
              Future<void>(() async {
                await tts.init(settings: appSettings);

                tts.applySettings(
                  enabled: appSettings.ttsEnabled,
                  speakNearNow: appSettings.speakNearNow,
                );
              }).catchError(
                (Object error, StackTrace stackTrace) {
                  developer.log(
                    'Gagal menginisialisasi TTS',
                    name: 'ABOT TTS',
                    error: error,
                    stackTrace: stackTrace,
                  );
                },
              ),
            );

            return tts;
          },
        ),

        // ============================================================
        // TRIP MANAGER
        // ============================================================
        ChangeNotifierProvider<TripManager>(
          create: (context) {
            return TripManager(
              ble: context.read<MockBleService>(),
              mqtt: context.read<AbotMqttService>(),
              gps: context.read<GpsService>(),
              osrm: context.read<OsrmService>(),
            );
          },
        ),
      ],

      child: Selector<SettingsService, AppTheme>(
        selector: (_, service) => service.theme,
        builder: (context, theme, _) {
          return MaterialApp(
            title: 'ABOT Driver',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            darkTheme: buildAppDarkTheme(),
            themeMode: _themeModeFrom(theme),
            home: const SplashScreen(),
          );
        },
      ),
    );
  }

  ThemeMode _themeModeFrom(AppTheme theme) {
    switch (theme) {
      case AppTheme.dark:
        return ThemeMode.dark;

      case AppTheme.system:
        return ThemeMode.system;

      default:
        return ThemeMode.light;
    }
  }
}