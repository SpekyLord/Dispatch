import 'dart:async';
import 'dart:math' as math;

import 'package:dispatch_mobile/core/services/kalman_location_filter.dart';
import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

class FusedLocationUpdate {
  const FusedLocationUpdate({
    required this.rawLocation,
    required this.displayLocation,
    required this.displayConfidenceMeters,
    required this.recordedAt,
    required this.isEstimating,
    this.headingDegrees,
  });

  final LocationData? rawLocation;
  final LocationData displayLocation;
  final double displayConfidenceMeters;
  final DateTime recordedAt;
  final bool isEstimating;
  final double? headingDegrees;
}

class ExperimentalLocationFusionService {
  ExperimentalLocationFusionService({
    required LocationService locationService,
    Stream<UserAccelerometerEvent>? accelerometerStream,
    Stream<GyroscopeEvent>? gyroscopeStream,
    Duration predictInterval = const Duration(milliseconds: 100),
    Duration gpsStaleThreshold = const Duration(seconds: 3),
    double weakGpsAccuracyMeters = 90,
    double strongGpsAccuracyMeters = 30,
    double deadReckoningMeasurementAccuracyMeters = 120,
  }) : _locationService = locationService,
       _accelerometerStream = accelerometerStream,
       _gyroscopeStream = gyroscopeStream,
       _predictInterval = predictInterval,
       _gpsStaleThreshold = gpsStaleThreshold,
       _weakGpsAccuracyMeters = weakGpsAccuracyMeters,
       _strongGpsAccuracyMeters = strongGpsAccuracyMeters,
       _deadReckoningMeasurementAccuracyMeters =
           deadReckoningMeasurementAccuracyMeters;

  final LocationService _locationService;
  final Stream<UserAccelerometerEvent>? _accelerometerStream;
  final Stream<GyroscopeEvent>? _gyroscopeStream;
  final Duration _predictInterval;
  final Duration _gpsStaleThreshold;
  final double _weakGpsAccuracyMeters;
  final double _strongGpsAccuracyMeters;
  final double _deadReckoningMeasurementAccuracyMeters;
  final KalmanLocationFilter _filter = KalmanLocationFilter();
  final _DeadReckoningEstimator _deadReckoner = _DeadReckoningEstimator();
  final StreamController<FusedLocationUpdate> _controller =
      StreamController<FusedLocationUpdate>.broadcast();

  StreamSubscription<LocationData>? _gpsSubscription;
  StreamSubscription<UserAccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  Timer? _predictTimer;
  LocationData? _lastRawLocation;
  LocationData? _lastTrustedGpsLocation;
  FusedLocationUpdate? _latestUpdate;
  bool _started = false;

  Stream<FusedLocationUpdate> watch() => _controller.stream;
  FusedLocationUpdate? get latestUpdate => _latestUpdate;

  Future<FusedLocationUpdate?> start() async {
    if (_started) {
      return _latestUpdate;
    }
    _started = true;

    if (!_sensorStreamsUnsupported) {
      _accelerometerSubscription =
          (_accelerometerStream ?? userAccelerometerEventStream()).listen(
            (event) => _deadReckoner.addAccelerometer(
              event,
              recordedAt: DateTime.now().toUtc(),
            ),
            onError: (_) {},
          );
      _gyroscopeSubscription = (_gyroscopeStream ?? gyroscopeEventStream())
          .listen(
            (event) => _deadReckoner.addGyroscope(
              event,
              recordedAt: DateTime.now().toUtc(),
            ),
            onError: (_) {},
          );
    }

    _gpsSubscription = _locationService.watchPosition().listen(
      _handleGpsLocation,
      onError: (_) {},
    );

    final current = await _locationService.getCurrentPosition();
    if (current != null) {
      _handleGpsLocation(current);
    }

    _predictTimer = Timer.periodic(_predictInterval, (_) {
      _emitPredictedUpdate(DateTime.now().toUtc());
    });
    return _latestUpdate;
  }

  Future<void> stop() async {
    _predictTimer?.cancel();
    _predictTimer = null;
    await _gpsSubscription?.cancel();
    await _accelerometerSubscription?.cancel();
    await _gyroscopeSubscription?.cancel();
    _gpsSubscription = null;
    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;
    _started = false;
  }

  void dispose() {
    unawaited(stop());
    unawaited(_controller.close());
  }

  void _handleGpsLocation(LocationData location) {
    final recordedAt = (location.timestamp ?? DateTime.now()).toUtc();
    final normalizedLocation = LocationData(
      latitude: location.latitude,
      longitude: location.longitude,
      accuracyMeters: location.accuracyMeters,
      timestamp: recordedAt,
    );

    _lastRawLocation = normalizedLocation;

    if (!_filter.isInitialized) {
      _filter.reset(normalizedLocation);
    } else {
      _filter.predict(timestamp: recordedAt);
      _filter.update(
        normalizedLocation,
        measurementAccuracyMeters: _normalizedGpsAccuracy(
          normalizedLocation.accuracyMeters,
        ),
      );
    }

    if (_normalizedGpsAccuracy(normalizedLocation.accuracyMeters) <=
        _strongGpsAccuracyMeters) {
      _lastTrustedGpsLocation = normalizedLocation;
      _deadReckoner.resetAnchor(
        normalizedLocation,
        initialHeadingDegrees: _filter.headingDegrees,
      );
    }

    _emitPredictedUpdate(recordedAt);
  }

  void _emitPredictedUpdate(DateTime now) {
    if (!_filter.isInitialized) {
      return;
    }

    _filter.predict(timestamp: now);
    final estimating = _shouldUseDeadReckoning(now);

    if (estimating) {
      final estimate = _deadReckoner.estimateLocation(
        now,
        fallbackHeadingDegrees: _filter.headingDegrees,
        baseAccuracyMeters: _deadReckoningMeasurementAccuracyMeters,
      );
      if (estimate != null) {
        _filter.update(
          estimate,
          measurementAccuracyMeters: estimate.accuracyMeters,
        );
      }
    }

    final currentEstimate = _filter.currentEstimate;
    if (currentEstimate == null) {
      return;
    }
    final confidence = estimating
        ? math.max(
            _deadReckoningMeasurementAccuracyMeters,
            _filter.confidenceMeters,
          )
        : _filter.confidenceMeters;
    final update = FusedLocationUpdate(
      rawLocation: _lastRawLocation,
      displayLocation: LocationData(
        latitude: currentEstimate.latitude,
        longitude: currentEstimate.longitude,
        accuracyMeters: confidence,
        timestamp: now,
      ),
      displayConfidenceMeters: confidence,
      recordedAt: now,
      isEstimating: estimating,
      headingDegrees: _filter.headingDegrees ?? _deadReckoner.headingDegrees,
    );
    _latestUpdate = update;
    if (!_controller.isClosed) {
      _controller.add(update);
    }
  }

  bool _shouldUseDeadReckoning(DateTime now) {
    final lastRawLocation = _lastRawLocation;
    if (_lastTrustedGpsLocation == null) {
      return false;
    }
    if (lastRawLocation == null) {
      return true;
    }
    final recordedAt = (lastRawLocation.timestamp ?? now).toUtc();
    final gpsIsStale = now.difference(recordedAt) > _gpsStaleThreshold;
    final accuracyIsWeak =
        _normalizedGpsAccuracy(lastRawLocation.accuracyMeters) >
        _weakGpsAccuracyMeters;
    return gpsIsStale || accuracyIsWeak;
  }

  double _normalizedGpsAccuracy(double accuracyMeters) {
    if (accuracyMeters <= 0) {
      return _strongGpsAccuracyMeters;
    }
    return accuracyMeters.clamp(
      _strongGpsAccuracyMeters,
      _deadReckoningMeasurementAccuracyMeters,
    );
  }

  bool get _sensorStreamsUnsupported {
    if (kIsWeb) {
      return true;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => false,
      _ => true,
    };
  }
}

class _DeadReckoningEstimator {
  static const double _headingFallbackSeconds = 1.5;
  static const double _movementCapMeters = 160;

  LocationData? _anchor;
  double _northOffsetMeters = 0;
  double _eastOffsetMeters = 0;
  double _speedMetersPerSecond = 0;
  double _headingRadians = 0;
  DateTime? _lastIntegratedAt;
  DateTime? _lastAccelerometerAt;
  DateTime? _lastGyroscopeAt;

  double? get headingDegrees {
    if (_anchor == null) {
      return null;
    }
    return _normalizeHeading(_headingRadians * 180 / math.pi);
  }

  void resetAnchor(LocationData location, {double? initialHeadingDegrees}) {
    _anchor = LocationData(
      latitude: location.latitude,
      longitude: location.longitude,
      accuracyMeters: location.accuracyMeters,
      timestamp: (location.timestamp ?? DateTime.now()).toUtc(),
    );
    _northOffsetMeters = 0;
    _eastOffsetMeters = 0;
    _speedMetersPerSecond = 0;
    _headingRadians = ((initialHeadingDegrees ?? 0) * math.pi) / 180;
    _lastIntegratedAt = _anchor!.timestamp;
    _lastAccelerometerAt = null;
    _lastGyroscopeAt = null;
  }

  void addAccelerometer(
    UserAccelerometerEvent event, {
    required DateTime recordedAt,
  }) {
    _integrateUntil(recordedAt);

    final previousRecordedAt = _lastAccelerometerAt;
    _lastAccelerometerAt = recordedAt;
    if (previousRecordedAt == null) {
      return;
    }

    final dtSeconds =
        recordedAt.difference(previousRecordedAt).inMilliseconds / 1000;
    if (dtSeconds <= 0) {
      return;
    }

    final planarAcceleration = math.sqrt(
      (event.x * event.x) + (event.y * event.y),
    );
    final dampedAcceleration = math.max(0, planarAcceleration - 0.12);
    final speedDelta = dampedAcceleration * dtSeconds * 0.9;
    _speedMetersPerSecond = (_speedMetersPerSecond + speedDelta).clamp(0, 2.4);
  }

  void addGyroscope(GyroscopeEvent event, {required DateTime recordedAt}) {
    final previousRecordedAt = _lastGyroscopeAt;
    _lastGyroscopeAt = recordedAt;
    if (previousRecordedAt == null) {
      _integrateUntil(recordedAt);
      return;
    }

    final dtSeconds =
        recordedAt.difference(previousRecordedAt).inMilliseconds / 1000;
    if (dtSeconds <= 0) {
      return;
    }
    _headingRadians += event.z * dtSeconds;
    _integrateUntil(recordedAt);
  }

  LocationData? estimateLocation(
    DateTime recordedAt, {
    required double? fallbackHeadingDegrees,
    required double baseAccuracyMeters,
  }) {
    final anchor = _anchor;
    if (anchor == null) {
      return null;
    }

    _integrateUntil(recordedAt, fallbackHeadingDegrees: fallbackHeadingDegrees);

    final offsetDistanceMeters = math.sqrt(
      (_northOffsetMeters * _northOffsetMeters) +
          (_eastOffsetMeters * _eastOffsetMeters),
    );
    if (offsetDistanceMeters > _movementCapMeters && offsetDistanceMeters > 0) {
      final scale = _movementCapMeters / offsetDistanceMeters;
      _northOffsetMeters *= scale;
      _eastOffsetMeters *= scale;
    }

    final latitude =
        anchor.latitude + (_northOffsetMeters / _metersPerLatitudeDegree);
    final longitude =
        anchor.longitude +
        (_eastOffsetMeters / _metersPerLongitudeDegree(anchor.latitude));
    final confidence = math.max(
      baseAccuracyMeters,
      baseAccuracyMeters + (offsetDistanceMeters * 0.35),
    );
    return LocationData(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: confidence,
      timestamp: recordedAt,
    );
  }

  void _integrateUntil(DateTime recordedAt, {double? fallbackHeadingDegrees}) {
    if (_anchor == null) {
      return;
    }

    final previousIntegratedAt = _lastIntegratedAt;
    _lastIntegratedAt = recordedAt;
    if (previousIntegratedAt == null) {
      return;
    }

    final dtSeconds =
        recordedAt.difference(previousIntegratedAt).inMilliseconds / 1000;
    if (dtSeconds <= 0) {
      return;
    }

    final lastGyroscopeAt = _lastGyroscopeAt;
    if (fallbackHeadingDegrees != null &&
        (lastGyroscopeAt == null ||
            recordedAt.difference(lastGyroscopeAt).inMilliseconds / 1000 >
                _headingFallbackSeconds)) {
      _headingRadians = (fallbackHeadingDegrees * math.pi) / 180;
    }

    final distanceMeters = _speedMetersPerSecond * dtSeconds;
    _northOffsetMeters += math.cos(_headingRadians) * distanceMeters;
    _eastOffsetMeters += math.sin(_headingRadians) * distanceMeters;
    _speedMetersPerSecond *= math.pow(0.92, dtSeconds * 8).toDouble();
  }

  double _metersPerLongitudeDegree(double latitude) {
    final cosine = math.cos(latitude * math.pi / 180).abs();
    return _metersPerLatitudeDegree * (cosine < 0.2 ? 0.2 : cosine);
  }

  static double _normalizeHeading(double headingDegrees) {
    final normalized = headingDegrees % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  static const double _metersPerLatitudeDegree = 111111;
}
