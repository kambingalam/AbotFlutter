import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

abstract final class AbotBgMessages {
  static const String stopTrip = 'stop_trip';
  static const String stopAck = 'stop_ack';
}

abstract final class AbotBgButtons {
  static const String stopTrip = 'stop_trip';
}

@pragma('vm:entry-point')
void startAbotBackgroundTask() {
  FlutterForegroundTask.setTaskHandler(AbotTaskHandler());
}

class AbotTaskHandler extends TaskHandler {
  static const Duration _ackTimeout = Duration(seconds: 2);

  bool _awaitingStopAck = false;
  Timer? _stopFallbackTimer;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[BG-TASK] onStart (starter=${starter.name})');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[BG-TASK] onDestroy');
    _stopFallbackTimer?.cancel();
    _stopFallbackTimer = null;
    _awaitingStopAck = false;
  }

  @override
  void onReceiveData(Object data) {
    if (data == AbotBgMessages.stopAck) {
      _awaitingStopAck = false;
      _stopFallbackTimer?.cancel();
      _stopFallbackTimer = null;
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id != AbotBgButtons.stopTrip || _awaitingStopAck) return;

    _awaitingStopAck = true;
    FlutterForegroundTask.sendDataToMain(AbotBgMessages.stopTrip);

    _stopFallbackTimer?.cancel();
    _stopFallbackTimer = Timer(_ackTimeout, () async {
      if (!_awaitingStopAck) return;
      debugPrint('[BG-TASK] No ack from main, stopping service');
      _awaitingStopAck = false;
      await FlutterForegroundTask.stopService();
    });
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {}
}
