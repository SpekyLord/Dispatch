import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/citizen_nearby_presence_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _chatSessionSentinel = Object();

enum CitizenBleChatSessionStatus { pending, accepted, rejected, expired, closed }

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

class CitizenBleChatSessionState {
  const CitizenBleChatSessionState({
    required this.sessions,
    required this.subscribed,
    required this.lastError,
    required this.lastRefreshAt,
  });

  const CitizenBleChatSessionState.initial()
    : sessions = const [],
      subscribed = false,
      lastError = null,
      lastRefreshAt = null;

  final List<CitizenBleChatSession> sessions;
  final bool subscribed;
  final String? lastError;
  final DateTime? lastRefreshAt;

  CitizenBleChatSessionState copyWith({
    List<CitizenBleChatSession>? sessions,
    bool? subscribed,
    Object? lastError = _chatSessionSentinel,
    Object? lastRefreshAt = _chatSessionSentinel,
  }) {
    return CitizenBleChatSessionState(
      sessions: sessions ?? this.sessions,
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

  RealtimeSubscriptionHandle? _realtimeHandle;
  Timer? _refreshTimer;
  bool _disposed = false;
  bool _refreshInFlight = false;
  String? _activeUserId;
  String? _displayName;
  DateTime? _peerUnavailableSince;

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

  bool canRequestChatForPin(NearbyCitizenPin pin) {
    if (pin.meshDeviceId.trim().isEmpty) {
      return false;
    }
    if (pin.distanceMeters > 20) {
      return false;
    }
    return _transport.hasPeerForDeviceId(pin.meshDeviceId) ||
        _transport.hasPeerForMeshIdentityHash(pin.meshIdentityHash);
  }

  String? requestAvailabilityReason(NearbyCitizenPin pin) {
    if (pin.meshDeviceId.trim().isEmpty) {
      return 'Nearby citizen has not published a mesh device id yet.';
    }
    if (pin.distanceMeters > 20) {
      return 'Move within about 20m so BLE pairing is reliable.';
    }
    if (!_transport.hasPeerForDeviceId(pin.meshDeviceId) &&
        !_transport.hasPeerForMeshIdentityHash(pin.meshIdentityHash)) {
      return 'Waiting for a live BLE peer match before requesting.';
    }
    return null;
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
    _realtimeHandle ??= _realtimeService.subscribeToTable(
      table: 'citizen_ble_chat_sessions',
      onChange: () => unawaited(refreshSessions()),
    );
    _refreshTimer ??= Timer.periodic(_refreshInterval, (_) {
      unawaited(_tick());
    });
    state = state.copyWith(subscribed: true, lastError: null);
    await refreshSessions();
  }

  Future<void> stop() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    await _realtimeHandle?.dispose();
    _realtimeHandle = null;
    if (_disposed) {
      return;
    }
    _peerUnavailableSince = null;
    state = state.copyWith(
      subscribed: false,
      sessions: const [],
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
      if (!accept) {
        _transport.clearSession(session.id);
      }
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

  Future<void> refreshSessions() async {
    if (_disposed || _refreshInFlight || _activeUserId == null) {
      return;
    }
    _refreshInFlight = true;
    final previousActiveSessionId = activeSession()?.id;
    try {
      final response = await _authService.listCitizenBleChatSessions();
      final sessions =
          (response['sessions'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((row) => CitizenBleChatSession.fromJson(Map<String, dynamic>.from(row)))
              .toList(growable: false)
            ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
      state = state.copyWith(
        sessions: sessions,
        lastRefreshAt: DateTime.now().toUtc(),
        lastError: null,
      );
      final active = activeSession();
      if (previousActiveSessionId != null &&
          (active == null || active.id != previousActiveSessionId)) {
        _transport.clearSession(previousActiveSessionId);
      }
      _evaluateActiveSessionPeer();
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
    _evaluateActiveSessionPeer();
    await refreshSessions();
  }

  void _handleTransportUpdated() {
    if (_disposed) {
      return;
    }
    _evaluateActiveSessionPeer();
  }

  void _evaluateActiveSessionPeer() {
    final active = activeSession();
    final userId = _activeUserId;
    if (active == null || userId == null) {
      _peerUnavailableSince = null;
      return;
    }

    final remoteDeviceId = active.remoteMeshDeviceId(userId);
    final peerAvailable = _transport.hasPeerForDeviceId(remoteDeviceId);
    if (peerAvailable) {
      _peerUnavailableSince = null;
      return;
    }

    final now = DateTime.now().toUtc();
    _peerUnavailableSince ??= now;
    if (now.difference(_peerUnavailableSince!) >= _peerLossGracePeriod) {
      unawaited(closeSession(active));
      _peerUnavailableSince = null;
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

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    unawaited(_realtimeHandle?.dispose());
    _transport.removeListener(_handleTransportUpdated);
    super.dispose();
  }
}
