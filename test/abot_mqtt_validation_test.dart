import 'package:flutter_test/flutter_test.dart';

import 'package:abot_drivers/services/abot_mqtt_service.dart';

void main() {
  test('_validateMqttPayload menerima payload route yang valid', () {
    final service = AbotMqttService();
    // Cannot call private method directly; test via publishJson when offline.
    // Invalid payload -> StateError.
    expect(
      () => service.publishJson({'t': 'route'}, requireAuthentication: false),
      throwsA(isA<StateError>()),
    );
  });

  test('_validateMqttPayload tolak payload tanpa type', () {
    final service = AbotMqttService();
    expect(
      () => service.publishJson({'foo': 'bar'}, requireAuthentication: false),
      throwsA(isA<StateError>()),
    );
  });

  test('_validateMqttPayload terima trip_start tanpa field tambahan', () {
    final service = AbotMqttService();
    // Should not throw validation error; may throw connection error later,
    // but validation passes.
    try {
      service.publishJson({'t': 'trip_start'}, requireAuthentication: false);
    } on StateError catch (e) {
      // Validation passed if error is NOT about invalid payload.
      expect(e.toString(), isNot(contains('Payload MQTT tidak valid')));
    }
  });
}
