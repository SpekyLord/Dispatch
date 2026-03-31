import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/sar_mode_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SarModeController', () {
    late MeshTransportService transport;
    late SarModeController controller;

    setUp(() async {
      transport = MeshTransportService();
      controller = SarModeController(transport: transport);
      await controller.setSarModeEnabled(true);
    });

    tearDown(() {
      controller.dispose();
      transport.dispose();
    });

    test('anonymizes MAC-style identifiers by zeroing the last two octets', () {
      final anonymized = SarModeController.anonymizeDeviceIdentifier(
        'AA:BB:CC:DD:EE:FF',
      );
      expect(anonymized, 'AA:BB:CC:DD:00:00');
    });

    test('deduplicates BLE detections inside the 60 second window', () {
      final location = const SarNodeLocation(
        lat: 14.5,
        lng: 121.0,
        accuracyMeters: 8,
      );
      final first = controller.registerBlePassiveScan(
        rawDeviceIdentifier: 'AA:BB:CC:DD:EE:FF',
        signalStrengthDbm: -70,
        nodeLocation: location,
        observedAt: DateTime.parse('2026-03-31T00:00:00Z'),
      );
      final duplicate = controller.registerBlePassiveScan(
        rawDeviceIdentifier: 'AA:BB:CC:DD:EE:FF',
        signalStrengthDbm: -69,
        nodeLocation: location,
        observedAt: DateTime.parse('2026-03-31T00:00:30Z'),
      );

      expect(first, isNotNull);
      expect(duplicate, isNull);
      expect(controller.state.activeSignals.length, 1);
      expect(transport.queueSize, 1);
    });

    test(
      'classifies acoustic windows locally and only emits positive matches',
      () {
        final location = const SarNodeLocation(
          lat: 14.5,
          lng: 121.0,
          accuracyMeters: 8,
        );
        final none = controller.registerAcousticWindow(
          sample: const AcousticSampleWindow(
            peakDb: 20,
            repeatedImpacts: false,
            voiceBandPresent: false,
            anomalyDetected: false,
          ),
          nodeLocation: location,
        );
        final voice = controller.registerAcousticWindow(
          sample: const AcousticSampleWindow(
            peakDb: 50,
            repeatedImpacts: false,
            voiceBandPresent: true,
            anomalyDetected: false,
          ),
          nodeLocation: location,
        );

        expect(none, isNull);
        expect(voice, isNotNull);
        expect(voice?.acousticPatternMatched, AcousticPatternMatched.voice);
        expect(transport.queueSize, 1);
      },
    );

    test('stores incoming survivor packets in the local SAR feed', () async {
      final packet = MeshPacket(
        messageId: 'incoming-sar',
        originDeviceId: 'peer-device',
        timestamp: '2026-03-31T00:00:00Z',
        payloadType: MeshPayloadType.survivorSignal,
        payload: {
          'detectionMethod': 'SOS_BEACON',
          'signalStrengthDbm': -55,
          'estimatedDistanceMeters': 2.5,
          'detectedDeviceIdentifier': 'AA:BB:CC:DD:00:00',
          'lastSeenTimestamp': '2026-03-31T00:00:00Z',
          'nodeLocation': {'lat': 14.5, 'lng': 121.0, 'accuracyMeters': 5},
          'confidence': 1.0,
          'acousticPatternMatched': 'none',
        },
      );

      transport.receivePacket(packet);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.activeSignals.length, 1);
      expect(controller.state.activeSignals.first.messageId, 'incoming-sar');
      expect(
        controller.state.activeSignals.first.detectionMethod,
        SarDetectionMethod.sosBeacon,
      );
    });

    test(
      'queues survivor resolve packets and applies relayed resolve updates',
      () async {
        final location = const SarNodeLocation(
          lat: 14.5,
          lng: 121.0,
          accuracyMeters: 5,
        );
        final signal = controller.registerSosBeacon(
          beaconIdentifier: 'AA:BB:CC:DD:EE:FF',
          signalStrengthDbm: -54,
          nodeLocation: location,
          observedAt: DateTime.parse('2026-03-31T00:00:00Z'),
        );

        expect(signal, isNotNull);
        controller.queueSurvivorResolution(
          signal: signal!,
          note: 'Located near the collapsed stairwell.',
          resolvedByUserId: 'dept-user-1',
        );

        final queuedSignal = controller.state.activeSignals.single;
        expect(queuedSignal.isResolved, isTrue);
        expect(queuedSignal.isResolutionQueued, isTrue);

        final drained = transport.drainQueue();
        final survivorPacket = drained.firstWhere(
          (packet) => packet.payloadType == MeshPayloadType.survivorSignal,
        );
        final resolvePacket = drained.firstWhere(
          (packet) => packet.payloadType == MeshPayloadType.statusUpdate,
        );
        expect(resolvePacket.maxHops, 15);
        expect(resolvePacket.payload['targetType'], 'SURVIVOR_SIGNAL');
        expect(resolvePacket.payload['survivorMessageId'], signal.messageId);

        final peerTransport = MeshTransportService();
        final peerController = SarModeController(transport: peerTransport);
        await peerController.setSarModeEnabled(true);
        addTearDown(() {
          peerController.dispose();
          peerTransport.dispose();
        });

        peerTransport.receivePacket(survivorPacket);
        await Future<void>.delayed(Duration.zero);
        peerTransport.receivePacket(resolvePacket);
        await Future<void>.delayed(Duration.zero);

        final relayedSignal = peerController.state.activeSignals.single;
        expect(relayedSignal.isResolved, isTrue);
        expect(relayedSignal.isResolutionQueued, isFalse);
        expect(
          relayedSignal.resolutionNote,
          'Located near the collapsed stairwell.',
        );
      },
    );
  });
}
