import 'dart:async';

import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/compass_sensor_service.dart';
import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/sar_mode_service.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session_controller.dart';
import 'package:dispatch_mobile/features/mesh/presentation/survivor_compass_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCompassAuthService extends AuthService {
  FakeCompassAuthService() : super();

  @override
  Future<List<Map<String, dynamic>>> getSurvivorSignals({
    String? status,
    String? detectionMethod,
  }) async {
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

void main() {
  Future<void> pumpCompass(
    WidgetTester tester, {
    required LocationData rescuerLocation,
    required double headingDegrees,
    required SarNodeLocation targetLocation,
  }) async {
    final transport = MeshTransportService();
    final controller = SarModeController(transport: transport);
    controller.setSarModeEnabled(true);
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
          authServiceProvider.overrideWithValue(FakeCompassAuthService()),
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
        ],
        child: const MaterialApp(
          home: SurvivorCompassScreen(showMiniMap: false),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 150));
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
}
