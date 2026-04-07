import 'dart:async';
import 'dart:math' as math;

import 'package:dispatch_mobile/core/services/experimental_location_fusion_service.dart';
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
    required this.displayLocation,
    this.motionMode = LocationMotionMode.acquiring,
    this.displayConfidenceMeters,
    this.isEstimatingPosition = false,
    this.headingDegrees,
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
      displayLocation = null,
      motionMode = LocationMotionMode.acquiring,
      displayConfidenceMeters = null,
      isEstimatingPosition = false,
      headingDegrees = null,
      persistedTrailPoints = const [],
      lastAcceptedTrailPoint = null,
      lastSampledAt = null,
      lastRejectionReason = null;

  final bool permissionResolved;
  final bool permissionGranted;
  final bool gpsEnabled;
  final bool trackingActive;
  final LocationData? latestLocation;
  final LocationData? displayLocation;
  final LocationMotionMode motionMode;
  final double? displayConfidenceMeters;
  final bool isEstimatingPosition;
  final double? headingDegrees;
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
    Object? displayLocation = _sentinel,
    LocationMotionMode? motionMode,
    Object? displayConfidenceMeters = _sentinel,
    bool? isEstimatingPosition,
    Object? headingDegrees = _sentinel,
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
      displayLocation: identical(displayLocation, _sentinel)
          ? this.displayLocation
          : displayLocation as LocationData?,
      motionMode: motionMode ?? this.motionMode,
      displayConfidenceMeters: identical(displayConfidenceMeters, _sentinel)
          ? this.displayConfidenceMeters
          : displayConfidenceMeters as double?,
      isEstimatingPosition: isEstimatingPosition ?? this.isEstimatingPosition,
      headingDegrees: identical(headingDegrees, _sentinel)
          ? this.headingDegrees
          : headingDegrees as double?,
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
    ExperimentalLocationFusionService? fusionService,
    Duration sampleInterval = const Duration(seconds: 5),
    int maxTrailPoints = 240,
  }) : _locationService = locationService,
       _fusionService = fusionService,
       _sampleInterval = sampleInterval,
       _maxTrailPoints = maxTrailPoints,
       super(const CitizenLocationTrailState.initial());

  final LocationService _locationService;
  final ExperimentalLocationFusionService? _fusionService;
  final Duration _sampleInterval;
  final int _maxTrailPoints;

  StreamSubscription<LocationData>? _locationSubscription;
  StreamSubscription<FusedLocationUpdate>? _fusionSubscription;
  Timer? _sampleTimer;
  LocationData? _latestSampleCandidate;
  LocationData? _pendingStableDisplayCandidate;
  int _pendingStableDisplayConfirmations = 0;
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
      isEstimatingPosition: false,
      headingDegrees: null,
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
        displayLocation: null,
        motionMode: LocationMotionMode.acquiring,
        displayConfidenceMeters: null,
        isEstimatingPosition: false,
        headingDegrees: null,
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
      isEstimatingPosition: false,
      headingDegrees: null,
    );

    if (!gpsEnabled) {
      return;
    }

    final fusionService = _fusionService;
    if (fusionService != null) {
      _fusionSubscription = fusionService.watch().listen(
        _handleFusedLocationUpdate,
        onError: (_) {
          if (_disposed) {
            return;
          }
          state = state.copyWith(
            lastSampledAt: DateTime.now().toUtc(),
            lastRejectionReason: 'Unable to read fused location updates.',
          );
        },
      );
      final initialUpdate = await fusionService.start();
      if (_disposed) {
        return;
      }
      if (initialUpdate != null) {
        _handleFusedLocationUpdate(initialUpdate);
      }
    } else {
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
    }

    _sampleTimer = Timer.periodic(_sampleInterval, (_) {
      unawaited(_sampleLatestLocation());
    });
  }

  Future<void> stopTracking() async {
    await _cancelTrackingResources();
    if (_disposed) {
      return;
    }
    state = state.copyWith(trackingActive: false, isEstimatingPosition: false);
  }

  void _handleLocationUpdate(LocationData location) {
    if (_disposed) {
      return;
    }

    _latestSampleCandidate = location;
    final estimatedLocation =
        _locationService.latestEstimatedLocation ?? location;
    final displayConfidenceMeters =
        _locationService.latestDisplayConfidenceMeters ??
        _fallbackDisplayConfidenceMeters(location);
    final nextDisplayLocation = _stabilizeDisplayAnchor(
      estimatedLocation: estimatedLocation,
      motionMode: _locationService.latestMotionMode,
      displayConfidenceMeters: displayConfidenceMeters,
    );
    state = state.copyWith(
      latestLocation: location,
      displayLocation: nextDisplayLocation,
      motionMode: _locationService.latestMotionMode,
      displayConfidenceMeters: displayConfidenceMeters,
      permissionResolved: true,
      permissionGranted: true,
      gpsEnabled: true,
      isEstimatingPosition: false,
      headingDegrees: null,
    );

    if (state.lastAcceptedTrailPoint == null) {
      final trustedAnchor = nextDisplayLocation;
      if (trustedAnchor != null &&
          _locationService.latestMotionMode != LocationMotionMode.degraded) {
        _evaluateCandidate(trustedAnchor, sampledAt: DateTime.now().toUtc());
      }
    }
  }

  void _handleFusedLocationUpdate(FusedLocationUpdate update) {
    if (_disposed) {
      return;
    }

    _latestSampleCandidate = update.displayLocation;
    final rawLocation = update.rawLocation ?? state.latestLocation;
    state = state.copyWith(
      latestLocation: rawLocation,
      displayLocation: update.displayLocation,
      motionMode: update.isEstimating
          ? LocationMotionMode.degraded
          : _locationService.latestMotionMode,
      displayConfidenceMeters: update.displayConfidenceMeters,
      permissionResolved: true,
      permissionGranted: true,
      gpsEnabled: true,
      isEstimatingPosition: update.isEstimating,
      headingDegrees: update.headingDegrees,
    );

    if (state.lastAcceptedTrailPoint == null &&
        !update.isEstimating &&
        update.displayLocation.accuracyMeters <= 30) {
      _evaluateCandidate(update.displayLocation, sampledAt: update.recordedAt);
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

    final rawCandidate = _latestSampleCandidate;
    if (rawCandidate == null) {
      state = state.copyWith(
        gpsEnabled: true,
        lastSampledAt: sampledAt,
        lastRejectionReason: 'Waiting for the first GPS fix.',
      );
      return;
    }

    if (state.isEstimatingPosition ||
        state.motionMode == LocationMotionMode.degraded) {
      state = state.copyWith(
        gpsEnabled: true,
        lastSampledAt: sampledAt,
        lastRejectionReason: state.isEstimatingPosition
            ? 'Skipped trail update because GPS is weak and the map is estimating.'
            : 'Skipped trail update because GPS confidence is too low.',
      );
      return;
    }

    final candidate = state.displayLocation;
    if (candidate == null) {
      state = state.copyWith(
        gpsEnabled: true,
        lastSampledAt: sampledAt,
        lastRejectionReason: 'Waiting for a trusted GPS anchor.',
      );
      return;
    }

    if (candidate.accuracyMeters > 30) {
      state = state.copyWith(
        gpsEnabled: true,
        lastSampledAt: sampledAt,
        lastRejectionReason:
            'Skipped trail update because accuracy exceeded 30m.',
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

    final accuracyReferenceMeters =
        state.latestLocation?.accuracyMeters ?? candidate.accuracyMeters;
    final minimumDistanceMeters = math
        .max(12, math.min(25, accuracyReferenceMeters))
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
    await _fusionSubscription?.cancel();
    await _fusionService?.stop();
    _locationSubscription = null;
    _fusionSubscription = null;
    _clearPendingStableDisplayCandidate();
  }

  LocationData? _stabilizeDisplayAnchor({
    required LocationData estimatedLocation,
    required LocationMotionMode motionMode,
    required double displayConfidenceMeters,
  }) {
    final currentDisplay = state.displayLocation;
    if (currentDisplay == null) {
      if (motionMode == LocationMotionMode.stationary) {
        return estimatedLocation;
      }
      return null;
    }

    if (motionMode == LocationMotionMode.degraded ||
        motionMode == LocationMotionMode.acquiring) {
      _clearPendingStableDisplayCandidate();
      return currentDisplay;
    }

    final distanceFromDisplay = Geolocator.distanceBetween(
      currentDisplay.latitude,
      currentDisplay.longitude,
      estimatedLocation.latitude,
      estimatedLocation.longitude,
    );
    final holdRadiusMeters = _anchorHoldRadiusMeters(displayConfidenceMeters);

    if (motionMode == LocationMotionMode.stationary) {
      if (distanceFromDisplay <= holdRadiusMeters) {
        _clearPendingStableDisplayCandidate();
      }
      if (distanceFromDisplay <= holdRadiusMeters) {
        if (_isMateriallyBetterAnchor(
          candidate: estimatedLocation,
          current: currentDisplay,
          displayConfidenceMeters: displayConfidenceMeters,
        )) {
          return estimatedLocation;
        }
        return currentDisplay;
      }

      if (_registerStableDisplayCandidate(
        currentDisplay: currentDisplay,
        estimatedLocation: estimatedLocation,
      )) {
        _clearPendingStableDisplayCandidate();
        return estimatedLocation;
      }
      return currentDisplay;
    }

    if (motionMode == LocationMotionMode.moving) {
      _clearPendingStableDisplayCandidate();
      if (distanceFromDisplay <= _movingAnchorStepMeters) {
        return estimatedLocation;
      }
      return _moveToward(
        from: currentDisplay,
        to: estimatedLocation,
        maxStepMeters: _movingAnchorStepMeters,
      );
    }

    return currentDisplay;
  }

  static const double _movingAnchorStepMeters = 8;

  double _fallbackDisplayConfidenceMeters(LocationData location) {
    final accuracyMeters = location.accuracyMeters <= 0
        ? 12
        : location.accuracyMeters;
    return math.max(5, math.min(35, accuracyMeters)).toDouble();
  }

  double _anchorHoldRadiusMeters(double displayConfidenceMeters) {
    return math.max(6, math.min(10, displayConfidenceMeters)).toDouble();
  }

  bool _isMateriallyBetterAnchor({
    required LocationData candidate,
    required LocationData current,
    required double displayConfidenceMeters,
  }) {
    if (candidate.accuracyMeters <= 0) {
      return false;
    }
    final currentAccuracyMeters = current.accuracyMeters <= 0
        ? displayConfidenceMeters
        : current.accuracyMeters;
    return candidate.accuracyMeters <= currentAccuracyMeters * 0.7;
  }

  bool _registerStableDisplayCandidate({
    required LocationData currentDisplay,
    required LocationData estimatedLocation,
  }) {
    final distanceFromDisplay = Geolocator.distanceBetween(
      currentDisplay.latitude,
      currentDisplay.longitude,
      estimatedLocation.latitude,
      estimatedLocation.longitude,
    );
    if (distanceFromDisplay < 6) {
      _clearPendingStableDisplayCandidate();
      return false;
    }

    final pendingCandidate = _pendingStableDisplayCandidate;
    if (pendingCandidate == null) {
      _pendingStableDisplayCandidate = estimatedLocation;
      _pendingStableDisplayConfirmations = 1;
      return false;
    }

    final driftMeters = Geolocator.distanceBetween(
      pendingCandidate.latitude,
      pendingCandidate.longitude,
      estimatedLocation.latitude,
      estimatedLocation.longitude,
    );
    if (driftMeters <= 8) {
      _pendingStableDisplayCandidate = estimatedLocation;
      _pendingStableDisplayConfirmations += 1;
      return _pendingStableDisplayConfirmations >= 2;
    }

    _pendingStableDisplayCandidate = estimatedLocation;
    _pendingStableDisplayConfirmations = 1;
    return false;
  }

  void _clearPendingStableDisplayCandidate() {
    _pendingStableDisplayCandidate = null;
    _pendingStableDisplayConfirmations = 0;
  }

  LocationData _moveToward({
    required LocationData from,
    required LocationData to,
    required double maxStepMeters,
  }) {
    final distanceMeters = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
    if (distanceMeters <= maxStepMeters) {
      return to;
    }
    if (distanceMeters <= 0) {
      return from;
    }
    final ratio = maxStepMeters / distanceMeters;
    return LocationData(
      latitude: from.latitude + ((to.latitude - from.latitude) * ratio),
      longitude: from.longitude + ((to.longitude - from.longitude) * ratio),
      accuracyMeters: to.accuracyMeters,
      timestamp: to.timestamp,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _sampleTimer?.cancel();
    _locationSubscription?.cancel();
    _fusionSubscription?.cancel();
    unawaited(_fusionService?.stop());
    super.dispose();
  }
}
