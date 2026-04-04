import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';

class MeshGatewaySyncResult {
  const MeshGatewaySyncResult({
    required this.didUpload,
    required this.packetCount,
    required this.topologyNodeCount,
    this.response,
  });

  final bool didUpload;
  final int packetCount;
  final int topologyNodeCount;
  final Map<String, dynamic>? response;
}

class MeshGatewaySyncService {
  MeshGatewaySyncService({
    required AuthService authService,
    required MeshTransportService transport,
  }) : _authService = authService,
       _transport = transport;

  final AuthService _authService;
  final MeshTransportService _transport;

  Future<MeshGatewaySyncResult> sync({
    String? operatorRole,
    String? departmentId,
    String? departmentName,
    String? displayName,
  }) async {
    final drainedPackets = _transport.drainQueue();
    final topologySnapshot = await _transport.buildTopologySnapshot(
      operatorRole: operatorRole,
      departmentId: departmentId,
      departmentName: departmentName,
      displayName: displayName,
    );

    if (drainedPackets.isEmpty && topologySnapshot == null) {
      return const MeshGatewaySyncResult(
        didUpload: false,
        packetCount: 0,
        topologyNodeCount: 0,
      );
    }

    try {
      final response = await _authService.ingestMeshPackets(
        drainedPackets.map((packet) => packet.toJson()).toList(growable: false),
        topologySnapshot: topologySnapshot,
      );
      _transport.processSyncAcks(
        (response['acks'] as List?)?.cast<Map<String, dynamic>>() ?? const [],
      );
      return MeshGatewaySyncResult(
        didUpload: true,
        packetCount: drainedPackets.length,
        topologyNodeCount:
            ((topologySnapshot?['nodes'] as List?)?.length ?? 0) +
            (topologySnapshot?['gateway'] == null ? 0 : 1),
        response: response,
      );
    } catch (_) {
      _transport.restoreQueue(drainedPackets);
      rethrow;
    }
  }
}
