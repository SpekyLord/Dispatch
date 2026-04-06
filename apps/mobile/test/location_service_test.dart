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

    for (final fix in fixes) {
      service.acceptPositionForTest(fix);
    }

    final output = service.latestEstimatedLocation;
    expect(output, isNotNull);
    final walkedMeters = (output!.latitude - 14.5995).abs() * 111111.0;
    expect(walkedMeters, lessThan(3));
    expect(service.latestMotionMode, LocationMotionMode.stationary);
  });

  test('fewer than three usable fixes stays in acquiring mode', () {
    final service = LocationService();
    final baseTime = DateTime.utc(2026, 4, 6, 0, 30, 0);

    service.acceptPositionForTest(
      _locationAt(
        latitude: 14.5995,
        accuracyMeters: 10,
        timestamp: baseTime,
      ),
    );
    service.acceptPositionForTest(
      _locationAt(
        latitude: 14.5995 + _metersToLatitudeDelta(4),
        accuracyMeters: 12,
        timestamp: baseTime.add(const Duration(seconds: 1)),
      ),
    );

    expect(service.latestMotionMode, LocationMotionMode.acquiring);
    expect(service.latestEstimatedLocation, isNotNull);
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

    for (final fix in fixes) {
      service.acceptPositionForTest(fix);
    }

    final output = service.latestEstimatedLocation;
    expect(output, isNotNull);
    final driftMeters = (output!.latitude - 14.5995).abs() * 111111.0;
    expect(driftMeters, lessThan(8));
    expect(service.latestMotionMode, LocationMotionMode.stationary);
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

    service.acceptPositionForTest(
      _locationAt(
        latitude: 14.5995,
        accuracyMeters: 5,
        timestamp: baseTime.add(const Duration(seconds: 1)),
      ),
    );

    final output = service.latestEstimatedLocation;
    expect(output, isNotNull);
    expect(output!.latitude, closeTo(14.5995, 0.00001));
  });

  test('two consecutive stable shifted windows produce moving mode', () {
    final service = LocationService();
    final baseTime = DateTime.utc(2026, 4, 6, 3, 0, 0);

    final firstCluster = <double>[0, 2, -2];
    for (var index = 0; index < firstCluster.length; index++) {
      service.acceptPositionForTest(
        _locationAt(
          latitude: 14.5995 + _metersToLatitudeDelta(firstCluster[index]),
          accuracyMeters: 8,
          timestamp: baseTime.add(Duration(milliseconds: index * 500)),
        ),
      );
    }

    final secondCluster = <double>[10, 11, 9];
    for (var index = 0; index < secondCluster.length; index++) {
      service.acceptPositionForTest(
        _locationAt(
          latitude: 14.5995 + _metersToLatitudeDelta(secondCluster[index]),
          accuracyMeters: 8,
          timestamp: baseTime.add(Duration(seconds: 1, milliseconds: index * 500)),
        ),
      );
    }

    final thirdCluster = <double>[11, 10, 12];
    for (var index = 0; index < thirdCluster.length; index++) {
      service.acceptPositionForTest(
        _locationAt(
          latitude: 14.5995 + _metersToLatitudeDelta(thirdCluster[index]),
          accuracyMeters: 8,
          timestamp: baseTime.add(Duration(seconds: 2, milliseconds: index * 500)),
        ),
      );
    }

    final output = service.latestEstimatedLocation;
    expect(output, isNotNull);
    final movementMeters = (output!.latitude - 14.5995) * 111111.0;
    expect(movementMeters, greaterThan(8));
    expect(service.latestMotionMode, LocationMotionMode.moving);
  });

  test('wide or weak stationary fixes are treated as degraded confidence', () {
    final service = LocationService();
    final baseTime = DateTime.utc(2026, 4, 6, 3, 30, 0);

    final fixes = <LocationData>[
      _locationAt(
        latitude: 14.5995,
        accuracyMeters: 18,
        timestamp: baseTime,
      ),
      _locationAt(
        latitude: 14.5995 + _metersToLatitudeDelta(10),
        accuracyMeters: 17,
        timestamp: baseTime.add(const Duration(milliseconds: 500)),
      ),
      _locationAt(
        latitude: 14.5995 - _metersToLatitudeDelta(9),
        accuracyMeters: 19,
        timestamp: baseTime.add(const Duration(seconds: 1)),
      ),
    ];

    for (final fix in fixes) {
      service.acceptPositionForTest(fix);
    }

    expect(service.latestMotionMode, LocationMotionMode.degraded);
    expect(service.latestDisplayConfidenceMeters, greaterThanOrEqualTo(20));
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
