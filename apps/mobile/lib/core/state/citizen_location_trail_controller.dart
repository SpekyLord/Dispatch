import 'dart:async';
import 'dart:math' as math;

import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

const _sentinel = Object();

class CitizenTrailPoint {
  const CitizenTrailPoint({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.recordedAt,
  });

  factory CitizenTrailPoint.fromLocation(LocationData location) {
    return CitizenTrailPoint(
      latitude: location.latitude,
      longitude: location.longitude,
      accuracyMeters: location.accuracyMeters,
      recordedAt: (location.timestamp ?? DateTime.now()).toUtc(),
    );
  }

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime recordedAt;
}

class CitizenLocationTrailState {
  const CitizenLocationTrailState({
    required this.permissionResolved,
    required this.permissionGranted,
    required this.gpsEnabled,
    required this.trackingActive,
    required this.latestLocation,
    required this.persistedTrailPoints,
    required this.lastAcceptedTrailPoint,
    required this.lastSampledAt,
    required this.lastRejectionReason,
  });

  const CitizenLocationTrailState.initial()
    : permissionResolved = false,
      permissionGranted = false,
      gpsEnabled = false,
      trackingActive = false,
      latestLocation = null,
      persistedTrailPoints = const [],
      lastAcceptedTrailPoint = null,
      lastSampledAt = null,
      lastRejectionReason = null;

  final bool permissionResolved;
  final bool permissionGranted;
  final bool gpsEnabled;
  final bool trackingActive;
  final LocationData? latestLocation;
  final List<CitizenTrailPoint> persistedTrailPoints;
  final CitizenTrailPoint? lastAcceptedTrailPoint;
  final DateTime? lastSampledAt;
  final String? lastRejectionReason;

  bool get waitingForFirstFix =>
      trackingActive &&
      permissionResolved &&
      permissionGranted &&
      gpsEnabled &&
      latestLocation == null;

  bool get hasLiveFix =>
      trackingActive &&
      permissionResolved &&
      permissionGranted &&
      gpsEnabled &&
      latestLocation != null;

  CitizenLocationTrailState copyWith({
    bool? permissionResolved,
    bool? permissionGranted,
    bool? gpsEnabled,
    bool? trackingActive,
    Object? latestLocation = _sentinel,
    List<CitizenTrailPoint>? persistedTrailPoints,
    Object? lastAcceptedTrailPoint = _sentinel,
    Object? lastSampledAt = _sentinel,
    Object? lastRejectionReason = _sentinel,
  }) {
    return CitizenLocationTrailState(
      permissionResolved: permissionResolved ?? this.permissionResolved,
      permissionGranted: permissionGranted ?? this.permissionGranted,
      gpsEnabled: gpsEnabled ?? this.gpsEnabled,
      trackingActive: trackingActive ?? this.trackingActive,
      latestLocation: identical(latestLocation, _sentinel)
          ? this.latestLocation
          : latestLocation as LocationData?,
      persistedTrailPoints: persistedTrailPoints ?? this.persistedTrailPoints,
      lastAcceptedTrailPoint: identical(lastAcceptedTrailPoint, _sentinel)
          ? this.lastAcceptedTrailPoint
          : lastAcceptedTrailPoint as CitizenTrailPoint?,
      lastSampledAt: identical(lastSampledAt, _sentinel)
          ? this.lastSampledAt
          : lastSampledAt as DateTime?,
      lastRejectionReason: identical(lastRejectionReason, _sentinel)
          ? this.lastRejectionReason
          : lastRejectionReason as String?,
    );
  }
}

class CitizenLocationTrailController
    extends StateNotifier<CitizenLocationTrailState> {
  CitizenLocationTrailController({
    required LocationService locationService,
    Duration sampleInterval = const Duration(seconds: 5),
    int maxTrailPoints = 240,
  }) : _locationService = locationService,
       _sampleInterval = sampleInterval,
       _maxTrailPoints = maxTrailPoints,
       super(const CitizenLocationTrailState.initial());

  final LocationService _locationService;
  final Duration _sampleInterval;
  final int _maxTrailPoints;

  StreamSubscription<LocationData>? _locationSubscription;
  Timer? _sampleTimer;
  LocationData? _latestSampleCandidate;
  bool _disposed = false;

  Future<void> startTracking() async {
    if (_disposed) {
      return;
    }

    await _cancelTrackingResources();
    state = state.copyWith(
      trackingActive: true,
      permissionResolved: false,
      lastRejectionReason: null,
    );

    final permissionGranted = await _locationService.ensurePermission();
    if (_disposed) {
      return;
    }

    if (!permissionGranted) {
      state = state.copyWith(
        permissionResolved: true,
        permissionGranted: false,
        gpsEnabled: false,
        latestLocation: null,
        lastSampledAt: DateTime.now().toUtc(),
        lastRejectionReason: 'Location permission denied.',
      );
      return;
    }

    final gpsEnabled = await _locationService.isGpsAvailable();
    if (_disposed) {
      return;
    }

    state = state.copyWith(
      permissionResolved: true,
      permissionGranted: true,
      gpsEnabled: gpsEnabled,
      lastSampledAt: DateTime.now().toUtc(),
      lastRejectionReason: gpsEnabled
          ? null
          : 'Location services are turned off.',
    );

    if (!gpsEnabled) {
      return;
    }

    _locationSubscription = _locationService.watchPosition().listen(
      _handleLocationUpdate,
      onError: (_) {
        if (_disposed) {
          return;
        }
        state = state.copyWith(
          lastSampledAt: DateTime.now().toUtc(),
          lastRejectionReason: 'Unable to read device GPS updates.',
        );
      },
    );

    final current = await _locationService.getCurrentPosition();
    if (_disposed || current == null) {
      return;
    }
    _handleLocationUpdate(current);

    _sampleTimer = Timer.periodic(_sampleInterval, (_) {
      unawaited(_sampleLatestLocation());
    });
  }

  Future<void> stopTracking() async {
    await _cancelTrackingResources();
    if (_disposed) {
      return;
    }
    state = state.copyWith(trackingActive: false);
  }

  void _handleLocationUpdate(LocationData location) {
    if (_disposed) {
      return;
    }

    _latestSampleCandidate = location;
    state = state.copyWith(
      latestLocation: location,
      permissionResolved: true,
      permissionGranted: true,
      gpsEnabled: true,
    );

    if (state.lastAcceptedTrailPoint == null) {
      _evaluateCandidate(location, sampledAt: DateTime.now().toUtc());
    }
  }

  Future<void> _sampleLatestLocation() async {
    if (_disposed || !state.trackingActive) {
      return;
    }

    final sampledAt = DateTime.now().toUtc();
    final gpsEnabled = await _locationService.isGpsAvailable();
    if (_disposed) {
      return;
    }

    if (!gpsEnabled) {
      state = state.copyWith(
        gpsEnabled: false,
        lastSampledAt: sampledAt,
        lastRejectionReason: 'Location services are turned off.',
      );
      return;
    }

    final candidate = _latestSampleCandidate;
    if (candidate == null) {
      state = state.copyWith(
        gpsEnabled: true,
        lastSampledAt: sampledAt,
        lastRejectionReason: 'Waiting for the first GPS fix.',
      );
      return;
    }

    _evaluateCandidate(candidate, sampledAt: sampledAt);
  }

  void _evaluateCandidate(
    LocationData candidate, {
    required DateTime sampledAt,
  }) {
    if (_disposed) {
      return;
    }

    if (candidate.accuracyMeters > 30) {
      state = state.copyWith(
        lastSampledAt: sampledAt,
        lastRejectionReason:
            'Skipped trail update because accuracy exceeded 30m.',
      );
      return;
    }

    final nextPoint = CitizenTrailPoint.fromLocation(candidate);
    final lastAccepted = state.lastAcceptedTrailPoint;

    if (lastAccepted == null) {
      _appendTrailPoint(nextPoint, sampledAt: sampledAt);
      return;
    }

    final minimumDistanceMeters = math
        .max(12, math.min(25, candidate.accuracyMeters))
        .toDouble();
    final movedDistanceMeters = Geolocator.distanceBetween(
      lastAccepted.latitude,
      lastAccepted.longitude,
      nextPoint.latitude,
      nextPoint.longitude,
    );

    if (movedDistanceMeters < minimumDistanceMeters) {
      state = state.copyWith(
        lastSampledAt: sampledAt,
        lastRejectionReason:
            'Skipped trail update because movement stayed below the threshold.',
      );
      return;
    }

    _appendTrailPoint(nextPoint, sampledAt: sampledAt);
  }

  void _appendTrailPoint(
    CitizenTrailPoint point, {
    required DateTime sampledAt,
  }) {
    final nextPoints = [...state.persistedTrailPoints, point];
    final trimmedPoints = nextPoints.length > _maxTrailPoints
        ? nextPoints.sublist(nextPoints.length - _maxTrailPoints)
        : nextPoints;

    state = state.copyWith(
      persistedTrailPoints: List<CitizenTrailPoint>.unmodifiable(trimmedPoints),
      lastAcceptedTrailPoint: point,
      lastSampledAt: sampledAt,
      lastRejectionReason: null,
    );
  }

  Future<void> _cancelTrackingResources() async {
    _sampleTimer?.cancel();
    _sampleTimer = null;
    await _locationSubscription?.cancel();
    _locationSubscription = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _sampleTimer?.cancel();
    _locationSubscription?.cancel();
    super.dispose();
  }
}
