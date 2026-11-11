import 'nav_step.dart';

class Trip {
  final String destinationName;
  final double destinationLat;
  final double destinationLon;

  final double totalDistance;
  final double totalDuration;
  final List<List<double>> coords;
  final List<NavStep> steps;

  /// Info tambahan untuk alternatif rute
  final int index;             // 0, 1, 2
  final String summary;        // "Tercepat", "Alternatif 1", ...
  final String viaRoads;       // "via Jl. Sudirman, Jl. Thamrin"

  Trip({
    required this.destinationName,
    required this.destinationLat,
    required this.destinationLon,
    required this.totalDistance,
    required this.totalDuration,
    required this.coords,
    required this.steps,
    this.index = 0,
    this.summary = '',
    this.viaRoads = '',
  });

  bool get isReady => coords.length >= 2 && steps.isNotEmpty;

  double get distanceKm => totalDistance / 1000.0;
  double get durationMin => totalDuration / 60.0;

  /// Salinan ringkas untuk ESP32: maksimal [maxPoints] titik, koordinat
  /// dibulatkan 5 desimal (~1 m), idx langkah dipetakan ke titik baru.
  /// Firmware membuang pesan >8 KB tanpa error, jadi rute kota harus dipangkas.
  Trip forDevice({int maxPoints = 120}) {
    final rounded = [
      for (final c in coords) [_round5(c[0]), _round5(c[1])],
    ];

    if (coords.length <= maxPoints) {
      return copyWith(coords: rounded);
    }

    final last = coords.length - 1;
    final gap = last / (maxPoints - 1);
    final keep = [
      for (var i = 0; i < maxPoints - 1; i++) (i * gap).round(),
      last,
    ];

    int mapIndex(int oldIndex) {
      var best = 0;
      for (var i = 0; i < keep.length; i++) {
        if ((keep[i] - oldIndex).abs() < (keep[best] - oldIndex).abs()) {
          best = i;
        }
      }
      return best;
    }

    return copyWith(
      coords: [for (final i in keep) rounded[i]],
      steps: [
        for (final s in steps)
          NavStep(
            instruction: s.instruction,
            road: s.road,
            distance: s.distance,
            routeIndex: mapIndex(s.routeIndex),
            routeDistance: s.routeDistance,
            important: s.important,
          ),
      ],
    );
  }

  static double _round5(double v) => (v * 100000).roundToDouble() / 100000;

  Trip copyWith({
    String? destinationName,
    double? destinationLat,
    double? destinationLon,
    double? totalDistance,
    double? totalDuration,
    List<List<double>>? coords,
    List<NavStep>? steps,
    int? index,
    String? summary,
    String? viaRoads,
  }) {
    return Trip(
      destinationName: destinationName ?? this.destinationName,
      destinationLat: destinationLat ?? this.destinationLat,
      destinationLon: destinationLon ?? this.destinationLon,
      totalDistance: totalDistance ?? this.totalDistance,
      totalDuration: totalDuration ?? this.totalDuration,
      coords: coords ?? this.coords,
      steps: steps ?? this.steps,
      index: index ?? this.index,
      summary: summary ?? this.summary,
      viaRoads: viaRoads ?? this.viaRoads,
    );
  }

  @override
  String toString() {
    return 'Trip($destinationName, '
        '${distanceKm.toStringAsFixed(1)}km, '
        '${durationMin.toStringAsFixed(0)}min, '
        '${steps.length} steps)';
  }
}