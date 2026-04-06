import 'dart:async';

import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
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
  CitizenNearbyPresenceController({
    required AuthService authService,
    required RealtimeService realtimeService,
    Duration refreshInterval = const Duration(seconds: 5),
    Duration heartbeatInterval = const Duration(seconds: 10),
    Duration freshnessWindow = const Duration(seconds: 15),
    double radiusMeters = 15,
  }) : _authService = authService,
       _realtimeService = realtimeService,
       _refreshInterval = refreshInterval,
       _heartbeatInterval = heartbeatInterval,
       _freshnessWindow = freshnessWindow,
       _radiusMeters = radiusMeters,
       super(const CitizenNearbyPresenceState.initial());

  final AuthService _authService;
  final RealtimeService _realtimeService;
  final Duration _refreshInterval;
  final Duration _heartbeatInterval;
  final Duration _freshnessWindow;
  final double _radiusMeters;

  RealtimeSubscriptionHandle? _realtimeHandle;
  Timer? _refreshTimer;
  String? _activeUserId;
  String? _displayName;
  LocationData? _lastAcceptedPresenceLocation;
  DateTime? _lastPublishedAt;
  bool _disposed = false;
  bool _refreshInFlight = false;

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
    state = state.copyWith(
      subscribed: false,
      nearbyUsers: const [],
      lastError: null,
    );
  }

  void updateSelfLocation(LocationData? location) {
    if (_disposed) {
      return;
    }
    state = state.copyWith(selfLocation: location);
    _pruneNearbyUsers();
  }

  Future<void> publishAcceptedLocation(LocationData location) async {
    if (_disposed || _activeUserId == null || _displayName == null) {
      return;
    }

    _lastAcceptedPresenceLocation = location;
    _lastPublishedAt = DateTime.now().toUtc();
    state = state.copyWith(selfLocation: location, lastError: null);

    try {
      await _authService.upsertCitizenNearbyPresence(
        displayName: _displayName!,
        latitude: location.latitude,
        longitude: location.longitude,
        accuracyMeters: location.accuracyMeters,
        lastSeenAt: location.timestamp,
      );
      if (!_disposed) {
        await refreshNearby();
      }
    } catch (error) {
      if (_disposed) {
        return;
      }
      state = state.copyWith(lastError: error.toString());
    }
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
        radiusMeters: _radiusMeters.round(),
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
              .where((pin) => pin.distanceMeters <= _radiusMeters)
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
      state = state.copyWith(lastError: error.toString());
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
    final lastAcceptedPresenceLocation = _lastAcceptedPresenceLocation;
    final lastPublishedAt = _lastPublishedAt;
    final shouldHeartbeat =
        lastAcceptedPresenceLocation != null &&
        (lastPublishedAt == null ||
            DateTime.now().toUtc().difference(lastPublishedAt) >=
                _heartbeatInterval);
    if (shouldHeartbeat) {
      await publishAcceptedLocation(lastAcceptedPresenceLocation);
      return;
    }
    await refreshNearby();
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
          return distanceMeters <= _radiusMeters;
        })
        .toList(growable: false);

    if (filtered.length != state.nearbyUsers.length) {
      state = state.copyWith(nearbyUsers: filtered);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    unawaited(_realtimeHandle?.dispose());
    super.dispose();
  }
}
