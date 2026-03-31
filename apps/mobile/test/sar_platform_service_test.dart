import 'dart:async';

import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/sar_mode_service.dart';
import 'package:dispatch_mobile/core/services/sar_platform_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SAR platform parsing', () {
    test('parses Wi-Fi probe observations from platform maps', () {
      final sample = WifiProbeObservation.fromPlatformMap({
        'macAddress': 'AA:BB:CC:DD:EE:FF',
        'rssi': -67,
        'timestamp': 1711843200000,
      });

      expect(sample.deviceIdentifier, 'AA:BB:CC:DD:EE:FF');
      expect(sample.signalStrengthDbm, -67);
      expect(sample.observedAt, DateTime.parse('2024-03-31T00:00:00.000Z'));
    });

    test('extracts BLE RSSI and beacon identity from scan payloads', () {
      final sample = BlePassiveScanSample.fromPlatformMap({
        'address': '11:22:33:44:55:66',
        'beaconIdentifier': 'A1B2C3D4',
        'rssi': -58,
        'isSosBeacon': true,
      });

      expect(sample.deviceIdentifier, 'A1B2C3D4');
      expect(sample.signalStrengthDbm, -58);
      expect(sample.isSosBeacon, isTrue);
    });
  });

  group('SAR platform controller integration', () {
    late MeshTransportService transport;
    late _FakeSarPlatformService platform;
    late SarModeController controller;

    setUp(() {
      transport = MeshTransportService();
      platform = _FakeSarPlatformService();
      controller = SarModeController(
        transport: transport,
        platform: platform,
        locationService: _FakeLocationService(),
      );
    });

    tearDown(() {
      controller.dispose();
      platform.dispose();
      transport.dispose();
    });

    test(
      'classifies mocked acoustic summaries without sharing raw audio',
      () async {
        await controller.setSarModeEnabled(true);
        platform.emit(
          SarPlatformEvent.fromPlatformMap({
            'type': 'acoustic_window',
            'peakDb': 52,
            'repeatedImpacts': false,
            'voiceBandPresent': true,
            'anomalyDetected': false,
            'timestamp': 1711843200000,
          }),
        );
        await Future<void>.delayed(Duration.zero);

        expect(controller.state.activeSignals, hasLength(1));
        expect(
          controller.state.activeSignals.single.detectionMethod,
          SarDetectionMethod.acoustic,
        );
        expect(
          controller.state.activeSignals.single.acousticPatternMatched,
          AcousticPatternMatched.voice,
        );
        expect(transport.queueSize, 1);
      },
    );
  });
}

class _FakeSarPlatformService implements SarPlatformService {
  final StreamController<SarPlatformEvent> _controller =
      StreamController<SarPlatformEvent>.broadcast();

  @override
  Stream<SarPlatformEvent> get events => _controller.stream;

  void emit(SarPlatformEvent event) {
    _controller.add(event);
  }

  @override
  Future<SarPlatformCapabilities> getCapabilities() async {
    return const SarPlatformCapabilities(
      wifiProbeSupported: false,
      blePassiveSupported: true,
      acousticSupported: true,
      sosBeaconSupported: true,
      wifiProbeNote: 'Unavailable in standard app sandboxes.',
      blePassiveNote: 'Ready',
      acousticNote: 'Ready',
      sosBeaconNote: 'Ready',
    );
  }

  @override
  Future<bool> startAcousticSampling() async => true;

  @override
  Future<bool> startBlePassiveScan() async => true;

  @override
  Future<bool> startSosBeaconBroadcast({required String deviceId}) async =>
      true;

  @override
  Future<void> stopAcousticSampling() async {}

  @override
  Future<void> stopBlePassiveScan() async {}

  @override
  Future<void> stopSosBeaconBroadcast() async {}

  @override
  void dispose() {
    _controller.close();
  }
}

class _FakeLocationService extends LocationService {
  @override
  Future<LocationData?> getCurrentPosition() async {
    return const LocationData(
      latitude: 14.5995,
      longitude: 120.9842,
      accuracyMeters: 6,
    );
  }
}
