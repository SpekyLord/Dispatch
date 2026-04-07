import 'package:dispatch_mobile/core/services/kalman_location_filter.dart';
import 'package:dispatch_mobile/core/services/location_service.dart';

class SmoothedTrackedLocation {
  const SmoothedTrackedLocation({
    required this.identity,
    required this.location,
    required this.isPredicting,
    required this.lastMeasurementAt,
    this.headingDegrees,
  });

  final String identity;
  final LocationData location;
  final bool isPredicting;
  final DateTime lastMeasurementAt;
  final double? headingDegrees;
}

class MeshLocationSmoothingService {
  MeshLocationSmoothingService({
    this.reinitializeAfter = const Duration(minutes: 2),
    this.staleAfter = const Duration(minutes: 5),
  });

  final Duration reinitializeAfter;
  final Duration staleAfter;
  final Map<String, _TrackedDeviceState> _trackedDevices =
      <String, _TrackedDeviceState>{};

  void ingestMeasurement(
    String identity,
    LocationData measurement, {
    double? measurementAccuracyMeters,
  }) {
    if (identity.isEmpty) {
      return;
    }
    final tracked = _trackedDevices.putIfAbsent(
      identity,
      _TrackedDeviceState.new,
    );
    final recordedAt = (measurement.timestamp ?? DateTime.now()).toUtc();

    if (!tracked.filter.isInitialized ||
        (tracked.lastMeasurementAt != null &&
            recordedAt.difference(tracked.lastMeasurementAt!) >
                reinitializeAfter)) {
      tracked.filter.reset(
        LocationData(
          latitude: measurement.latitude,
          longitude: measurement.longitude,
          accuracyMeters:
              measurementAccuracyMeters ?? measurement.accuracyMeters,
          timestamp: recordedAt,
        ),
      );
    } else {
      tracked.filter.predict(timestamp: recordedAt);
      tracked.filter.update(
        LocationData(
          latitude: measurement.latitude,
          longitude: measurement.longitude,
          accuracyMeters:
              measurementAccuracyMeters ?? measurement.accuracyMeters,
          timestamp: recordedAt,
        ),
        measurementAccuracyMeters:
            measurementAccuracyMeters ?? measurement.accuracyMeters,
      );
    }
    tracked.lastMeasurementAt = recordedAt;
  }

  SmoothedTrackedLocation? project(String identity, {DateTime? at}) {
    final tracked = _trackedDevices[identity];
    if (tracked == null || !tracked.filter.isInitialized) {
      return null;
    }
    final now = (at ?? DateTime.now()).toUtc();
    final lastMeasurementAt = tracked.lastMeasurementAt;
    if (lastMeasurementAt == null ||
        now.difference(lastMeasurementAt) > staleAfter) {
      _trackedDevices.remove(identity);
      return null;
    }

    tracked.filter.predict(timestamp: now);
    final estimate = tracked.filter.currentEstimate;
    if (estimate == null) {
      return null;
    }
    return SmoothedTrackedLocation(
      identity: identity,
      location: LocationData(
        latitude: estimate.latitude,
        longitude: estimate.longitude,
        accuracyMeters: tracked.filter.confidenceMeters,
        timestamp: now,
      ),
      isPredicting:
          now.difference(lastMeasurementAt) > const Duration(seconds: 1),
      lastMeasurementAt: lastMeasurementAt,
      headingDegrees: tracked.filter.headingDegrees,
    );
  }

  Map<String, SmoothedTrackedLocation> projectAll({DateTime? at}) {
    final now = (at ?? DateTime.now()).toUtc();
    final result = <String, SmoothedTrackedLocation>{};
    final identities = _trackedDevices.keys.toList(growable: false);
    for (final identity in identities) {
      final projected = project(identity, at: now);
      if (projected != null) {
        result[identity] = projected;
      }
    }
    return result;
  }
}

class _TrackedDeviceState {
  _TrackedDeviceState();

  final KalmanLocationFilter filter = KalmanLocationFilter();
  DateTime? lastMeasurementAt;
}
