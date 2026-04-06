import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/citizen_nearby_presence_controller.dart';
import 'package:dio/dio.dart';
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
  Object? upsertError;
  Object? nearbyError;

  @override
  Future<Map<String, dynamic>> upsertCitizenNearbyPresence({
    required String displayName,
    required double latitude,
    required double longitude,
    double? accuracyMeters,
    DateTime? lastSeenAt,
  }) async {
    if (upsertError != null) {
      throw upsertError!;
    }
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
    if (nearbyError != null) {
      throw nearbyError!;
    }
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
  double? accuracyMeters = 8,
  DateTime? lastSeenAt,
}) {
  final payload = <String, dynamic>{
    'user_id': userId,
    'display_name': displayName,
    'lat': latitude,
    'lng': longitude,
    'last_seen_at': (lastSeenAt ?? DateTime.now()).toUtc().toIso8601String(),
  };
  if (accuracyMeters != null) {
    payload['accuracy_meters'] = accuracyMeters;
  }
  return payload;
}

double _metersToLatitudeDelta(double meters) => meters / 111111.0;

void main() {
  test('publishes the first usable self fix immediately', () async {
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
    controller.updateSelfLocation(
      _location(latitude: 14.5995),
      latestAccuracyMeters: 6,
    );
    await Future<void>.delayed(Duration.zero);

    expect(auth.upsertCalls, hasLength(1));
    expect(auth.upsertCalls.first['display_name'], 'Citizen One');
    expect(auth.upsertCalls.first['accuracy_meters'], 6.0);
  });

  test(
    'repeated stationary updates keep the published coordinates frozen while heartbeats continue',
    () async {
      final auth = _FakeAuthService();
      final realtime = _FakeRealtimeService();
      final controller = CitizenNearbyPresenceController(
        authService: auth,
        realtimeService: realtime,
        refreshInterval: const Duration(milliseconds: 20),
        heartbeatInterval: const Duration(milliseconds: 20),
      );
      addTearDown(controller.dispose);

      await controller.start(userId: 'citizen-1', displayName: 'Citizen One');
      controller.updateSelfLocation(
        _location(latitude: 14.5995, accuracyMeters: 8),
        latestAccuracyMeters: 8,
      );
      await Future<void>.delayed(Duration.zero);
      final firstLat = auth.upsertCalls.single['lat'] as double;

      controller.updateSelfLocation(
        _location(
          latitude: 14.5995 + _metersToLatitudeDelta(5),
          accuracyMeters: 8,
        ),
        latestAccuracyMeters: 8,
      );
      controller.updateSelfLocation(
        _location(
          latitude: 14.5995 + _metersToLatitudeDelta(7),
          accuracyMeters: 8,
        ),
        latestAccuracyMeters: 8,
      );
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(auth.upsertCalls.length, greaterThanOrEqualTo(2));
      for (final call in auth.upsertCalls) {
        expect(call['lat'], firstLat);
      }
    },
  );

  test('moderate displacement requires three confirming samples', () async {
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
    controller.updateSelfLocation(
      _location(latitude: 14.5995, accuracyMeters: 8),
      latestAccuracyMeters: 8,
    );
    await Future<void>.delayed(Duration.zero);
    expect(auth.upsertCalls, hasLength(1));

    controller.updateSelfLocation(
      _location(
        latitude: 14.5995 + _metersToLatitudeDelta(18),
        accuracyMeters: 8,
      ),
      latestAccuracyMeters: 8,
    );
    await Future<void>.delayed(Duration.zero);
    expect(auth.upsertCalls, hasLength(1));

    controller.updateSelfLocation(
      _location(
        latitude: 14.5995 + _metersToLatitudeDelta(19),
        accuracyMeters: 8,
      ),
      latestAccuracyMeters: 8,
    );
    await Future<void>.delayed(Duration.zero);
    expect(auth.upsertCalls, hasLength(1));

    controller.updateSelfLocation(
      _location(
        latitude: 14.5995 + _metersToLatitudeDelta(20),
        accuracyMeters: 8,
      ),
      latestAccuracyMeters: 8,
    );
    await Future<void>.delayed(Duration.zero);
    expect(auth.upsertCalls, hasLength(2));
    expect(
      auth.upsertCalls.last['lat'] as double,
      closeTo(14.5995 + _metersToLatitudeDelta(20), 0.0000001),
    );
  });

  test('large displacement publishes immediately', () async {
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
    controller.updateSelfLocation(
      _location(latitude: 14.5995, accuracyMeters: 8),
      latestAccuracyMeters: 8,
    );
    await Future<void>.delayed(Duration.zero);

    controller.updateSelfLocation(
      _location(
        latitude: 14.5995 + _metersToLatitudeDelta(40),
        accuracyMeters: 8,
      ),
      latestAccuracyMeters: 8,
    );
    await Future<void>.delayed(Duration.zero);

    expect(auth.upsertCalls, hasLength(2));
    expect(
      auth.upsertCalls.last['lat'] as double,
      closeTo(14.5995 + _metersToLatitudeDelta(40), 0.0000001),
    );
  });

  test('materially better stationary accuracy can upgrade the published anchor once', () async {
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
    controller.updateSelfLocation(
      _location(latitude: 14.5995, accuracyMeters: 12),
      latestAccuracyMeters: 12,
    );
    await Future<void>.delayed(Duration.zero);

    controller.updateSelfLocation(
      _location(
        latitude: 14.5995 + _metersToLatitudeDelta(3),
        accuracyMeters: 6,
      ),
      latestAccuracyMeters: 6,
    );
    await Future<void>.delayed(Duration.zero);

    expect(auth.upsertCalls, hasLength(2));
    expect(
      auth.upsertCalls.last['lat'] as double,
      closeTo(14.5995 + _metersToLatitudeDelta(3), 0.0000001),
    );

    controller.updateSelfLocation(
      _location(
        latitude: 14.5995 + _metersToLatitudeDelta(4),
        accuracyMeters: 6,
      ),
      latestAccuracyMeters: 6,
    );
    await Future<void>.delayed(Duration.zero);
    expect(auth.upsertCalls, hasLength(2));
  });

  test('allows nearby users within the accuracy-adjusted visible radius', () async {
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
          latitude: 14.5995 + _metersToLatitudeDelta(22),
          lastSeenAt: now,
        ),
      ],
    };

    await controller.start(userId: 'citizen-1', displayName: 'Citizen One');
    controller.updateSelfLocation(
      _location(latitude: 14.5995, accuracyMeters: 18, timestamp: now),
      latestAccuracyMeters: 18,
    );
    await controller.refreshNearby();

    expect(controller.state.nearbyUsers, hasLength(1));
    expect(controller.state.nearbyUsers.first.userId, 'citizen-2');
    expect(controller.state.nearbyUsers.first.distanceMeters, greaterThan(18));
  });

  test('excludes users outside the accuracy-adjusted visible radius', () async {
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
          displayName: 'Too Far',
          latitude: 14.5995 + _metersToLatitudeDelta(38),
          lastSeenAt: now,
        ),
      ],
    };

    await controller.start(userId: 'citizen-1', displayName: 'Citizen One');
    controller.updateSelfLocation(
      _location(latitude: 14.5995, accuracyMeters: 18, timestamp: now),
      latestAccuracyMeters: 18,
    );
    await controller.refreshNearby();

    expect(controller.state.nearbyUsers, isEmpty);
  });

  test('falls back to a 25 meter visible radius when accuracy is missing', () async {
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
        {
          'user_id': 'citizen-2',
          'display_name': 'Nearby Citizen',
          'lat': 14.5995 + _metersToLatitudeDelta(24),
          'lng': 120.9842,
          'last_seen_at': now.toIso8601String(),
        },
        {
          'user_id': 'citizen-3',
          'display_name': 'Too Far',
          'lat': 14.5995 + _metersToLatitudeDelta(27),
          'lng': 120.9842,
          'last_seen_at': now.toIso8601String(),
        },
      ],
    };

    await controller.start(userId: 'citizen-1', displayName: 'Citizen One');
    controller.updateSelfLocation(
      _location(latitude: 14.5995, timestamp: now),
    );
    await controller.refreshNearby();

    expect(controller.state.nearbyUsers, hasLength(1));
    expect(controller.state.nearbyUsers.first.userId, 'citizen-2');
  });

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
        latestAccuracyMeters: 6,
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

  test('surfaces backend messages when nearby refresh fails', () async {
    final auth = _FakeAuthService();
    final realtime = _FakeRealtimeService();
    final controller = CitizenNearbyPresenceController(
      authService: auth,
      realtimeService: realtime,
      refreshInterval: const Duration(hours: 1),
      heartbeatInterval: const Duration(hours: 1),
    );
    addTearDown(controller.dispose);
    auth.nearbyError = DioException(
      requestOptions: RequestOptions(path: '/api/mesh/citizen-presence/nearby'),
      response: Response(
        requestOptions: RequestOptions(path: '/api/mesh/citizen-presence/nearby'),
        statusCode: 404,
      ),
    );

    await controller.start(userId: 'citizen-1', displayName: 'Citizen One');
    controller.updateSelfLocation(
      _location(latitude: 14.5995),
      latestAccuracyMeters: 6,
    );
    await controller.refreshNearby();

    expect(
      controller.state.lastError,
      'Nearby presence API is unavailable. Update the backend and apply the latest migrations.',
    );
  });

  test('heartbeat republishes stationary self presence', () async {
    final auth = _FakeAuthService();
    final realtime = _FakeRealtimeService();
    final controller = CitizenNearbyPresenceController(
      authService: auth,
      realtimeService: realtime,
      refreshInterval: const Duration(milliseconds: 20),
      heartbeatInterval: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);

    await controller.start(userId: 'citizen-1', displayName: 'Citizen One');
    controller.updateSelfLocation(
      _location(latitude: 14.5995),
      latestAccuracyMeters: 7,
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(auth.upsertCalls.length, greaterThanOrEqualTo(2));
    expect(auth.upsertCalls.last['lat'], auth.upsertCalls.first['lat']);
    expect(auth.upsertCalls.last['lng'], auth.upsertCalls.first['lng']);
    expect(auth.upsertCalls.last['accuracy_meters'], 7.0);
  });

  test('keeps users visible through one missed heartbeat and then expires them', () async {
    final auth = _FakeAuthService();
    final realtime = _FakeRealtimeService();
    final controller = CitizenNearbyPresenceController(
      authService: auth,
      realtimeService: realtime,
      refreshInterval: const Duration(hours: 1),
      heartbeatInterval: const Duration(hours: 1),
      freshnessWindow: const Duration(seconds: 20),
    );
    addTearDown(controller.dispose);
    final now = DateTime.now().toUtc();

    await controller.start(userId: 'citizen-1', displayName: 'Citizen One');
    controller.updateSelfLocation(
      _location(latitude: 14.5995, timestamp: now),
      latestAccuracyMeters: 10,
    );

    auth.nearbyResponse = {
      'users': [
        _nearbyUser(
          userId: 'citizen-2',
          displayName: 'Nearby Citizen',
          latitude: 14.5995 + _metersToLatitudeDelta(18),
          lastSeenAt: now.subtract(const Duration(seconds: 18)),
        ),
      ],
    };
    await controller.refreshNearby();
    expect(controller.state.nearbyUsers, hasLength(1));

    auth.nearbyResponse = {
      'users': [
        _nearbyUser(
          userId: 'citizen-2',
          displayName: 'Nearby Citizen',
          latitude: 14.5995 + _metersToLatitudeDelta(18),
          lastSeenAt: now.subtract(const Duration(seconds: 25)),
        ),
      ],
    };
    await controller.refreshNearby();
    expect(controller.state.nearbyUsers, isEmpty);
  });
}
