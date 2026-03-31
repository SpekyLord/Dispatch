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
    this.serverSignalId,
    this.isResolutionQueued = false,
    this.resolutionNote,
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
  final String? serverSignalId;
  final bool isResolutionQueued;
  final String? resolutionNote;

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

  SurvivorSignalEvent copyWith({
    SarDetectionMethod? detectionMethod,
    int? signalStrengthDbm,
    double? estimatedDistanceMeters,
    String? detectedDeviceIdentifier,
    DateTime? lastSeenTimestamp,
    SarNodeLocation? nodeLocation,
    double? confidence,
    AcousticPatternMatched? acousticPatternMatched,
    int? hopCount,
    int? maxHops,
    bool? isResolved,
    String? serverSignalId,
    bool? isResolutionQueued,
    String? resolutionNote,
  }) {
    return SurvivorSignalEvent(
      messageId: messageId,
      detectionMethod: detectionMethod ?? this.detectionMethod,
      signalStrengthDbm: signalStrengthDbm ?? this.signalStrengthDbm,
      estimatedDistanceMeters:
          estimatedDistanceMeters ?? this.estimatedDistanceMeters,
      detectedDeviceIdentifier:
          detectedDeviceIdentifier ?? this.detectedDeviceIdentifier,
      lastSeenTimestamp: lastSeenTimestamp ?? this.lastSeenTimestamp,
      nodeLocation: nodeLocation ?? this.nodeLocation,
      confidence: confidence ?? this.confidence,
      acousticPatternMatched:
          acousticPatternMatched ?? this.acousticPatternMatched,
      hopCount: hopCount ?? this.hopCount,
      maxHops: maxHops ?? this.maxHops,
      isResolved: isResolved ?? this.isResolved,
      serverSignalId: serverSignalId ?? this.serverSignalId,
      isResolutionQueued: isResolutionQueued ?? this.isResolutionQueued,
      resolutionNote: resolutionNote ?? this.resolutionNote,
    );
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

  factory SurvivorSignalEvent.fromServerJson(Map<String, dynamic> json) {
    final messageId =
        json['message_id'] as String? ?? json['messageId'] as String? ?? '';
    return SurvivorSignalEvent(
      messageId: messageId,
      detectionMethod: _detectionMethodFromWire(
        (json['detection_method'] as String?) ??
            (json['detectionMethod'] as String?) ??
            'BLE_PASSIVE',
      ),
      signalStrengthDbm:
          (json['signal_strength_dbm'] as num?)?.toInt() ??
          (json['signalStrengthDbm'] as num?)?.toInt() ??
          -90,
      estimatedDistanceMeters:
          (json['estimated_distance_meters'] as num?)?.toDouble() ??
          (json['estimatedDistanceMeters'] as num?)?.toDouble() ??
          0,
      detectedDeviceIdentifier:
          json['detected_device_identifier'] as String? ??
          json['detectedDeviceIdentifier'] as String? ??
          'unknown',
      lastSeenTimestamp:
          DateTime.tryParse(
            json['last_seen_timestamp'] as String? ??
                json['lastSeenTimestamp'] as String? ??
                json['created_at'] as String? ??
                DateTime.now().toUtc().toIso8601String(),
          ) ??
          DateTime.now().toUtc(),
      nodeLocation: SarNodeLocation.fromJson(
        json['node_location'] as Map<String, dynamic>? ??
            json['nodeLocation'] as Map<String, dynamic>? ??
            {},
      ),
      confidence:
          (json['confidence'] as num?)?.toDouble() ??
          (json['confidence_score'] as num?)?.toDouble() ??
          0,
      acousticPatternMatched: _acousticPatternFromWire(
        json['acoustic_pattern_matched'] as String? ??
            json['acousticPatternMatched'] as String? ??
            'none',
      ),
      hopCount:
          (json['hop_count'] as num?)?.toInt() ??
          (json['hopCount'] as num?)?.toInt() ??
          0,
      maxHops:
          (json['max_hops'] as num?)?.toInt() ??
          (json['maxHops'] as num?)?.toInt() ??
          15,
      isResolved: json['resolved'] == true || json['is_resolved'] == true,
      serverSignalId: json['id'] as String?,
      resolutionNote:
          json['resolution_note'] as String? ??
          json['resolutionNote'] as String?,
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
    this.activeTargetMessageId,
  });

  final bool isEnabled;
  final List<SurvivorSignalEvent> activeSignals;
  final Map<SarDetectionMethod, bool> subsystemActive;
  final String? activeTargetMessageId;

  SurvivorSignalEvent? get activeTarget {
    final targetId = activeTargetMessageId;
    if (targetId != null) {
      for (final signal in activeSignals) {
        if (signal.messageId == targetId) {
          return signal;
        }
      }
    }
    for (final signal in activeSignals) {
      if (!signal.isResolved) {
        return signal;
      }
    }
    return activeSignals.isEmpty ? null : activeSignals.first;
  }

  SarModeState copyWith({
    bool? isEnabled,
    List<SurvivorSignalEvent>? activeSignals,
    Map<SarDetectionMethod, bool>? subsystemActive,
    String? activeTargetMessageId,
    bool clearActiveTarget = false,
  }) {
    return SarModeState(
      isEnabled: isEnabled ?? this.isEnabled,
      activeSignals: activeSignals ?? this.activeSignals,
      subsystemActive: subsystemActive ?? this.subsystemActive,
      activeTargetMessageId: clearActiveTarget
          ? null
          : activeTargetMessageId ?? this.activeTargetMessageId,
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
      activeTargetMessageId: enabled ? state.activeTargetMessageId : null,
      clearActiveTarget: !enabled,
    );
  }

  void pinTarget(String messageId) {
    for (final signal in state.activeSignals) {
      if (signal.messageId == messageId) {
        state = state.copyWith(activeTargetMessageId: messageId);
        return;
      }
    }
  }

  void ingestServerSignals(Iterable<Map<String, dynamic>> rows) {
    final mergedById = <String, SurvivorSignalEvent>{
      for (final signal in state.activeSignals) signal.messageId: signal,
    };

    for (final row in rows) {
      final event = SurvivorSignalEvent.fromServerJson(row);
      if (event.messageId.isEmpty) {
        continue;
      }
      final existing = mergedById[event.messageId];
      mergedById[event.messageId] = existing == null
          ? event
          : _mergeSignal(existing, event);
    }

    final nextSignals = _sortSignals(
      mergedById.values.toList(),
    ).take(25).toList();
    state = state.copyWith(
      activeSignals: nextSignals,
      activeTargetMessageId: _nextTargetId(
        nextSignals,
        state.activeTargetMessageId,
      ),
    );
  }

  void markSignalResolved(
    String messageId, {
    String? serverSignalId,
    String? note,
    bool queued = false,
  }) {
    final nextSignals = _sortSignals(
      state.activeSignals
          .map(
            (signal) => signal.messageId == messageId
                ? signal.copyWith(
                    isResolved: true,
                    serverSignalId: serverSignalId,
                    isResolutionQueued: queued,
                    resolutionNote: note,
                  )
                : signal,
          )
          .toList(),
    );

    state = state.copyWith(
      activeSignals: nextSignals,
      activeTargetMessageId: _nextTargetId(
        nextSignals,
        state.activeTargetMessageId == messageId
            ? null
            : state.activeTargetMessageId,
      ),
      clearActiveTarget: state.activeTargetMessageId == messageId,
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
    final byId = <String, SurvivorSignalEvent>{
      for (final existing in state.activeSignals) existing.messageId: existing,
    };
    final existing = byId[event.messageId];
    byId[event.messageId] = existing == null
        ? event
        : _mergeSignal(existing, event);

    final nextSignals = _sortSignals(byId.values.toList()).take(25).toList();
    state = state.copyWith(
      activeSignals: nextSignals,
      activeTargetMessageId: _nextTargetId(
        nextSignals,
        state.activeTargetMessageId,
      ),
    );
  }

  SurvivorSignalEvent _mergeSignal(
    SurvivorSignalEvent current,
    SurvivorSignalEvent incoming,
  ) {
    final freshest =
        incoming.lastSeenTimestamp.isAfter(current.lastSeenTimestamp)
        ? incoming
        : current;
    final fallback = identical(freshest, incoming) ? current : incoming;

    return freshest.copyWith(
      isResolved: freshest.isResolved || fallback.isResolved,
      serverSignalId: freshest.serverSignalId ?? fallback.serverSignalId,
      isResolutionQueued:
          freshest.isResolutionQueued || fallback.isResolutionQueued,
      resolutionNote: freshest.resolutionNote ?? fallback.resolutionNote,
    );
  }

  List<SurvivorSignalEvent> _sortSignals(List<SurvivorSignalEvent> signals) {
    signals.sort((a, b) {
      if (a.isResolved != b.isResolved) {
        return a.isResolved ? 1 : -1;
      }
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
    return signals;
  }

  String? _nextTargetId(
    List<SurvivorSignalEvent> signals,
    String? preferredId,
  ) {
    if (preferredId != null) {
      for (final signal in signals) {
        if (signal.messageId == preferredId && !signal.isResolved) {
          return preferredId;
        }
      }
    }
    for (final signal in signals) {
      if (!signal.isResolved) {
        return signal.messageId;
      }
    }
    return signals.isEmpty ? null : signals.first.messageId;
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
