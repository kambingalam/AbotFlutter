import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DistanceUnit { km, miles }

enum AppTheme { light, dark, system }

class SettingsService extends ChangeNotifier {
  static const String _keyTtsEnabled = 'settings.tts.enabled';
  static const String _keySpeakNearNow = 'settings.tts.speakNearNow';
  static const String _keyDistanceUnit = 'settings.distance.unit';
  static const String _keySimSpeed = 'settings.sim.speed';
  static const String _keyAutoReroute = 'settings.autoroute';
  static const String _keyTheme = 'settings.theme';
  static const String _keyKeepScreenOn = 'settings.keepScreenOn';
  static const String _keyOnboardingDone = 'settings.onboarding.done';
  static const String _keyBackgroundMode = 'settings.backgroundMode';

  bool _ttsEnabled = true;
  bool _speakNearNow = true;
  DistanceUnit _distanceUnit = DistanceUnit.km;
  double _simSpeed = 5.0;
  bool _autoReroute = true;
  AppTheme _theme = AppTheme.light;
  bool _keepScreenOn = true;
  bool _onboardingDone = false;
  bool _backgroundMode = true;
  bool _loaded = false;
  String? _lastLoadError;

  bool get ttsEnabled => _ttsEnabled;
  bool get speakNearNow => _speakNearNow;
  DistanceUnit get distanceUnit => _distanceUnit;
  double get simSpeed => _simSpeed;
  bool get autoReroute => _autoReroute;
  AppTheme get theme => _theme;
  bool get keepScreenOn => _keepScreenOn;
  bool get onboardingDone => _onboardingDone;
  bool get backgroundMode => _backgroundMode;
  bool get isLoaded => _loaded;
  String? get lastLoadError => _lastLoadError;

  // ============================================================
  // LOAD
  // ============================================================
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _ttsEnabled = prefs.getBool(_keyTtsEnabled) ?? true;
      _speakNearNow = prefs.getBool(_keySpeakNearNow) ?? true;
      _distanceUnit = _parseUnit(prefs.getString(_keyDistanceUnit) ?? 'km');
      _simSpeed = prefs.getDouble(_keySimSpeed) ?? 5.0;
      _autoReroute = prefs.getBool(_keyAutoReroute) ?? true;
      _theme = _parseTheme(prefs.getString(_keyTheme) ?? 'light');
      _keepScreenOn = prefs.getBool(_keyKeepScreenOn) ?? true;
      _onboardingDone = prefs.getBool(_keyOnboardingDone) ?? false;
      _backgroundMode = prefs.getBool(_keyBackgroundMode) ?? true;

      _lastLoadError = null;
      debugPrint('[SETTINGS] Loaded');
    } catch (e) {
      _lastLoadError = e.toString();
      debugPrint('[SETTINGS] Load error: $e');
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  // ============================================================
  // SAVE HELPERS
  // ============================================================
  Future<bool> _save(
    String key,
    Future<bool> Function(SharedPreferences prefs) write,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await write(prefs);
    } catch (e) {
      debugPrint('[SETTINGS] save $key error: $e');
      return false;
    }
  }

  Future<bool> _saveBool(String key, bool v) =>
      _save(key, (p) => p.setBool(key, v));

  Future<bool> _saveDouble(String key, double v) =>
      _save(key, (p) => p.setDouble(key, v));

  Future<bool> _saveString(String key, String v) =>
      _save(key, (p) => p.setString(key, v));

  // ============================================================
  // SETTERS — simpan DULU, baru update state + notify.
  // Return true jika nilai berhasil tersimpan (atau sudah sama).
  // ============================================================
  Future<bool> setTtsEnabled(bool v) async {
    if (_ttsEnabled == v) return true;
    if (!await _saveBool(_keyTtsEnabled, v)) return false;
    _ttsEnabled = v;
    notifyListeners();
    return true;
  }

  Future<bool> setSpeakNearNow(bool v) async {
    if (_speakNearNow == v) return true;
    if (!await _saveBool(_keySpeakNearNow, v)) return false;
    _speakNearNow = v;
    notifyListeners();
    return true;
  }

  Future<bool> setDistanceUnit(DistanceUnit u) async {
    if (_distanceUnit == u) return true;
    if (!await _saveString(_keyDistanceUnit, u.name)) return false;
    _distanceUnit = u;
    notifyListeners();
    return true;
  }

  Future<bool> setSimSpeed(double s) async {
    final clamped = s.clamp(1.0, 50.0).toDouble();
    if (_simSpeed == clamped) return true;
    if (!await _saveDouble(_keySimSpeed, clamped)) return false;
    _simSpeed = clamped;
    notifyListeners();
    return true;
  }

  Future<bool> setAutoReroute(bool v) async {
    if (_autoReroute == v) return true;
    if (!await _saveBool(_keyAutoReroute, v)) return false;
    _autoReroute = v;
    notifyListeners();
    return true;
  }

  Future<bool> setTheme(AppTheme t) async {
    if (_theme == t) return true;
    if (!await _saveString(_keyTheme, t.name)) return false;
    _theme = t;
    notifyListeners();
    return true;
  }

  Future<bool> setKeepScreenOn(bool v) async {
    if (_keepScreenOn == v) return true;
    if (!await _saveBool(_keyKeepScreenOn, v)) return false;
    _keepScreenOn = v;
    notifyListeners();
    return true;
  }

  Future<bool> setOnboardingDone(bool v) async {
    if (_onboardingDone == v) return true;
    if (!await _saveBool(_keyOnboardingDone, v)) return false;
    _onboardingDone = v;
    notifyListeners();
    return true;
  }

  Future<bool> setBackgroundMode(bool v) async {
    if (_backgroundMode == v) return true;
    if (!await _saveBool(_keyBackgroundMode, v)) return false;
    _backgroundMode = v;
    notifyListeners();
    return true;
  }

  // ============================================================
  // PARSER
  // ============================================================
  DistanceUnit _parseUnit(String s) =>
      s == 'miles' ? DistanceUnit.miles : DistanceUnit.km;

  AppTheme _parseTheme(String s) {
    switch (s) {
      case 'dark':
        return AppTheme.dark;
      case 'system':
        return AppTheme.system;
      default:
        return AppTheme.light;
    }
  }

  // ============================================================
  // FORMAT
  // ============================================================
  String formatDistanceShort(double meters) {
    if (_distanceUnit == DistanceUnit.miles) {
      final miles = meters / 1609.344;
      if (miles < 0.1) return '${(miles * 5280).round()} ft';
      if (miles < 10) return '${miles.toStringAsFixed(1)} mi';
      return '${miles.round()} mi';
    } else {
      if (meters < 1000) return '${meters.round()} m';
      final km = meters / 1000;
      if (km < 10) return '${km.toStringAsFixed(1)} km';
      return '${km.round()} km';
    }
  }

  String formatDistanceSpoken(double meters) {
    if (_distanceUnit == DistanceUnit.miles) {
      final miles = meters / 1609.344;
      if (miles < 0.1) {
        // Bulatkan ke 50 kaki terdekat, minimal 50 (jangan "0 kaki").
        var feet = (miles * 5280 / 50).round() * 50;
        if (feet < 50) feet = 50;
        return '$feet kaki';
      }
      if (miles < 10) return '${miles.toStringAsFixed(1)} mil';
      return '${miles.round()} mil';
    } else {
      if (meters < 1000) {
        // <100 m bulatkan ke 10, selebihnya ke 50. Minimal 10 (jangan "0 meter").
        final step = meters < 100 ? 10 : 50;
        var rounded = (meters / step).round() * step;
        if (rounded < 10) rounded = 10;
        return '$rounded meter';
      }
      final km = meters / 1000;
      if (km < 10) return '${km.toStringAsFixed(1)} kilometer';
      return '${km.round()} kilometer';
    }
  }
}