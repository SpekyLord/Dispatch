import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Mesh communications packet factories', () {
    test('creates a mesh message packet with the expected payload', () {
      final packet = MeshTransportService.createMeshMessagePacket(
        deviceId: 'device-a',
        threadId: 'thread-a',
        recipientScope: 'broadcast',
        body: 'Bridge is passable from the east side.',
        authorDisplayName: 'Responder Mila',
        authorRole: 'department',
        authorOfflineToken: 'token-123',
      );

      expect(packet.payloadType, MeshPayloadType.meshMessage);
      expect(packet.payload['threadId'], 'thread-a');
      expect(packet.payload['recipientScope'], 'broadcast');
      expect(packet.payload['body'], 'Bridge is passable from the east side.');
      expect(packet.payload['authorDisplayName'], 'Responder Mila');
      expect(packet.payload['authorOfflineToken'], 'token-123');
    });

    test('creates a mesh post packet with the expected payload', () {
      final packet = MeshTransportService.createMeshPostPacket(
        deviceId: 'device-b',
        postId: 'post-a',
        category: 'alert',
        title: 'Evacuate Riverside',
        body: 'Proceed to the west gymnasium immediately.',
        authorDepartmentId: 'dept-7',
        authorOfflineToken: 'token-456',
        attachmentRefs: const ['map.pdf'],
      );

      expect(packet.payloadType, MeshPayloadType.meshPost);
      expect(packet.payload['postId'], 'post-a');
      expect(packet.payload['category'], 'alert');
      expect(packet.payload['title'], 'Evacuate Riverside');
      expect(packet.payload['attachmentRefs'], ['map.pdf']);
    });
  });

  group('Mesh communications relay priority', () {
    late MeshTransportService service;

    setUp(() {
      service = MeshTransportService();
    });

    tearDown(() {
      service.dispose();
    });

    test('prioritizes mesh messages ahead of mesh posts and incident reports', () {
      service.enqueuePacket(
        MeshTransportService.createIncidentPacket(
          deviceId: 'device-a',
          description: 'Flooded intersection',
        ),
      );
      service.enqueuePacket(
        MeshTransportService.createMeshPostPacket(
          deviceId: 'device-b',
          postId: 'post-1',
          category: 'warning',
          title: 'Curfew',
          body: 'Stay indoors after 8 PM.',
          authorDepartmentId: 'dept-1',
          authorOfflineToken: 'token-post',
        ),
      );
      service.enqueuePacket(
        MeshTransportService.createMeshMessagePacket(
          deviceId: 'device-c',
          threadId: 'thread-1',
          recipientScope: 'broadcast',
          body: 'Medic team moving to zone 2.',
          authorDisplayName: 'Responder Kai',
          authorRole: 'department',
        ),
      );

      final drained = service.drainQueue();

      expect(drained[0].payloadType, MeshPayloadType.meshMessage);
      expect(drained[1].payloadType, MeshPayloadType.meshPost);
      expect(drained[2].payloadType, MeshPayloadType.incidentReport);
    });
  });
}
