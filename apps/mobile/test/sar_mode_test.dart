import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/sar_mode_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SarModeController', () {
    late MeshTransportService transport;
    late SarModeController controller;

    setUp(() {
      transport = MeshTransportService();
      controller = SarModeController(transport: transport);
      controller.setSarModeEnabled(true);
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
  });
}
