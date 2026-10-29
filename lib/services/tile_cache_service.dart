
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

/// Service cache tile peta untuk ABOT Drivers.
///
/// Cache menggunakan FMTC 9.0.1.
/// Batas MB diterjemahkan menjadi perkiraan jumlah tile,
/// karena FMTC membatasi browse cache berdasarkan jumlah tile,
/// bukan ukuran MB yang mutlak.
class TileCacheService {
  static const String _storeName = 'abot_map_tiles';

  // Perkiraan: 1 tile = 50 KiB.
  // 300 MB berarti sekitar 6.000 tile.
  static const int _estimatedTileSizeKiB = 50;

  static bool _initialized = false;
  static bool get initialized => _initialized;
  static bool get isReady => _initialized;

  static int _sizeLimitMB = 300;
  static int get sizeLimitMB => _sizeLimitMB;

  static final StreamController<int> _sizeLimitController =
      StreamController<int>.broadcast();

  static Stream<int> get sizeLimitStream => _sizeLimitController.stream;

  static int get _maxTileCount {
    final bytes = _sizeLimitMB * 1024 * 1024;
    final estimatedBytes = _estimatedTileSizeKiB * 1024;

    return (bytes / estimatedBytes).floor().clamp(1, 1000000);
  }

  /// Provider yang dipakai semua layar peta.
  ///
  /// cacheFirst memprioritaskan cache dan menggunakan jaringan
  /// jika tile belum tersedia atau sudah kedaluwarsa.
  static TileProvider get tileProvider {
    return store.getTileProvider(
      settings: FMTCTileProviderSettings(
        behavior: CacheBehavior.cacheFirst,
        cachedValidDuration: const Duration(days: 16),
        maxStoreLength: _maxTileCount,
      ),
    );
  }

  /// Inisialisasi backend dan store satu kali.
  ///
  /// Kegagalan cache tidak dilempar keluar agar aplikasi
  /// tetap bisa mencoba berjalan tanpa cache.
  static Future<void> init() async {
    if (_initialized) return;

    try {
      await FMTCObjectBoxBackend().initialise();

      final currentStore = store;
      final exists = await currentStore.manage.ready;

      if (!exists) {
        await currentStore.manage.create();
      }

      final ready = await currentStore.manage.ready;

      if (!ready) {
        debugPrint('[CACHE] Store belum siap; cache dinonaktifkan.');
        return;
      }

      _initialized = true;

      debugPrint(
        '[CACHE] FMTC siap. '
        'Limit perkiraan: $_sizeLimitMB MB '
        '($_maxTileCount tile).',
      );

      unawaited(enforceSizeLimit());
    } catch (error, stackTrace) {
      debugPrint('[CACHE] Inisialisasi gagal: $error');
      debugPrint('[CACHE] Stack: $stackTrace');
    }
  }

  static FMTCStore get store => const FMTCStore(_storeName);

  /// Membaca statistik cache.
  static Future<CacheStats> getStats() async {
    if (!_initialized) {
      await init();
    }

    if (!_initialized) {
      return CacheStats.empty(limitMB: _sizeLimitMB);
    }

    try {
      final all = await store.stats.all;

      // Statistik FMTC menggunakan KiB.
      final usedBytes = (all.size * 1024).round();
      final limitBytes = _sizeLimitMB * 1024 * 1024;

      final percentage = limitBytes > 0
          ? (usedBytes / limitBytes * 100)
              .clamp(0.0, 100.0)
              .toDouble()
          : 0.0;

      return CacheStats(
        usedBytes: usedBytes,
        limitBytes: limitBytes,
        percentage: percentage,
        tileCount: all.length,
        hits: all.hits,
        misses: all.misses,
        sizeLimitMB: _sizeLimitMB,
      );
    } catch (error) {
      debugPrint('[CACHE] Gagal membaca statistik: $error');
      return CacheStats.empty(limitMB: _sizeLimitMB);
    }
  }

  /// Mengubah batas perkiraan cache.
  ///
  /// Ini bukan jaminan ukuran database persis dalam MB.
  static Future<bool> setSizeLimit(int mb) async {
    if (mb < 1 || mb > 1000000) {
      debugPrint('[CACHE] Limit tidak valid: $mb MB');
      return false;
    }

    _sizeLimitMB = mb;
    _sizeLimitController.add(mb);

    debugPrint(
      '[CACHE] Limit diubah menjadi $mb MB '
      '(perkiraan $_maxTileCount tile).',
    );

    await enforceSizeLimit();
    return true;
  }

  /// Pembersihan best-effort saat statistik melewati limit.
  ///
  /// FMTC 9.0.1 menyediakan penghapusan berdasarkan umur
  /// melalui API publik ini. Penghapusan tersebut tidak
  /// menjamin ukuran cache langsung turun di bawah limit.
  static Future<void> enforceSizeLimit() async {
    if (!_initialized) return;

    try {
      final stats = await getStats();

      if (stats.usedBytes <= stats.limitBytes) return;

      debugPrint(
        '[CACHE] Ukuran melewati perkiraan limit; '
        'mencoba menghapus tile berumur lebih dari 30 hari.',
      );

      await store.manage.removeTilesOlderThan(
        expiry: DateTime.now().subtract(const Duration(days: 30)),
      );

      final updatedStats = await getStats();

      debugPrint(
        '[CACHE] Setelah pembersihan: ${updatedStats.usedLabel}.',
      );
    } catch (error) {
      debugPrint('[CACHE] Pembersihan gagal: $error');
    }
  }

  /// Menghapus semua tile secara eksplisit.
  /// Fungsi ini tidak dipanggil saat startup.
  static Future<bool> clearAll() async {
    if (!_initialized) {
      await init();
    }

    if (!_initialized) return false;

    try {
      await store.manage.reset();
      debugPrint('[CACHE] Seluruh cache berhasil dihapus.');
      return true;
    } catch (error) {
      debugPrint('[CACHE] Gagal menghapus cache: $error');
      return false;
    }
  }
}

class CacheStats {
  final int usedBytes;
  final int limitBytes;
  final double percentage;
  final int tileCount;
  final int hits;
  final int misses;
  final int sizeLimitMB;

  const CacheStats({
    required this.usedBytes,
    required this.limitBytes,
    required this.percentage,
    required this.tileCount,
    required this.hits,
    required this.misses,
    required this.sizeLimitMB,
  });

  factory CacheStats.empty({int limitMB = 300}) {
    return CacheStats(
      usedBytes: 0,
      limitBytes: limitMB * 1024 * 1024,
      percentage: 0,
      tileCount: 0,
      hits: 0,
      misses: 0,
      sizeLimitMB: limitMB,
    );
  }

  String get usedLabel {
    if (usedBytes < 1024) return '$usedBytes B';

    if (usedBytes < 1024 * 1024) {
      return '${(usedBytes / 1024).toStringAsFixed(0)} KB';
    }

    return '${(usedBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String get limitLabel {
    if (limitBytes < 1024 * 1024) {
      return '${(limitBytes / 1024).toStringAsFixed(0)} KB';
    }

    return '${(limitBytes / 1024 / 1024).toStringAsFixed(0)} MB';
  }

  int get usedMB => (usedBytes / 1024 / 1024).round();

  double get hitRate {
    final total = hits + misses;
    if (total == 0) return 0;

    return (hits / total * 100).clamp(0.0, 100.0).toDouble();
  }
}
