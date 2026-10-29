import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../theme/app_theme.dart';

class DebugOverlay extends StatelessWidget {
  final Position? position;
  final int stepIndex;
  final int totalSteps;
  final double progressMeters;
  final double totalMeters;
  final bool bleConnected;
  final int bleSendCount;
  final int bleBytes;

  const DebugOverlay({
    super.key,
    this.position,
    required this.stepIndex,
    required this.totalSteps,
    required this.progressMeters,
    required this.totalMeters,
    required this.bleConnected,
    required this.bleSendCount,
    required this.bleBytes,
  });

  @override
  Widget build(BuildContext context) {
    final pos = position;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity( 0.85),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Colors.greenAccent,
          fontSize: 11,
          fontFamily: 'monospace',
          height: 1.5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _line(
              'GPS',
              pos == null
                  ? 'no signal'
                  : '${pos.latitude.toStringAsFixed(5)}, '
                        '${pos.longitude.toStringAsFixed(5)}',
            ),
            _line(
              'ACC',
              pos == null ? '-' : '${pos.accuracy.toStringAsFixed(1)} m',
            ),
            _line('STEP', '$stepIndex / $totalSteps'),
            _line(
              'PROG',
              '${progressMeters.toStringAsFixed(0)} / '
                  '${totalMeters.toStringAsFixed(0)} m',
            ),
            _line('BLE', bleConnected ? 'CONNECTED' : 'OFFLINE'),
            _line('SENT', '$bleSendCount msg / $bleBytes bytes'),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(label, style: const TextStyle(color: Colors.grey)),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(value, softWrap: true, overflow: TextOverflow.visible),
        ),
      ],
    );
  }
}
