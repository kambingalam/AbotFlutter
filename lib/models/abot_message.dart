import 'dart:convert';

class AbotMessage {
  final String type;
  final Map<String, dynamic> data;

  AbotMessage({required this.type, required this.data});

  factory AbotMessage.fromJson(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final type = decoded['t'] as String? ?? 'unknown';
    return AbotMessage(type: type, data: decoded);
  }

  String toJsonString() {
    final map = Map<String, dynamic>.from(data);
    map['t'] = type;
    return '${jsonEncode(map)}\n';
  }

  factory AbotMessage.route({
    required double distance,
    required double duration,
    required List<List<double>> coords,
    required List<Map<String, dynamic>> steps,
  }) {
    return AbotMessage(
      type: 'route',
      data: {
        'dist': distance,
        'dur': duration,
        'coords': coords,
        'steps': steps,
      },
    );
  }

  factory AbotMessage.gpsProgress(double progressMeters) {
    return AbotMessage(type: 'gps', data: {'progress': progressMeters});
  }

  factory AbotMessage.gpsLatLon(double lat, double lon) {
    return AbotMessage(type: 'gps', data: {'lat': lat, 'lon': lon});
  }

  factory AbotMessage.tripStart() => AbotMessage(type: 'trip_start', data: {});
  factory AbotMessage.tripEnd() => AbotMessage(type: 'trip_end', data: {});
  factory AbotMessage.reset() => AbotMessage(type: 'reset', data: {});
  factory AbotMessage.ping() => AbotMessage(type: 'ping', data: {});
}