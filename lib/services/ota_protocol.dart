/// ABOT OTA Protocol v1 — konstanta pesan, kode error, dan model manifest.
/// Dokumentasi protokol OTA.
library;

/// Tipe pesan (field `t`).
class OtaMsg {
  OtaMsg._();

  // Aplikasi -> ABOT
  static const String start = 'ota_start';
  static const String cancel = 'ota_cancel';

  // ABOT -> aplikasi
  static const String accepted = 'ota_accepted';
  static const String progress = 'ota_progress';
  static const String done = 'ota_done';
  static const String error = 'ota_error';
  static const String result = 'ota_result';

  // Legacy: firmware V3.45 di Wokwi.
  static const String simulated = 'ota_simulated';
}

/// Tahap pada `ota_progress.stage`.
class OtaStage {
  OtaStage._();

  static const String wifi = 'wifi';
  static const String manifest = 'manifest';
  static const String download = 'download';
  static const String verify = 'verify';
  static const String install = 'install';
}

/// Kode error (`ota_error.code`) + pesan untuk pengguna.
enum OtaErrorCode {
  busy('busy', 'ABOT sedang sibuk. Coba lagi sebentar lagi.'),
  tripActive('trip_active', 'Tidak bisa update saat trip atau rute aktif.'),
  lowBattery('low_battery', 'Baterai ABOT terlalu rendah untuk update.'),
  noWifi('no_wifi', 'ABOT belum tersambung ke WiFi.'),
  wifiLost('wifi_lost', 'WiFi putus saat update.'),
  manifestFailed('manifest_failed', 'Info update tidak bisa diambil.'),
  manifestInvalid('manifest_invalid', 'Info update tidak valid.'),
  noUpdate('no_update', 'Tidak ada pembaruan untuk versi ini.'),
  noSpace('no_space', 'Firmware terlalu besar untuk perangkat.'),
  downloadFailed('download_failed', 'Unduhan firmware gagal.'),
  tlsFailed('tls_failed', 'Koneksi aman (HTTPS) gagal diverifikasi.'),
  badHash('bad_hash', 'File firmware rusak (checksum tidak cocok).'),
  badSignature('bad_signature', 'Tanda tangan firmware tidak valid.'),
  writeFailed('write_failed', 'Gagal menulis firmware ke ABOT.'),
  cancelled('cancelled', 'Update dibatalkan.'),
  unauthorized('unauthorized', 'ABOT belum terautentikasi.'),
  bootFailed(
    'boot_failed',
    'Firmware baru gagal berjalan, ABOT kembali ke versi sebelumnya.',
  ),
  appTimeout('app_timeout', 'ABOT berhenti merespons.'),
  linkLost('link_lost', 'Tidak bisa terhubung ke ABOT.'),
  unknown('unknown', 'Terjadi kesalahan yang tidak diketahui.');

  const OtaErrorCode(this.wire, this.message);

  /// Nilai di kabel (JSON).
  final String wire;

  /// Pesan default untuk pengguna (Bahasa Indonesia).
  final String message;

  static OtaErrorCode parse(String? wire) {
    for (final code in values) {
      if (code.wire == wire) return code;
    }
    return unknown;
  }
}

class OtaManifestException implements Exception {
  OtaManifestException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Manifest firmware (lihat bagian 4 spesifikasi).
class OtaManifest {
  const OtaManifest({
    required this.schema,
    required this.device,
    required this.version,
    required this.url,
    required this.size,
    required this.sha256,
    this.minVersion,
    this.minBattery = 30,
    this.released,
    this.notes = const <String>[],
  });

  final int schema;
  final String device;
  final String version;
  final String? minVersion;
  final String url;
  final int size;
  final String sha256;
  final int minBattery;
  final String? released;
  final List<String> notes;

  static final RegExp _versionPattern = RegExp(r'^\d+(\.\d+){0,2}$');
  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-fA-F]{64}$');

  factory OtaManifest.fromJson(Map<String, dynamic> json) {
    String requireString(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw OtaManifestException('Manifest: field "$key" tidak ada.');
      }
      return value;
    }

    if (json['schema'] != 1) {
      throw OtaManifestException('Manifest: schema tidak didukung.');
    }

    final version = requireString('version');
    if (!_versionPattern.hasMatch(version)) {
      throw OtaManifestException('Manifest: format versi salah ($version).');
    }

    final url = requireString('url');
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      throw OtaManifestException('Manifest: URL firmware harus HTTPS.');
    }

    final size = json['size'];
    if (size is! int || size <= 0) {
      throw OtaManifestException('Manifest: "size" tidak valid.');
    }

    final sha256 = requireString('sha256');
    if (!_sha256Pattern.hasMatch(sha256)) {
      throw OtaManifestException('Manifest: "sha256" tidak valid.');
    }

    final rawNotes = json['notes'];
    final minBattery = json['min_battery'];

    return OtaManifest(
      schema: 1,
      device: requireString('device'),
      version: version,
      minVersion: json['min_version']?.toString(),
      url: url,
      size: size,
      sha256: sha256,
      minBattery: minBattery is int ? minBattery.clamp(0, 100) : 30,
      released: json['released']?.toString(),
      notes: rawNotes is List
          ? rawNotes.map((e) => e.toString()).toList()
          : const <String>[],
    );
  }

  /// Manifest tiruan untuk uji di Wokwi (tidak ada unduhan nyata).
  factory OtaManifest.simulated({
    required String from,
    String device = 'abot-esp32s3',
  }) {
    return OtaManifest(
      schema: 1,
      device: device,
      version: bumpVersion(from),
      url: 'https://example.invalid/simulated.bin',
      size: 1,
      sha256: '0' * 64,
      notes: const <String>['Simulasi update (tanpa unduhan nyata)'],
    );
  }
}

/// Bandingkan dua versi. Negatif: a < b, 0: sama, positif: a > b.
int compareVersions(String a, String b) {
  List<int> parse(String v) => v
      .split('.')
      .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();

  final pa = parse(a);
  final pb = parse(b);
  final length = pa.length > pb.length ? pa.length : pb.length;

  for (var i = 0; i < length; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }

  return 0;
}

/// "3.45" -> "3.46"
String bumpVersion(String version) {
  final clean = version.replaceAll(RegExp(r'[^0-9.]'), '');
  final parts = clean.isEmpty ? <String>['0'] : clean.split('.');
  final last = int.tryParse(parts.last) ?? 0;
  parts[parts.length - 1] = '${last + 1}';
  return parts.join('.');
}