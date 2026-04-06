import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';

LocationData _locationAt({
  required double latitude,
  double longitude = 120.9842,
  required double accuracyMeters,
  required DateTime timestamp,
}) {
  return LocationData(
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: accuracyMeters,
    timestamp: timestamp.toUtc(),
  );
}

double _metersToLatitudeDelta(double meters) => meters / 111111.0;

void main() {
  test('repeated stationary noise does not create cumulative walk-away', () {
    final service = LocationService();
    final baseTime = DateTime.utc(2026, 4, 6, 0, 0, 0);

    final fixes = <LocationData>[
      _locationAt(
        latitude: 14.5995,
        accuracyMeters: 8,
        timestamp: baseTime,
      ),
      for (var index = 1; index <= 20; index++)
        _locationAt(
          latitude: 14.5995 + _metersToLatitudeDelta(index.isEven ? 7 : -7),
          accuracyMeters: 8,
          timestamp: baseTime.add(Duration(seconds: index)),
        ),
    ];

    LocationData? output;
    for (final fix in fixes) {
      output = service.acceptPositionForTest(fix);
    }

    expect(output, isNotNull);
    final walkedMeters = (output!.latitude - 14.5995).abs() * 111111.0;
    expect(walkedMeters, lessThan(3));
  });

  test('output remains bounded near the stationary cluster center', () {
    final service = LocationService();
    final baseTime = DateTime.utc(2026, 4, 6, 1, 0, 0);

    final fixes = <LocationData>[
      _locationAt(
        latitude: 14.5995,
        accuracyMeters: 12,
        timestamp: baseTime,
      ),
      for (var index = 1; index <= 10; index++)
        _locationAt(
          latitude: 14.5995 + _metersToLatitudeDelta(5 + (index % 3).toDouble()),
          accuracyMeters: 10,
          timestamp: baseTime.add(Duration(seconds: index)),
        ),
    ];

    LocationData? output;
    for (final fix in fixes) {
      output = service.acceptPositionForTest(fix);
    }

    expect(output, isNotNull);
    final driftMeters = (output!.latitude - 14.5995).abs() * 111111.0;
    expect(driftMeters, lessThan(8));
  });

  test('a more accurate stationary fix can re-anchor the output', () {
    final service = LocationService();
    final baseTime = DateTime.utc(2026, 4, 6, 2, 0, 0);

    service.acceptPositionForTest(
      _locationAt(
        latitude: 14.5995 + _metersToLatitudeDelta(4),
        accuracyMeters: 18,
        timestamp: baseTime,
      ),
    );

    final output = service.acceptPositionForTest(
      _locationAt(
        latitude: 14.5995,
        accuracyMeters: 5,
        timestamp: baseTime.add(const Duration(seconds: 1)),
      ),
    );

    expect(output, isNotNull);
    expect(output!.latitude, closeTo(14.5995, 0.0000001));
  });

  test('real movement beyond the stationary band advances the output', () {
    final service = LocationService();
    final baseTime = DateTime.utc(2026, 4, 6, 3, 0, 0);

    service.acceptPositionForTest(
      _locationAt(
        latitude: 14.5995,
        accuracyMeters: 8,
        timestamp: baseTime,
      ),
    );

    final output = service.acceptPositionForTest(
      _locationAt(
        latitude: 14.5995 + _metersToLatitudeDelta(20),
        accuracyMeters: 8,
        timestamp: baseTime.add(const Duration(seconds: 2)),
      ),
    );

    expect(output, isNotNull);
    final movementMeters = (output!.latitude - 14.5995) * 111111.0;
    expect(movementMeters, greaterThan(15));
  });

  test('large jump rejection still works with raw and output split', () {
    final service = LocationService();
    final baseTime = DateTime.utc(2026, 4, 6, 4, 0, 0);

    final first = service.acceptPositionForTest(
      _locationAt(
        latitude: 14.5995,
        accuracyMeters: 8,
        timestamp: baseTime,
      ),
    );
    final jumped = service.acceptPositionForTest(
      _locationAt(
        latitude: 14.5995 + _metersToLatitudeDelta(300),
        accuracyMeters: 8,
        timestamp: baseTime.add(const Duration(seconds: 1)),
      ),
    );

    expect(first, isNotNull);
    expect(jumped, isNotNull);
    expect(jumped!.latitude, closeTo(first!.latitude, 0.0000001));
  });

  test('poor last-known fallback still returns the prior output', () {
    final service = LocationService();
    final baseTime = DateTime.utc(2026, 4, 6, 5, 0, 0);

    final first = service.acceptPositionForTest(
      _locationAt(
        latitude: 14.5995,
        accuracyMeters: 8,
        timestamp: baseTime,
      ),
    );
    final fallback = service.acceptPositionForTest(
      _locationAt(
        latitude: 14.5995 + _metersToLatitudeDelta(80),
        accuracyMeters: 100,
        timestamp: baseTime.subtract(const Duration(minutes: 5)),
      ),
      fromLastKnown: true,
    );

    expect(fallback, isNotNull);
    expect(fallback!.latitude, closeTo(first!.latitude, 0.0000001));
  });
}
