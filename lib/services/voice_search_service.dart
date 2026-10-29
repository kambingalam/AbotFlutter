import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Voice search service — bahasa Indonesia.
class VoiceSearchService {
  final SpeechToText _speech = SpeechToText();

  Future<bool>? _initFuture;
  bool _initialized = false;
  bool _available = false;

  bool _listening = false;
  bool _starting = false;

  /// Locale yang dipakai (hasil resolve dari daftar locale device).
  String? _localeId;

  String _lastWords = '';

  /// Mencegah onFinalResult terpanggil dua kali dalam satu sesi
  /// (dari finalResult dan dari fallback status `done`).
  bool _finalDelivered = false;

  bool get listening => _listening;
  bool get available => _available;
  bool get initialized => _initialized;
  String get lastWords => _lastWords;

  void Function(String text)? onFinalResult;
  void Function(bool listening)? onListeningChanged;
  void Function(String error)? onError;

  // ============================================================
  // INIT
  // ============================================================
  Future<bool> init() {
    // Aman dipanggil berkali-kali / bersamaan.
    return _initFuture ??= _doInit();
  }

  Future<bool> _doInit() async {
    try {
      _available = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onSpeechError,
        debugLogging: false,
      );

      if (_available) {
        _localeId = await _resolveLocale();
      }

      debugPrint('[VOICE] init: $_available, locale: $_localeId');
    } catch (e) {
      debugPrint('[VOICE] init error: $e');
      _available = false;
    }

    _initialized = true;
    return _available;
  }

  /// Cari locale Indonesia di device. Format bisa `id_ID` atau `id-ID`.
  /// Kalau tidak ada, fallback ke locale sistem.
  Future<String?> _resolveLocale() async {
    try {
      final locales = await _speech.locales();
      for (final l in locales) {
        final id = l.localeId.toLowerCase();
        if (id == 'id_id' || id == 'id-id') return l.localeId;
      }
      for (final l in locales) {
        if (l.localeId.toLowerCase().startsWith('id')) return l.localeId;
      }
      final system = await _speech.systemLocale();
      return system?.localeId;
    } catch (e) {
      debugPrint('[VOICE] locale error: $e');
      return null; // biarkan plugin pakai default
    }
  }

  // ============================================================
  // START / STOP
  // ============================================================
  Future<bool> start() async {
    // Guard: kalau sedang start, jangan re-entry.
    if (_starting) {
      debugPrint('[VOICE] start() ignored — already starting');
      return false;
    }
    // Guard: kalau sudah listening, anggap sukses.
    if (_listening) {
      debugPrint('[VOICE] start() ignored — already listening');
      return true;
    }

    _starting = true;

    try {
      if (!_initialized) await init();

      if (!_available) {
        onError?.call('Voice tidak tersedia di device ini');
        return false;
      }

      _lastWords = '';
      _finalDelivered = false;

      // Set listening=true LANGSUNG, jangan tunggu callback onStatus
      // yang kadang lambat / tidak fire di beberapa device.
      _listening = true;
      onListeningChanged?.call(true);

      await _speech.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          localeId: _localeId,
          listenFor: const Duration(seconds: 10),
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.search,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[VOICE] start error: $e');
      // Reset state kalau gagal
      _listening = false;
      onListeningChanged?.call(false);
      onError?.call('Gagal memulai: $e');
      return false;
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    // Set false LANGSUNG, jangan tunggu callback
    final wasListening = _listening;
    _listening = false;
    if (wasListening) {
      onListeningChanged?.call(false);
    }

    try {
      await _speech.stop();
    } catch (_) {}
  }

  Future<void> cancel() async {
    final wasListening = _listening;
    _listening = false;
    if (wasListening) {
      onListeningChanged?.call(false);
    }

    try {
      await _speech.cancel();
    } catch (_) {}
  }

  /// Paksa notify status ke UI. Berguna kalau state lokal UI tidak
  /// sinkron dengan service (misal karena race atau rebuild).
  void syncStatus() {
    onListeningChanged?.call(_listening);
  }

  // ============================================================
  // CALLBACKS
  // ============================================================
  void _onStatus(String status) {
    debugPrint('[VOICE] status: $status');

    // Update _listening berdasarkan status dari plugin.
    final newListening = status == SpeechToText.listeningStatus;

    if (_listening != newListening) {
      _listening = newListening;
      onListeningChanged?.call(_listening);
    }

    // Fallback: sesi selesai (timeout / pause) tapi finalResult belum datang.
    if (status == SpeechToText.doneStatus) {
      _deliverFinal(_lastWords);
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    _lastWords = result.recognizedWords;

    if (result.finalResult) {
      debugPrint('[VOICE] final: "$_lastWords"');
      _deliverFinal(_lastWords);
    }
  }

  void _deliverFinal(String text) {
    final trimmed = text.trim();
    if (_finalDelivered || trimmed.isEmpty) return;
    _finalDelivered = true;
    onFinalResult?.call(trimmed);
  }

  void _onSpeechError(SpeechRecognitionError error) {
    debugPrint(
      '[VOICE] error: ${error.errorMsg} (permanent: ${error.permanent})',
    );

    // Set false + notify
    if (_listening) {
      _listening = false;
      onListeningChanged?.call(false);
    }

    final msg = error.errorMsg;
    if (msg.contains('permission')) {
      onError?.call('Izin mikrofon ditolak');
    } else if (msg.contains('no_match') || msg.contains('speech_timeout')) {
      onError?.call('Tidak terdengar jelas, coba lagi');
    } else if (msg.contains('network')) {
      onError?.call('Butuh koneksi internet');
    } else if (msg.contains('language')) {
      onError?.call('Bahasa Indonesia belum tersedia di device ini');
    } else {
      onError?.call('Error: $msg');
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================
  Future<void> dispose() async {
    // Kosongkan callback dulu supaya tidak memanggil widget yang sudah dispose.
    onFinalResult = null;
    onListeningChanged = null;
    onError = null;
    await cancel();
  }
}
