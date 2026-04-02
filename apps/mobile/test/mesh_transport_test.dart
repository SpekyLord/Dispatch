import 'dart:async';

// Phase 4 mobile tests - offline queue, dedup, hop limit, token rejection.

import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/mesh_platform_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLocationService extends LocationService {
  @override
  Future<LocationData?> getCurrentPosition() async => null;

  @override
  Stream<LocationData> watchPosition() => const Stream<LocationData>.empty();
}


class _FakeMeshPlatformService implements MeshPlatformService {
  final StreamController<MeshPlatformEvent> _controller =
      StreamController<MeshPlatformEvent>.broadcast();
  final List<Map<String, dynamic>> sentPackets = [];
  final List<List<String>> exclusionHistory = [];
  bool started = false;

  @override
  Stream<MeshPlatformEvent> get events => _controller.stream;

  @override
  Future<MeshPlatformCapabilities> getCapabilities() async {
    return const MeshPlatformCapabilities(
      bleDiscoverySupported: true,
      bleAdvertisingSupported: true,
      wifiDirectSupported: true,
      bleNote: 'ready',
      wifiDirectNote: 'ready',
    );
  }

  @override
  Future<bool> startDiscovery({
    required String localDeviceId,
    required bool isGateway,
  }) async {
    started = true;
    return true;
  }

  @override
  Future<MeshPacketSendResult> sendPacket({
    required Map<String, dynamic> packet,
    required String preferredTransport,
    List<String> excludeEndpointIds = const [],
  }) async {
    sentPackets.add(packet);
    exclusionHistory.add(List<String>.from(excludeEndpointIds));
    return const MeshPacketSendResult(
      sentEndpointIds: ['peer-b'],
      attemptedPeerCount: 1,
      transport: 'wifi_direct',
    );
  }

  void emitTransportState({
    required int connectedPeerCount,
    String? activeTransport = 'wifi_direct',
    String? note,
  }) {
    _controller.add(
      MeshPlatformEvent.fromPlatformMap({
        'type': 'transport_state',
        'connectedPeerCount': connectedPeerCount,
        'activeTransport': activeTransport,
        'note': note,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  void emitPeer({
    required String endpointId,
    required String deviceName,
    bool isConnected = true,
  }) {
    _controller.add(
      MeshPlatformEvent.fromPlatformMap({
        'type': 'peer_seen',
        'endpointId': endpointId,
        'deviceName': deviceName,
        'supportsWifiDirect': true,
        'isConnected': isConnected,
        'transport': isConnected ? 'wifi_direct' : 'wifi_discovery',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  void emitInboundPacket(
    Map<String, dynamic> packet, {
    String sourceEndpointId = 'peer-a',
  }) {
    _controller.add(
      MeshPlatformEvent.fromPlatformMap({
        'type': 'packet_received',
        'sourceEndpointId': sourceEndpointId,
        'transport': 'wifi_direct',
        'packet': packet,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  @override
  Future<void> stopDiscovery() async {
    started = false;
  }

  @override
  void dispose() {
    _controller.close();
  }
}

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
    late _FakeMeshPlatformService platform;

    setUp(() {
      platform = _FakeMeshPlatformService();
      svc = MeshTransportService(
        locationService: _FakeLocationService(),
        platform: platform,
      );
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

    test('location beacon scheduler switches between normal and SOS cadence', () {
      svc.setConnectivity(false);
      expect(svc.activeLocationBeaconInterval, const Duration(seconds: 30));

      svc.startSosBeaconBroadcast(deviceId: 'sos-dev');
      expect(svc.activeLocationBeaconInterval, const Duration(seconds: 10));

      svc.stopSosBeaconBroadcast();
      expect(svc.activeLocationBeaconInterval, const Duration(seconds: 30));
    });


    test('enqueue relays packets over connected Wi-Fi Direct peers', () async {
      await svc.initialize();
      await svc.startDiscovery();
      platform.emitTransportState(connectedPeerCount: 1);
      await Future<void>.delayed(Duration.zero);

      svc.enqueuePacket(
        MeshTransportService.createMeshMessagePacket(
          deviceId: 'device-c',
          threadId: 'thread-1',
          recipientScope: 'broadcast',
          body: 'Medic team moving to zone 2.',
          authorDisplayName: 'Responder Kai',
          authorRole: 'department',
        ),
      );

      await Future<void>.delayed(Duration.zero);
      expect(platform.sentPackets, isNotEmpty);
      expect(platform.sentPackets.last['payloadType'], 'MESH_MESSAGE');
      expect(svc.activeRelayTransport, 'wifi_direct');
    });

    test('transport state promotes an offline node into relay role', () async {
      await svc.initialize();
      await svc.startDiscovery();

      platform.emitTransportState(connectedPeerCount: 2, note: 'relay ready');
      await Future<void>.delayed(Duration.zero);

      expect(svc.role, MeshNodeRole.relay);
      expect(svc.connectedRelayPeerCount, 2);
      expect(svc.transportStatusNote, 'relay ready');
    });

    test('received packets are rebroadcast without echoing to the source peer', () async {
      await svc.initialize();
      await svc.startDiscovery();
      platform.emitTransportState(connectedPeerCount: 2);
      await Future<void>.delayed(Duration.zero);

      platform.emitInboundPacket({
        'messageId': 'relay-inbound',
        'originDeviceId': 'other-dev',
        'timestamp': '2026-03-31T00:00:00Z',
        'hopCount': 0,
        'maxHops': 7,
        'payloadType': 'INCIDENT_REPORT',
        'payload': {'description': 'Relayed warehouse fire'},
        'signature': '',
      });

      await Future<void>.delayed(Duration.zero);
      expect(platform.sentPackets.last['messageId'], 'relay-inbound');
      expect(platform.sentPackets.last['hopCount'], 1);
      expect(platform.exclusionHistory.last, contains('peer-a'));
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

  group('Survivor resolve packet factory', () {
    test('builds a status update packet for survivor resolve relay', () {
      final pkt = MeshTransportService.createSurvivorResolvePacket(
        deviceId: 'dept-device',
        survivorMessageId: 'sar-msg-1',
        signalId: 'sig-1',
        note: 'Located near the riverbank.',
        resolvedByUserId: 'dept-user-1',
      );

      expect(pkt.payloadType, MeshPayloadType.statusUpdate);
      expect(pkt.maxHops, 15);
      expect(pkt.payload['targetType'], 'SURVIVOR_SIGNAL');
      expect(pkt.payload['survivorMessageId'], 'sar-msg-1');
      expect(pkt.payload['signalId'], 'sig-1');
      expect(pkt.payload['resolvedByUserId'], 'dept-user-1');
    });
  });
}

