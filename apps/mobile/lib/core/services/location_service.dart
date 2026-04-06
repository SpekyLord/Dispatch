import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

class LocationData {
  const LocationData({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters = 0,
    this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime? timestamp;
}

enum LocationMotionMode { acquiring, stationary, moving, degraded }

class LocationService {
  static const Duration _maxLastKnownAge = Duration(minutes: 2);
  static const double _maxLastKnownAccuracyMeters = 80;
  static const double _maxStreamAccuracyMeters = 90;
  static const double _maxUsableEstimatorAccuracyMeters = 25;
  static const double _maxDiagnosticEstimatorAccuracyMeters = 50;
  static const double _stableBestAccuracyMeters = 15;
  static const double _stableSpreadMeters = 8;
  static const double _stableShiftMeters = 6;
  static const double _maxSnapBackDistanceMeters = 120;
  static const double _maxReasonableSpeedMetersPerSecond = 55;
  static const double _pendingJumpConfirmationRadiusMeters = 45;
  static const int _pendingJumpVotesRequired = 2;
  static const int _fixWindowSize = 6;
  static const Duration _fixWindowDuration = Duration(seconds: 6);
  static const double _minimumMovementMeters = 4;
  static const int _movingWindowVotesRequired = 2;

  LocationData? _lastRawAcceptedLocation;
  final List<LocationData> _acceptedFixWindow = <LocationData>[];
  List<LocationData> _recentUsableFixes = const <LocationData>[];
  LocationData? _pendingJumpCandidate;
  int _pendingJumpVotes = 0;
  LocationData? _latestEstimatedLocation;
  double? _latestDisplayConfidenceMeters;
  LocationMotionMode _latestMotionMode = LocationMotionMode.acquiring;
  LocationData? _lastStableCenter;
  LocationData? _pendingMovingCenter;
  int _pendingMovingVotes = 0;

  LocationMotionMode get latestMotionMode => _latestMotionMode;
  LocationData? get latestEstimatedLocation => _latestEstimatedLocation;
  double? get latestDisplayConfidenceMeters => _latestDisplayConfidenceMeters;
  List<LocationData> get recentUsableFixes =>
      List<LocationData>.unmodifiable(_recentUsableFixes);

  Future<bool> isGpsAvailable() => Geolocator.isLocationServiceEnabled();

  Future<bool> ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
  }

  Future<LocationData?> getCurrentPosition() async {
    final hasPermission = await ensurePermission();
    if (!hasPermission) {
      return null;
    }
    final gpsAvailable = await isGpsAvailable();
    if (!gpsAvailable) {
      return await getLastKnownPosition();
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: _currentLocationSettings(),
      );
      return _acceptPosition(_toLocationData(pos), fromLastKnown: false);
    } catch (_) {
      return await getLastKnownPosition();
    }
  }

  Future<LocationData?> getLastKnownPosition() async {
    final hasPermission = await ensurePermission();
    if (!hasPermission) {
      return null;
    }
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos == null) {
        return null;
      }
      return _acceptPosition(_toLocationData(pos), fromLastKnown: true);
    } catch (_) {
      return null;
    }
  }

  Stream<LocationData> watchPosition() async* {
    final hasPermission = await ensurePermission();
    if (!hasPermission) {
      return;
    }

    yield* Geolocator.getPositionStream(
          locationSettings: _streamLocationSettings(),
        )
        .asyncMap((position) async {
          return _acceptPosition(
            _toLocationData(position),
            fromLastKnown: false,
          );
        })
        .where((location) => location != null)
        .cast<LocationData>();
  }

  LocationSettings _currentLocationSettings() {
    if (kIsWeb) {
      return const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 10),
      );
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 2),
        timeLimit: const Duration(seconds: 12),
        forceLocationManager: false,
      ),
      TargetPlatform.iOS || TargetPlatform.macOS => AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        timeLimit: const Duration(seconds: 12),
        pauseLocationUpdatesAutomatically: false,
        activityType: ActivityType.fitness,
        allowBackgroundLocationUpdates: false,
        showBackgroundLocationIndicator: false,
      ),
      _ => const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 10),
      ),
    };
  }

  LocationSettings _streamLocationSettings() {
    if (kIsWeb) {
      return const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 1,
      );
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
        intervalDuration: const Duration(milliseconds: 500),
        forceLocationManager: false,
      ),
      TargetPlatform.iOS || TargetPlatform.macOS => AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
        pauseLocationUpdatesAutomatically: false,
        activityType: ActivityType.fitness,
        allowBackgroundLocationUpdates: false,
        showBackgroundLocationIndicator: false,
      ),
      _ => const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    };
  }

  LocationData _toLocationData(Position position) {
    return LocationData(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      timestamp: position.timestamp.toUtc(),
    );
  }

  LocationData? _acceptPosition(
    LocationData candidate, {
    required bool fromLastKnown,
  }) {
    final timestamp = candidate.timestamp?.toUtc();
    if (fromLastKnown && timestamp != null) {
      final age = DateTime.now().toUtc().difference(timestamp);
      if (age > _maxLastKnownAge &&
          candidate.accuracyMeters > _maxLastKnownAccuracyMeters) {
        return _lastRawAcceptedLocation ?? _latestEstimatedLocation;
      }
    }

    final currentRaw = _lastRawAcceptedLocation;
    if (currentRaw == null) {
      _clearPendingJump();
      _lastRawAcceptedLocation = candidate;
      _rememberAcceptedFix(candidate);
      _recomputeEstimate(referenceTimestamp: candidate.timestamp);
      return candidate;
    }

    final distanceMeters = Geolocator.distanceBetween(
      currentRaw.latitude,
      currentRaw.longitude,
      candidate.latitude,
      candidate.longitude,
    );
    final elapsedSeconds = _elapsedSeconds(
      currentRaw.timestamp,
      candidate.timestamp,
    );
    final inferredSpeedMetersPerSecond =
        elapsedSeconds == null || elapsedSeconds <= 0
        ? null
        : distanceMeters / elapsedSeconds;
    final jitterThresholdMeters = _jitterThresholdMeters(currentRaw, candidate);
    final hasWorseAccuracy =
        candidate.accuracyMeters > currentRaw.accuracyMeters;
    final candidateAccuracyPoor =
        candidate.accuracyMeters > _maxStreamAccuracyMeters;
    final likelyNoisyStreamJump =
        !fromLastKnown &&
        candidateAccuracyPoor &&
        distanceMeters > _maxSnapBackDistanceMeters;
    final likelyStaleFallback =
        fromLastKnown &&
        hasWorseAccuracy &&
        distanceMeters > _maxSnapBackDistanceMeters;
    final impossibleSpeedJump =
        inferredSpeedMetersPerSecond != null &&
        inferredSpeedMetersPerSecond > _maxReasonableSpeedMetersPerSecond;

    if (distanceMeters <= jitterThresholdMeters) {
      _clearPendingJump();
      _lastRawAcceptedLocation = candidate;
      _rememberAcceptedFix(candidate);
      _recomputeEstimate(referenceTimestamp: candidate.timestamp);
      return candidate;
    }

    if (_isMeaningfullyMoreAccurate(candidate, currentRaw)) {
      _clearPendingJump();
      _lastRawAcceptedLocation = candidate;
      _rememberAcceptedFix(candidate);
      _recomputeEstimate(referenceTimestamp: candidate.timestamp);
      return candidate;
    }

    if (impossibleSpeedJump || likelyNoisyStreamJump || likelyStaleFallback) {
      if (_shouldAcceptPendingJump(candidate)) {
        _clearPendingJump();
        _lastRawAcceptedLocation = candidate;
        _rememberAcceptedFix(candidate);
        _recomputeEstimate(referenceTimestamp: candidate.timestamp);
        return candidate;
      }
      return currentRaw;
    }

    _clearPendingJump();
    _lastRawAcceptedLocation = candidate;
    _rememberAcceptedFix(candidate);
    _recomputeEstimate(referenceTimestamp: candidate.timestamp);
    return candidate;
  }

  void _clearPendingJump() {
    _pendingJumpCandidate = null;
    _pendingJumpVotes = 0;
  }

  bool _shouldAcceptPendingJump(LocationData candidate) {
    final pending = _pendingJumpCandidate;
    if (pending == null) {
      _pendingJumpCandidate = candidate;
      _pendingJumpVotes = 1;
      return false;
    }

    final delta = Geolocator.distanceBetween(
      pending.latitude,
      pending.longitude,
      candidate.latitude,
      candidate.longitude,
    );
    if (delta <= _pendingJumpConfirmationRadiusMeters) {
      _pendingJumpCandidate = candidate;
      _pendingJumpVotes += 1;
      return _pendingJumpVotes >= _pendingJumpVotesRequired;
    }

    _pendingJumpCandidate = candidate;
    _pendingJumpVotes = 1;
    return false;
  }

  void _rememberAcceptedFix(LocationData candidate) {
    _acceptedFixWindow.add(candidate);
    if (_acceptedFixWindow.length > _fixWindowSize + 4) {
      _acceptedFixWindow.removeRange(0, _acceptedFixWindow.length - (_fixWindowSize + 4));
    }
  }

  void _recomputeEstimate({DateTime? referenceTimestamp}) {
    final latestRaw = _lastRawAcceptedLocation;
    if (latestRaw == null) {
      _recentUsableFixes = const <LocationData>[];
      _latestEstimatedLocation = null;
      _latestDisplayConfidenceMeters = null;
      _latestMotionMode = LocationMotionMode.acquiring;
      return;
    }

    final referenceTime = referenceTimestamp?.toUtc() ?? latestRaw.timestamp?.toUtc();
    var recentFixes =
        _acceptedFixWindow.where((fix) {
          if (referenceTime == null || fix.timestamp == null) {
            return true;
          }
          return referenceTime.difference(fix.timestamp!.toUtc()) <=
              _fixWindowDuration;
        }).toList(growable: false);
    if (recentFixes.length > _fixWindowSize) {
      recentFixes = recentFixes.sublist(recentFixes.length - _fixWindowSize);
    }

    final usableFixes = recentFixes
        .where((fix) => fix.accuracyMeters <= _maxUsableEstimatorAccuracyMeters)
        .toList(growable: false);
    final diagnosticFixes = recentFixes
        .where(
          (fix) =>
              fix.accuracyMeters > _maxUsableEstimatorAccuracyMeters &&
              fix.accuracyMeters <= _maxDiagnosticEstimatorAccuracyMeters,
        )
        .toList(growable: false);
    _recentUsableFixes = usableFixes;

    if (usableFixes.isEmpty) {
      final diagnosticAccuracyMeters =
          diagnosticFixes.isEmpty ? latestRaw.accuracyMeters : _bestAccuracyMeters(diagnosticFixes);
      _latestEstimatedLocation = latestRaw;
      _latestDisplayConfidenceMeters = _confidenceRadiusForMode(
        mode: LocationMotionMode.acquiring,
        baseAccuracyMeters: diagnosticAccuracyMeters,
      );
      _latestMotionMode = LocationMotionMode.acquiring;
      _clearPendingMovingWindow();
      return;
    }

    final weightedCenter = _weightedCenter(usableFixes);
    final clusterRadius = _clusterRadiusMeters(weightedCenter, usableFixes);
    final bestAccuracyMeters = _bestAccuracyMeters(usableFixes);
    final nextMotionMode = _classifyMotionMode(
      center: weightedCenter,
      bestAccuracyMeters: bestAccuracyMeters,
      clusterRadiusMeters: clusterRadius,
      usableFixCount: usableFixes.length,
    );
    final confidenceMeters = _confidenceRadiusForMode(
      mode: nextMotionMode,
      baseAccuracyMeters: bestAccuracyMeters,
    );
    final estimatedLocation = LocationData(
      latitude: weightedCenter.latitude,
      longitude: weightedCenter.longitude,
      accuracyMeters: confidenceMeters,
      timestamp: latestRaw.timestamp,
    );
    _latestEstimatedLocation = estimatedLocation;
    _latestDisplayConfidenceMeters = confidenceMeters;
    _latestMotionMode = nextMotionMode;
  }

  LocationData _weightedCenter(List<LocationData> fixes) {
    var latitudeWeight = 0.0;
    var longitudeWeight = 0.0;
    var totalWeight = 0.0;
    for (final fix in fixes) {
      final accuracy = fix.accuracyMeters <= 0 ? 12.0 : fix.accuracyMeters;
      final weight = 1 / math.max(accuracy, 3);
      latitudeWeight += fix.latitude * weight;
      longitudeWeight += fix.longitude * weight;
      totalWeight += weight;
    }
    if (totalWeight <= 0) {
      return fixes.last;
    }
    return LocationData(
      latitude: latitudeWeight / totalWeight,
      longitude: longitudeWeight / totalWeight,
      accuracyMeters: 0,
      timestamp: fixes.last.timestamp,
    );
  }

  double _clusterRadiusMeters(LocationData center, List<LocationData> fixes) {
    var maxRadius = 0.0;
    for (final fix in fixes) {
      final distanceMeters = Geolocator.distanceBetween(
        center.latitude,
        center.longitude,
        fix.latitude,
        fix.longitude,
      );
      if (distanceMeters > maxRadius) {
        maxRadius = distanceMeters;
      }
    }
    return maxRadius;
  }

  double _bestAccuracyMeters(List<LocationData> fixes) {
    var bestAccuracyMeters = fixes.first.accuracyMeters <= 0
        ? 12.0
        : fixes.first.accuracyMeters;
    for (final fix in fixes.skip(1)) {
      final accuracyMeters = fix.accuracyMeters <= 0 ? 12.0 : fix.accuracyMeters;
      if (accuracyMeters < bestAccuracyMeters) {
        bestAccuracyMeters = accuracyMeters;
      }
    }
    return bestAccuracyMeters;
  }

  LocationMotionMode _classifyMotionMode({
    required LocationData center,
    required double bestAccuracyMeters,
    required double clusterRadiusMeters,
    required int usableFixCount,
  }) {
    if (usableFixCount < 3) {
      _clearPendingMovingWindow();
      return LocationMotionMode.acquiring;
    }

    if (bestAccuracyMeters > _stableBestAccuracyMeters ||
        clusterRadiusMeters > _stableSpreadMeters) {
      _clearPendingMovingWindow();
      return LocationMotionMode.degraded;
    }

    final lastStableCenter = _lastStableCenter;
    if (lastStableCenter == null) {
      _lastStableCenter = center;
      _clearPendingMovingWindow();
      return LocationMotionMode.stationary;
    }

    final shiftMeters = Geolocator.distanceBetween(
      lastStableCenter.latitude,
      lastStableCenter.longitude,
      center.latitude,
      center.longitude,
    );
    if (shiftMeters < _stableShiftMeters) {
      _lastStableCenter = center;
      _clearPendingMovingWindow();
      return LocationMotionMode.stationary;
    }

    if (_registerMovingWindow(center)) {
      _lastStableCenter = center;
      _clearPendingMovingWindow();
      return LocationMotionMode.moving;
    }

    return LocationMotionMode.stationary;
  }

  bool _registerMovingWindow(LocationData center) {
    final pendingMovingCenter = _pendingMovingCenter;
    if (pendingMovingCenter == null) {
      _pendingMovingCenter = center;
      _pendingMovingVotes = 1;
      return false;
    }

    final driftMeters = Geolocator.distanceBetween(
      pendingMovingCenter.latitude,
      pendingMovingCenter.longitude,
      center.latitude,
      center.longitude,
    );
    if (driftMeters <= _stableSpreadMeters) {
      _pendingMovingCenter = center;
      _pendingMovingVotes += 1;
      return _pendingMovingVotes >= _movingWindowVotesRequired;
    }

    _pendingMovingCenter = center;
    _pendingMovingVotes = 1;
    return false;
  }

  void _clearPendingMovingWindow() {
    _pendingMovingCenter = null;
    _pendingMovingVotes = 0;
  }

  double _confidenceRadiusForMode({
    required LocationMotionMode mode,
    required double baseAccuracyMeters,
  }) {
    final normalizedAccuracy = baseAccuracyMeters <= 0 ? 12.0 : baseAccuracyMeters;
    return switch (mode) {
      LocationMotionMode.stationary => normalizedAccuracy.clamp(5, 15).toDouble(),
      LocationMotionMode.moving => normalizedAccuracy.clamp(8, 20).toDouble(),
      LocationMotionMode.degraded => normalizedAccuracy.clamp(20, 40).toDouble(),
      LocationMotionMode.acquiring => normalizedAccuracy.clamp(20, 40).toDouble(),
    };
  }

  double _jitterThresholdMeters(LocationData current, LocationData candidate) {
    final currentAccuracy = current.accuracyMeters <= 0 ? 10 : current.accuracyMeters;
    final candidateAccuracy =
        candidate.accuracyMeters <= 0 ? 10 : candidate.accuracyMeters;
    final combinedAccuracy = ((currentAccuracy + candidateAccuracy) / 2).clamp(
      _minimumMovementMeters,
      18,
    );
    return combinedAccuracy.toDouble();
  }

  bool _isMeaningfullyMoreAccurate(
    LocationData candidate,
    LocationData current,
  ) {
    return candidate.accuracyMeters > 0 &&
        (current.accuracyMeters <= 0 ||
            candidate.accuracyMeters <= current.accuracyMeters * 0.65);
  }

  double? _elapsedSeconds(DateTime? start, DateTime? end) {
    if (start == null || end == null) {
      return null;
    }
    final milliseconds = end.toUtc().difference(start.toUtc()).inMilliseconds;
    if (milliseconds <= 0) {
      return null;
    }
    return milliseconds / 1000;
  }

  @visibleForTesting
  LocationData? acceptPositionForTest(
    LocationData candidate, {
    bool fromLastKnown = false,
  }) {
    return _acceptPosition(candidate, fromLastKnown: fromLastKnown);
  }
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => LocationService(),
);
