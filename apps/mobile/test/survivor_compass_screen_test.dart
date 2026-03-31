import 'dart:async';

import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/compass_sensor_service.dart';
import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/sar_mode_service.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/services/session_storage.dart';
import 'package:dispatch_mobile/core/state/session_controller.dart';
import 'package:dispatch_mobile/core/state/session_state.dart';
import 'package:dispatch_mobile/features/mesh/presentation/survivor_compass_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCompassAuthService extends AuthService {
  FakeCompassAuthService({this.throwOnFetch = false}) : super();

  final bool throwOnFetch;

  @override
  Future<List<Map<String, dynamic>>> getSurvivorSignals({
    String? status,
    String? detectionMethod,
  }) async {
    if (throwOnFetch) {
      throw Exception('offline');
    }
    return const [];
  }

  @override
  Future<Map<String, dynamic>> resolveSurvivorSignal(
    String signalId, {
    String note = '',
  }) async {
    return {
      'id': signalId,
      'message_id': signalId,
      'resolved': true,
      'resolution_note': note,
    };
  }
}

class FakeLocationService extends LocationService {
  FakeLocationService({
    required this.currentPosition,
    Stream<LocationData>? positionStream,
  }) : _positionStream = positionStream;

  final LocationData? currentPosition;
  final Stream<LocationData>? _positionStream;

  @override
  Future<LocationData?> getCurrentPosition() async => currentPosition;

  @override
  Stream<LocationData> watchPosition() {
    return _positionStream ??
        (currentPosition == null
            ? const Stream<LocationData>.empty()
            : Stream<LocationData>.value(currentPosition!));
  }
}

class CompassHarness {
  CompassHarness({required this.transport, required this.controller});

  final MeshTransportService transport;
  final SarModeController controller;
}

void main() {
  Future<CompassHarness> pumpCompass(
    WidgetTester tester, {
    required LocationData rescuerLocation,
    required double headingDegrees,
    required SarNodeLocation targetLocation,
    AuthService? authService,
  }) async {
    final transport = MeshTransportService();
    final controller = SarModeController(transport: transport);
    await controller.setSarModeEnabled(true);
    final signal = controller.registerSosBeacon(
      beaconIdentifier: 'AA:BB:CC:DD:EE:FF',
      signalStrengthDbm: -52,
      nodeLocation: targetLocation,
      observedAt: DateTime.parse('2026-03-31T01:00:00Z'),
    );

    expect(signal, isNotNull);
    controller.pinTarget(signal!.messageId);

    addTearDown(transport.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(
            authService ?? FakeCompassAuthService(),
          ),
          meshTransportProvider.overrideWithValue(transport),
          sarModeControllerProvider.overrideWith((ref) => controller),
          locationServiceProvider.overrideWithValue(
            FakeLocationService(currentPosition: rescuerLocation),
          ),
          compassSensorProvider.overrideWithValue(
            CompassSensorService(
              headingStream: Stream<CompassHeadingSample>.value(
                CompassHeadingSample(
                  headingDegrees: headingDegrees,
                  accuracy: 4,
                  recordedAt: DateTime.parse('2026-03-31T01:00:00Z'),
                ),
              ),
            ),
          ),
          sessionControllerProvider.overrideWith(
            (ref) => _FakeSessionController(),
          ),
        ],
        child: const MaterialApp(
          home: SurvivorCompassScreen(showMiniMap: false),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 150));
    return CompassHarness(transport: transport, controller: controller);
  }

  testWidgets('shows the target bearing for mock GPS coordinates', (
    tester,
  ) async {
    await pumpCompass(
      tester,
      rescuerLocation: const LocationData(latitude: 14.5, longitude: 121.0),
      headingDegrees: 0,
      targetLocation: const SarNodeLocation(
        lat: 14.51,
        lng: 121.0,
        accuracyMeters: 5,
      ),
    );

    expect(find.text('Bearing N'), findsOneWidget);
  });

  testWidgets('shows turn guidance from the heading stream', (tester) async {
    await pumpCompass(
      tester,
      rescuerLocation: const LocationData(latitude: 14.5, longitude: 121.0),
      headingDegrees: 270,
      targetLocation: const SarNodeLocation(
        lat: 14.51,
        lng: 121.0,
        accuracyMeters: 5,
      ),
    );

    expect(find.text('Turn 90 deg right'), findsOneWidget);
  });

  testWidgets('switches to proximity pulse state within three meters', (
    tester,
  ) async {
    await pumpCompass(
      tester,
      rescuerLocation: const LocationData(latitude: 14.5, longitude: 121.0),
      headingDegrees: 0,
      targetLocation: const SarNodeLocation(
        lat: 14.500009,
        lng: 121.0,
        accuracyMeters: 3,
      ),
    );

    expect(find.text('Proximity pulse active'), findsOneWidget);
  });

  testWidgets('queues a survivor resolve packet for mesh relay when offline', (
    tester,
  ) async {
    final harness = await pumpCompass(
      tester,
      rescuerLocation: const LocationData(latitude: 14.5, longitude: 121.0),
      headingDegrees: 0,
      targetLocation: const SarNodeLocation(
        lat: 14.5004,
        lng: 121.0,
        accuracyMeters: 5,
      ),
      authService: FakeCompassAuthService(throwOnFetch: true),
    );

    await tester.scrollUntilVisible(find.text('Mark located'), 160);
    final noteField = find.byType(TextField);
    expect(noteField, findsOneWidget);
    await tester.enterText(noteField, 'Located near the collapsed stairwell.');
    await tester.tap(find.text('Mark located'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Resolve queued for mesh'), findsWidgets);

    final queuedPackets = harness.transport.drainQueue();
    final resolvePacket = queuedPackets.firstWhere(
      (packet) => packet.payloadType == MeshPayloadType.statusUpdate,
    );
    expect(resolvePacket.payload['targetType'], 'SURVIVOR_SIGNAL');
    expect(
      resolvePacket.payload['survivorMessageId'],
      harness.controller.state.activeSignals.first.messageId,
    );
    expect(
      resolvePacket.payload['resolutionNote'],
      'Located near the collapsed stairwell.',
    );
  });
}

class _FakeSessionController extends SessionController {
  _FakeSessionController()
    : super(
        _NoopSessionStorage(
          const SessionState(
            accessToken: 'token',
            userId: 'dept-user-1',
            role: AppRole.department,
            fullName: 'Responder One',
          ),
        ),
        AuthService(),
      );
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
