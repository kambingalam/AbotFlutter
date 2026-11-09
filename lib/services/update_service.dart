import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Cek apakah ada versi baru di GitHub Releases.
/// Tidak memaksa update — hanya memberitahu dan membuka halaman rilis.
class UpdateService {
  static const _repo = 'kambingalam/AbotFlutter';
  static const _api =
      'https://api.github.com/repos/$_repo/releases/latest';

  /// Hasil pengecekan update.
  final String? latestTag;
  final String? htmlUrl;
  final bool updateAvailable;

  const UpdateService._({
    this.latestTag,
    this.htmlUrl,
    required this.updateAvailable,
  });

  /// Cek versi terbaru di GitHub dan bandingkan dengan versi app saat ini.
  /// Return null kalau gagal (jaringan, API, parsing) — dianggap tidak ada update.
  static Future<UpdateService> check() async {
    final info = await PackageInfo.fromPlatform();
    final current = _parseVersion(info.version);

    try {
      final response = await http.get(
        Uri.parse(_api),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return const UpdateService._(updateAvailable: false);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = data['tag_name'] as String?;
      if (tag == null) {
        return const UpdateService._(updateAvailable: false);
      }

      final latest = _parseVersion(tag);
      final available = _isNewer(latest, current);

      return UpdateService._(
        latestTag: tag,
        htmlUrl: data['html_url'] as String?,
        updateAvailable: available,
      );
    } catch (_) {
      return const UpdateService._(updateAvailable: false);
    }
  }

  /// Parsi '0.1.0+1' atau 'v1.0.1' → [major, minor, patch].
  static List<int> _parseVersion(String v) {
    final clean = v.replaceFirst(RegExp(r'^v'), '');
    final parts = clean.split(RegExp(r'[.\+]'));
    int at(int i) {
      if (i >= parts.length) return 0;
      return int.tryParse(parts[i]) ?? 0;
    }
    return [at(0), at(1), at(2)];
  }

  static bool _isNewer(List<int> a, List<int> b) {
    for (var i = 0; i < 3; i++) {
      if (a[i] > b[i]) return true;
      if (a[i] < b[i]) return false;
    }
    return false;
  }
}
