import 'dart:math' as math;

import 'package:dispatch_mobile/core/services/location_service.dart';

class KalmanLocationFilter {
  KalmanLocationFilter({
    this.processSpeedMetersPerSecond = 1.5,
    this.minimumMeasurementAccuracyMeters = 4,
    this.maximumMeasurementAccuracyMeters = 150,
    this.maximumEstimatedSpeedMetersPerSecond = 8,
  });

  final double processSpeedMetersPerSecond;
  final double minimumMeasurementAccuracyMeters;
  final double maximumMeasurementAccuracyMeters;
  final double maximumEstimatedSpeedMetersPerSecond;

  final List<double> _state = List<double>.filled(4, 0);
  final List<List<double>> _covariance = List<List<double>>.generate(
    4,
    (_) => List<double>.filled(4, 0),
  );

  DateTime? _lastTimestamp;

  bool get isInitialized => _lastTimestamp != null;
  DateTime? get lastTimestamp => _lastTimestamp;

  LocationData? get currentEstimate {
    if (!isInitialized) {
      return null;
    }
    return LocationData(
      latitude: _state[0],
      longitude: _state[1],
      accuracyMeters: confidenceMeters,
      timestamp: _lastTimestamp,
    );
  }

  double get confidenceMeters {
    if (!isInitialized) {
      return maximumMeasurementAccuracyMeters;
    }
    final latitudeStdDegrees = math.sqrt(
      _covariance[0][0].clamp(0, double.infinity),
    );
    final longitudeStdDegrees = math.sqrt(
      _covariance[1][1].clamp(0, double.infinity),
    );
    final latitudeMeters = latitudeStdDegrees * _metersPerLatitudeDegree;
    final longitudeMeters =
        longitudeStdDegrees * _metersPerLongitudeDegree(_state[0]);
    return math.max(
      minimumMeasurementAccuracyMeters,
      ((latitudeMeters + longitudeMeters) / 2).clamp(
        minimumMeasurementAccuracyMeters,
        maximumMeasurementAccuracyMeters,
      ),
    );
  }

  double get speedMetersPerSecond {
    if (!isInitialized) {
      return 0;
    }
    final latitudeSpeed = _state[2] * _metersPerLatitudeDegree;
    final longitudeSpeed = _state[3] * _metersPerLongitudeDegree(_state[0]);
    return math.sqrt(
      (latitudeSpeed * latitudeSpeed) + (longitudeSpeed * longitudeSpeed),
    );
  }

  double? get headingDegrees {
    if (!isInitialized || speedMetersPerSecond < 0.15) {
      return null;
    }
    final northMetersPerSecond = _state[2] * _metersPerLatitudeDegree;
    final eastMetersPerSecond =
        _state[3] * _metersPerLongitudeDegree(_state[0]);
    final heading =
        math.atan2(eastMetersPerSecond, northMetersPerSecond) * 180 / math.pi;
    return _normalizeHeading(heading);
  }

  void reset(LocationData measurement) {
    final normalizedAccuracy = _normalizedAccuracy(measurement.accuracyMeters);
    final positionVariance = math
        .pow(_metersToLatitudeDegrees(normalizedAccuracy), 2)
        .toDouble();
    final velocityVariance = math
        .pow(_metersToLatitudeDegrees(processSpeedMetersPerSecond * 2), 2)
        .toDouble();

    _state[0] = measurement.latitude;
    _state[1] = measurement.longitude;
    _state[2] = 0;
    _state[3] = 0;

    for (var row = 0; row < 4; row += 1) {
      for (var column = 0; column < 4; column += 1) {
        _covariance[row][column] = 0;
      }
    }

    _covariance[0][0] = positionVariance;
    _covariance[1][1] = positionVariance;
    _covariance[2][2] = velocityVariance;
    _covariance[3][3] = velocityVariance;
    _lastTimestamp = (measurement.timestamp ?? DateTime.now()).toUtc();
  }

  LocationData? predict({DateTime? timestamp}) {
    if (!isInitialized) {
      return null;
    }

    final nextTimestamp = (timestamp ?? DateTime.now()).toUtc();
    final dtSeconds =
        nextTimestamp.difference(_lastTimestamp!).inMilliseconds / 1000;
    if (dtSeconds <= 0) {
      return currentEstimate;
    }

    _predictInternal(dtSeconds);
    _lastTimestamp = nextTimestamp;
    return currentEstimate;
  }

  LocationData update(
    LocationData measurement, {
    double? measurementAccuracyMeters,
  }) {
    final measurementTimestamp = (measurement.timestamp ?? DateTime.now())
        .toUtc();
    if (!isInitialized) {
      reset(
        LocationData(
          latitude: measurement.latitude,
          longitude: measurement.longitude,
          accuracyMeters:
              measurementAccuracyMeters ?? measurement.accuracyMeters,
          timestamp: measurementTimestamp,
        ),
      );
      return currentEstimate!;
    }

    predict(timestamp: measurementTimestamp);

    final latitudeVariance = math
        .pow(
          _metersToLatitudeDegrees(
            _normalizedAccuracy(
              measurementAccuracyMeters ?? measurement.accuracyMeters,
            ),
          ),
          2,
        )
        .toDouble();
    final longitudeVariance = math
        .pow(
          _metersToLongitudeDegrees(
            _normalizedAccuracy(
              measurementAccuracyMeters ?? measurement.accuracyMeters,
            ),
            _state[0],
          ),
          2,
        )
        .toDouble();

    final innovation = <double>[
      measurement.latitude - _state[0],
      measurement.longitude - _state[1],
    ];

    final innovationCovariance = <List<double>>[
      <double>[_covariance[0][0] + latitudeVariance, _covariance[0][1]],
      <double>[_covariance[1][0], _covariance[1][1] + longitudeVariance],
    ];
    final inverseInnovationCovariance =
        _invert2x2(innovationCovariance) ?? _identityMatrix2();

    final kalmanGain = List<List<double>>.generate(
      4,
      (row) => List<double>.filled(2, 0),
    );
    for (var row = 0; row < 4; row += 1) {
      kalmanGain[row][0] =
          (_covariance[row][0] * inverseInnovationCovariance[0][0]) +
          (_covariance[row][1] * inverseInnovationCovariance[1][0]);
      kalmanGain[row][1] =
          (_covariance[row][0] * inverseInnovationCovariance[0][1]) +
          (_covariance[row][1] * inverseInnovationCovariance[1][1]);
    }

    for (var row = 0; row < 4; row += 1) {
      _state[row] +=
          (kalmanGain[row][0] * innovation[0]) +
          (kalmanGain[row][1] * innovation[1]);
    }

    _limitVelocity();

    final identityMinusKh = List<List<double>>.generate(
      4,
      (row) => List<double>.filled(4, 0),
    );
    for (var row = 0; row < 4; row += 1) {
      for (var column = 0; column < 4; column += 1) {
        final hValue = column < 2 ? kalmanGain[row][column] : 0;
        identityMinusKh[row][column] = (row == column ? 1.0 : 0.0) - hValue;
      }
    }

    final nextCovariance = _multiply4x4(identityMinusKh, _covariance);
    for (var row = 0; row < 4; row += 1) {
      for (var column = 0; column < 4; column += 1) {
        _covariance[row][column] = nextCovariance[row][column];
      }
    }
    _lastTimestamp = measurementTimestamp;
    return currentEstimate!;
  }

  void _predictInternal(double dtSeconds) {
    final transition = <List<double>>[
      <double>[1, 0, dtSeconds, 0],
      <double>[0, 1, 0, dtSeconds],
      <double>[0, 0, 1, 0],
      <double>[0, 0, 0, 1],
    ];

    final previousState = List<double>.from(_state);
    for (var row = 0; row < 4; row += 1) {
      _state[row] = 0;
      for (var column = 0; column < 4; column += 1) {
        _state[row] += transition[row][column] * previousState[column];
      }
    }

    final projectedCovariance = _multiply4x4(
      _multiply4x4(transition, _covariance),
      _transpose4x4(transition),
    );
    final processNoise = _buildProcessNoise(dtSeconds, _state[0]);
    for (var row = 0; row < 4; row += 1) {
      for (var column = 0; column < 4; column += 1) {
        _covariance[row][column] =
            projectedCovariance[row][column] + processNoise[row][column];
      }
    }
  }

  List<List<double>> _buildProcessNoise(double dtSeconds, double latitude) {
    final positionNoiseMeters =
        processSpeedMetersPerSecond * math.max(dtSeconds, 0.1);
    final velocityNoiseMetersPerSecond = processSpeedMetersPerSecond * 0.6;
    final latitudePositionNoise = _metersToLatitudeDegrees(positionNoiseMeters);
    final longitudePositionNoise = _metersToLongitudeDegrees(
      positionNoiseMeters,
      latitude,
    );
    final latitudeVelocityNoise = _metersToLatitudeDegrees(
      velocityNoiseMetersPerSecond,
    );
    final longitudeVelocityNoise = _metersToLongitudeDegrees(
      velocityNoiseMetersPerSecond,
      latitude,
    );

    return <List<double>>[
      <double>[latitudePositionNoise * latitudePositionNoise, 0, 0, 0],
      <double>[0, longitudePositionNoise * longitudePositionNoise, 0, 0],
      <double>[0, 0, latitudeVelocityNoise * latitudeVelocityNoise, 0],
      <double>[0, 0, 0, longitudeVelocityNoise * longitudeVelocityNoise],
    ];
  }

  void _limitVelocity() {
    final currentSpeed = speedMetersPerSecond;
    if (currentSpeed <= maximumEstimatedSpeedMetersPerSecond ||
        currentSpeed <= 0) {
      return;
    }
    final scale = maximumEstimatedSpeedMetersPerSecond / currentSpeed;
    _state[2] *= scale;
    _state[3] *= scale;
  }

  double _normalizedAccuracy(double accuracyMeters) {
    final candidate = accuracyMeters <= 0
        ? minimumMeasurementAccuracyMeters
        : accuracyMeters;
    return candidate.clamp(
      minimumMeasurementAccuracyMeters,
      maximumMeasurementAccuracyMeters,
    );
  }

  double _metersToLatitudeDegrees(double meters) =>
      meters / _metersPerLatitudeDegree;

  double _metersToLongitudeDegrees(double meters, double latitude) =>
      meters / _metersPerLongitudeDegree(latitude);

  double _metersPerLongitudeDegree(double latitude) {
    final cosine = math.cos(latitude * math.pi / 180).abs();
    return _metersPerLatitudeDegree * (cosine < 0.2 ? 0.2 : cosine);
  }

  static const double _metersPerLatitudeDegree = 111111;

  List<List<double>> _multiply4x4(
    List<List<double>> left,
    List<List<double>> right,
  ) {
    final result = List<List<double>>.generate(
      4,
      (_) => List<double>.filled(4, 0),
    );
    for (var row = 0; row < 4; row += 1) {
      for (var column = 0; column < 4; column += 1) {
        for (var pivot = 0; pivot < 4; pivot += 1) {
          result[row][column] += left[row][pivot] * right[pivot][column];
        }
      }
    }
    return result;
  }

  List<List<double>> _transpose4x4(List<List<double>> matrix) {
    final result = List<List<double>>.generate(
      4,
      (_) => List<double>.filled(4, 0),
    );
    for (var row = 0; row < 4; row += 1) {
      for (var column = 0; column < 4; column += 1) {
        result[row][column] = matrix[column][row];
      }
    }
    return result;
  }

  List<List<double>>? _invert2x2(List<List<double>> matrix) {
    final determinant =
        (matrix[0][0] * matrix[1][1]) - (matrix[0][1] * matrix[1][0]);
    if (determinant.abs() < 1e-12) {
      return null;
    }
    final scale = 1 / determinant;
    return <List<double>>[
      <double>[matrix[1][1] * scale, -matrix[0][1] * scale],
      <double>[-matrix[1][0] * scale, matrix[0][0] * scale],
    ];
  }

  List<List<double>> _identityMatrix2() => const <List<double>>[
    <double>[1, 0],
    <double>[0, 1],
  ];

  static double _normalizeHeading(double headingDegrees) {
    final normalized = headingDegrees % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }
}
