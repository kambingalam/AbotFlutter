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