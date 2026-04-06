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
  Future<LocationData?> getCurrentPosition() async => currentPosition;

  @override
  Stream<LocationData> watchPosition() => _controller.stream;

  Future<void> emit(LocationData location) async {
    currentPosition = location;
    _controller.add(location);
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

void main() {
  test('stores the first valid point immediately', () async {
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

    expect(controller.state.permissionResolved, isTrue);
    expect(controller.state.latestLocation, isNotNull);
    expect(controller.state.persistedTrailPoints, hasLength(1));
    expect(controller.state.lastAcceptedTrailPoint, isNotNull);
  });

  test('does not append trail points for sub-threshold movement', () async {
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
    await fakeLocationService.emit(
      _locationAt(
        latitude: 14.5995 + _metersToLatitudeDelta(5),
        accuracyMeters: 8,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 18));

    expect(controller.state.persistedTrailPoints, hasLength(1));
    expect(
      controller.state.lastRejectionReason,
      contains('movement stayed below the threshold'),
    );
    expect(controller.state.permissionResolved, isTrue);
  });

  test('appends a new trail point for meaningful movement', () async {
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
    await fakeLocationService.emit(
      _locationAt(
        latitude: 14.5995 + _metersToLatitudeDelta(18),
        accuracyMeters: 8,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 18));

    expect(controller.state.permissionResolved, isTrue);
    expect(controller.state.persistedTrailPoints, hasLength(2));
    expect(controller.state.lastRejectionReason, isNull);
  });

  test(
    'updates the live marker without persisting poor-accuracy samples',
    () async {
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
      expect(controller.state.persistedTrailPoints, hasLength(1));
      expect(
        controller.state.lastRejectionReason,
        contains('accuracy exceeded 30m'),
      );
      expect(controller.state.permissionResolved, isTrue);
    },
  );

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
    for (var index = 1; index <= 245; index++) {
      await fakeLocationService.emit(
        _locationAt(
          latitude: 14.5995 + _metersToLatitudeDelta(index * 14),
          accuracyMeters: 8,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    expect(controller.state.persistedTrailPoints, hasLength(240));
    expect(controller.state.permissionResolved, isTrue);
    expect(
      controller.state.persistedTrailPoints.first.latitude,
      closeTo(14.5995 + _metersToLatitudeDelta(6 * 14), 0.00001),
    );
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
    expect(
      controller.state.lastRejectionReason,
      'Location permission denied.',
    );
  });
}
