import 'package:flutter/services.dart';

/// Wrapper haptic feedback supaya konsisten di seluruh app.
/// Style: Gojek Driver — halus tapi terasa.
class HapticService {
  /// Tombol besar: Mulai Trip, Selesai, dll
  static Future<void> tap() => HapticFeedback.lightImpact();

  /// Tombol penting: Arrived, Off-route warning, Terima kasih
  static Future<void> success() => HapticFeedback.mediumImpact();

  /// Tap kartu, pilih opsi, scroll wheel picker
  static Future<void> select() => HapticFeedback.selectionClick();

  /// Error / warning / GPS gagal
  static Future<void> warning() => HapticFeedback.heavyImpact();

  /// Vibrasi panjang untuk notifikasi penting
  static Future<void> vibrate() => HapticFeedback.vibrate();
}
