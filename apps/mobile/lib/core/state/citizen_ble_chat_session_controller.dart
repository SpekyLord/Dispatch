import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/citizen_nearby_presence_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _chatSessionSentinel = Object();

enum CitizenBleChatSessionStatus { pending, accepted, rejected, expired, closed }

enum CitizenBleChatRoomStatus { active, closed, expired }

enum CitizenBleChatRoomMemberStatus { active, left }

enum NearbyCitizenBleAvailabilityStatus {
  ready,
  missingIdentity,
  awaitingBleDiscovery,
  identityMismatch,
  sessionPending,
  roomAvailable,
  roomJoined,
}

class NearbyCitizenBleAvailability {
  const NearbyCitizenBleAvailability({
    required this.userId,
    required this.status,
    required this.reason,
    required this.canRequest,
    required this.canJoin,
    this.matchedPeerDeviceId,
    this.lastSeenAt,
    this.activeRoomId,
    this.pendingSessionId,
    this.pendingIncoming = false,
  });

  final String userId;
  final NearbyCitizenBleAvailabilityStatus status;
  final String? reason;
  final String? matchedPeerDeviceId;
  final DateTime? lastSeenAt;
  final bool canRequest;
  final bool canJoin;
  final String? activeRoomId;
  final String? pendingSessionId;
  final bool pendingIncoming;
}

class CitizenBleChatRoomMember {
  const CitizenBleChatRoomMember({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.meshDeviceId,
    required this.displayName,
    required this.status,
    required this.joinedAt,
    this.leftAt,
  });

  factory CitizenBleChatRoomMember.fromJson(Map<String, dynamic> json) {
    return CitizenBleChatRoomMember(
      id: json['id'] as String? ?? '',
      roomId: json['room_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      meshDeviceId: json['mesh_device_id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? 'Nearby Citizen',
      status: _roomMemberStatusFromString(json['status'] as String?),
      joinedAt:
          DateTime.tryParse(json['joined_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      leftAt: DateTime.tryParse(json['left_at'] as String? ?? '')?.toUtc(),
    );
  }

  final String id;
  final String roomId;
  final String userId;
  final String meshDeviceId;
  final String displayName;
  final CitizenBleChatRoomMemberStatus status;
  final DateTime joinedAt;
  final DateTime? leftAt;

  bool get isActive => status == CitizenBleChatRoomMemberStatus.active;
}

class CitizenBleChatRoom {
  const CitizenBleChatRoom({
    required this.id,
    required this.creatorUserId,
    required this.status,
    required this.createdAt,
    required this.members,
    this.expiresAt,
    this.closedAt,
  });

  factory CitizenBleChatRoom.fromJson(Map<String, dynamic> json) {
    return CitizenBleChatRoom(
      id: json['id'] as String? ?? '',
      creatorUserId: json['creator_user_id'] as String? ?? '',
      status: _roomStatusFromString(json['status'] as String?),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      expiresAt:
          DateTime.tryParse(json['expires_at'] as String? ?? '')?.toUtc(),
      closedAt: DateTime.tryParse(json['closed_at'] as String? ?? '')?.toUtc(),
      members:
          (json['members'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map(
                (row) =>
                    CitizenBleChatRoomMember.fromJson(Map<String, dynamic>.from(row)),
              )
              .toList(growable: false),
    );
  }

  final String id;
  final String creatorUserId;
  final CitizenBleChatRoomStatus status;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? closedAt;
  final List<CitizenBleChatRoomMember> members;

  bool get isActive => status == CitizenBleChatRoomStatus.active;

  List<CitizenBleChatRoomMember> get activeMembers =>
      members.where((member) => member.isActive).toList(growable: false);

  bool hasActiveMember(String userId) =>
      activeMembers.any((member) => member.userId == userId);

  bool hasRemoteUser(String userId) =>
      activeMembers.any((member) => member.userId == userId);

  String threadId() => MeshTransportService.roomThreadId(id);
}

class CitizenBleChatSession {
  const CitizenBleChatSession({
    required this.id,
    required this.requesterUserId,
    required this.recipientUserId,
    required this.requesterMeshDeviceId,
    required this.recipientMeshDeviceId,
    required this.requesterDisplayName,
    required this.recipientDisplayName,
    required this.status,
    required this.createdAt,
    this.roomId,
    this.acceptedAt,
    this.expiresAt,
    this.closedAt,
  });

  factory CitizenBleChatSession.fromJson(Map<String, dynamic> json) {
    return CitizenBleChatSession(
      id: json['id'] as String? ?? '',
      requesterUserId: json['requester_user_id'] as String? ?? '',
      recipientUserId: json['recipient_user_id'] as String? ?? '',
      requesterMeshDeviceId:
          json['requester_mesh_device_id'] as String? ?? '',
      recipientMeshDeviceId:
          json['recipient_mesh_device_id'] as String? ?? '',
      requesterDisplayName:
          json['requester_display_name'] as String? ?? 'Nearby Citizen',
      recipientDisplayName:
          json['recipient_display_name'] as String? ?? 'Nearby Citizen',
      status: _statusFromString(json['status'] as String?),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      roomId: json['room_id'] as String?,
      acceptedAt:
          DateTime.tryParse(json['accepted_at'] as String? ?? '')?.toUtc(),
      expiresAt:
          DateTime.tryParse(json['expires_at'] as String? ?? '')?.toUtc(),
      closedAt: DateTime.tryParse(json['closed_at'] as String? ?? '')?.toUtc(),
    );
  }

  final String id;
  final String requesterUserId;
  final String recipientUserId;
  final String requesterMeshDeviceId;
  final String recipientMeshDeviceId;
  final String requesterDisplayName;
  final String recipientDisplayName;
  final CitizenBleChatSessionStatus status;
  final DateTime createdAt;
  final String? roomId;
  final DateTime? acceptedAt;
  final DateTime? expiresAt;
  final DateTime? closedAt;

  bool isParticipant(String userId) =>
      requesterUserId == userId || recipientUserId == userId;

  bool isPendingIncoming(String userId) =>
      recipientUserId == userId && status == CitizenBleChatSessionStatus.pending;

  bool isPendingOutgoing(String userId) =>
      requesterUserId == userId && status == CitizenBleChatSessionStatus.pending;

  bool isActiveFor(String userId) =>
      isParticipant(userId) && status == CitizenBleChatSessionStatus.accepted;

  String remoteUserId(String userId) =>
      requesterUserId == userId ? recipientUserId : requesterUserId;

  String remoteDisplayName(String userId) =>
      requesterUserId == userId ? recipientDisplayName : requesterDisplayName;

  String remoteMeshDeviceId(String userId) =>
      requesterUserId == userId
          ? recipientMeshDeviceId
          : requesterMeshDeviceId;

  String threadId() => MeshTransportService.ephemeralSessionThreadId(id);
}

CitizenBleChatSessionStatus _statusFromString(String? raw) {
  return switch ((raw ?? '').trim().toLowerCase()) {
    'accepted' => CitizenBleChatSessionStatus.accepted,
    'rejected' => CitizenBleChatSessionStatus.rejected,
    'expired' => CitizenBleChatSessionStatus.expired,
    'closed' => CitizenBleChatSessionStatus.closed,
    _ => CitizenBleChatSessionStatus.pending,
  };
}

CitizenBleChatRoomStatus _roomStatusFromString(String? raw) {
  return switch ((raw ?? '').trim().toLowerCase()) {
    'closed' => CitizenBleChatRoomStatus.closed,
    'expired' => CitizenBleChatRoomStatus.expired,
    _ => CitizenBleChatRoomStatus.active,
  };
}

CitizenBleChatRoomMemberStatus _roomMemberStatusFromString(String? raw) {
  return switch ((raw ?? '').trim().toLowerCase()) {
    'left' => CitizenBleChatRoomMemberStatus.left,
    _ => CitizenBleChatRoomMemberStatus.active,
  };
}

class CitizenBleChatSessionState {
  const CitizenBleChatSessionState({
    required this.sessions,
    required this.rooms,
    required this.subscribed,
    required this.lastError,
    required this.lastRefreshAt,
  });

  const CitizenBleChatSessionState.initial()
    : sessions = const [],
      rooms = const [],
      subscribed = false,
      lastError = null,
      lastRefreshAt = null;

  final List<CitizenBleChatSession> sessions;
  final List<CitizenBleChatRoom> rooms;
  final bool subscribed;
  final String? lastError;
  final DateTime? lastRefreshAt;

  CitizenBleChatSessionState copyWith({
    List<CitizenBleChatSession>? sessions,
    List<CitizenBleChatRoom>? rooms,
    bool? subscribed,
    Object? lastError = _chatSessionSentinel,
    Object? lastRefreshAt = _chatSessionSentinel,
  }) {
    return CitizenBleChatSessionState(
      sessions: sessions ?? this.sessions,
      rooms: rooms ?? this.rooms,
      subscribed: subscribed ?? this.subscribed,
      lastError: identical(lastError, _chatSessionSentinel)
          ? this.lastError
          : lastError as String?,
      lastRefreshAt: identical(lastRefreshAt, _chatSessionSentinel)
          ? this.lastRefreshAt
          : lastRefreshAt as DateTime?,
    );
  }
}

class CitizenBleChatSessionController
    extends StateNotifier<CitizenBleChatSessionState> {
  static const Duration _requestPeerFreshnessWindow = Duration(seconds: 30);
  static const Duration _roomPeerFreshnessWindow = Duration(seconds: 30);

  CitizenBleChatSessionController({
    required AuthService authService,
    required RealtimeService realtimeService,
    required MeshTransportService transport,
    Duration refreshInterval = const Duration(seconds: 5),
    Duration peerLossGracePeriod = const Duration(seconds: 30),
  }) : _authService = authService,
       _realtimeService = realtimeService,
       _transport = transport,
       _refreshInterval = refreshInterval,
       _peerLossGracePeriod = peerLossGracePeriod,
       super(const CitizenBleChatSessionState.initial()) {
    _transport.addListener(_handleTransportUpdated);
  }

  final AuthService _authService;
  final RealtimeService _realtimeService;
  final MeshTransportService _transport;
  final Duration _refreshInterval;
  final Duration _peerLossGracePeriod;

  final List<RealtimeSubscriptionHandle> _realtimeHandles = [];
  final Map<String, DateTime> _peerUnavailableSinceByRoom = {};
  Timer? _refreshTimer;
  bool _disposed = false;
  bool _refreshInFlight = false;
  String? _activeUserId;
  String? _displayName;

  CitizenBleChatSession? activeSession() {
    final userId = _activeUserId;
    if (userId == null) {
      return null;
    }
    for (final session in state.sessions) {
      if (session.isActiveFor(userId)) {
        return session;
      }
    }
    return null;
  }

  CitizenBleChatRoom? activeRoom() {
    final userId = _activeUserId;
    if (userId == null) {
      return null;
    }
    for (final room in state.rooms) {
      if (room.isActive && room.hasActiveMember(userId)) {
        return room;
      }
    }
    return null;
  }

  CitizenBleChatRoom? roomForId(String? roomId) {
    final normalized = roomId?.trim() ?? '';
    if (normalized.isEmpty) {
      return null;
    }
    for (final room in state.rooms) {
      if (room.id == normalized) {
        return room;
      }
    }
    return null;
  }

  CitizenBleChatRoom? roomForRemoteUser(String userId) {
    final normalized = userId.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (final room in state.rooms) {
      if (room.isActive && room.hasRemoteUser(normalized)) {
        return room;
      }
    }
    return null;
  }

  List<CitizenBleChatSession> pendingIncomingSessions() {
    final userId = _activeUserId;
    if (userId == null) {
      return const [];
    }
    return state.sessions
        .where((session) => session.isPendingIncoming(userId))
        .toList(growable: false);
  }

  CitizenBleChatSession? sessionForRemoteUser(String userId) {
    final currentUserId = _activeUserId;
    if (currentUserId == null) {
      return null;
    }
    for (final session in state.sessions) {
      if (session.remoteUserId(currentUserId) == userId &&
          (session.status == CitizenBleChatSessionStatus.pending ||
              session.status == CitizenBleChatSessionStatus.accepted)) {
        return session;
      }
    }
    return null;
  }

  bool isCurrentUserInRoom(CitizenBleChatRoom room) {
    final currentUserId = _activeUserId;
    if (currentUserId == null) {
      return false;
    }
    return room.hasActiveMember(currentUserId);
  }

  NearbyCitizenBleAvailability availabilityForPin(NearbyCitizenPin pin) {
    final normalizedUserId = pin.userId.trim();
    final normalizedDeviceId = pin.meshDeviceId.trim();
    final normalizedIdentityHash =
        pin.meshIdentityHash.trim().isNotEmpty
            ? pin.meshIdentityHash.trim()
            : (normalizedDeviceId.isNotEmpty
                ? MeshTransportService.meshIdentityHash(normalizedDeviceId)
                : '');
    final currentUserId = _activeUserId;
    final session = sessionForRemoteUser(normalizedUserId);
    final room = roomForRemoteUser(normalizedUserId);
    final peerMatch = _resolvePeerMatch(
      meshDeviceId: normalizedDeviceId,
      meshIdentityHash: normalizedIdentityHash,
    );
    final matchedPeer = peerMatch.peer;
    final matchedPeerDeviceId = (matchedPeer?.deviceId ?? '').trim();
    final peerSeenRecently =
        matchedPeer != null &&
        DateTime.now().toUtc().difference(matchedPeer.lastSeen.toUtc()) <=
            _requestPeerFreshnessWindow;

    if (room != null &&
        room.isActive &&
        currentUserId != null &&
        room.hasActiveMember(currentUserId)) {
      return NearbyCitizenBleAvailability(
        userId: normalizedUserId,
        status: NearbyCitizenBleAvailabilityStatus.roomJoined,
        reason: 'Temporary nearby room is active and ready to open.',
        matchedPeerDeviceId:
            peerSeenRecently && matchedPeerDeviceId.isNotEmpty
                ? matchedPeerDeviceId
                : null,
        lastSeenAt: matchedPeer?.lastSeen.toUtc(),
        canRequest: false,
        canJoin: false,
        activeRoomId: room.id,
      );
    }

    if (room != null && room.isActive) {
      final roomPeer = _resolveRoomPeer(room, currentUserId);
      final canJoin = roomPeer.peer != null && roomPeer.isRecent;
      return NearbyCitizenBleAvailability(
        userId: normalizedUserId,
        status: NearbyCitizenBleAvailabilityStatus.roomAvailable,
        reason: canJoin
            ? 'Nearby room is ready to join over BLE.'
            : 'Waiting for a live BLE peer match to a current room member.',
        matchedPeerDeviceId: canJoin ? roomPeer.peer!.deviceId?.trim() : null,
        lastSeenAt: roomPeer.peer?.lastSeen.toUtc(),
        canRequest: false,
        canJoin: canJoin,
        activeRoomId: room.id,
      );
    }

    if (session != null &&
        session.status == CitizenBleChatSessionStatus.pending) {
      final pendingIncoming =
          currentUserId != null && session.isPendingIncoming(currentUserId);
      return NearbyCitizenBleAvailability(
        userId: normalizedUserId,
        status: NearbyCitizenBleAvailabilityStatus.sessionPending,
        reason: pendingIncoming
            ? 'Open the incoming request prompt to accept or decline.'
            : 'Waiting for the other citizen to accept the BLE chat request.',
        matchedPeerDeviceId:
            peerSeenRecently && matchedPeerDeviceId.isNotEmpty
                ? matchedPeerDeviceId
                : null,
        lastSeenAt: matchedPeer?.lastSeen.toUtc(),
        canRequest: false,
        canJoin: false,
        pendingSessionId: session.id,
        pendingIncoming: pendingIncoming,
      );
    }

    if (normalizedDeviceId.isEmpty && normalizedIdentityHash.isEmpty) {
      return NearbyCitizenBleAvailability(
        userId: normalizedUserId,
        status: NearbyCitizenBleAvailabilityStatus.missingIdentity,
        reason: 'Nearby citizen has not published a mesh device id yet.',
        canRequest: false,
        canJoin: false,
      );
    }

    if (peerMatch.identityMismatch) {
      return NearbyCitizenBleAvailability(
        userId: normalizedUserId,
        status: NearbyCitizenBleAvailabilityStatus.identityMismatch,
        reason: 'BLE peer discovered, but identity does not match this nearby citizen.',
        matchedPeerDeviceId:
            matchedPeerDeviceId.isNotEmpty ? matchedPeerDeviceId : null,
        lastSeenAt: matchedPeer?.lastSeen.toUtc(),
        canRequest: false,
        canJoin: false,
      );
    }

    if (peerSeenRecently) {
      return NearbyCitizenBleAvailability(
        userId: normalizedUserId,
        status: NearbyCitizenBleAvailabilityStatus.ready,
        reason: 'BLE nearby and ready.',
        matchedPeerDeviceId:
            matchedPeerDeviceId.isNotEmpty ? matchedPeerDeviceId : null,
        lastSeenAt: matchedPeer.lastSeen.toUtc(),
        canRequest: true,
        canJoin: false,
      );
    }

    return NearbyCitizenBleAvailability(
      userId: normalizedUserId,
      status: NearbyCitizenBleAvailabilityStatus.awaitingBleDiscovery,
      reason: 'Waiting for a live BLE peer match before requesting.',
      matchedPeerDeviceId:
          matchedPeerDeviceId.isNotEmpty ? matchedPeerDeviceId : null,
      lastSeenAt: matchedPeer?.lastSeen.toUtc(),
      canRequest: false,
      canJoin: false,
    );
  }

  bool canRequestChatForPin(NearbyCitizenPin pin) {
    return availabilityForPin(pin).canRequest;
  }

  String? requestAvailabilityReason(NearbyCitizenPin pin) {
    return availabilityForPin(pin).canRequest ? null : availabilityForPin(pin).reason;
  }

  bool canJoinRoomForPin(NearbyCitizenPin pin) {
    return availabilityForPin(pin).canJoin;
  }

  String? joinAvailabilityReason(NearbyCitizenPin pin) {
    final availability = availabilityForPin(pin);
    return availability.canJoin ? null : availability.reason;
  }

  Future<void> start({
    required String userId,
    required String displayName,
  }) async {
    if (_disposed) {
      return;
    }
    _activeUserId = userId;
    _displayName = displayName.trim();
    if (_realtimeHandles.isEmpty) {
      _realtimeHandles.addAll([
        _realtimeService.subscribeToTable(
          table: 'citizen_ble_chat_sessions',
          onChange: () => unawaited(refresh()),
        ),
        _realtimeService.subscribeToTable(
          table: 'citizen_ble_chat_rooms',
          onChange: () => unawaited(refresh()),
        ),
        _realtimeService.subscribeToTable(
          table: 'citizen_ble_chat_room_members',
          onChange: () => unawaited(refresh()),
        ),
      ]);
    }
    _refreshTimer ??= Timer.periodic(_refreshInterval, (_) {
      unawaited(_tick());
    });
    state = state.copyWith(subscribed: true, lastError: null);
    await refresh();
  }

  Future<void> stop() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    for (final handle in _realtimeHandles) {
      await handle.dispose();
    }
    _realtimeHandles.clear();
    if (_disposed) {
      return;
    }
    _peerUnavailableSinceByRoom.clear();
    _transport.setActiveEphemeralRoomIds(const []);
    state = state.copyWith(
      subscribed: false,
      sessions: const [],
      rooms: const [],
      lastError: null,
    );
  }

  Future<void> requestChatForPin(NearbyCitizenPin pin) async {
    if (_disposed || _activeUserId == null || _displayName == null) {
      return;
    }
    if (!canRequestChatForPin(pin)) {
      return;
    }
    try {
      final response = await _authService.requestCitizenBleChat(
        recipientUserId: pin.userId,
        requesterMeshDeviceId: _transport.localDeviceId,
        recipientMeshDeviceId: pin.meshDeviceId,
        requesterDisplayName: _displayName!,
        recipientDisplayName: pin.displayName,
      );
      final session = CitizenBleChatSession.fromJson(
        Map<String, dynamic>.from(
          (response['session'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
      );
      _mergeSession(session);
      state = state.copyWith(lastError: null);
    } catch (error) {
      state = state.copyWith(lastError: _describeError(error));
    }
  }

  Future<void> respondToSession({
    required CitizenBleChatSession session,
    required bool accept,
  }) async {
    try {
      final previousRooms = state.rooms;
      final response = await _authService.respondToCitizenBleChat(
        sessionId: session.id,
        accept: accept,
      );
      final updated = CitizenBleChatSession.fromJson(
        Map<String, dynamic>.from(
          (response['session'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
      );
      _mergeSession(updated);
      final roomData = response['room'];
      if (roomData is Map) {
        _mergeRoom(
          CitizenBleChatRoom.fromJson(Map<String, dynamic>.from(roomData)),
        );
      } else if (accept) {
        await refresh();
      }
      if (!accept) {
        _transport.clearSession(session.id);
      }
      _synchronizeTransportRoomMemberships(previousRooms: previousRooms);
      state = state.copyWith(lastError: null);
    } catch (error) {
      state = state.copyWith(lastError: _describeError(error));
    }
  }

  Future<void> closeSession(CitizenBleChatSession session) async {
    try {
      final response = await _authService.closeCitizenBleChat(
        sessionId: session.id,
      );
      final updated = CitizenBleChatSession.fromJson(
        Map<String, dynamic>.from(
          (response['session'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
      );
      _mergeSession(updated);
      _transport.clearSession(session.id);
      state = state.copyWith(lastError: null);
    } catch (error) {
      state = state.copyWith(lastError: _describeError(error));
    }
  }

  Future<void> joinRoomForPin(NearbyCitizenPin pin) async {
    final room = roomForRemoteUser(pin.userId);
    if (_displayName == null || room == null || !canJoinRoomForPin(pin)) {
      return;
    }
    try {
      final response = await _authService.joinCitizenBleChatRoom(
        roomId: room.id,
        meshDeviceId: _transport.localDeviceId,
        displayName: _displayName!,
      );
      final updated = CitizenBleChatRoom.fromJson(
        Map<String, dynamic>.from(
          (response['room'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
      );
      final previousRooms = state.rooms;
      _mergeRoom(updated);
      _synchronizeTransportRoomMemberships(previousRooms: previousRooms);
      state = state.copyWith(lastError: null);
    } catch (error) {
      state = state.copyWith(lastError: _describeError(error));
    }
  }

  Future<void> leaveRoom(CitizenBleChatRoom room) async {
    try {
      final previousRooms = state.rooms;
      final response = await _authService.leaveCitizenBleChatRoom(roomId: room.id);
      final updated = CitizenBleChatRoom.fromJson(
        Map<String, dynamic>.from(
          (response['room'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
      );
      _mergeRoom(updated);
      _transport.clearRoom(room.id);
      _synchronizeTransportRoomMemberships(previousRooms: previousRooms);
      state = state.copyWith(lastError: null);
    } catch (error) {
      state = state.copyWith(lastError: _describeError(error));
    }
  }

  Future<void> refresh() async {
    if (_disposed || _refreshInFlight || _activeUserId == null) {
      return;
    }
    _refreshInFlight = true;
    final previousSessions = state.sessions;
    final previousRooms = state.rooms;
    try {
      final sessionResponse = await _authService.listCitizenBleChatSessions();
      final roomResponse = await _authService.listCitizenBleChatRooms();
      final sessions =
          (sessionResponse['sessions'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map(
                (row) =>
                    CitizenBleChatSession.fromJson(Map<String, dynamic>.from(row)),
              )
              .toList(growable: false)
            ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
      final rooms =
          (roomResponse['rooms'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map(
                (row) => CitizenBleChatRoom.fromJson(Map<String, dynamic>.from(row)),
              )
              .toList(growable: false)
            ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
      state = state.copyWith(
        sessions: sessions,
        rooms: rooms,
        lastRefreshAt: DateTime.now().toUtc(),
        lastError: null,
      );
      _clearRemovedSessions(previousSessions: previousSessions, currentSessions: sessions);
      _synchronizeTransportRoomMemberships(previousRooms: previousRooms);
      _evaluateActiveRoomPeers();
    } catch (error) {
      state = state.copyWith(lastError: _describeError(error));
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> _tick() async {
    if (_disposed) {
      return;
    }
    _evaluateActiveRoomPeers();
    await refresh();
  }

  void _handleTransportUpdated() {
    if (_disposed) {
      return;
    }
    _evaluateActiveRoomPeers();
  }

  void _evaluateActiveRoomPeers() {
    final currentUserId = _activeUserId;
    if (currentUserId == null) {
      _peerUnavailableSinceByRoom.clear();
      return;
    }
    final activeRooms = state.rooms
        .where((room) => room.isActive && room.hasActiveMember(currentUserId))
        .toList(growable: false);
    final activeIds = activeRooms.map((room) => room.id).toSet();
    _peerUnavailableSinceByRoom.removeWhere((roomId, _) => !activeIds.contains(roomId));

    for (final room in activeRooms) {
      final hasPeer = room.activeMembers.any(
        (member) =>
            member.userId != currentUserId &&
            _peerForMeshDeviceIdOrHash(member.meshDeviceId) != null,
      );
      if (hasPeer) {
        _peerUnavailableSinceByRoom.remove(room.id);
        continue;
      }
      final now = DateTime.now().toUtc();
      final firstUnavailableAt = _peerUnavailableSinceByRoom.putIfAbsent(
        room.id,
        () => now,
      );
      if (now.difference(firstUnavailableAt) >= _peerLossGracePeriod) {
        unawaited(leaveRoom(room));
        _peerUnavailableSinceByRoom.remove(room.id);
      }
    }
  }

  void _synchronizeTransportRoomMemberships({
    required List<CitizenBleChatRoom> previousRooms,
  }) {
    final previousIds = _currentUserActiveRoomIds(previousRooms);
    final currentIds = _currentUserActiveRoomIds(state.rooms);
    for (final roomId in previousIds.difference(currentIds)) {
      _transport.clearRoom(roomId);
    }
    _transport.setActiveEphemeralRoomIds(currentIds);
  }

  Set<String> _currentUserActiveRoomIds(List<CitizenBleChatRoom> rooms) {
    final currentUserId = _activeUserId;
    if (currentUserId == null) {
      return <String>{};
    }
    return rooms
        .where((room) => room.isActive && room.hasActiveMember(currentUserId))
        .map((room) => room.id)
        .toSet();
  }

  void _clearRemovedSessions({
    required List<CitizenBleChatSession> previousSessions,
    required List<CitizenBleChatSession> currentSessions,
  }) {
    final currentIds = currentSessions.map((session) => session.id).toSet();
    for (final session in previousSessions) {
      if (!currentIds.contains(session.id)) {
        _transport.clearSession(session.id);
      }
    }
  }

  void _mergeSession(CitizenBleChatSession session) {
    final sessions = List<CitizenBleChatSession>.from(state.sessions);
    final index = sessions.indexWhere((item) => item.id == session.id);
    if (index >= 0) {
      sessions[index] = session;
    } else {
      sessions.add(session);
    }
    sessions.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    state = state.copyWith(sessions: sessions);
  }

  void _mergeRoom(CitizenBleChatRoom room) {
    final rooms = List<CitizenBleChatRoom>.from(state.rooms);
    final index = rooms.indexWhere((item) => item.id == room.id);
    if (index >= 0) {
      rooms[index] = room;
    } else {
      rooms.add(room);
    }
    rooms.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    state = state.copyWith(rooms: rooms);
  }

  String _describeError(Object error) {
    if (error is DioException) {
      final payload = error.response?.data;
      if (payload is Map<String, dynamic>) {
        final apiError = payload['error'];
        if (apiError is Map<String, dynamic>) {
          final message = apiError['message'] as String?;
          if (message != null && message.trim().isNotEmpty) {
            return message.trim();
          }
        }
      }
      if (error.message != null && error.message!.trim().isNotEmpty) {
        return error.message!.trim();
      }
    }
    return error.toString();
  }

  _BlePeerResolution _resolvePeerMatch({
    required String meshDeviceId,
    required String meshIdentityHash,
  }) {
    final devicePeer = _transport.peerForDeviceId(meshDeviceId);
    final hashPeer = _transport.peerForMeshIdentityHash(meshIdentityHash);
    final matchedPeer = devicePeer ?? hashPeer;
    var identityMismatch = false;

    if (devicePeer != null &&
        meshIdentityHash.isNotEmpty &&
        (devicePeer.meshIdentityHash ?? '').trim().isNotEmpty &&
        (devicePeer.meshIdentityHash ?? '').trim().toUpperCase() !=
            meshIdentityHash.trim().toUpperCase()) {
      identityMismatch = true;
    }

    if (hashPeer != null &&
        meshDeviceId.isNotEmpty &&
        (hashPeer.deviceId ?? '').trim().isNotEmpty &&
        (hashPeer.deviceId ?? '').trim() != meshDeviceId.trim()) {
      identityMismatch = true;
    }

    return _BlePeerResolution(
      peer: matchedPeer,
      identityMismatch: identityMismatch,
    );
  }

  _RoomPeerAvailability _resolveRoomPeer(
    CitizenBleChatRoom room,
    String? currentUserId,
  ) {
    for (final member in room.activeMembers) {
      if (member.userId == currentUserId) {
        continue;
      }
      final peer = _peerForMeshDeviceIdOrHash(member.meshDeviceId);
      if (peer == null) {
        continue;
      }
      final isRecent =
          DateTime.now().toUtc().difference(peer.lastSeen.toUtc()) <=
              _roomPeerFreshnessWindow;
      return _RoomPeerAvailability(peer: peer, isRecent: isRecent);
    }
    return const _RoomPeerAvailability(peer: null, isRecent: false);
  }

  MeshPeer? _peerForMeshDeviceIdOrHash(String meshDeviceId) {
    final normalizedDeviceId = meshDeviceId.trim();
    if (normalizedDeviceId.isEmpty) {
      return null;
    }
    final devicePeer = _transport.peerForDeviceId(normalizedDeviceId);
    if (devicePeer != null) {
      return devicePeer;
    }
    return _transport.peerForMeshIdentityHash(
      MeshTransportService.meshIdentityHash(normalizedDeviceId),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    for (final handle in _realtimeHandles) {
      unawaited(handle.dispose());
    }
    _transport.setActiveEphemeralRoomIds(const []);
    _transport.removeListener(_handleTransportUpdated);
    super.dispose();
  }
}

class _BlePeerResolution {
  const _BlePeerResolution({
    required this.peer,
    required this.identityMismatch,
  });

  final MeshPeer? peer;
  final bool identityMismatch;
}

class _RoomPeerAvailability {
  const _RoomPeerAvailability({
    required this.peer,
    required this.isRecent,
  });

  final MeshPeer? peer;
  final bool isRecent;
}
