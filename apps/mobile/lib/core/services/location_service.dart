import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

class LocationData {
  const LocationData({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters = 0,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
}

class LocationService {
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return _toLocationData(pos);
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
      return _toLocationData(pos);
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
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    ).map(_toLocationData);
  }

  LocationData _toLocationData(Position position) {
    return LocationData(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
    );
  }
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => LocationService(),
);
