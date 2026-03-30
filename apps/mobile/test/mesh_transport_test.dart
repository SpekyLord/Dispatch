// Phase 4 mobile tests - offline queue, dedup, hop limit, token rejection.

import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MeshPacket', () {
    test('serializes to JSON and back', () {
      final pkt = MeshPacket(
        messageId: 'test-1',
        originDeviceId: 'dev-001',
        timestamp: '2026-03-31T00:00:00Z',
        hopCount: 2,
        maxHops: 7,
        payloadType: MeshPayloadType.incidentReport,
        payload: {'description': 'Test fire'},
        signature: 'sig-123',
      );

      final json = pkt.toJson();
      expect(json['messageId'], 'test-1');
      expect(json['payloadType'], 'INCIDENT_REPORT');
      expect(json['hopCount'], 2);

      final restored = MeshPacket.fromJson(json);
      expect(restored.messageId, 'test-1');
      expect(restored.payloadType, MeshPayloadType.incidentReport);
      expect(restored.hopCount, 2);
    });

    test('requiresWifiDirect false for small payloads', () {
      final pkt = MeshPacket(
        messageId: 'small',
        originDeviceId: 'dev',
        timestamp: '2026-03-31T00:00:00Z',
        payloadType: MeshPayloadType.distress,
        payload: {'description': 'Help'},
      );
      expect(pkt.requiresWifiDirect, false);
    });

    test('requiresWifiDirect true for large payloads', () {
      final bigPayload = <String, dynamic>{'description': 'x' * 15000};
      final pkt = MeshPacket(
        messageId: 'big',
        originDeviceId: 'dev',
        timestamp: '2026-03-31T00:00:00Z',
        payloadType: MeshPayloadType.incidentReport,
        payload: bigPayload,
      );
      expect(pkt.requiresWifiDirect, true);
    });
  });

  group('MeshTransportService', () {
    late MeshTransportService svc;

    setUp(() {
      svc = MeshTransportService();
    });

    tearDown(() {
      svc.dispose();
    });

    test('initializes with origin role', () async {
      await svc.initialize();
      expect(svc.role, MeshNodeRole.origin);
    });

    test('enqueue adds packet to queue', () {
      final pkt = MeshPacket(
        messageId: 'q-1',
        originDeviceId: 'dev',
        timestamp: '2026-03-31T00:00:00Z',
        payloadType: MeshPayloadType.incidentReport,
        payload: {'description': 'Test'},
      );
      svc.enqueuePacket(pkt);
      expect(svc.queueSize, 1);
    });

    test('drainQueue returns packets and clears', () {
      final pkt = MeshPacket(
        messageId: 'q-2',
        originDeviceId: 'dev',
        timestamp: '2026-03-31T00:00:00Z',
        payloadType: MeshPayloadType.incidentReport,
        payload: {'description': 'Test'},
      );
      svc.enqueuePacket(pkt);
      final drained = svc.drainQueue();
      expect(drained.length, 1);
      expect(svc.queueSize, 0);
      expect(svc.lastSyncTime, isNotNull);
    });

    test('receivePacket deduplicates by messageId', () {
      final pkt = MeshPacket(
        messageId: 'dedup-1',
        originDeviceId: 'dev',
        timestamp: '2026-03-31T00:00:00Z',
        payloadType: MeshPayloadType.incidentReport,
        payload: {'description': 'Test'},
      );

      final accepted = svc.receivePacket(pkt);
      expect(accepted, true);

      final pkt2 = MeshPacket.fromJson(pkt.toJson());
      pkt2.hopCount = 0;
      final rejected = svc.receivePacket(pkt2);
      expect(rejected, false);
    });

    test('receivePacket drops packets at hop limit', () {
      final pkt = MeshPacket(
        messageId: 'hop-limit',
        originDeviceId: 'dev',
        timestamp: '2026-03-31T00:00:00Z',
        hopCount: 7,
        maxHops: 7,
        payloadType: MeshPayloadType.incidentReport,
        payload: {'description': 'Test'},
      );
      final result = svc.receivePacket(pkt);
      expect(result, false);
    });

    test('receivePacket increments hop count on relay', () {
      final pkt = MeshPacket(
        messageId: 'hop-inc',
        originDeviceId: 'dev',
        timestamp: '2026-03-31T00:00:00Z',
        hopCount: 2,
        maxHops: 7,
        payloadType: MeshPayloadType.incidentReport,
        payload: {'description': 'Test'},
      );
      svc.receivePacket(pkt);
      expect(pkt.hopCount, 3);
    });

    test('gateway role queues received packets for upload', () async {
      await svc.initialize();
      svc.setConnectivity(true);
      expect(svc.role, MeshNodeRole.gateway);

      final pkt = MeshPacket(
        messageId: 'gw-1',
        originDeviceId: 'other-dev',
        timestamp: '2026-03-31T00:00:00Z',
        payloadType: MeshPayloadType.incidentReport,
        payload: {'description': 'Relay test'},
      );
      svc.receivePacket(pkt);
      expect(svc.queueSize, 1);
    });

    test('setConnectivity toggles role', () {
      svc.setConnectivity(true);
      expect(svc.role, MeshNodeRole.gateway);
      svc.setConnectivity(false);
      expect(svc.role, MeshNodeRole.origin);
    });

    test('onPeerDiscovered adds and updates peers', () {
      svc.onPeerDiscovered('ep-1', 'Phone A');
      expect(svc.peerCount, 1);
      svc.onPeerDiscovered('ep-1', 'Phone A');
      expect(svc.peerCount, 1);
      svc.onPeerDiscovered('ep-2', 'Phone B');
      expect(svc.peerCount, 2);
    });

    test(
      'drainQueue prioritizes survivor signals ahead of incident reports',
      () {
        svc.enqueuePacket(
          MeshPacket(
            messageId: 'incident-first',
            originDeviceId: 'dev',
            timestamp: '2026-03-31T00:00:00Z',
            payloadType: MeshPayloadType.incidentReport,
            payload: {'description': 'Test'},
          ),
        );
        svc.enqueuePacket(
          MeshPacket(
            messageId: 'survivor-priority',
            originDeviceId: 'dev',
            timestamp: '2026-03-31T00:00:00Z',
            maxHops: 15,
            payloadType: MeshPayloadType.survivorSignal,
            payload: {'detectionMethod': 'BLE_PASSIVE'},
          ),
        );

        final drained = svc.drainQueue();
        expect(drained.first.messageId, 'survivor-priority');
      },
    );

    test('SOS beacon broadcast state can be toggled for SAR detection', () {
      svc.startSosBeaconBroadcast(deviceId: 'sos-dev');
      expect(svc.isSosBeaconBroadcasting, true);
      expect(svc.sosBeaconDeviceId, 'sos-dev');
      svc.stopSosBeaconBroadcast();
      expect(svc.isSosBeaconBroadcasting, false);
    });
  });

  group('Distress packet factory', () {
    test('creates distress with maxHops=15', () {
      final pkt = MeshTransportService.createDistressPacket(
        deviceId: 'sos-dev',
        description: 'Trapped',
        reporterName: 'Juan',
        contactInfo: '09171234567',
        latitude: 14.5,
        longitude: 121.0,
      );
      expect(pkt.maxHops, 15);
      expect(pkt.payloadType, MeshPayloadType.distress);
      expect(pkt.payload['reporter_name'], 'Juan');
      expect(pkt.messageId.isNotEmpty, true);
    });
  });

  group('Announcement packet factory', () {
    test('requires offline token in payload', () {
      final pkt = MeshTransportService.createAnnouncementPacket(
        deviceId: 'dept-dev',
        departmentId: 'dept-1',
        offlineToken: 'valid-jwt',
        title: 'Evacuation',
        content: 'Leave now',
        category: 'alert',
      );
      expect(pkt.payloadType, MeshPayloadType.announcement);
      expect(pkt.payload['offline_verification_token'], 'valid-jwt');
      expect(pkt.payload['department_id'], 'dept-1');
    });
  });
}
