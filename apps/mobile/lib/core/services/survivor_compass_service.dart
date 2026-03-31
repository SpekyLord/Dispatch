import 'dart:math' as math;

import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/sar_mode_service.dart';
import 'package:latlong2/latlong.dart';

enum SurvivorCompassConfidenceBand { directLock, relayAssist, broadSearch }

class SurvivorCompassSnapshot {
  const SurvivorCompassSnapshot({
    required this.headingDegrees,
    required this.bearingDegrees,
    required this.relativeTurnDegrees,
    required this.distanceToDetectionNodeMeters,
    required this.targetCardinalLabel,
    required this.confidenceBand,
    required this.rescuerPoint,
    required this.targetPoint,
    required this.peerPreviewPoints,
  });

  final double headingDegrees;
  final double bearingDegrees;
  final double relativeTurnDegrees;
  final double distanceToDetectionNodeMeters;
  final String targetCardinalLabel;
  final SurvivorCompassConfidenceBand confidenceBand;
  final LatLng rescuerPoint;
  final LatLng targetPoint;
  final List<LatLng> peerPreviewPoints;

  bool get shouldPulse => distanceToDetectionNodeMeters < 3;
}

class SurvivorCompassService {
  static const Distance _distance = Distance();

  static SurvivorCompassSnapshot buildSnapshot({
    required LocationData rescuerLocation,
    required double headingDegrees,
    required SurvivorSignalEvent target,
    required List<MeshPeer> peers,
  }) {
    final bearing = bearingDegrees(rescuerLocation, target);
    return SurvivorCompassSnapshot(
      headingDegrees: normalizeDegrees(headingDegrees),
      bearingDegrees: bearing,
      relativeTurnDegrees: relativeTurnDegrees(
        headingDegrees: headingDegrees,
        bearingDegrees: bearing,
      ),
      distanceToDetectionNodeMeters: distanceMeters(rescuerLocation, target),
      targetCardinalLabel: cardinalLabel(bearing),
      confidenceBand: confidenceBandFor(target),
      rescuerPoint: LatLng(rescuerLocation.latitude, rescuerLocation.longitude),
      targetPoint: LatLng(target.nodeLocation.lat, target.nodeLocation.lng),
      peerPreviewPoints: buildPeerPreviewPoints(rescuerLocation, peers),
    );
  }

  static double distanceMeters(
    LocationData rescuerLocation,
    SurvivorSignalEvent target,
  ) {
    return _distance.as(
      LengthUnit.Meter,
      LatLng(rescuerLocation.latitude, rescuerLocation.longitude),
      LatLng(target.nodeLocation.lat, target.nodeLocation.lng),
    );
  }

  static double bearingDegrees(
    LocationData rescuerLocation,
    SurvivorSignalEvent target,
  ) {
    final startLat = rescuerLocation.latitude * math.pi / 180;
    final endLat = target.nodeLocation.lat * math.pi / 180;
    final deltaLng =
        (target.nodeLocation.lng - rescuerLocation.longitude) * math.pi / 180;
    final y = math.sin(deltaLng) * math.cos(endLat);
    final x =
        math.cos(startLat) * math.sin(endLat) -
        math.sin(startLat) * math.cos(endLat) * math.cos(deltaLng);
    return normalizeDegrees(math.atan2(y, x) * 180 / math.pi);
  }

  static double relativeTurnDegrees({
    required double headingDegrees,
    required double bearingDegrees,
  }) {
    final delta =
        (normalizeDegrees(bearingDegrees) -
                normalizeDegrees(headingDegrees) +
                540) %
            360 -
        180;
    return delta;
  }

  static double normalizeDegrees(double degrees) {
    final normalized = degrees % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  static String cardinalLabel(double degrees) {
    const labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((normalizeDegrees(degrees) + 22.5) ~/ 45) % labels.length;
    return labels[index];
  }

  static SurvivorCompassConfidenceBand confidenceBandFor(
    SurvivorSignalEvent target,
  ) {
    if (!target.isRelayed && target.confidence >= 0.85) {
      return SurvivorCompassConfidenceBand.directLock;
    }
    if (target.hopCount <= 2 && target.confidence >= 0.7) {
      return SurvivorCompassConfidenceBand.relayAssist;
    }
    return SurvivorCompassConfidenceBand.broadSearch;
  }

  static String confidenceBandLabel(SurvivorCompassConfidenceBand band) {
    return switch (band) {
      SurvivorCompassConfidenceBand.directLock => 'Direct lock',
      SurvivorCompassConfidenceBand.relayAssist => 'Relay assist',
      SurvivorCompassConfidenceBand.broadSearch => 'Broad search',
    };
  }

  static String confidenceBandBody(SurvivorCompassConfidenceBand band) {
    return switch (band) {
      SurvivorCompassConfidenceBand.directLock =>
        'Signal likely came from the detecting node itself. Tighten the search radius as you close in.',
      SurvivorCompassConfidenceBand.relayAssist =>
        'This signal passed through nearby responders. Use the compass to reach the detector node, then sweep locally.',
      SurvivorCompassConfidenceBand.broadSearch =>
        'Multi-hop relay adds uncertainty. Treat this as a search corridor rather than a precise point.',
    };
  }

  // Relative peer points keep nearby discovery visible even before peer GPS
  // uploads are available in the mesh sync contract.
  static List<LatLng> buildPeerPreviewPoints(
    LocationData rescuerLocation,
    List<MeshPeer> peers,
  ) {
    if (peers.isEmpty) {
      return const [];
    }

    final latMeters = 111320.0;
    final lngScale = math.cos(rescuerLocation.latitude * math.pi / 180).abs();
    final lngMeters = latMeters * (lngScale < 0.2 ? 0.2 : lngScale);
    final points = <LatLng>[];

    for (var index = 0; index < peers.length; index += 1) {
      final angle = (2 * math.pi * index) / peers.length;
      final radiusMeters = 28 + (index % 3) * 12;
      final latOffset = (math.sin(angle) * radiusMeters) / latMeters;
      final lngOffset = (math.cos(angle) * radiusMeters) / lngMeters;
      points.add(
        LatLng(
          rescuerLocation.latitude + latOffset,
          rescuerLocation.longitude + lngOffset,
        ),
      );
    }

    return points;
  }
}
