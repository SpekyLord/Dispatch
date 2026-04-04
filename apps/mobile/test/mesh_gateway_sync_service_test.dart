import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/mesh_gateway_sync_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLocationService extends LocationService {
  _FakeLocationService({this.currentPosition});

  LocationData? currentPosition;

  @override
  Future<LocationData?> getCurrentPosition() async => currentPosition;
}

class _FakeSyncAuthService extends AuthService {
  _FakeSyncAuthService({
    this.throwOnIngest = false,
    this.response = const {'acks': []},
  }) : super();

  bool throwOnIngest;
  final Map<String, dynamic> response;
  int calls = 0;
  List<Map<String, dynamic>>? lastPackets;
  Map<String, dynamic>? lastTopologySnapshot;

  @override
  Future<Map<String, dynamic>> ingestMeshPackets(
    List<Map<String, dynamic>> packets, {
    Map<String, dynamic>? topologySnapshot,
  }) async {
    calls += 1;
    lastPackets = packets;
    lastTopologySnapshot = topologySnapshot;
    if (throwOnIngest) {
      throw Exception('sync failed');
    }
    return response;
  }
}

void main() {
  test('sync uploads topology-only payload when queue is empty', () async {
    final locationService = _FakeLocationService(
      currentPosition: const LocationData(
        latitude: 14.601,
        longitude: 120.982,
        accuracyMeters: 5,
      ),
    );
    final transport = MeshTransportService(locationService: locationService);
    addTearDown(transport.dispose);
    final auth = _FakeSyncAuthService();
    final service = MeshGatewaySyncService(
      authService: auth,
      transport: transport,
    );

    final result = await service.sync(
      operatorRole: 'municipality',
      displayName: 'Gateway One',
    );

    expect(result.didUpload, true);
    expect(result.packetCount, 0);
    expect(result.topologyNodeCount, greaterThanOrEqualTo(1));
    expect(auth.calls, 1);
    expect(auth.lastPackets, isNotNull);
    expect(auth.lastPackets, isEmpty);
    expect(auth.lastTopologySnapshot, isNotNull);
  });

  test('sync no-ops when queue and topology are both unavailable', () async {
    final transport = MeshTransportService(
      locationService: _FakeLocationService(),
    );
    addTearDown(transport.dispose);
    final auth = _FakeSyncAuthService();
    final service = MeshGatewaySyncService(
      authService: auth,
      transport: transport,
    );

    final result = await service.sync();
    expect(result.didUpload, false);
    expect(auth.calls, 0);
  });

  test('failed sync restores drained queue packets', () async {
    final transport = MeshTransportService(
      locationService: _FakeLocationService(),
    );
    addTearDown(transport.dispose);
    final auth = _FakeSyncAuthService(throwOnIngest: true);
    final service = MeshGatewaySyncService(
      authService: auth,
      transport: transport,
    );

    final packet = MeshPacket(
      messageId: 'packet-1',
      originDeviceId: 'dev-1',
      timestamp: DateTime.now().toUtc().toIso8601String(),
      payloadType: MeshPayloadType.meshMessage,
      payload: const {'body': 'hello'},
    );
    transport.enqueuePacket(packet);
    expect(transport.queueSize, 1);

    await expectLater(service.sync(), throwsException);
    expect(transport.queueSize, 1);

    final drained = transport.drainQueue();
    expect(drained.length, 1);
    expect(drained.first.messageId, 'packet-1');
  });
}
