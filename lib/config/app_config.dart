class AppConfig {
  // ============================================================
  // BLE
  // ============================================================
  static const String abotDeviceName = "ABOT-01";
  static const String abotServiceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  static const String abotRxCharUuid = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
  static const String abotTxCharUuid = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

  // ============================================================
  // OSRM
  // ============================================================
  static const String osrmBaseUrl =
      "http://router.project-osrm.org/route/v1/driving";

  // ============================================================
  // GPS
  // ============================================================
  static const Duration gpsInterval = Duration(seconds: 1);
  static const double gpsDistanceFilterMeters = 2.0;

  // ============================================================
  // LINK PROTOCOL
  // ============================================================
  static const Duration linkTimeout = Duration(seconds: 30);

  // ============================================================
  // DEFAULT LOCATION (Medan)
  // ============================================================
  static const double defaultLat = 3.5915;
  static const double defaultLon = 98.6777;

  // ============================================================
  // PRESET TUJUAN (shortcut)
  // ============================================================
  static const List<Map<String, dynamic>> presetDestinations = [
    {"name": "Merdeka Walk", "lat": 3.5915, "lon": 98.6777},
    {"name": "Istana Maimun", "lat": 3.5753, "lon": 98.6839},
    {"name": "Sun Plaza", "lat": 3.5768, "lon": 98.6594},
    {"name": "Kualanamu Airport", "lat": 3.6422, "lon": 98.8853},
    {"name": "Ringroad City Walk", "lat": 3.5576, "lon": 98.6457},
  ];
}
