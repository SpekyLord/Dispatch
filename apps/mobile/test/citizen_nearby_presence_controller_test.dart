import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/citizen_nearby_presence_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRealtimeService extends RealtimeService {
  _FakeRealtimeService()
    : super(
        config: const AppConfig(
          apiBaseUrl: '',
          supabaseAnonKey: '',
          supabaseUrl: '',
        ),
      );

  final Map<String, List<VoidCallback>> _listeners = {};

  @override
  RealtimeSubscriptionHandle subscribeToTable({
    required String table,
    String? eqColumn,
    Object? eqValue,
    required VoidCallback onChange,
  }) {
    _listeners.putIfAbsent(table, () => []).add(onChange);
    return RealtimeSubscriptionHandle(() async {
      _listeners[table]?.remove(onChange);
    });
  }

  void emit(String table) {
    for (final callback in List<VoidCallback>.from(
      _listeners[table] ?? const [],
    )) {
      callback();
    }
  }
}

class _FakeAuthService extends AuthService {
  _FakeAuthService() : super();

  final List<Map<String, dynamic>> upsertCalls = [];
  Map<String, dynamic> nearbyResponse = const {
    'users': <Map<String, dynamic>>[],
  };

  @override
  Future<Map<String, dynamic>> upsertCitizenNearbyPresence({
    required String displayName,
    required double latitude,
    required double longitude,
    double? accuracyMeters,
    DateTime? lastSeenAt,
  }) async {
    final payload = {
      'display_name': displayName,
      'lat': latitude,
      'lng': longitude,
      'accuracy_meters': accuracyMeters,
      'last_seen_at': lastSeenAt?.toUtc().toIso8601String(),
    };
    upsertCalls.add(payload);
    return {'presence': payload};
  }

  @override
  Future<Map<String, dynamic>> getNearbyCitizenPresence({
    required double latitude,
    required double longitude,
    int radiusMeters = 15,
    int freshnessSeconds = 15,
    int limit = 100,
  }) async {
    return nearbyResponse;
  }
}

LocationData _location({
  required double latitude,
  double longitude = 120.9842,
  double accuracyMeters = 6,
  DateTime? timestamp,
}) {
  return LocationData(
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: accuracyMeters,
    timestamp: (timestamp ?? DateTime.now()).toUtc(),
  );
}

Map<String, dynamic> _nearbyUser({
  required String userId,
  required String displayName,
  required double latitude,
  double longitude = 120.9842,
  DateTime? lastSeenAt,
}) {
  return {
    'user_id': userId,
    'display_name': displayName,
    'lat': latitude,
    'lng': longitude,
    'accuracy_meters': 8,
    'last_seen_at': (lastSeenAt ?? DateTime.now()).toUtc().toIso8601String(),
  };
}

double _metersToLatitudeDelta(double meters) => meters / 111111.0;

void main() {
  test('publishes the first accepted self fix', () async {
    final auth = _FakeAuthService();
    final realtime = _FakeRealtimeService();
    final controller = CitizenNearbyPresenceController(
      authService: auth,
      realtimeService: realtime,
      refreshInterval: const Duration(hours: 1),
      heartbeatInterval: const Duration(hours: 1),
    );
    addTearDown(controller.dispose);

    await controller.start(userId: 'citizen-1', displayName: 'Citizen One');
    await controller.publishAcceptedLocation(_location(latitude: 14.5995));

    expect(auth.upsertCalls, hasLength(1));
    expect(auth.upsertCalls.first['display_name'], 'Citizen One');
  });

  test(
    'filters by real meter distance, freshness, and excludes self',
    () async {
      final auth = _FakeAuthService();
      final realtime = _FakeRealtimeService();
      final controller = CitizenNearbyPresenceController(
        authService: auth,
        realtimeService: realtime,
        refreshInterval: const Duration(hours: 1),
        heartbeatInterval: const Duration(hours: 1),
      );
      addTearDown(controller.dispose);
      final now = DateTime.now().toUtc();
      auth.nearbyResponse = {
        'users': [
          _nearbyUser(
            userId: 'citizen-1',
            displayName: 'Self',
            latitude: 14.5995,
            lastSeenAt: now,
          ),
          _nearbyUser(
            userId: 'citizen-2',
            displayName: 'Nearby Citizen',
            latitude: 14.5995 + _metersToLatitudeDelta(10),
            lastSeenAt: now,
          ),
          _nearbyUser(
            userId: 'citizen-3',
            displayName: 'Too Far',
            latitude: 14.5995 + _metersToLatitudeDelta(22),
            lastSeenAt: now,
          ),
          _nearbyUser(
            userId: 'citizen-4',
            displayName: 'Stale Citizen',
            latitude: 14.5995 + _metersToLatitudeDelta(6),
            lastSeenAt: now.subtract(const Duration(seconds: 40)),
          ),
        ],
      };

      await controller.start(userId: 'citizen-1', displayName: 'Citizen One');
      controller.updateSelfLocation(
        _location(latitude: 14.5995, timestamp: now),
      );
      await controller.refreshNearby();

      expect(controller.state.nearbyUsers, hasLength(1));
      expect(controller.state.nearbyUsers.first.userId, 'citizen-2');
      expect(
        controller.state.nearbyUsers.first.distanceMeters,
        lessThanOrEqualTo(15),
      );
    },
  );

  test(
    'realtime refresh moves an existing nearby user without duplicating it',
    () async {
      final auth = _FakeAuthService();
      final realtime = _FakeRealtimeService();
      final controller = CitizenNearbyPresenceController(
        authService: auth,
        realtimeService: realtime,
        refreshInterval: const Duration(hours: 1),
        heartbeatInterval: const Duration(hours: 1),
      );
      addTearDown(controller.dispose);
      final now = DateTime.now().toUtc();
      auth.nearbyResponse = {
        'users': [
          _nearbyUser(
            userId: 'citizen-2',
            displayName: 'Nearby Citizen',
            latitude: 14.5995 + _metersToLatitudeDelta(10),
            lastSeenAt: now,
          ),
        ],
      };

      await controller.start(userId: 'citizen-1', displayName: 'Citizen One');
      controller.updateSelfLocation(
        _location(latitude: 14.5995, timestamp: now),
      );
      await controller.refreshNearby();

      auth.nearbyResponse = {
        'users': [
          _nearbyUser(
            userId: 'citizen-2',
            displayName: 'Nearby Citizen',
            latitude: 14.5995 + _metersToLatitudeDelta(6),
            lastSeenAt: now.add(const Duration(seconds: 2)),
          ),
        ],
      };
      realtime.emit('citizen_nearby_presence');
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.nearbyUsers, hasLength(1));
      expect(controller.state.nearbyUsers.first.distanceMeters, lessThan(10));
    },
  );
}
