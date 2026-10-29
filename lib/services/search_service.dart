import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/place.dart';

class SearchService {
  static const String _photonUrl = 'https://photon.komoot.io/api';
  static const String _nominatimUrl =
      'https://nominatim.openstreetmap.org/search';

  Future<List<Place>> search(String query,
      {double? nearLat, double? nearLon}) async {
    if (query.trim().length < 3) return [];

    try {
      final results = await _searchPhoton(query, nearLat, nearLon);
      if (results.isNotEmpty) return results;
    } catch (e) {
      debugPrint('[SEARCH] Photon error: $e');
    }

    try {
      return await _searchNominatim(query);
    } catch (e) {
      debugPrint('[SEARCH] Nominatim error: $e');
      return [];
    }
  }

  Future<List<Place>> _searchPhoton(
      String query, double? lat, double? lon) async {
    final params = <String, String>{
      'q': query,
      'limit': '10',
      'lang': 'id',
    };

    if (lat != null && lon != null) {
      params['lat'] = lat.toString();
      params['lon'] = lon.toString();
    }

    final uri = Uri.parse(_photonUrl).replace(queryParameters: params);
    final resp = await http.get(uri).timeout(const Duration(seconds: 8));

    if (resp.statusCode != 200) return [];

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final features = data['features'] as List? ?? [];

    return features
        .map((f) => Place.fromPhoton(f as Map<String, dynamic>))
        .toList();
  }

  Future<List<Place>> _searchNominatim(String query) async {
    final uri = Uri.parse(_nominatimUrl).replace(queryParameters: {
      'q': query,
      'format': 'json',
      'limit': '10',
      'addressdetails': '1',
    });

    final resp = await http.get(uri, headers: {
      'User-Agent': 'AbotDriver/1.0',
    }).timeout(const Duration(seconds: 8));

    if (resp.statusCode != 200) return [];

    final data = jsonDecode(resp.body) as List;
    return data.map((item) {
      final m = item as Map<String, dynamic>;
      return Place(
        displayName: m['display_name'] as String? ?? '',
        shortName:
            (m['display_name'] as String? ?? '').split(',').first.trim(),
        lat: double.parse(m['lat'] as String),
        lon: double.parse(m['lon'] as String),
        type: m['type'] as String?,
      );
    }).toList();
  }
}