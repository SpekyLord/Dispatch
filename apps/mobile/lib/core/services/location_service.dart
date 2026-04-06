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

class LocationService {
  static const Duration _maxLastKnownAge = Duration(minutes: 2);
  static const double _maxLastKnownAccuracyMeters = 80;
  static const double _maxStreamAccuracyMeters = 90;
  static const double _maxSnapBackDistanceMeters = 120;
  static const double _maxReasonableSpeedMetersPerSecond = 55;
  static const double _pendingJumpConfirmationRadiusMeters = 45;
  static const int _pendingJumpVotesRequired = 2;
  static const double _minimumMovementMeters = 4;

  LocationData? _lastAcceptedLocation;
  LocationData? _pendingJumpCandidate;
  int _pendingJumpVotes = 0;

  Future<bool> isGpsAvailable() => Geolocator.isLocationServiceEnabled();

  Future<bool> _ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
  }

  Future<LocationData?> getCurrentPosition() async {
    final hasPermission = await _ensurePermission();
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
    final hasPermission = await _ensurePermission();
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
    final hasPermission = await _ensurePermission();
    if (!hasPermission) {
      return;
    }

    yield* Geolocator.getPositionStream(
      locationSettings: _streamLocationSettings(),
    ).asyncMap((position) async {
      return _acceptPosition(_toLocationData(position), fromLastKnown: false);
    }).where((location) => location != null).cast<LocationData>();
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
        distanceFilter: 5,
      );
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
        intervalDuration: const Duration(seconds: 2),
        forceLocationManager: false,
      ),
      TargetPlatform.iOS || TargetPlatform.macOS => AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
        pauseLocationUpdatesAutomatically: false,
        activityType: ActivityType.fitness,
        allowBackgroundLocationUpdates: false,
        showBackgroundLocationIndicator: false,
      ),
      _ => const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
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
        return _lastAcceptedLocation;
      }
    }

    final current = _lastAcceptedLocation;
    if (current == null) {
      _clearPendingJump();
      _lastAcceptedLocation = candidate;
      return candidate;
    }

    final distanceMeters = Geolocator.distanceBetween(
      current.latitude,
      current.longitude,
      candidate.latitude,
      candidate.longitude,
    );
    final elapsedSeconds = _elapsedSeconds(current.timestamp, candidate.timestamp);
    final inferredSpeedMetersPerSecond =
        elapsedSeconds == null || elapsedSeconds <= 0
            ? null
            : distanceMeters / elapsedSeconds;
    final jitterThresholdMeters = _jitterThresholdMeters(current, candidate);
    final hasWorseAccuracy = candidate.accuracyMeters > current.accuracyMeters;
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
      if (_isMeaningfullyMoreAccurate(candidate, current)) {
        _clearPendingJump();
        _lastAcceptedLocation = candidate;
        return candidate;
      }
      return current;
    }

    if (impossibleSpeedJump || likelyNoisyStreamJump || likelyStaleFallback) {
      if (_shouldAcceptPendingJump(candidate)) {
        final promoted = _blendLocation(current, candidate);
        _clearPendingJump();
        _lastAcceptedLocation = promoted;
        return promoted;
      }
      return current;
    }

    _clearPendingJump();
    final next = _blendLocation(current, candidate);
    _lastAcceptedLocation = next;
    return next;
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

  double _jitterThresholdMeters(LocationData current, LocationData candidate) {
    final combinedAccuracy =
        ((current.accuracyMeters + candidate.accuracyMeters) / 2)
            .clamp(_minimumMovementMeters, 18);
    return combinedAccuracy.toDouble();
  }

  bool _isMeaningfullyMoreAccurate(LocationData candidate, LocationData current) {
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

  LocationData _blendLocation(LocationData current, LocationData candidate) {
    final distanceMeters = Geolocator.distanceBetween(
      current.latitude,
      current.longitude,
      candidate.latitude,
      candidate.longitude,
    );
    if (distanceMeters <= _minimumMovementMeters) {
      return _isMeaningfullyMoreAccurate(candidate, current) ? candidate : current;
    }

    final accuracyBlend =
        candidate.accuracyMeters <= 10
            ? 0.9
            : candidate.accuracyMeters <= 20
            ? 0.72
            : candidate.accuracyMeters <= 35
            ? 0.58
            : candidate.accuracyMeters <= 50
            ? 0.44
            : 0.3;
    final distanceBlend =
        distanceMeters >= 120
            ? 0.16
            : distanceMeters >= 50
            ? 0.08
            : 0.0;
    final alpha = (accuracyBlend + distanceBlend).clamp(0.25, 0.92);

    return LocationData(
      latitude:
          current.latitude + ((candidate.latitude - current.latitude) * alpha),
      longitude:
          current.longitude +
          ((candidate.longitude - current.longitude) * alpha),
      accuracyMeters: candidate.accuracyMeters,
      timestamp: candidate.timestamp,
    );
  }
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => LocationService(),
);
