import 'dart:async';

import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/session_storage.dart';
import 'package:dispatch_mobile/core/state/citizen_location_trail_controller.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/mesh/presentation/mesh_people_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class _FakeSessionController extends SessionController {
  _FakeSessionController(SessionState state)
    : super(_NoopSessionStorage(state), AuthService()) {
    this.state = state;
  }
}

class _SeededCitizenLocationTrailController
    extends CitizenLocationTrailController {
  _SeededCitizenLocationTrailController({
    required super.locationService,
    required CitizenLocationTrailState initialState,
  }) {
    state = initialState;
  }

  @override
  Future<void> startTracking() async {}

  @override
  Future<void> stopTracking() async {}
}

class _NoopSessionStorage extends SessionStorage {
  _NoopSessionStorage(this._state);

  final SessionState _state;

  @override
  Future<void> clear() async {}

  @override
  Future<SessionState> load() async => _state;

  @override
  Future<void> save(SessionState state) async {}
}

LocationData _locationAt({
  required double latitude,
  double longitude = 120.9842,
  double accuracyMeters = 8,
}) {
  return LocationData(
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: accuracyMeters,
    timestamp: DateTime.now().toUtc(),
  );
}

double _metersToLatitudeDelta(double meters) => meters / 111111.0;

Future<void> _pumpMap(
  WidgetTester tester, {
  required _FakeLocationService locationService,
  required CitizenLocationTrailController trailController,
  bool initiallySelectSelfNode = false,
}) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await locationService.dispose();
  });

  final transport = MeshTransportService(
    locationService: locationService,
    automaticLocationBeaconing: false,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        locationServiceProvider.overrideWith((ref) => locationService),
        meshTransportProvider.overrideWith((ref) => transport),
        citizenLocationTrailControllerProvider.overrideWith(
          (ref) => trailController,
        ),
        sessionControllerProvider.overrideWith(
          (ref) => _FakeSessionController(
            const SessionState(
              role: AppRole.citizen,
              email: 'citizen@test.com',
              fullName: 'Citizen One',
            ),
          ),
        ),
      ],
      child: MaterialApp(
        home: MeshPeopleMapScreen(
          title: 'Mesh Feed Map',
          subtitle: 'Interactive map',
          allowResolveActions: false,
          allowCompassActions: true,
          enableSelfTracking: true,
          selfTrackingActive: true,
          initiallySelectSelfNode: initiallySelectSelfNode,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 40));
}

void main() {
  testWidgets('renders the citizen self marker from provider state', (
    tester,
  ) async {
    final fakeLocationService = _FakeLocationService(
      permissionGranted: true,
      gpsEnabled: true,
      currentPosition: _locationAt(latitude: 14.5995),
    );
    final liveLocation = _locationAt(latitude: 14.5995);
    final trailController = _SeededCitizenLocationTrailController(
      locationService: fakeLocationService,
      initialState: CitizenLocationTrailState(
        permissionResolved: true,
        permissionGranted: true,
        gpsEnabled: true,
        trackingActive: true,
        latestLocation: liveLocation,
        persistedTrailPoints: const [],
        lastAcceptedTrailPoint: null,
        lastSampledAt: liveLocation.timestamp,
        lastRejectionReason: null,
      ),
    );

    await _pumpMap(
      tester,
      locationService: fakeLocationService,
      trailController: trailController,
    );

    expect(find.textContaining('You'), findsOneWidget);
    expect(find.textContaining('Live tracking active'), findsOneWidget);
  });

  testWidgets('shows the self trail polyline after selecting You', (
    tester,
  ) async {
    final fakeLocationService = _FakeLocationService(
      permissionGranted: true,
      gpsEnabled: true,
      currentPosition: _locationAt(latitude: 14.5995),
    );
    final firstLocation = _locationAt(latitude: 14.5995);
    final secondLocation = _locationAt(
      latitude: 14.5995 + _metersToLatitudeDelta(18),
    );
    final trailController = _SeededCitizenLocationTrailController(
      locationService: fakeLocationService,
      initialState: CitizenLocationTrailState(
        permissionResolved: true,
        permissionGranted: true,
        gpsEnabled: true,
        trackingActive: true,
        latestLocation: secondLocation,
        persistedTrailPoints: [
          CitizenTrailPoint.fromLocation(firstLocation),
          CitizenTrailPoint.fromLocation(secondLocation),
        ],
        lastAcceptedTrailPoint: CitizenTrailPoint.fromLocation(secondLocation),
        lastSampledAt: secondLocation.timestamp,
        lastRejectionReason: null,
      ),
    );

    await _pumpMap(
      tester,
      locationService: fakeLocationService,
      trailController: trailController,
      initiallySelectSelfNode: true,
    );

    final polylineLayers = tester
        .widgetList<PolylineLayer>(find.byType(PolylineLayer))
        .toList();
    final hasSelfTrail = polylineLayers.any(
      (layer) => layer.polylines.any(
        (polyline) =>
            polyline.strokeWidth == 3.5 && polyline.points.length >= 2,
      ),
    );

    expect(hasSelfTrail, isTrue);
  });

  testWidgets('shows a permission denied state when GPS access is blocked', (
    tester,
  ) async {
    final fakeLocationService = _FakeLocationService(
      permissionGranted: false,
      gpsEnabled: false,
    );
    final trailController = _SeededCitizenLocationTrailController(
      locationService: fakeLocationService,
      initialState: const CitizenLocationTrailState(
        permissionResolved: true,
        permissionGranted: false,
        gpsEnabled: false,
        trackingActive: true,
        latestLocation: null,
        persistedTrailPoints: [],
        lastAcceptedTrailPoint: null,
        lastSampledAt: null,
        lastRejectionReason: 'Location permission denied.',
      ),
    );

    await _pumpMap(
      tester,
      locationService: fakeLocationService,
      trailController: trailController,
    );

    expect(find.text('Location permission denied'), findsOneWidget);
  });

  testWidgets(
    'shows a checking state while location permission is still resolving',
    (tester) async {
      final fakeLocationService = _FakeLocationService(
        permissionGranted: false,
        gpsEnabled: false,
      );
      final trailController = _SeededCitizenLocationTrailController(
        locationService: fakeLocationService,
        initialState: const CitizenLocationTrailState(
          permissionResolved: false,
          permissionGranted: false,
          gpsEnabled: false,
          trackingActive: true,
          latestLocation: null,
          persistedTrailPoints: [],
          lastAcceptedTrailPoint: null,
          lastSampledAt: null,
          lastRejectionReason: null,
        ),
      );

      await _pumpMap(
        tester,
        locationService: fakeLocationService,
        trailController: trailController,
      );

      expect(find.text('Checking location permission'), findsOneWidget);
      expect(find.text('Location permission denied'), findsNothing);
    },
  );

  testWidgets('shows a GPS off state when location services are disabled', (
    tester,
  ) async {
    final fakeLocationService = _FakeLocationService(
      permissionGranted: true,
      gpsEnabled: false,
    );
    final trailController = _SeededCitizenLocationTrailController(
      locationService: fakeLocationService,
      initialState: const CitizenLocationTrailState(
        permissionResolved: true,
        permissionGranted: true,
        gpsEnabled: false,
        trackingActive: true,
        latestLocation: null,
        persistedTrailPoints: [],
        lastAcceptedTrailPoint: null,
        lastSampledAt: null,
        lastRejectionReason: 'Location services are turned off.',
      ),
    );

    await _pumpMap(
      tester,
      locationService: fakeLocationService,
      trailController: trailController,
    );

    expect(find.text('Location services off'), findsOneWidget);
  });
}
