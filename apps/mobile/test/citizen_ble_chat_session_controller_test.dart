import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/citizen_ble_chat_session_controller.dart';
import 'package:dispatch_mobile/core/state/citizen_nearby_presence_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRealtimeService extends RealtimeService {
  _FakeRealtimeService() : super();
}

class _FakeAuthService extends AuthService {
  Map<String, dynamic> listSessionsResponse = const {'sessions': []};
  Map<String, dynamic> listRoomsResponse = const {'rooms': []};
  Map<String, dynamic> requestResponse = const {};
  Map<String, dynamic> respondResponse = const {};
  Map<String, dynamic> joinResponse = const {};
  Map<String, dynamic> leaveResponse = const {};

  @override
  Future<Map<String, dynamic>> listCitizenBleChatSessions({
    int limit = 50,
  }) async {
    return listSessionsResponse;
  }

  @override
  Future<Map<String, dynamic>> listCitizenBleChatRooms({
    int limit = 50,
  }) async {
    return listRoomsResponse;
  }

  @override
  Future<Map<String, dynamic>> requestCitizenBleChat({
    required String recipientUserId,
    required String requesterMeshDeviceId,
    required String recipientMeshDeviceId,
    required String requesterDisplayName,
    required String recipientDisplayName,
  }) async {
    return requestResponse;
  }

  @override
  Future<Map<String, dynamic>> respondToCitizenBleChat({
    required String sessionId,
    required bool accept,
  }) async {
    return respondResponse;
  }

  @override
  Future<Map<String, dynamic>> joinCitizenBleChatRoom({
    required String roomId,
    required String meshDeviceId,
    required String displayName,
  }) async {
    return joinResponse;
  }

  @override
  Future<Map<String, dynamic>> leaveCitizenBleChatRoom({
    required String roomId,
  }) async {
    return leaveResponse;
  }
}

Map<String, dynamic> _roomJson({
  required String roomId,
  required List<Map<String, dynamic>> members,
}) {
  return {
    'id': roomId,
    'creator_user_id': 'citizen-1',
    'status': 'active',
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'expires_at': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 10))
        .toIso8601String(),
    'closed_at': null,
    'members': members,
  };
}

Map<String, dynamic> _memberJson({
  required String roomId,
  required String userId,
  required String meshDeviceId,
  required String displayName,
}) {
  return {
    'id': '$roomId:$userId',
    'room_id': roomId,
    'user_id': userId,
    'mesh_device_id': meshDeviceId,
    'display_name': displayName,
    'status': 'active',
    'joined_at': DateTime.now().toUtc().toIso8601String(),
    'left_at': null,
  };
}

void main() {
  test('availability resolves to awaiting BLE discovery when the peer is not live yet', () async {
    final auth = _FakeAuthService();
    final transport = MeshTransportService(automaticLocationBeaconing: false);
    addTearDown(transport.dispose);
    final controller = CitizenBleChatSessionController(
      authService: auth,
      realtimeService: _FakeRealtimeService(),
      transport: transport,
    );
    addTearDown(controller.dispose);

    await controller.start(userId: 'citizen-1', displayName: 'Citizen One');
    final pin = NearbyCitizenPin(
      userId: 'citizen-2',
      displayName: 'Citizen Two',
      meshDeviceId: 'mesh-device-2',
      meshIdentityHash: MeshTransportService.meshIdentityHash('mesh-device-2'),
      latitude: 14.5995,
      longitude: 120.9842,
      accuracyMeters: 8,
      lastSeenAt: DateTime.now().toUtc(),
      distanceMeters: 6,
    );

    final availability = controller.availabilityForPin(pin);
    expect(
      availability.status,
      NearbyCitizenBleAvailabilityStatus.awaitingBleDiscovery,
    );
    expect(availability.canRequest, isFalse);
  });

  test('availability resolves to missing identity when the nearby citizen has no BLE identity', () async {
    final auth = _FakeAuthService();
    final transport = MeshTransportService(automaticLocationBeaconing: false);
    addTearDown(transport.dispose);
    final controller = CitizenBleChatSessionController(
      authService: auth,
      realtimeService: _FakeRealtimeService(),
      transport: transport,
    );
    addTearDown(controller.dispose);

    await controller.start(userId: 'citizen-1', displayName: 'Citizen One');
    final pin = NearbyCitizenPin(
      userId: 'citizen-2',
      displayName: 'Citizen Two',
      meshDeviceId: '',
      meshIdentityHash: '',
      latitude: 14.5995,
      longitude: 120.9842,
      accuracyMeters: 8,
      lastSeenAt: DateTime.now().toUtc(),
      distanceMeters: 6,
    );

    final availability = controller.availabilityForPin(pin);
    expect(
      availability.status,
      NearbyCitizenBleAvailabilityStatus.missingIdentity,
    );
    expect(availability.canRequest, isFalse);
  });

  test('availability resolves to ready from mesh identity hash when the device peer id is not present', () async {
    final auth = _FakeAuthService();
    final transport = MeshTransportService(automaticLocationBeaconing: false);
    addTearDown(transport.dispose);
    final controller = CitizenBleChatSessionController(
      authService: auth,
      realtimeService: _FakeRealtimeService(),
      transport: transport,
    );
    addTearDown(controller.dispose);

    await controller.start(userId: 'citizen-1', displayName: 'Citizen One');
    final hash = MeshTransportService.meshIdentityHash('mesh-device-2');
    transport.onPeerDiscovered(
      'endpoint-2',
      'Citizen Two',
      meshIdentityHash: hash,
      isConnected: true,
    );
    final pin = NearbyCitizenPin(
      userId: 'citizen-2',
      displayName: 'Citizen Two',
      meshDeviceId: 'mesh-device-2',
      meshIdentityHash: hash,
      latitude: 14.5995,
      longitude: 120.9842,
      accuracyMeters: 8,
      lastSeenAt: DateTime.now().toUtc(),
      distanceMeters: 6,
    );

    final availability = controller.availabilityForPin(pin);
    expect(availability.status, NearbyCitizenBleAvailabilityStatus.ready);
    expect(availability.canRequest, isTrue);
  });

  test('availability resolves to identity mismatch when BLE peer identity conflicts', () async {
    final auth = _FakeAuthService();
    final transport = MeshTransportService(automaticLocationBeaconing: false);
    addTearDown(transport.dispose);
    final controller = CitizenBleChatSessionController(
      authService: auth,
      realtimeService: _FakeRealtimeService(),
      transport: transport,
    );
    addTearDown(controller.dispose);

    await controller.start(userId: 'citizen-1', displayName: 'Citizen One');
    transport.onPeerDiscovered(
      'endpoint-2',
      'Citizen Two',
      deviceId: 'mesh-device-2',
      meshIdentityHash: 'WRONG-HASH',
      isConnected: true,
    );
    final pin = NearbyCitizenPin(
      userId: 'citizen-2',
      displayName: 'Citizen Two',
      meshDeviceId: 'mesh-device-2',
      meshIdentityHash: MeshTransportService.meshIdentityHash('mesh-device-2'),
      latitude: 14.5995,
      longitude: 120.9842,
      accuracyMeters: 8,
      lastSeenAt: DateTime.now().toUtc(),
      distanceMeters: 6,
    );

    final availability = controller.availabilityForPin(pin);
    expect(
      availability.status,
      NearbyCitizenBleAvailabilityStatus.identityMismatch,
    );
    expect(availability.canRequest, isFalse);
  });

  test('BLE match allows request even when GPS distance is outside the old threshold', () async {
    final auth = _FakeAuthService();
    final transport = MeshTransportService(automaticLocationBeaconing: false);
    addTearDown(transport.dispose);
    final controller = CitizenBleChatSessionController(
      authService: auth,
      realtimeService: _FakeRealtimeService(),
      transport: transport,
    );
    addTearDown(controller.dispose);

    await controller.start(userId: 'citizen-1', displayName: 'Citizen One');
    final pin = NearbyCitizenPin(
      userId: 'citizen-2',
      displayName: 'Citizen Two',
      meshDeviceId: 'mesh-device-2',
      meshIdentityHash: MeshTransportService.meshIdentityHash('mesh-device-2'),
      latitude: 14.5995,
      longitude: 120.9842,
      accuracyMeters: 8,
      lastSeenAt: DateTime.now().toUtc(),
      distanceMeters: 42,
    );

    expect(controller.canRequestChatForPin(pin), isFalse);
    expect(
      controller.requestAvailabilityReason(pin),
      'Waiting for a live BLE peer match before requesting.',
    );

    transport.onPeerDiscovered(
      'endpoint-2',
      'Citizen Two',
      deviceId: 'mesh-device-2',
      meshIdentityHash: MeshTransportService.meshIdentityHash('mesh-device-2'),
      isConnected: true,
    );

    expect(controller.canRequestChatForPin(pin), isTrue);
    expect(controller.requestAvailabilityReason(pin), isNull);
  });

  test('request success transitions immediately into a pending session state', () async {
    final auth = _FakeAuthService();
    final transport = MeshTransportService(automaticLocationBeaconing: false);
    addTearDown(transport.dispose);
    final controller = CitizenBleChatSessionController(
      authService: auth,
      realtimeService: _FakeRealtimeService(),
      transport: transport,
    );
    addTearDown(controller.dispose);

    await controller.start(userId: 'citizen-1', displayName: 'Citizen One');
    transport.onPeerDiscovered(
      'endpoint-2',
      'Citizen Two',
      deviceId: 'mesh-device-2',
      meshIdentityHash: MeshTransportService.meshIdentityHash('mesh-device-2'),
      isConnected: true,
    );
    final pin = NearbyCitizenPin(
      userId: 'citizen-2',
      displayName: 'Citizen Two',
      meshDeviceId: 'mesh-device-2',
      meshIdentityHash: MeshTransportService.meshIdentityHash('mesh-device-2'),
      latitude: 14.5995,
      longitude: 120.9842,
      accuracyMeters: 8,
      lastSeenAt: DateTime.now().toUtc(),
      distanceMeters: 6,
    );
    auth.requestResponse = {
      'session': {
        'id': 'session-1',
        'requester_user_id': 'citizen-1',
        'recipient_user_id': 'citizen-2',
        'requester_mesh_device_id': transport.localDeviceId,
        'recipient_mesh_device_id': 'mesh-device-2',
        'requester_display_name': 'Citizen One',
        'recipient_display_name': 'Citizen Two',
        'status': 'pending',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(seconds: 30))
            .toIso8601String(),
      },
    };

    await controller.requestChatForPin(pin);

    expect(controller.state.sessions, hasLength(1));
    expect(controller.state.sessions.single.status, CitizenBleChatSessionStatus.pending);
    final availability = controller.availabilityForPin(pin);
    expect(availability.status, NearbyCitizenBleAvailabilityStatus.sessionPending);
  });

  test('accepting a BLE request creates a room with the original pair', () async {
    final auth = _FakeAuthService();
    final transport = MeshTransportService(automaticLocationBeaconing: false);
    addTearDown(transport.dispose);
    final controller = CitizenBleChatSessionController(
      authService: auth,
      realtimeService: _FakeRealtimeService(),
      transport: transport,
    );
    addTearDown(controller.dispose);

    await controller.start(userId: 'citizen-2', displayName: 'Citizen Two');
    final incoming = CitizenBleChatSession.fromJson({
      'id': 'session-1',
      'requester_user_id': 'citizen-1',
      'recipient_user_id': 'citizen-2',
      'requester_mesh_device_id': 'mesh-device-1',
      'recipient_mesh_device_id': 'mesh-device-2',
      'requester_display_name': 'Citizen One',
      'recipient_display_name': 'Citizen Two',
      'status': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(seconds: 30))
          .toIso8601String(),
    });
    auth.respondResponse = {
      'session': {
        'id': 'session-1',
        'room_id': 'room-1',
        'requester_user_id': 'citizen-1',
        'recipient_user_id': 'citizen-2',
        'requester_mesh_device_id': 'mesh-device-1',
        'recipient_mesh_device_id': 'mesh-device-2',
        'requester_display_name': 'Citizen One',
        'recipient_display_name': 'Citizen Two',
        'status': 'accepted',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'accepted_at': DateTime.now().toUtc().toIso8601String(),
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(seconds: 30))
            .toIso8601String(),
      },
      'room': _roomJson(
        roomId: 'room-1',
        members: [
          _memberJson(
            roomId: 'room-1',
            userId: 'citizen-1',
            meshDeviceId: 'mesh-device-1',
            displayName: 'Citizen One',
          ),
          _memberJson(
            roomId: 'room-1',
            userId: 'citizen-2',
            meshDeviceId: 'mesh-device-2',
            displayName: 'Citizen Two',
          ),
        ],
      ),
    };

    await controller.respondToSession(session: incoming, accept: true);

    expect(controller.state.rooms, hasLength(1));
    expect(controller.state.rooms.first.id, 'room-1');
    expect(controller.state.rooms.first.activeMembers, hasLength(2));
    expect(controller.state.sessions.single.roomId, 'room-1');
  });

  test('nearby room join is only enabled with a live BLE peer match', () async {
    final auth = _FakeAuthService();
    final transport = MeshTransportService(automaticLocationBeaconing: false);
    addTearDown(transport.dispose);
    auth.listRoomsResponse = {
      'rooms': [
        _roomJson(
          roomId: 'room-join',
          members: [
            _memberJson(
              roomId: 'room-join',
              userId: 'citizen-2',
              meshDeviceId: 'mesh-device-2',
              displayName: 'Citizen Two',
            ),
          ],
        ),
      ],
    };
    final controller = CitizenBleChatSessionController(
      authService: auth,
      realtimeService: _FakeRealtimeService(),
      transport: transport,
    );
    addTearDown(controller.dispose);

    await controller.start(userId: 'citizen-3', displayName: 'Citizen Three');
    final pin = NearbyCitizenPin(
      userId: 'citizen-2',
      displayName: 'Citizen Two',
      meshDeviceId: 'mesh-device-2',
      meshIdentityHash: MeshTransportService.meshIdentityHash('mesh-device-2'),
      latitude: 14.5995,
      longitude: 120.9842,
      accuracyMeters: 8,
      lastSeenAt: DateTime.now().toUtc(),
      distanceMeters: 36,
    );

    expect(controller.canJoinRoomForPin(pin), isFalse);
    expect(
      controller.joinAvailabilityReason(pin),
      'Waiting for a live BLE peer match to a current room member.',
    );

    transport.onPeerDiscovered(
      'endpoint-2',
      'Citizen Two',
      deviceId: 'mesh-device-2',
      meshIdentityHash: MeshTransportService.meshIdentityHash('mesh-device-2'),
      isConnected: true,
    );

    expect(controller.canJoinRoomForPin(pin), isTrue);
    expect(controller.joinAvailabilityReason(pin), isNull);
  });

  test('leaving a room clears local room thread messages', () async {
    final auth = _FakeAuthService();
    final transport = MeshTransportService(automaticLocationBeaconing: false);
    addTearDown(transport.dispose);
    final room = CitizenBleChatRoom.fromJson(
      _roomJson(
        roomId: 'room-leave',
        members: [
          _memberJson(
            roomId: 'room-leave',
            userId: 'citizen-1',
            meshDeviceId: transport.localDeviceId,
            displayName: 'Citizen One',
          ),
          _memberJson(
            roomId: 'room-leave',
            userId: 'citizen-2',
            meshDeviceId: 'mesh-device-2',
            displayName: 'Citizen Two',
          ),
        ],
      ),
    );
    final controller = CitizenBleChatSessionController(
      authService: auth,
      realtimeService: _FakeRealtimeService(),
      transport: transport,
    );
    addTearDown(controller.dispose);

    auth.listRoomsResponse = {'rooms': [_roomJson(roomId: 'room-leave', members: [
      _memberJson(
        roomId: 'room-leave',
        userId: 'citizen-1',
        meshDeviceId: transport.localDeviceId,
        displayName: 'Citizen One',
      ),
      _memberJson(
        roomId: 'room-leave',
        userId: 'citizen-2',
        meshDeviceId: 'mesh-device-2',
        displayName: 'Citizen Two',
      ),
    ])]};
    await controller.start(userId: 'citizen-1', displayName: 'Citizen One');
    final packet = MeshTransportService.createMeshMessagePacket(
      deviceId: transport.localDeviceId,
      threadId: room.threadId(),
      recipientScope: 'room',
      roomId: room.id,
      body: 'Temporary room message',
      authorDisplayName: 'Citizen One',
      authorRole: 'citizen',
      ephemeral: true,
    );
    transport.enqueuePacket(packet);
    expect(transport.threadItems(room.threadId()), hasLength(1));

    auth.leaveResponse = {
      'room': {
        ..._roomJson(roomId: 'room-leave', members: [
          {
            ..._memberJson(
              roomId: 'room-leave',
              userId: 'citizen-1',
              meshDeviceId: transport.localDeviceId,
              displayName: 'Citizen One',
            ),
            'status': 'left',
            'left_at': DateTime.now().toUtc().toIso8601String(),
          },
        ]),
        'status': 'closed',
        'closed_at': DateTime.now().toUtc().toIso8601String(),
      },
    };

    await controller.leaveRoom(room);

    expect(transport.threadItems(room.threadId()), isEmpty);
  });
}
