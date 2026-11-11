import 'package:flutter_test/flutter_test.dart';

import 'package:abot_drivers/models/abot_message.dart';
import 'package:abot_drivers/models/nav_step.dart';
import 'package:abot_drivers/models/trip.dart';

Trip buildTrip(int points, {int stepEvery = 25}) => Trip(
      destinationName: 'Tujuan',
      destinationLat: 3.6,
      destinationLon: 98.7,
      totalDistance: 12400.6,
      totalDuration: 1832.4,
      coords: [
        for (var i = 0; i < points; i++)
          [98.6 + i * 0.0003333, 3.5 + i * 0.0001111],
      ],
      steps: [
        for (var i = 0; i < points; i += stepEvery)
          NavStep(
            instruction: 'BELOK KIRI',
            road: 'Jl. Sudirman Raya Yang Namanya Panjang Sekali',
            distance: 123.456,
            routeIndex: i,
            routeDistance: 987.654,
            important: true,
          ),
      ],
    );

void main() {
  test('rute panjang dipangkas ke 120 titik, ujung tetap', () {
    final trip = buildTrip(900);
    final device = trip.forDevice();

    expect(device.coords.length, 120);
    expect(device.coords.first[0], trip.coords.first[0]);
    expect(device.coords.last[0], closeTo(trip.coords.last[0], 0.00001));
  });

  test('idx langkah tetap valid dan menaik setelah dipangkas', () {
    final device = buildTrip(900).forDevice();
    var previous = -1;

    for (final step in device.steps) {
      expect(step.routeIndex, inInclusiveRange(0, device.coords.length - 1));
      expect(step.routeIndex, greaterThanOrEqualTo(previous));
      previous = step.routeIndex;
    }
  });

  test('rute pendek tidak dipangkas', () {
    expect(buildTrip(5).forDevice().coords.length, 5);
  });

  test('toJson memotong nama jalan ke ASCII 20 karakter', () {
    final json = buildTrip(5).steps.first.toJson();

    expect((json['road'] as String).length, lessThanOrEqualTo(20));
    expect(json['dist'], 123.5);
  });

  test('payload rute 120 titik muat di bawah 8 KB', () {
    final device = buildTrip(900).forDevice();

    final message = AbotMessage.route(
      distance: device.totalDistance.roundToDouble(),
      duration: device.totalDuration.roundToDouble(),
      coords: device.coords,
      steps: device.steps.map((step) => step.toJson()).toList(),
    );

    expect(message.toJsonString().length, lessThan(8000));
  });
}
