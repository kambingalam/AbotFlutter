import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'settings_service.dart';

class TtsStep {
  final String instruction;
  final String? road;
  final double distanceMeters;

  TtsStep({required this.instruction, this.road, required this.distanceMeters});
}

class TtsService extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();
  SettingsService? _settings;

  bool _initialized = false;
  bool _enabled = true;
  bool _speakNearNow = true;
  String _lastSpoken = '';
  DateTime _lastSpokenAt = DateTime.now();

  bool _isSpeaking = false;
  String? _pendingText;
  DateTime? _pendingAt;
  static const Duration _pendingMaxAge = Duration(seconds: 5);

  bool get enabled => _enabled;
  bool get speakNearNow => _speakNearNow;
  bool get isSpeaking => _isSpeaking;
  bool get isInitialized => _initialized;

  Future<void> init({SettingsService? settings}) async {
    _settings = settings;
    if (_initialized) return;

    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      debugPrint('[TTS] Audio session configured');
    } catch (e) {
      debugPrint('[TTS] Audio session config failed: $e');
    }

    await Future.delayed(const Duration(milliseconds: 500));

    for (var i = 0; i < 3; i++) {
      try {
        final result = await _tts.setLanguage('id-ID');
        debugPrint('[TTS] setLanguage result: $result');

        if (result == 1) {
          await _tts.setSpeechRate(0.5);
          await _tts.setVolume(1.0);
          await _tts.setPitch(1.0);
          await _tts.awaitSpeakCompletion(true);

          _tts.setCompletionHandler(_onSpeakComplete);
          _tts.setCancelHandler(_onSpeakCancel);
          _tts.setErrorHandler(_onSpeakError);

          _initialized = true;
          debugPrint('[TTS] Initialized (id-ID)');
          notifyListeners();
          return;
        }
      } catch (e) {
        debugPrint('[TTS] init attempt ${i + 1} failed: $e');
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    debugPrint('[TTS] GAGAL init setelah 3 percobaan');
  }

  void _onSpeakComplete() {
    if (!_isSpeaking) return;
    _isSpeaking = false;
    notifyListeners();
    _flushPending();
  }

  void _onSpeakCancel() {
    if (!_isSpeaking) return;
    _isSpeaking = false;
    _pendingText = null;
    _pendingAt = null;
    notifyListeners();
  }

  void _onSpeakError(dynamic e) {
    debugPrint('[TTS] speak error: $e');
    _isSpeaking = false;
    _pendingText = null;
    _pendingAt = null;
    notifyListeners();
  }

  void applySettings({required bool enabled, required bool speakNearNow}) {
    _enabled = enabled;
    _speakNearNow = speakNearNow;
    if (!enabled) {
      _pendingText = null;
      _pendingAt = null;
      _isSpeaking = false;
      _tts.stop();
    }
    notifyListeners();
    debugPrint(
      '[TTS] Settings applied: enabled=$enabled, nearNow=$speakNearNow',
    );
  }

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) {
      _pendingText = null;
      _pendingAt = null;
      _isSpeaking = false;
      _tts.stop();
    }
    notifyListeners();
  }

  void setSpeakNearNow(bool value) {
    if (_speakNearNow == value) return;
    _speakNearNow = value;
    notifyListeners();
  }

  Future<void> speak(String text, {bool force = false}) async {
    if (!_enabled) return;
    if (text.trim().isEmpty) return;

    final now = DateTime.now();
    if (!force &&
        text == _lastSpoken &&
        now.difference(_lastSpokenAt).inSeconds < 3) {
      return;
    }

    _lastSpoken = text;
    _lastSpokenAt = now;

    if (_isSpeaking) {
      _pendingText = text;
      _pendingAt = now;
      debugPrint('[TTS] (queued) $text');
      return;
    }

    _isSpeaking = true;
    notifyListeners();
    debugPrint('[TTS] $text');

    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
      debugPrint('[TTS] Audio focus activated');
    } catch (e) {
      debugPrint('[TTS] Audio focus failed: $e');
    }

    try {
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[TTS] speak throw: $e');
      _isSpeaking = false;
      notifyListeners();
    }
  }

  Future<void> _flushPending() async {
    if (!_enabled) return;

    final pending = _pendingText;
    final pendingAt = _pendingAt;
    if (pending == null || pending.isEmpty) return;

    _pendingText = null;
    _pendingAt = null;

    if (pendingAt != null &&
        DateTime.now().difference(pendingAt) > _pendingMaxAge) {
      debugPrint('[TTS] (dropped stale) $pending');
      return;
    }

    if (_isSpeaking) return;

    _isSpeaking = true;
    notifyListeners();
    debugPrint('[TTS] (flushed) $pending');

    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (_) {}

    try {
      await _tts.speak(pending);
    } catch (e) {
      debugPrint('[TTS] flush throw: $e');
      _isSpeaking = false;
      notifyListeners();
    }
  }

  Future<void> speakBeforeInstruction({required List<TtsStep> steps}) async {
    if (steps.isEmpty) return;

    final first = steps[0];
    String text;

    if (first.distanceMeters <= 50 && _speakNearNow) {
      text = 'Sekarang, ${first.instruction.toLowerCase()}';
    } else {
      final dist = _formatSpoken(first.distanceMeters);
      text = 'Dalam $dist, ${first.instruction.toLowerCase()}';
    }
    if (first.road != null && first.road!.isNotEmpty) {
      text += ' ke ${first.road}';
    }

    for (var i = 1; i < steps.length; i++) {
      final s = steps[i];
      final connector = s.distanceMeters < 50 ? 'lalu langsung' : 'lalu';
      text += ', $connector ${s.instruction.toLowerCase()}';
      if (s.road != null && s.road!.isNotEmpty) {
        text += ' ke ${s.road}';
      }
    }

    await speak(text);
  }

  Future<void> speakAfterInstruction({
    double? distanceMeters,
    bool isLastStep = false,
  }) async {
    String text;

    if (isLastStep) {
      text = 'Setelah ini langsung menuju tujuan';
    } else if (distanceMeters != null && distanceMeters > 0) {
      final dist = _formatSpoken(distanceMeters);
      text = 'Terus lurus sejauh $dist';
    } else {
      return;
    }

    await speak(text);
  }

  Future<void> speakNearDestination({
    required String destinationName,
    required double distanceMeters,
  }) async {
    final dist = _formatSpoken(distanceMeters);
    await speak('Anda akan tiba di $destinationName dalam $dist');
  }

  Future<void> speakArrived(String destinationName) async {
    await speak('Anda sudah sampai di $destinationName. Terima kasih.');
  }

  Future<void> speakTripStart(String destinationName) async {
    await speak('Mulai perjalanan ke $destinationName. Hati-hati di jalan.');
  }

  String _formatSpoken(double m) {
    if (_settings != null) return _settings!.formatDistanceSpoken(m);

    if (m < 50) return 'sekarang';
    if (m < 1000) {
      final rounded = (m / 50).round() * 50;
      return '$rounded meter';
    }
    final km = m / 1000;
    if (km < 10) return '${km.toStringAsFixed(1)} kilometer';
    return '${km.round()} kilometer';
  }

  Future<void> stop() async {
    _pendingText = null;
    _pendingAt = null;
    _isSpeaking = false;
    notifyListeners();
    await _tts.stop();
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {}
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}
