import 'dart:async';

import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/citizen_ble_chat_session_controller.dart';
import 'package:dispatch_mobile/core/services/session_storage.dart';
import 'package:dispatch_mobile/core/state/citizen_location_trail_controller.dart';
import 'package:dispatch_mobile/core/state/citizen_nearby_presence_controller.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/mesh/presentation/mesh_people_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLocationService extends LocationService {
  _FakeLocationService({this.currentPosition});

  LocationData? currentPosition;
  final StreamController<LocationData> _controller =
      StreamController<LocationData>.broadcast();

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<bool> isGpsAvailable() async => true;

  @override
  Future<LocationData?> getCurrentPosition() async => currentPosition;

  @override
  Stream<LocationData> watchPosition() => _controller.stream;

  Future<void> dispose() => _controller.close();
}

class _FakeRealtimeService extends RealtimeService {
  _FakeRealtimeService() : super();
}

class _FakeBleRoomAuthService extends AuthService {
  _FakeBleRoomAuthService({required this.roomsResponse});

  final Map<String, dynamic> roomsResponse;

  @override
  Future<Map<String, dynamic>> listCitizenBleChatSessions({
    int limit = 50,
  }) async {
    return const {'sessions': []};
  }

  @override
  Future<Map<String, dynamic>> listCitizenBleChatRooms({
    int limit = 50,
  }) async {
    return roomsResponse;
  }
}

class _FakeSessionController extends SessionController {
  _FakeSessionController(SessionState state)
    : super(_NoopSessionStorage(state), AuthService()) {
    this.state = state;
  }
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

class _SeededCitizenNearbyPresenceController
    extends CitizenNearbyPresenceController {
  _SeededCitizenNearbyPresenceController({
    required super.authService,
    required super.realtimeService,
    required super.transport,
    required CitizenNearbyPresenceState initialState,
  }) {
    state = initialState;
  }

  @override
  Future<void> start({
    required String userId,
    required String displayName,
  }) async {}

  @override
  Future<void> stop() async {}

  void setNearbyUsers(List<NearbyCitizenPin> nearbyUsers) {
    state = state.copyWith(nearbyUsers: nearbyUsers);
  }
}

class _SeededCitizenBleChatSessionController
    extends CitizenBleChatSessionController {
  _SeededCitizenBleChatSessionController({
    required super.authService,
    required super.realtimeService,
    required super.transport,
    required CitizenBleChatSessionState initialState,
  }) {
    state = initialState;
  }

  @override
  Future<void> start({
    required String userId,
    required String displayName,
  }) async {}

  @override
  Future<void> stop() async {}
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

Future<void> _pumpMap(
  WidgetTester tester, {
  required _FakeLocationService locationService,
  required CitizenLocationTrailController trailController,
  required CitizenNearbyPresenceController nearbyController,
  required CitizenBleChatSessionController bleChatController,
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
        citizenNearbyPresenceControllerProvider.overrideWith(
          (ref) => nearbyController,
        ),
        citizenBleChatSessionControllerProvider.overrideWith(
          (ref) => bleChatController,
        ),
        realtimeServiceProvider.overrideWith((ref) => _FakeRealtimeService()),
        sessionControllerProvider.overrideWith(
          (ref) => _FakeSessionController(
            const SessionState(
              role: AppRole.citizen,
              userId: 'citizen-1',
              email: 'citizen@test.com',
              fullName: 'Citizen One',
            ),
          ),
        ),
      ],
      child: const MaterialApp(
        home: MeshPeopleMapScreen(
          title: 'Mesh Feed Map',
          subtitle: 'Interactive map',
          enableSelfTracking: true,
          selfTrackingActive: true,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 40));
}

void main() {
  testWidgets('renders a nearby citizen pin distinct from the self pin', (
    tester,
  ) async {
    final locationService = _FakeLocationService(
      currentPosition: _locationAt(latitude: 14.5995),
    );
    final trailController = _SeededCitizenLocationTrailController(
      locationService: locationService,
      initialState: CitizenLocationTrailState(
        permissionResolved: true,
        permissionGranted: true,
        gpsEnabled: true,
        trackingActive: true,
        latestLocation: _locationAt(latitude: 14.5995),
        displayLocation: _locationAt(latitude: 14.5995),
        persistedTrailPoints: const [],
        lastAcceptedTrailPoint: null,
        lastSampledAt: DateTime.now().toUtc(),
        lastRejectionReason: null,
      ),
    );
    final nearbyController = _SeededCitizenNearbyPresenceController(
      authService: AuthService(),
      realtimeService: _FakeRealtimeService(),
      transport: MeshTransportService(automaticLocationBeaconing: false),
      initialState: CitizenNearbyPresenceState(
        selfLocation: _locationAt(latitude: 14.5995),
        nearbyUsers: [
          NearbyCitizenPin(
            userId: 'citizen-2',
            displayName: 'Citizen Two',
            meshDeviceId: 'mesh-device-2',
            meshIdentityHash: 'ABC123',
            latitude: 14.59955,
            longitude: 120.9842,
            accuracyMeters: 7,
            lastSeenAt: DateTime.now().toUtc(),
            distanceMeters: 6,
          ),
        ],
        subscribed: true,
        lastRefreshAt: DateTime.now().toUtc(),
        lastError: null,
      ),
    );
    final bleChatController = _SeededCitizenBleChatSessionController(
      authService: AuthService(),
      realtimeService: _FakeRealtimeService(),
      transport: MeshTransportService(automaticLocationBeaconing: false),
      initialState: const CitizenBleChatSessionState.initial(),
    );

    await _pumpMap(
      tester,
      locationService: locationService,
      trailController: trailController,
      nearbyController: nearbyController,
      bleChatController: bleChatController,
    );

    expect(find.textContaining('You'), findsOneWidget);
    expect(find.textContaining('CITIZEN TWO'), findsOneWidget);
  });

  testWidgets('shows Open Nearby Room when the selected citizen is in an active room', (
    tester,
  ) async {
    final locationService = _FakeLocationService(
      currentPosition: _locationAt(latitude: 14.5995),
    );
    final trailController = _SeededCitizenLocationTrailController(
      locationService: locationService,
      initialState: CitizenLocationTrailState(
        permissionResolved: true,
        permissionGranted: true,
        gpsEnabled: true,
        trackingActive: true,
        latestLocation: _locationAt(latitude: 14.5995),
        displayLocation: _locationAt(latitude: 14.5995),
        persistedTrailPoints: const [],
        lastAcceptedTrailPoint: null,
        lastSampledAt: DateTime.now().toUtc(),
        lastRejectionReason: null,
      ),
    );
    final nearbyController = _SeededCitizenNearbyPresenceController(
      authService: AuthService(),
      realtimeService: _FakeRealtimeService(),
      transport: MeshTransportService(automaticLocationBeaconing: false),
      initialState: CitizenNearbyPresenceState(
        selfLocation: _locationAt(latitude: 14.5995),
        nearbyUsers: [
          NearbyCitizenPin(
            userId: 'citizen-2',
            displayName: 'Citizen Two',
            meshDeviceId: 'mesh-device-2',
            meshIdentityHash: 'ABC123',
            latitude: 14.59955,
            longitude: 120.9842,
            accuracyMeters: 7,
            lastSeenAt: DateTime.now().toUtc(),
            distanceMeters: 6,
          ),
        ],
        subscribed: true,
        lastRefreshAt: DateTime.now().toUtc(),
        lastError: null,
      ),
    );
    final bleRoomAuth = _FakeBleRoomAuthService(
      roomsResponse: {
        'rooms': [
          {
            'id': 'room-1',
            'creator_user_id': 'citizen-1',
            'status': 'active',
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'expires_at': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 10))
                .toIso8601String(),
            'members': [
              {
                'id': 'room-1:citizen-1',
                'room_id': 'room-1',
                'user_id': 'citizen-1',
                'mesh_device_id': 'mesh-device-1',
                'display_name': 'Citizen One',
                'status': 'active',
                'joined_at': DateTime.now().toUtc().toIso8601String(),
              },
              {
                'id': 'room-1:citizen-2',
                'room_id': 'room-1',
                'user_id': 'citizen-2',
                'mesh_device_id': 'mesh-device-2',
                'display_name': 'Citizen Two',
                'status': 'active',
                'joined_at': DateTime.now().toUtc().toIso8601String(),
              },
            ],
          },
        ],
      },
    );
    final bleChatController = CitizenBleChatSessionController(
      authService: bleRoomAuth,
      realtimeService: _FakeRealtimeService(),
      transport: MeshTransportService(automaticLocationBeaconing: false),
    );

    await _pumpMap(
      tester,
      locationService: locationService,
      trailController: trailController,
      nearbyController: nearbyController,
      bleChatController: bleChatController,
    );
    await tester.tap(find.textContaining('CITIZEN TWO').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Open Nearby Room'), findsOneWidget);
  });

  testWidgets(
    'explains why BLE request is unavailable instead of leaving a dead tap',
    (tester) async {
      final locationService = _FakeLocationService(
        currentPosition: _locationAt(latitude: 14.5995),
      );
      final trailController = _SeededCitizenLocationTrailController(
        locationService: locationService,
        initialState: CitizenLocationTrailState(
          permissionResolved: true,
          permissionGranted: true,
          gpsEnabled: true,
          trackingActive: true,
          latestLocation: _locationAt(latitude: 14.5995),
          displayLocation: _locationAt(latitude: 14.5995),
          persistedTrailPoints: const [],
          lastAcceptedTrailPoint: null,
          lastSampledAt: DateTime.now().toUtc(),
          lastRejectionReason: null,
        ),
      );
      final nearbyController = _SeededCitizenNearbyPresenceController(
        authService: AuthService(),
        realtimeService: _FakeRealtimeService(),
        transport: MeshTransportService(automaticLocationBeaconing: false),
        initialState: CitizenNearbyPresenceState(
          selfLocation: _locationAt(latitude: 14.5995),
          nearbyUsers: [
            NearbyCitizenPin(
              userId: 'citizen-2',
              displayName: 'Citizen Two',
              meshDeviceId: 'mesh-device-2',
              meshIdentityHash: 'ABC123',
              latitude: 14.59955,
              longitude: 120.9842,
              accuracyMeters: 7,
              lastSeenAt: DateTime.now().toUtc(),
              distanceMeters: 6,
            ),
          ],
          subscribed: true,
          lastRefreshAt: DateTime.now().toUtc(),
          lastError: null,
        ),
      );
      final bleChatController = _SeededCitizenBleChatSessionController(
        authService: AuthService(),
        realtimeService: _FakeRealtimeService(),
        transport: MeshTransportService(automaticLocationBeaconing: false),
        initialState: const CitizenBleChatSessionState.initial(),
      );

      await _pumpMap(
        tester,
        locationService: locationService,
        trailController: trailController,
        nearbyController: nearbyController,
        bleChatController: bleChatController,
      );
      await tester.tap(find.textContaining('CITIZEN TWO').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Request BLE Connection'), findsOneWidget);
      expect(
        find.text('Nearby Citizen - GPS visible, waiting for BLE - +/-7m'),
        findsOneWidget,
      );
      expect(
        find.text('Waiting for a live BLE peer match before requesting.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Request BLE Connection'));
      await tester.pump();

      expect(
        find.text(
          'Nearby chat unavailable right now. Waiting for a live BLE peer match before requesting.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'enables BLE request when a live peer match exists even if GPS distance is larger than 20m',
    (tester) async {
      final locationService = _FakeLocationService(
        currentPosition: _locationAt(latitude: 14.5995),
      );
      final trailController = _SeededCitizenLocationTrailController(
        locationService: locationService,
        initialState: CitizenLocationTrailState(
          permissionResolved: true,
          permissionGranted: true,
          gpsEnabled: true,
          trackingActive: true,
          latestLocation: _locationAt(latitude: 14.5995),
          displayLocation: _locationAt(latitude: 14.5995),
          persistedTrailPoints: const [],
          lastAcceptedTrailPoint: null,
          lastSampledAt: DateTime.now().toUtc(),
          lastRejectionReason: null,
        ),
      );
      final nearbyController = _SeededCitizenNearbyPresenceController(
        authService: AuthService(),
        realtimeService: _FakeRealtimeService(),
        transport: MeshTransportService(automaticLocationBeaconing: false),
        initialState: CitizenNearbyPresenceState(
          selfLocation: _locationAt(latitude: 14.5995),
          nearbyUsers: [
            NearbyCitizenPin(
              userId: 'citizen-2',
              displayName: 'Citizen Two',
              meshDeviceId: 'mesh-device-2',
              meshIdentityHash: 'ABC123',
              latitude: 14.59975,
              longitude: 120.9842,
              accuracyMeters: 7,
              lastSeenAt: DateTime.now().toUtc(),
              distanceMeters: 32,
              bleMatched: true,
            ),
          ],
          subscribed: true,
          lastRefreshAt: DateTime.now().toUtc(),
          lastError: null,
        ),
      );
      final bleTransport = MeshTransportService(automaticLocationBeaconing: false);
      final bleChatController = _SeededCitizenBleChatSessionController(
        authService: AuthService(),
        realtimeService: _FakeRealtimeService(),
        transport: bleTransport,
        initialState: const CitizenBleChatSessionState.initial(),
      );
      bleTransport.onPeerDiscovered(
        'endpoint-2',
        'Citizen Two',
        deviceId: 'mesh-device-2',
        meshIdentityHash: 'ABC123',
        isConnected: true,
      );

      await _pumpMap(
        tester,
        locationService: locationService,
        trailController: trailController,
        nearbyController: nearbyController,
        bleChatController: bleChatController,
      );
      await tester.tap(find.textContaining('CITIZEN TWO').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Request BLE Connection'), findsOneWidget);
      expect(find.text('Nearby Citizen - BLE nearby and ready - +/-7m'), findsOneWidget);
      expect(
        find.text('Waiting for a live BLE peer match before requesting.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'keeps BLE request helper text after the live nearby pin drops out during refresh',
    (tester) async {
      final locationService = _FakeLocationService(
        currentPosition: _locationAt(latitude: 14.5995),
      );
      final trailController = _SeededCitizenLocationTrailController(
        locationService: locationService,
        initialState: CitizenLocationTrailState(
          permissionResolved: true,
          permissionGranted: true,
          gpsEnabled: true,
          trackingActive: true,
          latestLocation: _locationAt(latitude: 14.5995),
          displayLocation: _locationAt(latitude: 14.5995),
          persistedTrailPoints: const [],
          lastAcceptedTrailPoint: null,
          lastSampledAt: DateTime.now().toUtc(),
          lastRejectionReason: null,
        ),
      );
      final nearbyController = _SeededCitizenNearbyPresenceController(
        authService: AuthService(),
        realtimeService: _FakeRealtimeService(),
        transport: MeshTransportService(automaticLocationBeaconing: false),
        initialState: CitizenNearbyPresenceState(
          selfLocation: _locationAt(latitude: 14.5995),
          nearbyUsers: [
            NearbyCitizenPin(
              userId: 'citizen-2',
              displayName: 'Citizen Two',
              meshDeviceId: 'mesh-device-2',
              meshIdentityHash: 'ABC123',
              latitude: 14.59955,
              longitude: 120.9842,
              accuracyMeters: 7,
              lastSeenAt: DateTime.now().toUtc(),
              distanceMeters: 6,
            ),
          ],
          subscribed: true,
          lastRefreshAt: DateTime.now().toUtc(),
          lastError: null,
        ),
      );
      final bleChatController = _SeededCitizenBleChatSessionController(
        authService: AuthService(),
        realtimeService: _FakeRealtimeService(),
        transport: MeshTransportService(automaticLocationBeaconing: false),
        initialState: const CitizenBleChatSessionState.initial(),
      );

      await _pumpMap(
        tester,
        locationService: locationService,
        trailController: trailController,
        nearbyController: nearbyController,
        bleChatController: bleChatController,
      );
      await tester.tap(find.textContaining('CITIZEN TWO').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      nearbyController.setNearbyUsers(const []);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.text('Nearby citizen details are still loading.'),
        findsNothing,
      );
      expect(
        find.text('Waiting for a live BLE peer match before requesting.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Request BLE Connection'));
      await tester.pump();

      expect(
        find.text(
          'Nearby chat unavailable right now. Waiting for a live BLE peer match before requesting.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'removes a nearby citizen pin when the provider state is cleared',
    (tester) async {
      final locationService = _FakeLocationService(
        currentPosition: _locationAt(latitude: 14.5995),
      );
      final trailController = _SeededCitizenLocationTrailController(
        locationService: locationService,
        initialState: CitizenLocationTrailState(
          permissionResolved: true,
          permissionGranted: true,
          gpsEnabled: true,
          trackingActive: true,
          latestLocation: _locationAt(latitude: 14.5995),
          displayLocation: _locationAt(latitude: 14.5995),
          persistedTrailPoints: const [],
          lastAcceptedTrailPoint: null,
          lastSampledAt: DateTime.now().toUtc(),
          lastRejectionReason: null,
        ),
      );
      final nearbyController = _SeededCitizenNearbyPresenceController(
        authService: AuthService(),
        realtimeService: _FakeRealtimeService(),
        transport: MeshTransportService(automaticLocationBeaconing: false),
        initialState: CitizenNearbyPresenceState(
          selfLocation: _locationAt(latitude: 14.5995),
          nearbyUsers: [
            NearbyCitizenPin(
            userId: 'citizen-2',
            displayName: 'Citizen Two',
            meshDeviceId: 'mesh-device-2',
            meshIdentityHash: 'ABC123',
            latitude: 14.59955,
              longitude: 120.9842,
              accuracyMeters: 7,
              lastSeenAt: DateTime.now().toUtc(),
              distanceMeters: 6,
            ),
          ],
          subscribed: true,
          lastRefreshAt: DateTime.now().toUtc(),
          lastError: null,
        ),
      );
      final bleChatController = _SeededCitizenBleChatSessionController(
        authService: AuthService(),
        realtimeService: _FakeRealtimeService(),
        transport: MeshTransportService(automaticLocationBeaconing: false),
        initialState: const CitizenBleChatSessionState.initial(),
      );

      await _pumpMap(
        tester,
        locationService: locationService,
        trailController: trailController,
        nearbyController: nearbyController,
        bleChatController: bleChatController,
      );
      expect(find.textContaining('CITIZEN TWO'), findsOneWidget);

      nearbyController.setNearbyUsers(const []);
      await tester.pump();

      expect(find.textContaining('CITIZEN TWO'), findsNothing);
    },
  );

  testWidgets('renders nearby citizens beyond 15m when already included by presence logic', (
    tester,
  ) async {
    final locationService = _FakeLocationService(
      currentPosition: _locationAt(latitude: 14.5995),
    );
    final trailController = _SeededCitizenLocationTrailController(
      locationService: locationService,
      initialState: CitizenLocationTrailState(
        permissionResolved: true,
        permissionGranted: true,
        gpsEnabled: true,
        trackingActive: true,
        latestLocation: _locationAt(latitude: 14.5995, accuracyMeters: 18),
        displayLocation: _locationAt(latitude: 14.5995, accuracyMeters: 8),
        persistedTrailPoints: const [],
        lastAcceptedTrailPoint: null,
        lastSampledAt: DateTime.now().toUtc(),
        lastRejectionReason: null,
      ),
    );
    final nearbyController = _SeededCitizenNearbyPresenceController(
      authService: AuthService(),
      realtimeService: _FakeRealtimeService(),
      transport: MeshTransportService(automaticLocationBeaconing: false),
      initialState: CitizenNearbyPresenceState(
        selfLocation: _locationAt(latitude: 14.5995),
        nearbyUsers: [
          NearbyCitizenPin(
            userId: 'citizen-2',
            displayName: 'Citizen Two',
            meshDeviceId: 'mesh-device-2',
            meshIdentityHash: 'ABC123',
            latitude: 14.5995 + (24 / 111111.0),
            longitude: 120.9842,
            accuracyMeters: 8,
            lastSeenAt: DateTime.now().toUtc(),
            distanceMeters: 24,
          ),
        ],
        subscribed: true,
        lastRefreshAt: DateTime.now().toUtc(),
        lastError: null,
      ),
    );
    final bleChatController = _SeededCitizenBleChatSessionController(
      authService: AuthService(),
      realtimeService: _FakeRealtimeService(),
      transport: MeshTransportService(automaticLocationBeaconing: false),
      initialState: const CitizenBleChatSessionState.initial(),
    );

    await _pumpMap(
      tester,
      locationService: locationService,
      trailController: trailController,
      nearbyController: nearbyController,
      bleChatController: bleChatController,
    );

    expect(find.textContaining('CITIZEN TWO'), findsOneWidget);
  });
}
