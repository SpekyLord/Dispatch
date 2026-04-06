import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

const _presenceSentinel = Object();

class NearbyCitizenPin {
  const NearbyCitizenPin({
    required this.userId,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    required this.lastSeenAt,
    required this.distanceMeters,
    this.accuracyMeters,
  });

  factory NearbyCitizenPin.fromJson(Map<String, dynamic> json) {
    return NearbyCitizenPin(
      userId: json['user_id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? 'Nearby User',
      latitude: (json['lat'] as num?)?.toDouble() ?? 0,
      longitude: (json['lng'] as num?)?.toDouble() ?? 0,
      accuracyMeters: (json['accuracy_meters'] as num?)?.toDouble(),
      lastSeenAt:
          DateTime.tryParse(json['last_seen_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      distanceMeters: (json['distance_meters'] as num?)?.toDouble() ?? 0,
    );
  }

  final String userId;
  final String displayName;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final DateTime lastSeenAt;
  final double distanceMeters;
}

class CitizenNearbyPresenceState {
  const CitizenNearbyPresenceState({
    required this.selfLocation,
    required this.nearbyUsers,
    required this.subscribed,
    required this.lastRefreshAt,
    required this.lastError,
  });

  const CitizenNearbyPresenceState.initial()
    : selfLocation = null,
      nearbyUsers = const [],
      subscribed = false,
      lastRefreshAt = null,
      lastError = null;

  final LocationData? selfLocation;
  final List<NearbyCitizenPin> nearbyUsers;
  final bool subscribed;
  final DateTime? lastRefreshAt;
  final String? lastError;

  CitizenNearbyPresenceState copyWith({
    Object? selfLocation = _presenceSentinel,
    List<NearbyCitizenPin>? nearbyUsers,
    bool? subscribed,
    Object? lastRefreshAt = _presenceSentinel,
    Object? lastError = _presenceSentinel,
  }) {
    return CitizenNearbyPresenceState(
      selfLocation: identical(selfLocation, _presenceSentinel)
          ? this.selfLocation
          : selfLocation as LocationData?,
      nearbyUsers: nearbyUsers ?? this.nearbyUsers,
      subscribed: subscribed ?? this.subscribed,
      lastRefreshAt: identical(lastRefreshAt, _presenceSentinel)
          ? this.lastRefreshAt
          : lastRefreshAt as DateTime?,
      lastError: identical(lastError, _presenceSentinel)
          ? this.lastError
          : lastError as String?,
    );
  }
}

class CitizenNearbyPresenceController
    extends StateNotifier<CitizenNearbyPresenceState> {
  static const double _immediatePublishDistanceMeters = 35;
  static const int _pendingMovementConfirmationsRequired = 3;
  static const double _pendingMovementClusterRadiusMeters = 10;

  CitizenNearbyPresenceController({
    required AuthService authService,
    required RealtimeService realtimeService,
    Duration refreshInterval = const Duration(seconds: 5),
    Duration heartbeatInterval = const Duration(seconds: 10),
    Duration freshnessWindow = const Duration(seconds: 20),
    double fetchRadiusMeters = 40,
    double baseVisibleRadiusMeters = 25,
    double maxVisibleRadiusMeters = 35,
  }) : _authService = authService,
       _realtimeService = realtimeService,
       _refreshInterval = refreshInterval,
       _heartbeatInterval = heartbeatInterval,
       _freshnessWindow = freshnessWindow,
       _fetchRadiusMeters = fetchRadiusMeters,
       _baseVisibleRadiusMeters = baseVisibleRadiusMeters,
       _maxVisibleRadiusMeters = maxVisibleRadiusMeters,
       super(const CitizenNearbyPresenceState.initial());

  final AuthService _authService;
  final RealtimeService _realtimeService;
  final Duration _refreshInterval;
  final Duration _heartbeatInterval;
  final Duration _freshnessWindow;
  final double _fetchRadiusMeters;
  final double _baseVisibleRadiusMeters;
  final double _maxVisibleRadiusMeters;

  RealtimeSubscriptionHandle? _realtimeHandle;
  Timer? _refreshTimer;
  String? _activeUserId;
  String? _displayName;
  double? _selfAccuracyMeters;
  double? _publishedAccuracyMeters;
  DateTime? _lastPublishedAt;
  LocationData? _publishedPresenceLocation;
  LocationData? _pendingPublishedCandidate;
  int _pendingPublishedConfirmations = 0;
  bool _disposed = false;
  bool _refreshInFlight = false;

  Future<void> start({
    required String userId,
    required String displayName,
  }) async {
    if (_disposed) {
      return;
    }

    if (_activeUserId != userId) {
      _publishedPresenceLocation = null;
      _publishedAccuracyMeters = null;
      _clearPendingPublishedCandidate();
      _lastPublishedAt = null;
    }
    _activeUserId = userId;
    _displayName = displayName.trim();

    _realtimeHandle ??= _realtimeService.subscribeToTable(
      table: 'citizen_nearby_presence',
      onChange: () => unawaited(refreshNearby()),
    );
    _refreshTimer ??= Timer.periodic(_refreshInterval, (_) {
      unawaited(_tick());
    });

    state = state.copyWith(subscribed: true, lastError: null);
    await refreshNearby();
  }

  Future<void> stop() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    await _realtimeHandle?.dispose();
    _realtimeHandle = null;
    if (_disposed) {
      return;
    }
    _clearPendingPublishedCandidate();
    state = state.copyWith(
      subscribed: false,
      nearbyUsers: const [],
      lastError: null,
    );
  }

  void updateSelfLocation(LocationData? location, {double? latestAccuracyMeters}) {
    if (_disposed) {
      return;
    }
    _selfAccuracyMeters = latestAccuracyMeters;
    state = state.copyWith(selfLocation: location);
    _pruneNearbyUsers();
    if (location == null) {
      _clearPendingPublishedCandidate();
      return;
    }
    unawaited(_syncPublishedPresence());
  }

  Future<void> publishSelfLocation() async {
    await _syncPublishedPresence(forceHeartbeat: true);
  }

  Future<void> refreshNearby() async {
    if (_disposed || _refreshInFlight) {
      return;
    }
    final selfLocation = state.selfLocation;
    if (_activeUserId == null || selfLocation == null) {
      _pruneNearbyUsers();
      return;
    }

    _refreshInFlight = true;
    try {
      final response = await _authService.getNearbyCitizenPresence(
        latitude: selfLocation.latitude,
        longitude: selfLocation.longitude,
        radiusMeters: _fetchRadiusMeters.round(),
        freshnessSeconds: _freshnessWindow.inSeconds,
      );
      if (_disposed) {
        return;
      }

      final now = DateTime.now().toUtc();
      final nearbyUsers =
          (response['users'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map(
                (row) =>
                    NearbyCitizenPin.fromJson(Map<String, dynamic>.from(row)),
              )
              .where((pin) => pin.userId != _activeUserId)
              .where(
                (pin) => now.difference(pin.lastSeenAt) <= _freshnessWindow,
              )
              .map((pin) {
                final distanceMeters = Geolocator.distanceBetween(
                  selfLocation.latitude,
                  selfLocation.longitude,
                  pin.latitude,
                  pin.longitude,
                );
                return NearbyCitizenPin(
                  userId: pin.userId,
                  displayName: pin.displayName,
                  latitude: pin.latitude,
                  longitude: pin.longitude,
                  accuracyMeters: pin.accuracyMeters,
                  lastSeenAt: pin.lastSeenAt,
                  distanceMeters: distanceMeters,
                );
              })
              .where(
                (pin) => pin.distanceMeters <=
                    _effectiveVisibleRadius(
                      _selfAccuracyMeters,
                      pin.accuracyMeters,
                    ),
              )
              .toList(growable: false)
            ..sort(
              (left, right) =>
                  left.distanceMeters.compareTo(right.distanceMeters),
            );

      state = state.copyWith(
        nearbyUsers: nearbyUsers,
        lastRefreshAt: now,
        lastError: null,
      );
    } catch (error) {
      if (_disposed) {
        return;
      }
      state = state.copyWith(lastError: _describePresenceError(error));
      _pruneNearbyUsers();
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> _tick() async {
    if (_disposed) {
      return;
    }
    _pruneNearbyUsers();
    final lastPublishedAt = _lastPublishedAt;
    final shouldHeartbeat =
        state.selfLocation != null &&
        (lastPublishedAt == null ||
            DateTime.now().toUtc().difference(lastPublishedAt) >=
                _heartbeatInterval);
    if (shouldHeartbeat) {
      await _syncPublishedPresence(forceHeartbeat: true);
      return;
    }
    await refreshNearby();
  }

  Future<void> _syncPublishedPresence({bool forceHeartbeat = false}) async {
    final selfLocation = state.selfLocation;
    if (_disposed ||
        _activeUserId == null ||
        _displayName == null ||
        selfLocation == null) {
      return;
    }

    final publishedAnchor = _publishedPresenceLocation;
    if (publishedAnchor == null) {
      await _publishPresence(
        location: selfLocation,
        accuracyMeters: _selfAccuracyMeters,
      );
      return;
    }

    final distanceFromPublished = Geolocator.distanceBetween(
      publishedAnchor.latitude,
      publishedAnchor.longitude,
      selfLocation.latitude,
      selfLocation.longitude,
    );
    final holdRadiusMeters = _stationaryHoldRadiusMeters(
      _selfAccuracyMeters ?? selfLocation.accuracyMeters,
    );

    if (distanceFromPublished <= holdRadiusMeters) {
      _clearPendingPublishedCandidate();
      if (_shouldUpgradePublishedAnchor(
        currentPublished: publishedAnchor,
        candidate: selfLocation,
        currentPublishedAccuracyMeters: _publishedAccuracyMeters,
        latestAccuracyMeters: _selfAccuracyMeters,
      )) {
        await _publishPresence(
          location: selfLocation,
          accuracyMeters: _selfAccuracyMeters,
        );
        return;
      }
      if (forceHeartbeat) {
        await _publishPresence(
          location: publishedAnchor,
          accuracyMeters: _selfAccuracyMeters ?? _publishedAccuracyMeters,
        );
        return;
      }
      return;
    }

    if (distanceFromPublished >= _immediatePublishDistanceMeters) {
      _clearPendingPublishedCandidate();
      await _publishPresence(
        location: selfLocation,
        accuracyMeters: _selfAccuracyMeters,
      );
      return;
    }

    final shouldPromoteCandidate = _registerPendingPublishedCandidate(
      selfLocation,
      holdRadiusMeters: holdRadiusMeters,
      publishedAnchor: publishedAnchor,
    );
    if (shouldPromoteCandidate) {
      _clearPendingPublishedCandidate();
      await _publishPresence(
        location: selfLocation,
        accuracyMeters: _selfAccuracyMeters,
      );
      return;
    }

    if (forceHeartbeat) {
      await _publishPresence(
        location: publishedAnchor,
        accuracyMeters: _selfAccuracyMeters ?? _publishedAccuracyMeters,
      );
    }
  }

  Future<void> _publishPresence({
    required LocationData location,
    required double? accuracyMeters,
  }) async {
    final publishedAt = DateTime.now().toUtc();
    _lastPublishedAt = publishedAt;
    state = state.copyWith(lastError: null);

    try {
      await _authService.upsertCitizenNearbyPresence(
        displayName: _displayName!,
        latitude: location.latitude,
        longitude: location.longitude,
        accuracyMeters: accuracyMeters,
        lastSeenAt: publishedAt,
      );
      if (_disposed) {
        return;
      }
      _publishedPresenceLocation = location;
      _publishedAccuracyMeters = accuracyMeters;
      await refreshNearby();
    } catch (error) {
      if (_disposed) {
        return;
      }
      state = state.copyWith(lastError: _describePresenceError(error));
    }
  }

  void _pruneNearbyUsers() {
    if (_disposed) {
      return;
    }
    final selfLocation = state.selfLocation;
    final now = DateTime.now().toUtc();
    final filtered = state.nearbyUsers
        .where((pin) {
          if (now.difference(pin.lastSeenAt) > _freshnessWindow) {
            return false;
          }
          if (selfLocation == null) {
            return true;
          }
          final distanceMeters = Geolocator.distanceBetween(
            selfLocation.latitude,
            selfLocation.longitude,
            pin.latitude,
            pin.longitude,
          );
          return distanceMeters <=
              _effectiveVisibleRadius(
                _selfAccuracyMeters,
                pin.accuracyMeters,
              );
        })
        .toList(growable: false);

    if (filtered.length != state.nearbyUsers.length) {
      state = state.copyWith(nearbyUsers: filtered);
    }
  }

  double _effectiveVisibleRadius(
    double? selfAccuracyMeters,
    double? otherAccuracyMeters,
  ) {
    if (selfAccuracyMeters == null || otherAccuracyMeters == null) {
      return _baseVisibleRadiusMeters;
    }
    final combinedAccuracyMeters = selfAccuracyMeters + otherAccuracyMeters;
    return math.max(
      _baseVisibleRadiusMeters,
      math.min(_maxVisibleRadiusMeters, combinedAccuracyMeters),
    );
  }

  double _stationaryHoldRadiusMeters(double accuracyMeters) {
    return math.max(12, math.min(20, accuracyMeters * 1.5)).toDouble();
  }

  bool _registerPendingPublishedCandidate(
    LocationData candidate, {
    required double holdRadiusMeters,
    required LocationData publishedAnchor,
  }) {
    final distanceFromPublished = Geolocator.distanceBetween(
      publishedAnchor.latitude,
      publishedAnchor.longitude,
      candidate.latitude,
      candidate.longitude,
    );
    if (distanceFromPublished <= holdRadiusMeters) {
      _clearPendingPublishedCandidate();
      return false;
    }

    final pending = _pendingPublishedCandidate;
    if (pending == null) {
      _pendingPublishedCandidate = candidate;
      _pendingPublishedConfirmations = 1;
      return false;
    }

    final clusterDistance = Geolocator.distanceBetween(
      pending.latitude,
      pending.longitude,
      candidate.latitude,
      candidate.longitude,
    );
    if (clusterDistance <= _pendingMovementClusterRadiusMeters) {
      _pendingPublishedCandidate = candidate;
      _pendingPublishedConfirmations += 1;
      return _pendingPublishedConfirmations >=
          _pendingMovementConfirmationsRequired;
    }

    _pendingPublishedCandidate = candidate;
    _pendingPublishedConfirmations = 1;
    return false;
  }

  bool _shouldUpgradePublishedAnchor({
    required LocationData currentPublished,
    required LocationData candidate,
    required double? currentPublishedAccuracyMeters,
    required double? latestAccuracyMeters,
  }) {
    final publishedAccuracy =
        currentPublishedAccuracyMeters ?? currentPublished.accuracyMeters;
    final candidateAccuracy = latestAccuracyMeters ?? candidate.accuracyMeters;
    if (publishedAccuracy <= 0 || candidateAccuracy <= 0) {
      return false;
    }
    return candidateAccuracy <= publishedAccuracy * 0.6;
  }

  void _clearPendingPublishedCandidate() {
    _pendingPublishedCandidate = null;
    _pendingPublishedConfirmations = 0;
  }

  String _describePresenceError(Object error) {
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError) {
        final configHelp = buildMobileApiUrlHelp(
          isWeb: kIsWeb,
          isAndroid: defaultTargetPlatform == TargetPlatform.android,
          url: _authService.baseUrl,
        );
        if (configHelp != null) {
          return configHelp;
        }
        return 'Unable to reach nearby presence at ${_authService.baseUrl}.';
      }

      final payload = error.response?.data;
      if (payload is Map<String, dynamic>) {
        final data = payload['error'];
        if (data is Map<String, dynamic>) {
          final message = data['message'] as String?;
          if (message != null && message.trim().isNotEmpty) {
            return message.trim();
          }
        }
      }

      final statusCode = error.response?.statusCode;
      if (statusCode == 404) {
        return 'Nearby presence API is unavailable. Update the backend and apply the latest migrations.';
      }
      if (statusCode != null) {
        return 'Nearby presence request failed ($statusCode).';
      }
      if (error.message != null && error.message!.trim().isNotEmpty) {
        return error.message!.trim();
      }
      return 'Nearby presence request failed.';
    }

    return error.toString();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    unawaited(_realtimeHandle?.dispose());
    super.dispose();
  }
}
