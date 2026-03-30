import 'dart:async';

import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SarDetectionMethod { wifiProbe, blePassive, acoustic, sosBeacon }

enum AcousticPatternMatched { tapping, voice, anomalousSound, none }

extension SarDetectionMethodWireFormat on SarDetectionMethod {
  String get wireValue {
    return switch (this) {
      SarDetectionMethod.wifiProbe => 'WIFI_PROBE',
      SarDetectionMethod.blePassive => 'BLE_PASSIVE',
      SarDetectionMethod.acoustic => 'ACOUSTIC',
      SarDetectionMethod.sosBeacon => 'SOS_BEACON',
    };
  }
}

extension AcousticPatternWireFormat on AcousticPatternMatched {
  String get wireValue {
    return switch (this) {
      AcousticPatternMatched.tapping => 'tapping',
      AcousticPatternMatched.voice => 'voice',
      AcousticPatternMatched.anomalousSound => 'anomalous_sound',
      AcousticPatternMatched.none => 'none',
    };
  }
}

SarDetectionMethod _detectionMethodFromWire(String value) {
  return switch (value) {
    'WIFI_PROBE' => SarDetectionMethod.wifiProbe,
    'BLE_PASSIVE' => SarDetectionMethod.blePassive,
    'ACOUSTIC' => SarDetectionMethod.acoustic,
    'SOS_BEACON' => SarDetectionMethod.sosBeacon,
    _ => SarDetectionMethod.blePassive,
  };
}

AcousticPatternMatched _acousticPatternFromWire(String value) {
  return switch (value) {
    'tapping' => AcousticPatternMatched.tapping,
    'voice' => AcousticPatternMatched.voice,
    'anomalous_sound' => AcousticPatternMatched.anomalousSound,
    _ => AcousticPatternMatched.none,
  };
}

class SarNodeLocation {
  const SarNodeLocation({
    required this.lat,
    required this.lng,
    required this.accuracyMeters,
  });

  final double lat;
  final double lng;
  final double accuracyMeters;

  Map<String, dynamic> toJson() {
    return {'lat': lat, 'lng': lng, 'accuracyMeters': accuracyMeters};
  }

  factory SarNodeLocation.fromJson(Map<String, dynamic> json) {
    return SarNodeLocation(
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble() ?? 0,
    );
  }
}

class SurvivorSignalEvent {
  const SurvivorSignalEvent({
    required this.messageId,
    required this.detectionMethod,
    required this.signalStrengthDbm,
    required this.estimatedDistanceMeters,
    required this.detectedDeviceIdentifier,
    required this.lastSeenTimestamp,
    required this.nodeLocation,
    required this.confidence,
    required this.acousticPatternMatched,
    this.hopCount = 0,
    this.maxHops = 15,
    this.isResolved = false,
  });

  final String messageId;
  final SarDetectionMethod detectionMethod;
  final int signalStrengthDbm;
  final double estimatedDistanceMeters;
  final String detectedDeviceIdentifier;
  final DateTime lastSeenTimestamp;
  final SarNodeLocation nodeLocation;
  final double confidence;
  final AcousticPatternMatched acousticPatternMatched;
  final int hopCount;
  final int maxHops;
  final bool isResolved;

  bool get isRelayed => hopCount > 0;

  Map<String, dynamic> toPayload() {
    return {
      'detectionMethod': detectionMethod.wireValue,
      'signalStrengthDbm': signalStrengthDbm,
      'estimatedDistanceMeters': estimatedDistanceMeters,
      'detectedDeviceIdentifier': detectedDeviceIdentifier,
      'lastSeenTimestamp': lastSeenTimestamp.toUtc().toIso8601String(),
      'nodeLocation': nodeLocation.toJson(),
      'confidence': confidence,
      'acousticPatternMatched': acousticPatternMatched.wireValue,
    };
  }

  factory SurvivorSignalEvent.fromPacket(MeshPacket packet) {
    final payload = packet.payload;
    return SurvivorSignalEvent(
      messageId: packet.messageId,
      detectionMethod: _detectionMethodFromWire(
        payload['detectionMethod'] as String? ?? '',
      ),
      signalStrengthDbm: payload['signalStrengthDbm'] as int? ?? -90,
      estimatedDistanceMeters:
          (payload['estimatedDistanceMeters'] as num?)?.toDouble() ?? 0,
      detectedDeviceIdentifier:
          payload['detectedDeviceIdentifier'] as String? ?? 'unknown',
      lastSeenTimestamp:
          DateTime.tryParse(
            payload['lastSeenTimestamp'] as String? ?? packet.timestamp,
          ) ??
          DateTime.now().toUtc(),
      nodeLocation: SarNodeLocation.fromJson(
        payload['nodeLocation'] as Map<String, dynamic>? ?? {},
      ),
      confidence: (payload['confidence'] as num?)?.toDouble() ?? 0,
      acousticPatternMatched: _acousticPatternFromWire(
        payload['acousticPatternMatched'] as String? ?? 'none',
      ),
      hopCount: packet.hopCount,
      maxHops: packet.maxHops,
    );
  }
}

class AcousticSampleWindow {
  const AcousticSampleWindow({
    required this.peakDb,
    required this.repeatedImpacts,
    required this.voiceBandPresent,
    required this.anomalyDetected,
  });

  final double peakDb;
  final bool repeatedImpacts;
  final bool voiceBandPresent;
  final bool anomalyDetected;
}

class AcousticSampleClassifier {
  const AcousticSampleClassifier();

  AcousticPatternMatched classify(AcousticSampleWindow sample) {
    if (sample.voiceBandPresent && sample.peakDb >= 45) {
      return AcousticPatternMatched.voice;
    }
    if (sample.repeatedImpacts && sample.peakDb >= 35) {
      return AcousticPatternMatched.tapping;
    }
    if (sample.anomalyDetected && sample.peakDb >= 40) {
      return AcousticPatternMatched.anomalousSound;
    }
    return AcousticPatternMatched.none;
  }
}

class SarModeState {
  const SarModeState({
    this.isEnabled = false,
    this.activeSignals = const [],
    this.subsystemActive = const {
      SarDetectionMethod.wifiProbe: false,
      SarDetectionMethod.blePassive: false,
      SarDetectionMethod.acoustic: false,
      SarDetectionMethod.sosBeacon: false,
    },
  });

  final bool isEnabled;
  final List<SurvivorSignalEvent> activeSignals;
  final Map<SarDetectionMethod, bool> subsystemActive;

  SarModeState copyWith({
    bool? isEnabled,
    List<SurvivorSignalEvent>? activeSignals,
    Map<SarDetectionMethod, bool>? subsystemActive,
  }) {
    return SarModeState(
      isEnabled: isEnabled ?? this.isEnabled,
      activeSignals: activeSignals ?? this.activeSignals,
      subsystemActive: subsystemActive ?? this.subsystemActive,
    );
  }
}

class SarModeController extends StateNotifier<SarModeState> {
  SarModeController({
    required MeshTransportService transport,
    AcousticSampleClassifier acousticClassifier =
        const AcousticSampleClassifier(),
  }) : _transport = transport,
       _acousticClassifier = acousticClassifier,
       super(const SarModeState()) {
    _packetSubscription = _transport.packetStream.listen(_handlePacket);
  }

  final MeshTransportService _transport;
  final AcousticSampleClassifier _acousticClassifier;
  final Map<String, DateTime> _dedupWindow = {};
  late final StreamSubscription<MeshPacket> _packetSubscription;

  void setSarModeEnabled(bool enabled) {
    state = state.copyWith(
      isEnabled: enabled,
      subsystemActive: {
        SarDetectionMethod.wifiProbe: enabled,
        SarDetectionMethod.blePassive: enabled,
        SarDetectionMethod.acoustic: enabled,
        SarDetectionMethod.sosBeacon: _transport.isSosBeaconBroadcasting,
      },
    );
  }

  SurvivorSignalEvent? registerWifiProbe({
    required String rawDeviceIdentifier,
    required int signalStrengthDbm,
    required SarNodeLocation nodeLocation,
    DateTime? observedAt,
    double confidence = 0.74,
  }) {
    return _registerDetection(
      SurvivorSignalEvent(
        messageId: _generateLocalMessageId(),
        detectionMethod: SarDetectionMethod.wifiProbe,
        signalStrengthDbm: signalStrengthDbm,
        estimatedDistanceMeters: estimateDistanceMeters(signalStrengthDbm),
        detectedDeviceIdentifier: anonymizeDeviceIdentifier(
          rawDeviceIdentifier,
        ),
        lastSeenTimestamp: observedAt ?? DateTime.now().toUtc(),
        nodeLocation: nodeLocation,
        confidence: confidence,
        acousticPatternMatched: AcousticPatternMatched.none,
      ),
    );
  }

  SurvivorSignalEvent? registerBlePassiveScan({
    required String rawDeviceIdentifier,
    required int signalStrengthDbm,
    required SarNodeLocation nodeLocation,
    DateTime? observedAt,
    double confidence = 0.8,
  }) {
    return _registerDetection(
      SurvivorSignalEvent(
        messageId: _generateLocalMessageId(),
        detectionMethod: SarDetectionMethod.blePassive,
        signalStrengthDbm: signalStrengthDbm,
        estimatedDistanceMeters: estimateDistanceMeters(signalStrengthDbm),
        detectedDeviceIdentifier: anonymizeDeviceIdentifier(
          rawDeviceIdentifier,
        ),
        lastSeenTimestamp: observedAt ?? DateTime.now().toUtc(),
        nodeLocation: nodeLocation,
        confidence: confidence,
        acousticPatternMatched: AcousticPatternMatched.none,
      ),
    );
  }

  SurvivorSignalEvent? registerSosBeacon({
    required String beaconIdentifier,
    required int signalStrengthDbm,
    required SarNodeLocation nodeLocation,
    DateTime? observedAt,
  }) {
    return _registerDetection(
      SurvivorSignalEvent(
        messageId: _generateLocalMessageId(),
        detectionMethod: SarDetectionMethod.sosBeacon,
        signalStrengthDbm: signalStrengthDbm,
        estimatedDistanceMeters: estimateDistanceMeters(signalStrengthDbm),
        detectedDeviceIdentifier: anonymizeDeviceIdentifier(beaconIdentifier),
        lastSeenTimestamp: observedAt ?? DateTime.now().toUtc(),
        nodeLocation: nodeLocation,
        confidence: 1,
        acousticPatternMatched: AcousticPatternMatched.none,
      ),
    );
  }

  SurvivorSignalEvent? registerAcousticWindow({
    required AcousticSampleWindow sample,
    required SarNodeLocation nodeLocation,
    DateTime? observedAt,
  }) {
    final classification = _acousticClassifier.classify(sample);
    if (classification == AcousticPatternMatched.none) {
      return null;
    }

    return _registerDetection(
      SurvivorSignalEvent(
        messageId: _generateLocalMessageId(),
        detectionMethod: SarDetectionMethod.acoustic,
        signalStrengthDbm: -45,
        estimatedDistanceMeters: 3,
        detectedDeviceIdentifier: 'acoustic-${classification.wireValue}',
        lastSeenTimestamp: observedAt ?? DateTime.now().toUtc(),
        nodeLocation: nodeLocation,
        confidence: classification == AcousticPatternMatched.voice
            ? 0.86
            : 0.72,
        acousticPatternMatched: classification,
      ),
    );
  }

  void refreshSubsystemStatus() {
    state = state.copyWith(
      subsystemActive: {
        ...state.subsystemActive,
        SarDetectionMethod.sosBeacon: _transport.isSosBeaconBroadcasting,
      },
    );
  }

  SurvivorSignalEvent? _registerDetection(
    SurvivorSignalEvent event, {
    bool enqueuePacket = true,
  }) {
    if (enqueuePacket && !state.isEnabled) {
      return null;
    }
    if (_isDuplicate(event)) {
      return null;
    }

    _remember(event);
    _upsertSignal(event);

    if (enqueuePacket) {
      _transport.enqueuePacket(
        MeshPacket(
          messageId: event.messageId,
          originDeviceId: _transport.sosBeaconDeviceId ?? 'local-device',
          timestamp: event.lastSeenTimestamp.toUtc().toIso8601String(),
          maxHops: 15,
          payloadType: MeshPayloadType.survivorSignal,
          payload: event.toPayload(),
        ),
      );
    }

    return event;
  }

  // Dedupe is keyed by sensing method + anonymized source so one phone or
  // sound source does not spam the feed and relay queue during a short sweep.
  bool _isDuplicate(SurvivorSignalEvent event) {
    final key =
        '${event.detectionMethod.wireValue}:${event.detectedDeviceIdentifier}';
    final lastSeen = _dedupWindow[key];
    if (lastSeen == null) {
      return false;
    }
    return event.lastSeenTimestamp.difference(lastSeen).inSeconds.abs() < 60;
  }

  void _remember(SurvivorSignalEvent event) {
    final key =
        '${event.detectionMethod.wireValue}:${event.detectedDeviceIdentifier}';
    _dedupWindow[key] = event.lastSeenTimestamp;
  }

  void _upsertSignal(SurvivorSignalEvent event) {
    final nextSignals =
        [
          for (final existing in state.activeSignals)
            if (existing.messageId != event.messageId) existing,
          event,
        ]..sort((a, b) {
          final distanceCompare = a.estimatedDistanceMeters.compareTo(
            b.estimatedDistanceMeters,
          );
          if (distanceCompare != 0) {
            return distanceCompare;
          }
          final confidenceCompare = b.confidence.compareTo(a.confidence);
          if (confidenceCompare != 0) {
            return confidenceCompare;
          }
          return b.lastSeenTimestamp.compareTo(a.lastSeenTimestamp);
        });

    state = state.copyWith(activeSignals: nextSignals.take(25).toList());
  }

  void _handlePacket(MeshPacket packet) {
    if (packet.payloadType != MeshPayloadType.survivorSignal) {
      return;
    }
    final event = SurvivorSignalEvent.fromPacket(packet);
    _remember(event);
    _upsertSignal(event);
  }

  @override
  void dispose() {
    _packetSubscription.cancel();
    super.dispose();
  }

  static double estimateDistanceMeters(int signalStrengthDbm) {
    final txPower = -59;
    if (signalStrengthDbm == 0) {
      return 0;
    }
    final ratio = signalStrengthDbm / txPower;
    final estimate = ratio < 1
        ? ratio * ratio * 2
        : 0.89976 * ratio * ratio * ratio + 0.111;
    return double.parse(estimate.clamp(1, 25).toStringAsFixed(1));
  }

  static String anonymizeDeviceIdentifier(String rawIdentifier) {
    final segments = rawIdentifier
        .toUpperCase()
        .replaceAll('-', ':')
        .split(':');
    if (segments.length < 6) {
      final cleaned = rawIdentifier.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      if (cleaned.length <= 4) {
        return cleaned.padRight(4, 'X');
      }
      return '${cleaned.substring(0, cleaned.length - 4)}XXXX';
    }
    final normalized = [...segments.take(4), '00', '00'];
    return normalized.join(':');
  }

  String _generateLocalMessageId() {
    return 'sar-${DateTime.now().toUtc().microsecondsSinceEpoch}';
  }
}
