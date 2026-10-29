import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'background_task_handler.dart';

class BackgroundService {
  BackgroundService._();

  static bool _initialized = false;
  static Future<bool>? _starting;

  static const Duration _minUpdateInterval = Duration(seconds: 5);
  static String? _lastTitle;
  static String? _lastText;
  static DateTime? _lastUpdateAt;

  static final StreamController<void> _stopRequests =
      StreamController<void>.broadcast();

  static Stream<void> get stopRequests => _stopRequests.stream;

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  static void init() {
    if (_initialized) return;

    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'abot_navigation_v2',
        channelName: 'ABOT Navigation',
        channelDescription: 'Notifikasi navigasi aktif dari ABOT Driver',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );

    _initialized = true;
    debugPrint('[BG] BackgroundService initialized');
  }

  static void _onTaskData(Object data) {
    if (data == AbotBgMessages.stopTrip) {
      FlutterForegroundTask.sendDataToTask(AbotBgMessages.stopAck);
      _stopRequests.add(null);
    }
  }

  static Future<bool> start({
    required String destinationName,
    required String distanceText,
    required String etaText,
    bool useBle = false,
  }) {
    return _starting ??= _doStart(
      destinationName: destinationName,
      distanceText: distanceText,
      etaText: etaText,
    ).whenComplete(() => _starting = null);
  }

  static Future<bool> _doStart({
    required String destinationName,
    required String distanceText,
    required String etaText,
  }) async {
    try {
      if (!_initialized) init();

      final title = _title(destinationName);
      final text = _text(distanceText, etaText);

      if (await FlutterForegroundTask.isRunningService) {
        debugPrint('[BG] Already running, refreshing notification');
        await _pushUpdate(title, text);
        return true;
      }

      var permission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        permission =
            await FlutterForegroundTask.requestNotificationPermission();
      }
      if (permission != NotificationPermission.granted) {
        debugPrint('[BG] Notification permission not granted');
      }

      await FlutterForegroundTask.startService(
        notificationTitle: title,
        notificationText: text,
        notificationButtons: const [
          NotificationButton(id: AbotBgButtons.stopTrip, text: 'Selesai'),
        ],
        callback: startAbotBackgroundTask,
      );

      _lastTitle = title;
      _lastText = text;
      _lastUpdateAt = DateTime.now();

      debugPrint('[BG] Service started');
      return true;
    } catch (e, st) {
      debugPrint('[BG] Start error: $e\n$st');
      return false;
    }
  }

  static Future<void> updateNotification({
    required String destinationName,
    required String distanceText,
    required String etaText,
  }) async {
    final title = _title(destinationName);
    final text = _text(distanceText, etaText);

    if (title == _lastTitle && text == _lastText) return;

    final last = _lastUpdateAt;
    if (last != null && DateTime.now().difference(last) < _minUpdateInterval) {
      return;
    }

    if (!await FlutterForegroundTask.isRunningService) return;
    await _pushUpdate(title, text);
  }

  static Future<void> _pushUpdate(String title, String text) async {
    _lastTitle = title;
    _lastText = text;
    _lastUpdateAt = DateTime.now();
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  static Future<void> stop() async {
    final pending = _starting;
    if (pending != null) {
      await pending.catchError((_) => false);
    }

    _lastTitle = null;
    _lastText = null;
    _lastUpdateAt = null;

    if (!await FlutterForegroundTask.isRunningService) return;

    await FlutterForegroundTask.stopService();
    debugPrint('[BG] Service stopped');
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    return FlutterForegroundTask.isIgnoringBatteryOptimizations;
  }

  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    return FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }

  static String _title(String destinationName) =>
      'ABOT Driver · $destinationName';

  static String _text(String distanceText, String etaText) =>
      '$distanceText · $etaText';
}
