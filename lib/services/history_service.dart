import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/place.dart';

class HistoryService {
  static const String _key = 'search_history';
  static const int _maxItems = 20;

  Future<List<Place>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];

    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((j) => Place.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(Place place) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getHistory();

    list.removeWhere((p) =>
        p.displayName == place.displayName &&
        (p.lat - place.lat).abs() < 0.0001 &&
        (p.lon - place.lon).abs() < 0.0001);

    list.insert(0, place);

    if (list.length > _maxItems) list.removeRange(_maxItems, list.length);

    await prefs.setString(
        _key, jsonEncode(list.map((p) => p.toJson()).toList()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}