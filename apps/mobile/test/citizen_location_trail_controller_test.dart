import 'dart:async';

import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/state/citizen_location_trail_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLocationService extends LocationService {
  _FakeLocationService({
    required this.permissionGranted,
    required this.gpsEnabled,
    this.currentPosition,
  });

  bool permissionGranted;
  bool gpsEnabled;
  LocationData? currentPosition;
  final StreamController<LocationData> _controller =
      StreamController<LocationData>.broadcast();

  @override
  Future<bool> ensurePermission() async => permissionGranted;

  @override
  Future<bool> isGpsAvailable() async => gpsEnabled;

  @override
  Future<LocationData?> getCurrentPosition() async {
    final position = currentPosition;
    if (position == null) {
      return null;
    }
    return acceptPositionForTest(position);
  }

  @override
  Stream<LocationData> watchPosition() => _controller.stream;

  Future<void> emit(LocationData location) async {
    currentPosition = location;
    final accepted = acceptPositionForTest(location);
    if (accepted != null) {
      _controller.add(accepted);
    }
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> dispose() => _controller.close();
}

LocationData _locationAt({
  required double latitude,
  double longitude = 120.9842,
  required double accuracyMeters,
}) {
  return LocationData(
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: accuracyMeters,
    timestamp: DateTime.now().toUtc(),
  );
}

double _metersToLatitudeDelta(double meters) => meters / 111111.0;

Future<void> _emitStableCluster(
  _FakeLocationService service, {
  required double baseLatitude,
  required List<double> offsetsMeters,
  double accuracyMeters = 8,
}) async {
  for (final offsetMeters in offsetsMeters) {
    await service.emit(
      _locationAt(
        latitude: baseLatitude + _metersToLatitudeDelta(offsetMeters),
        accuracyMeters: accuracyMeters,
      ),
    );
  }
}

void main() {
  test('initializes the trusted anchor and first trail point from stable fixes', () async {
    final fakeLocationService = _FakeLocationService(
      permissionGranted: true,
      gpsEnabled: true,
      currentPosition: _locationAt(latitude: 14.5995, accuracyMeters: 8),
    );
    final controller = CitizenLocationTrailController(
      locationService: fakeLocationService,
      sampleInterval: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);
    addTearDown(fakeLocationService.dispose);

    await controller.startTracking();
    await _emitStableCluster(
      fakeLocationService,
      baseLatitude: 14.5995,
      offsetsMeters: const [0, 2, -1, 1],
    );
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(controller.state.permissionResolved, isTrue);
    expect(controller.state.motionMode, LocationMotionMode.stationary);
    expect(controller.state.displayLocation, isNotNull);
    expect(controller.state.persistedTrailPoints, hasLength(1));
    expect(controller.state.lastAcceptedTrailPoint, isNotNull);
  });

  test('low-confidence updates keep the pin frozen and skip trail persistence', () async {
    final fakeLocationService = _FakeLocationService(
      permissionGranted: true,
      gpsEnabled: true,
      currentPosition: _locationAt(latitude: 14.5995, accuracyMeters: 8),
    );
    final controller = CitizenLocationTrailController(
      locationService: fakeLocationService,
      sampleInterval: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);
    addTearDown(fakeLocationService.dispose);

    await controller.startTracking();
    await _emitStableCluster(
      fakeLocationService,
      baseLatitude: 14.5995,
      offsetsMeters: const [0, 2, -1, 1],
    );
    await Future<void>.delayed(const Duration(milliseconds: 25));
    final trustedLatitude = controller.state.displayLocation!.latitude;

    await fakeLocationService.emit(
      _locationAt(
        latitude: 14.5995 + _metersToLatitudeDelta(18),
        accuracyMeters: 24,
      ),
    );
    await fakeLocationService.emit(
      _locationAt(
        latitude: 14.5995 - _metersToLatitudeDelta(16),
        accuracyMeters: 23,
      ),
    );
    await fakeLocationService.emit(
      _locationAt(
        latitude: 14.5995 + _metersToLatitudeDelta(14),
        accuracyMeters: 22,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(controller.state.motionMode, LocationMotionMode.degraded);
    expect(controller.state.displayLocation?.latitude, trustedLatitude);
    expect(controller.state.persistedTrailPoints, hasLength(1));
    expect(
      controller.state.lastRejectionReason,
      contains('GPS confidence is too low'),
    );
  });

  test('stable movement after repeated windows advances the anchor and trail', () async {
    final fakeLocationService = _FakeLocationService(
      permissionGranted: true,
      gpsEnabled: true,
      currentPosition: _locationAt(latitude: 14.5995, accuracyMeters: 8),
    );
    final controller = CitizenLocationTrailController(
      locationService: fakeLocationService,
      sampleInterval: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);
    addTearDown(fakeLocationService.dispose);

    await controller.startTracking();
    await _emitStableCluster(
      fakeLocationService,
      baseLatitude: 14.5995,
      offsetsMeters: const [0, 2, -1, 1],
    );
    await Future<void>.delayed(const Duration(milliseconds: 25));

    await _emitStableCluster(
      fakeLocationService,
      baseLatitude: 14.5995 + _metersToLatitudeDelta(14),
      offsetsMeters: const [0, 1, -1],
    );
    await _emitStableCluster(
      fakeLocationService,
      baseLatitude: 14.5995 + _metersToLatitudeDelta(15),
      offsetsMeters: const [0, 1, -1],
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(controller.state.displayLocation, isNotNull);
    expect(controller.state.displayLocation!.latitude, greaterThan(14.5995));
    expect(controller.state.persistedTrailPoints.length, greaterThanOrEqualTo(2));
  });

  test('updates latest raw location without moving the trusted pin for poor-accuracy samples', () async {
    final fakeLocationService = _FakeLocationService(
      permissionGranted: true,
      gpsEnabled: true,
      currentPosition: _locationAt(latitude: 14.5995, accuracyMeters: 8),
    );
    final controller = CitizenLocationTrailController(
      locationService: fakeLocationService,
      sampleInterval: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);
    addTearDown(fakeLocationService.dispose);

    await controller.startTracking();
    await _emitStableCluster(
      fakeLocationService,
      baseLatitude: 14.5995,
      offsetsMeters: const [0, 2, -1, 1],
    );
    await Future<void>.delayed(const Duration(milliseconds: 25));
    final trustedLatitude = controller.state.displayLocation!.latitude;

    final poorAccuracyLocation = _locationAt(
      latitude: 14.5995 + _metersToLatitudeDelta(40),
      accuracyMeters: 45,
    );
    await fakeLocationService.emit(poorAccuracyLocation);
    await Future<void>.delayed(const Duration(milliseconds: 18));

    expect(
      controller.state.latestLocation?.latitude,
      poorAccuracyLocation.latitude,
    );
    expect(controller.state.displayLocation?.latitude, trustedLatitude);
    expect(controller.state.persistedTrailPoints, hasLength(1));
  });

  test('trims the persisted trail to the latest 240 points', () async {
    final fakeLocationService = _FakeLocationService(
      permissionGranted: true,
      gpsEnabled: true,
      currentPosition: _locationAt(latitude: 14.5995, accuracyMeters: 8),
    );
    final controller = CitizenLocationTrailController(
      locationService: fakeLocationService,
      sampleInterval: const Duration(milliseconds: 1),
    );
    addTearDown(controller.dispose);
    addTearDown(fakeLocationService.dispose);

    await controller.startTracking();
    await _emitStableCluster(
      fakeLocationService,
      baseLatitude: 14.5995,
      offsetsMeters: const [0, 2, -1, 1],
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    for (var index = 1; index <= 260; index++) {
      await _emitStableCluster(
        fakeLocationService,
        baseLatitude: 14.5995 + _metersToLatitudeDelta(index * 16),
        offsetsMeters: const [0, 1, -1],
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    expect(controller.state.persistedTrailPoints, hasLength(240));
    expect(controller.state.permissionResolved, isTrue);
  });

  test('marks permission as resolved when access is denied', () async {
    final fakeLocationService = _FakeLocationService(
      permissionGranted: false,
      gpsEnabled: true,
    );
    final controller = CitizenLocationTrailController(
      locationService: fakeLocationService,
      sampleInterval: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);
    addTearDown(fakeLocationService.dispose);

    await controller.startTracking();

    expect(controller.state.permissionResolved, isTrue);
    expect(controller.state.permissionGranted, isFalse);
    expect(controller.state.latestLocation, isNull);
    expect(controller.state.displayLocation, isNull);
    expect(
      controller.state.lastRejectionReason,
      'Location permission denied.',
    );
  });
}
