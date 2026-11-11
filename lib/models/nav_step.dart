class NavStep {
  final String instruction;
  final String road;
  final double distance;
  final int routeIndex;
  final double routeDistance;
  final bool important;

  NavStep({
    required this.instruction,
    required this.road,
    required this.distance,
    required this.routeIndex,
    required this.routeDistance,
    required this.important,
  });

  factory NavStep.fromOsrm(
      Map<String, dynamic> step, int routeIndex, double routeDistance) {
    final maneuver = step['maneuver'] as Map<String, dynamic>? ?? {};
    final type = (maneuver['type'] as String? ?? '').toLowerCase();
    final modifier = (maneuver['modifier'] as String? ?? '').toLowerCase();

    String instruction = 'LANJUT';
    if (type.contains('roundabout')) {
      instruction = 'PUTARAN';
    } else if (modifier.contains('uturn')) {
      instruction = 'PUTAR BALIK';
    } else if (modifier.contains('left')) {
      instruction = 'BELOK KIRI';
    } else if (modifier.contains('right')) {
      instruction = 'BELOK KANAN';
    } else if (type == 'merge') {
      instruction = 'GABUNG';
    } else if (type == 'fork') {
      instruction = 'PILIH JALUR';
    }

    final important = (type == 'turn' ||
        type == 'merge' ||
        type == 'fork' ||
        type == 'roundabout' ||
        type == 'on ramp' ||
        type == 'off ramp');

    return NavStep(
      instruction: instruction,
      road: step['name'] as String? ?? '',
      distance: (step['distance'] as num?)?.toDouble() ?? 0.0,
      routeIndex: routeIndex,
      routeDistance: routeDistance,
      important: important,
    );
  }

  Map<String, dynamic> toJson() => {
        'instr': instruction,
        'road': _ascii20(road),
        'dist': _round1(distance),
        'idx': routeIndex,
        'routeDist': _round1(routeDistance),
        'imp': important,
      };

  /// Font OLED firmware hanya ASCII dan kolomnya sempit.
  static String _ascii20(String s) {
    final out = StringBuffer();
    for (final rune in s.runes) {
      if (out.length >= 20) break;
      out.writeCharCode(rune < 128 ? rune : 63); // '?'
    }
    return out.toString();
  }

  static double _round1(double v) => (v * 10).roundToDouble() / 10;
}