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
  Future<bool> _saveBool(String key, bool v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setBool(key, v);
    } catch (e) {
      debugPrint('[SETTINGS] save $key error: $e');
      return false;
    }
  }

  Future<bool> _saveDouble(String key, double v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setDouble(key, v);
    } catch (e) {
      debugPrint('[SETTINGS] save $key error: $e');
      return false;
    }
  }

  Future<bool> _saveString(String key, String v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(key, v);
    } catch (e) {
      debugPrint('[SETTINGS] save $key error: $e');
      return false;
    }
  }

  // ============================================================
  // SETTERS — await save DULU, baru notify
  // ============================================================
  Future<void> setTtsEnabled(bool v) async {
    if (_ttsEnabled == v) return;
    final ok = await _saveBool(_keyTtsEnabled, v);
    if (!ok) return;
    _ttsEnabled = v;
    notifyListeners();
  }

  Future<void> setSpeakNearNow(bool v) async {
    if (_speakNearNow == v) return;
    final ok = await _saveBool(_keySpeakNearNow, v);
    if (!ok) return;
    _speakNearNow = v;
    notifyListeners();
  }

  Future<void> setDistanceUnit(DistanceUnit u) async {
    if (_distanceUnit == u) return;
    final ok = await _saveString(_keyDistanceUnit, u.name);
    if (!ok) return;
    _distanceUnit = u;
    notifyListeners();
  }

  Future<void> setSimSpeed(double s) async {
    final clamped = s.clamp(1.0, 50.0).toDouble();
    if (_simSpeed == clamped) return;
    final ok = await _saveDouble(_keySimSpeed, clamped);
    if (!ok) return;
    _simSpeed = clamped;
    notifyListeners();
  }

  Future<void> setAutoReroute(bool v) async {
    if (_autoReroute == v) return;
    final ok = await _saveBool(_keyAutoReroute, v);
    if (!ok) return;
    _autoReroute = v;
    notifyListeners();
  }

  Future<void> setTheme(AppTheme t) async {
    if (_theme == t) return;
    final ok = await _saveString(_keyTheme, t.name);
    if (!ok) return;
    _theme = t;
    notifyListeners();
  }

  Future<void> setKeepScreenOn(bool v) async {
    if (_keepScreenOn == v) return;
    final ok = await _saveBool(_keyKeepScreenOn, v);
    if (!ok) return;
    _keepScreenOn = v;
    notifyListeners();
  }

  Future<void> setOnboardingDone(bool v) async {
    if (_onboardingDone == v) return;
    final ok = await _saveBool(_keyOnboardingDone, v);
    if (!ok) return;
    _onboardingDone = v;
    notifyListeners();
  }

  Future<void> setBackgroundMode(bool v) async {
    if (_backgroundMode == v) return;
    final ok = await _saveBool(_keyBackgroundMode, v);
    if (!ok) return;
    _backgroundMode = v;
    notifyListeners();
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
      if (miles < 0.1) return '${(miles * 5280 / 50).round() * 50} kaki';
      if (miles < 10) return '${miles.toStringAsFixed(1)} mil';
      return '${miles.round()} mil';
    } else {
      if (meters < 1000) {
        final rounded = (meters / 50).round() * 50;
        return '$rounded meter';
      }
      final km = meters / 1000;
      if (km < 10) return '${km.toStringAsFixed(1)} kilometer';
      return '${km.round()} kilometer';
    }
  }
}
