import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/nav_step.dart';
import '../models/trip.dart';

class OsrmException implements Exception {
  final String message;
  final OsrmErrorType type;

  OsrmException(this.message, this.type);

  @override
  String toString() => 'OsrmException(${type.name}): $message';
}

enum OsrmErrorType { network, http, badResponse, parse, unknown }

class OsrmService {
  Future<Trip?> getRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required String destinationName,
  }) async {
    try {
      final routes = await getRoutes(
        fromLat: fromLat,
        fromLon: fromLon,
        toLat: toLat,
        toLon: toLon,
        destinationName: destinationName,
        alternatives: 1,
      );
      return routes.isEmpty ? null : routes.first;
    } on OsrmException catch (e) {
      debugPrint('[OSRM] getRoute gagal: $e');
      return null;
    }
  }

  Future<List<Trip>> getRoutes({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required String destinationName,
    int alternatives = 3,
  }) async {
    if (!_isValidCoord(fromLat, fromLon) || !_isValidCoord(toLat, toLon)) {
      throw OsrmException('Koordinat tidak valid', OsrmErrorType.badResponse);
    }

    final url = Uri.parse(
      '${AppConfig.osrmBaseUrl}/'
      '$fromLon,$fromLat;$toLon,$toLat'
      '?overview=simplified&geometries=geojson&steps=true'
      '&alternatives=$alternatives',
    );

    debugPrint('[OSRM] GET $url');

    http.Response response;
    try {
      response = await http.get(url).timeout(const Duration(seconds: 12));
    } on Exception catch (e) {
      throw OsrmException('Network: $e', OsrmErrorType.network);
    }

    if (response.statusCode != 200) {
      throw OsrmException('HTTP ${response.statusCode}', OsrmErrorType.http);
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw OsrmException('JSON parse: $e', OsrmErrorType.parse);
    }

    final code = data['code'] as String?;
    if (code == null || code != 'Ok') {
      final msg = data['message'] as String? ?? 'no message';
      throw OsrmException(
        'OSRM code=$code msg=$msg',
        OsrmErrorType.badResponse,
      );
    }

    final routesRaw = data['routes'];
    if (routesRaw is! List || routesRaw.isEmpty) {
      throw OsrmException('No routes in response', OsrmErrorType.badResponse);
    }

    final sorted =
        List<Map<String, dynamic>>.from(
          routesRaw.map((r) => r as Map<String, dynamic>),
        )..sort((a, b) {
          final da = (a['duration'] as num?)?.toDouble() ?? 0;
          final db = (b['duration'] as num?)?.toDouble() ?? 0;
          return da.compareTo(db);
        });

    final trips = <Trip>[];
    for (var i = 0; i < sorted.length; i++) {
      final trip = _parseRoute(
        route: sorted[i],
        index: i,
        destinationName: destinationName,
        toLat: toLat,
        toLon: toLon,
      );
      if (trip != null) trips.add(trip);
    }

    if (trips.isEmpty) {
      throw OsrmException('Semua route gagal di-parse', OsrmErrorType.parse);
    }

    return trips;
  }

  bool _isValidCoord(double lat, double lon) {
    if (lat.isNaN || lat.isInfinite) return false;
    if (lon.isNaN || lon.isInfinite) return false;
    if (lat < -90 || lat > 90) return false;
    if (lon < -180 || lon > 180) return false;
    return true;
  }

  Trip? _parseRoute({
    required Map<String, dynamic> route,
    required int index,
    required String destinationName,
    required double toLat,
    required double toLon,
  }) {
    try {
      final distance = (route['distance'] as num?)?.toDouble();
      final duration = (route['duration'] as num?)?.toDouble();
      if (distance == null || duration == null) return null;

      final geometry = route['geometry'];
      if (geometry is! Map<String, dynamic>) return null;

      final rawCoords = geometry['coordinates'];
      if (rawCoords is! List || rawCoords.length < 2) return null;

      final coords = <List<double>>[];
      for (final c in rawCoords) {
        if (c is! List || c.length < 2) continue;
        final lon = (c[0] as num?)?.toDouble();
        final lat = (c[1] as num?)?.toDouble();
        if (lon == null || lat == null) continue;
        if (!_isValidCoord(lat, lon)) continue;
        coords.add([lon, lat]);
      }

      if (coords.length < 2) return null;

      final cumulative = <double>[0.0];
      for (var i = 1; i < coords.length; i++) {
        final d = _haversine(
          coords[i - 1][1],
          coords[i - 1][0],
          coords[i][1],
          coords[i][0],
        );
        cumulative.add(cumulative[i - 1] + d);
      }

      final steps = <NavStep>[];
      final viaRoads = <String>[];
      final legs = route['legs'] as List? ?? [];
      for (final leg in legs) {
        if (leg is! Map) continue;
        final rawSteps = leg['steps'] as List? ?? [];
        for (final s in rawSteps) {
          if (s is! Map<String, dynamic>) continue;
          final maneuver = s['maneuver'];
          if (maneuver is! Map<String, dynamic>) continue;
          final loc = maneuver['location'];
          int routeIndex = 0;
          double routeDistance = 0;

          if (loc is List && loc.length >= 2) {
            final mLon = (loc[0] as num?)?.toDouble();
            final mLat = (loc[1] as num?)?.toDouble();
            if (mLon != null && mLat != null) {
              double best = double.infinity;
              for (var i = 0; i < coords.length; i++) {
                final d = _haversine(mLat, mLon, coords[i][1], coords[i][0]);
                if (d < best) {
                  best = d;
                  routeIndex = i;
                  routeDistance = cumulative[i];
                }
              }
            }
          }

          steps.add(NavStep.fromOsrm(s, routeIndex, routeDistance));

          final roadName = s['name'] as String? ?? '';
          if (roadName.isNotEmpty &&
              !viaRoads.contains(roadName) &&
              viaRoads.length < 3) {
            viaRoads.add(roadName);
          }
        }
      }

      final summary = index == 0 ? 'Tercepat' : 'Alternatif $index';
      final viaText = viaRoads.isEmpty ? '' : 'via ${viaRoads.join(', ')}';

      return Trip(
        destinationName: destinationName,
        destinationLat: toLat,
        destinationLon: toLon,
        totalDistance: distance,
        totalDuration: duration,
        coords: coords,
        steps: steps,
        index: index,
        summary: summary,
        viaRoads: viaText,
      );
    } catch (e) {
      debugPrint('[OSRM] _parseRoute[$index] gagal: $e');
      return null;
    }
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _toRad(double deg) => deg * math.pi / 180.0;
}
