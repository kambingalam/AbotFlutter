# Laporan Analisis Keamanan (Pentest Read-Only) — AbotFlutter

**Repo:** `https://github.com/kambingalam/AbotFlutter.git`
**Stack:** Flutter/Dart 3.13.5+, Android (minSdk 24, targetSdk 36)
**Tipe:** Driver companion app untuk device ABOT (BLE + MQTT + GPS + offline maps)
**Scope:** Analisis statis read-only — tidak ada modifikasi kode.
**Tanggal:** 2026-10-29
**Auditor:** Hermes Agent (read-only static analysis)

---

## 1. Ringkasan Temuan (Executive Summary)

| Kategori | Temuan | Tingkat |
|---|---|---|
| **Transport Security** | OSRM API pakai **HTTP plaintext** (`http://router.project-osrm.org`) | **HIGH** |
| **Network Exposure** | MQTT ke broker publik `broker.emqx.io:1883` tanpa TLS, client ID predictable | **HIGH** |
| **Data Storage** | Semua preferensi (settings, history) di `shared_preferences` **tanpa enkripsi** | **MEDIUM** |
| **Permissions** | Android manifest minta 17 permission (termasuk `BACKGROUND_LOCATION`, `RECORD_AUDIO`, `BLUETOOTH_CONNECT`) — perlu justifikasi minimal | **MEDIUM** |
| **Input Validation** | Parsing JSON OSRM/Nominatim/Photon **tanpa schema validation** ketat | **MEDIUM** |
| **Secrets Management** | **Tidak ada hardcoded secret/token/api key** di codebase | **GOOD** |
| **Code Quality** | Error handling ada, logging debugPrint (bocor di release), tidak ada certificate pinning | **LOW–MEDIUM** |

---

## 2. Detail Temuan per Kategori

### 2.1 Transport Security — HIGH

**File:** `lib/config/app_config.dart:13-14`
```dart
static const String osrmBaseUrl = "http://router.project-osrm.org/route/v1/driving";
```

- **Masalah:** OSRM endpoint pakai **HTTP**, bukan HTTPS. Seluruh request routing (koordinat asal/tujuan, geometri rute) dikirim plaintext.
- **Dampak:** Man-in-the-middle (MITM) bisa:
  - Intercept lokasi real-time driver
  - Inject rute palsu (routing attack)
  - Profiling pola pergerakan
- **Rekomendasi:** Ganti ke `https://router.project-osrm.org` (OSRM public instance mendukung HTTPS). Atau host OSRM sendiri di VPS dengan TLS.

**File:** `lib/services/search_service.dart:7-9`
```dart
static const String _photonUrl = 'https://photon.komoot.io/api';      // OK (HTTPS)
static const String _nominatimUrl = 'https://nominatim.openstreetmap.org/search'; // OK (HTTPS)
```
Search API sudah pakai HTTPS.

---

### 2.2 MQTT Security — HIGH

**File:** `lib/services/abot_mqtt_service.dart:9-15`
```dart
static const String host = 'broker.emqx.io';
static const int port = 1883;  // PLAINTEXT MQTT
static const String commandTopic = 'abot/wokwi/477375325542330369/v337/command';
static const String statusTopic = 'abot/wokwi/477375325542330369/v337/status';
```

| Issue | Detail |
|---|---|
| **Port 1883 (plaintext)** | Tidak ada TLS (port 8883 untuk MQTTS tidak dipakai). Semua payload command/status terbaca sniffing WiFi/BLE. |
| **Broker publik** | `broker.emqx.io` shared broker — siapa saja bisa subscribe/publish ke topic yang sama kalau tau topic name. |
| **Topic predictable** | Format `abot/wokwi/<device_id>/v337/...` — device ID (`477375325542330369`) hardcoded, versi `v337` naik turun. Enumerasi trivial. |
| **Client ID predictable** | `'ABOT-FLUTTER-${DateTime.now().millisecondsSinceEpoch}'` — timestamp epoch, brute-force mudah. |
| **No authentication** | Tidak ada username/password, client cert, atau token. Siapa saja bisa connect & publish command ke device. |
| **No payload signing** | Command `route`, `trip_start`, `gps` dikirim tanpa HMAC/signature — replay/modification attack trivial. |

**Attack scenario realistis:**
1. Attacker subscribe `abot/wokwi/+/+/status` → dapet semua device ID aktif
2. Publish ke `abot/wokwi/<target>/+/command` payload `{"t":"route",...}` dengan koordinat palsu → device ABOT teresak ke lokasi attacker
3. Atau DoS: flood `command` topic → device hang/baterai habis

**Rekomendasi (prioritas):**
1. **Wajib:** Migrasi ke MQTTS (port 8883) + CA cert pinning di Flutter (`mqtt_client` support `SecurityContext`)
2. **Wajib:** Broker dedicated (bukan publik) + ACL per client ID / username-password
3. **Wajib:** Topic pakai random UUID per device, bukan device ID sequential
4. **Sebaiknya:** Payload signing (HMAC-SHA256) dengan shared secret di device + app
5. **Sebaiknya:** Client ID pakai cryptographically random, bukan timestamp

---

### 2.3 Data Storage — MEDIUM

**Files:** `lib/services/settings_service.dart`, `lib/services/history_service.dart`

| Data | Storage | Enkripsi | Risiko |
|---|---|---|---|
| Settings (TTS, theme, GPS config, background mode) | `shared_preferences` (XML/SharedPreferences Android) | Tidak | Root/backup bisa baca/modif preferensi |
| Search history (lokasi user, 20 item) | `shared_preferences` (JSON string) | Tidak | Profiling lokasi user, history sensitif |
| Trip data (runtime only) | Memory (StreamController) | N/A | OK — tidak persist |

**Android specifics:** `shared_preferences` di Android = `SharedPreferences` (XML di `/data/data/com.example.abot_drivers/shared_prefs/`). Akses butuh root atau `adb backup` (kalau `android:allowBackup="true"` — default `true`).

**Rekomendasi:**
- `flutter_secure_storage` untuk data sensitif (history lokasi, preferensi kritis)
- Atau encrypt JSON sebelum simpan ke `shared_preferences` (AES-GCM, key dari Android Keystore / iOS Keychain)
- Set `android:allowBackup="false"` di `<application>` manifest (sudah default Flutter baru, tapi cek)

---

### 2.4 Android Permissions — MEDIUM

**File:** `android/app/src/main/AndroidManifest.xml` — 17 `<uses-permission>`

| Permission | Justifikasi di Kode | Catatan |
|---|---|---|
| `ACCESS_FINE_LOCATION` | GPS navigation | Wajib |
| `ACCESS_COARSE_LOCATION` | Fallback GPS | Wajib |
| `ACCESS_BACKGROUND_LOCATION` | Foreground service navigation | Wajib (tapi butuh rationale ke user) |
| `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT` + `BLUETOOTH_ADVERTISE` | BLE ke device ABOT | Wajib (Android 12+) |
| `RECORD_AUDIO` | `speech_to_text` (voice search) | **Over-privilege** — voice search optional, tapi permission mandatory |
| `FOREGROUND_SERVICE_LOCATION` + `CONNECTED_DEVICE` + `SPECIAL_USE` | Background navigation | Wajib (Android 14+) |
| `WAKE_LOCK` | `wakelock_plus` keep screen on | Wajib |
| `POST_NOTIFICATIONS` | Foreground service notif | Wajib (Android 13+) |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Background service survival | Wajib |

**Rekomendasi:**
- `RECORD_AUDIO` → pindah ke **runtime request** hanya saat user buka voice search (bukan di manifest mandatory), atau gunakan `flutter_permission_handler` request saat perlu
- Tambah `android:allowBackup="false"` di `<application>` (hindari backup data sensitif)
- Tambah `android:networkSecurityConfig="@xml/network_security_config"` untuk enforce HTTPS & cert pinning

---

### 2.5 Input Validation & Parsing — MEDIUM

**File:** `lib/services/osrm_service.dart:79-93`
```dart
data = jsonDecode(response.body) as Map<String, dynamic>;
final code = data['code'] as String?;
if (code == null || code != 'Ok') { ... }
final routesRaw = data['routes'];
if (routesRaw is! List || routesRaw.isEmpty) { ... }
```
- Parsing pakai `as` cast + null check — **OK tapi brittle**. Kalau OSRM ganti format response, crash atau silent fail.
- Tidak ada **schema validation** (mis. `json_schema` atau `freezed`/`built_value` dengan validation).

**File:** `lib/services/search_service.dart:48-53, 70-81`
```dart
final data = jsonDecode(resp.body) as Map<String, dynamic>;
final features = data['features'] as List? ?? [];
// ...
final data = jsonDecode(resp.body) as List;
final m = item as Map<String, dynamic>;
return Place(..., lat: double.parse(m['lat'] as String), ...);
```
- `double.parse` tanpa `try-catch` — kalau Nominatim balikin `null` atau format beda, **crash**.
- Tidak ada sanitasi `display_name` sebelum dipakai di UI (potensi XSS kalau dirender ke WebView — tapi ini native Flutter, risiko rendah).

**File:** `lib/models/abot_message.dart:9-13`
```dart
factory AbotMessage.fromJson(String raw) {
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final type = decoded['t'] as String? ?? 'unknown';
  return AbotMessage(type: type, data: decoded);
}
```
- **Full decoded map dimasukin ke `data`** — field tambahan dari attacker ikut tersimpan & diproses downstream. Harus **allowlist field** yang diketahui.

**Rekomendasi:**
- Pakai `json_serializable` + `@JsonSerializable(explicitToJson: true)` + validasi manual field wajib
- Atau `freezed` dengan `fromJson` yang strict
- Sanitasi semua input external (MQTT, HTTP, BLE) sebelum dipakai

---

### 2.6 BLE Security — MEDIUM

**File:** `lib/config/app_config.dart:5-8`
```dart
static const String abotDeviceName = "ABOT-01";
static const String abotServiceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"; // Nordic UART Service
static const String abotRxCharUuid = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
static const String abotTxCharUuid = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";
```

- **Nordic UART Service (NUS) UUID standar** — siapa saja dengan BLE scanner bisa connect & komunikasi kalau tidak ada pairing/bonding.
- **Device name fix** `"ABOT-01"` — enumeration trivial.
- **Tidak ada encryption/pairing** di kode Flutter (bergantung OS-level BLE bonding).
- **MockBleService** dipakai di production (`main.dart:48`) — **real BLE service tidak ada di codebase ini** (mungkin di branch lain atau firmware side only).

**Rekomendasi:**
- Enforce **LE Secure Connections** (Android 12+ `BLUETOOTH_CONNECT` + `android:permissionFlags="encrypted"`)
- Device name unik per unit (serial number), bukan fix
- Implement application-layer encryption pada payload BLE (AES-GCM shared secret)

---

### 2.7 Logging & Debug Output — LOW

**Polanya:** `debugPrint('[TAG] ...')` di seluruh service (MQTT, GPS, Trip, BLE, TTS, OSRM, Search, Background).

- `debugPrint` di **release build Flutter tetap output ke stdout/logcat** (tidak di-strip).
- Log mencatat: koordinat GPS real-time, payload MQTT command/status, rute OSRM, search query, TTS text.
- **Data sensitif bocor ke logcat** — app lain dengan `READ_LOGS` (pre-Android 4.1) atau `adb logcat` bisa baca.

**Rekomendasi:**
- Wrapper logger yang strip di `kReleaseMode` (pakai `kDebugMode` guard)
- Atau `flutter_logs` package dengan level config
- Jangan log koordinat mentah / payload command di release

---

### 2.8 Certificate Pinning / Network Security Config — MISSING

- Tidak ada `network_security_config.xml` di `android/app/src/main/res/xml/`
- HTTP client (`http` package) pakai default trust store — **vuln ke MITM dengan CA rogue / user-installed CA**
- OSRM HTTP (sudah bahaya) + tidak ada pinning = **total plaintext exposure**

**Rekomendasi:**
```xml
<!-- res/xml/network_security_config.xml -->
<network-security-config>
  <domain-config cleartextTrafficPermitted="false">
    <domain includeSubdomains="true">router.project-osrm.org</domain>
    <domain includeSubdomains="true">photon.komoot.io</domain>
    <domain includeSubdomains="true">nominatim.openstreetmap.org</domain>
    <pin-set expiration="2026-12-31">
      <pin algorithm="SHA-256">BASE64_SHA256_OF_LEAF_CERT</pin>
      <pin algorithm="SHA-256">BASE64_SHA256_OF_BACKUP_CERT</pin>
    </pin-set>
  </domain-config>
  <debug-overrides>
    <trust-anchors>
      <certificates src="user" />
    </trust-anchors>
  </debug-overrides>
</network-security-config>
```
Lalu di `AndroidManifest.xml`: `android:networkSecurityConfig="@xml/network_security_config"`

---

### 2.9 Dependency Security — LOW

**`pubspec.lock` scan:** 180+ transitive deps. Beberapa perhatian:

| Package | Version | Catatan |
|---|---|---|
| `http` | 1.6.0 | Current, OK |
| `mqtt_client` | 10.13.0 | Current, support TLS |
| `flutter_blue_plus` | 1.36.8 | Current |
| `geolocator` | 12.0.0 | Current |
| `shared_preferences` | 2.5.6 | Current |
| `flutter_foreground_task` | 8.13.0 | Current |
| `permission_handler` | 11.4.0 | Current |
| `sqlite3` | 2.9.4 | Transitive (objectbox) — native code, audit supply chain |
| `objectbox` | 2.5.1 | Transitive — native binary, verify provenance |

**Action:** Jalankan `flutter pub outdated` berkala. Setup `dependabot` / `renovate` untuk PR otomatis.

---

### 2.10 Build & Supply Chain — LOW

**`android/app/build.gradle.kts:26-27`**
```kotlin
release {
    signingConfig = signingConfigs.getByName("debug")
}
```
- **Release build ditandatangani debug key** — **TIDAK BOLEH** untuk production Play Store / distribusi.
- `debug` keystore default Flutter dikenal publik, bisa di-reverse & resign.

**Rekomendasi:** Buat `keystore.jks` sendiri, config `signingConfigs.release` di `build.gradle.kts` / `key.properties` (gitignored).

---

### 2.11 iOS Configuration — UNKNOWN

- Folder `ios/` **kosong / tidak ada di clone depth=1** (mungkin di `.gitignore` atau branch terpisah).
- Tidak bisa audit `Info.plist` (NSCameraUsageDescription, NSLocationUsageDescription, ITSAppUsesNonExemptEncryption, dll).
- **Butuh cek manual** di repo penuh / branch lain.

---

### 2.12 Architecture / Code Quality Positif (Defense-in-Depth)

| Aspek | Status | Bukti |
|---|---|---|
| Error handling | Baik | `try-catch` + `debugPrint` + `rethrow` di MQTT, OSRM, GPS |
| Resource cleanup | Baik | `dispose()` cancel subscription, close StreamController di semua service |
| State management | Baik | `provider` + `ChangeNotifier`, lifecycle jelas |
| Concurrency safety | Baik | `unawaited` + `catchError` untuk fire-and-forget, cooldown reroute |
| Input sanitasi GPS | Ada | `_isValidCoord` filter NaN/Inf/range di OSRM |
| Trip distance limit | Ada | `straightDist > 200km` reject di `TripManager.startTrip` |
| No eval/dynamic code | Tidak ada | Tidak pakai `dart:mirrors`, `eval`, `Function.apply` dynamic |

---

## 3. Prioritas Perbaikan (Roadmap)

| Prioritas | Item | Estimasi Effort |
|---|---|---|
| **P0 (Critical)** | OSRM → HTTPS | 1 jam (ganti URL + test) |
| **P0 (Critical)** | MQTT → MQTTS (TLS) + broker dedicated + auth | 1-2 hari (infra + config Flutter) |
| **P0 (Critical)** | MQTT payload signing (HMAC) | 4-6 jam (app + firmware ESP32) |
| **P1 (High)** | `flutter_secure_storage` untuk history + settings sensitif | 2-3 jam |
| **P1 (High)** | `network_security_config.xml` + cert pinning OSRM/Photon/Nominatim | 2-3 jam |
| **P1 (High)** | `RECORD_AUDIO` → runtime request only | 1 jam |
| **P1 (High)** | Release signing config (keystore) | 30 menit |
| **P2 (Medium)** | Schema validation JSON (freezed/json_serializable strict) | 4-6 jam |
| **P2 (Medium)** | BLE encryption layer (application-level) | 1-2 hari (butuh firmware sync) |
| **P2 (Medium)** | Logger guard `kReleaseMode` | 1 jam |
| **P3 (Low)** | Dependency scanning CI (OSSF Scorecard / `flutter pub outdated` bot) | 2 jam setup |
| **P3 (Low)** | iOS `Info.plist` audit (ketika folder tersedia) | - |

---

## 4. Bukti Pendukung (Evidence) — File & Baris Kunci

| Temuan | File | Baris |
|---|---|---|
| OSRM HTTP plaintext | `lib/config/app_config.dart` | 13-14 |
| MQTT plaintext + broker publik + topic predict | `lib/services/abot_mqtt_service.dart` | 9-15, 60, 81-83 |
| MQTT client ID predictable | `lib/services/abot_mqtt_service.dart` | 60 |
| No MQTT auth / TLS | `lib/services/abot_mqtt_service.dart` | 62-79 |
| SharedPreferences unencrypted | `lib/services/settings_service.dart` | 48, 76, 86, 96 |
| Search history unencrypted | `lib/services/history_service.dart` | 10, 25, 37 |
| JSON parsing tanpa validasi ketat | `lib/services/osrm_service.dart` | 79-98 |
| double.parse tanpa try-catch | `lib/services/search_service.dart` | 77-78 |
| AbotMessage allow-all fields | `lib/models/abot_message.dart` | 9-13 |
| BLE UUID standar NUS | `lib/config/app_config.dart` | 6-8 |
| Debug logging sensitif | `lib/services/*.dart` | banyak |
| Release signing = debug key | `android/app/build.gradle.kts` | 26-27 |
| Permissions lengkap | `android/app/src/main/AndroidManifest.xml` | 5-33 |

---

## 5. Catatan Metodologi

- Analisis **statis read-only** pada clone `depth=1` (commit `HEAD` public).
- Tidak ada dynamic analysis (runtime, network capture, binary reversing APK).
- iOS tidak dievaluasi (folder `ios/` tidak ada di clone).
- Firmware ESP32 / device ABOT **di luar scope** (hanya lihat sisi Flutter).
- Temuan berbasis kode sumber saja — false positive mungkin ada (mis. BLE encryption di OS layer), tapi **defense-in-depth butuh layer aplikasi**.

---

## 6. Next Steps (Untukmu)

1. **Quick wins (hari ini):** Ganti OSRM ke HTTPS, bikin keystore release, tarik `RECORD_AUDIO` ke runtime request.
2. **Minggu ini:** Setup MQTTS broker (EMQX self-host / CloudMQTT / HiveMQ) + TLS cert + Flutter `SecurityContext` config.
3. **Sprint depan:** HMAC signing payload MQTT + BLE (butuh coord dgn firmware team), `flutter_secure_storage`, network security config.
4. **CI/CD:** Tambah `flutter analyze --fatal-infos`, `dart run dcms` / `melos`, dependabot.