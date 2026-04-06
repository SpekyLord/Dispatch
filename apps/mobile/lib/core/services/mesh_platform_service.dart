import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

class MeshPlatformCapabilities {
  const MeshPlatformCapabilities({
    required this.bleDiscoverySupported,
    required this.bleAdvertisingSupported,
    required this.wifiDirectSupported,
    this.bleNote,
    this.wifiDirectNote,
  });

  final bool bleDiscoverySupported;
  final bool bleAdvertisingSupported;
  final bool wifiDirectSupported;
  final String? bleNote;
  final String? wifiDirectNote;

  factory MeshPlatformCapabilities.fromJson(Map<dynamic, dynamic> json) {
    return MeshPlatformCapabilities(
      bleDiscoverySupported: json['bleDiscoverySupported'] == true,
      bleAdvertisingSupported: json['bleAdvertisingSupported'] == true,
      wifiDirectSupported: json['wifiDirectSupported'] == true,
      bleNote: json['bleNote'] as String?,
      wifiDirectNote: json['wifiDirectNote'] as String?,
    );
  }

  factory MeshPlatformCapabilities.unsupported([String? note]) {
    return MeshPlatformCapabilities(
      bleDiscoverySupported: false,
      bleAdvertisingSupported: false,
      wifiDirectSupported: false,
      bleNote: note,
      wifiDirectNote: note,
    );
  }
}

class MeshPeerObservation {
  const MeshPeerObservation({
    required this.endpointId,
    required this.deviceId,
    required this.deviceName,
    required this.isGateway,
    required this.supportsWifiDirect,
    required this.isConnected,
    required this.observedAt,
    this.transport,
  });

  final String endpointId;
  final String? deviceId;
  final String deviceName;
  final bool isGateway;
  final bool supportsWifiDirect;
  final bool isConnected;
  final String? transport;
  final DateTime observedAt;

  factory MeshPeerObservation.fromPlatformMap(Map<dynamic, dynamic> json) {
    return MeshPeerObservation(
      endpointId: (json['endpointId'] as String?) ?? 'unknown-peer',
      deviceId: json['deviceId'] as String?,
      deviceName: (json['deviceName'] as String?) ?? 'Dispatch Node',
      isGateway: json['isGateway'] == true,
      supportsWifiDirect: json['supportsWifiDirect'] == true,
      isConnected: json['isConnected'] == true,
      transport: json['transport'] as String?,
      observedAt: _readObservedAt(json['timestamp']) ?? DateTime.now().toUtc(),
    );
  }
}

class MeshTransportSnapshot {
  const MeshTransportSnapshot({
    required this.discoveryActive,
    required this.connectedPeerCount,
    this.activeTransport,
    this.note,
  });

  final bool discoveryActive;
  final int connectedPeerCount;
  final String? activeTransport;
  final String? note;

  factory MeshTransportSnapshot.fromPlatformMap(Map<dynamic, dynamic> json) {
    return MeshTransportSnapshot(
      discoveryActive: json['discoveryActive'] == true,
      connectedPeerCount: (json['connectedPeerCount'] as num?)?.toInt() ?? 0,
      activeTransport: json['activeTransport'] as String?,
      note: json['note'] as String?,
    );
  }
}

class MeshInboundPacket {
  const MeshInboundPacket({
    required this.packet,
    required this.receivedAt,
    this.sourceEndpointId,
    this.transport,
  });

  final Map<String, dynamic> packet;
  final DateTime receivedAt;
  final String? sourceEndpointId;
  final String? transport;

  factory MeshInboundPacket.fromPlatformMap(Map<dynamic, dynamic> json) {
    return MeshInboundPacket(
      packet: ((json['packet'] as Map<dynamic, dynamic>?) ?? const {})
          .map((key, value) => MapEntry('$key', value)),
      receivedAt: _readObservedAt(json['timestamp']) ?? DateTime.now().toUtc(),
      sourceEndpointId: json['sourceEndpointId'] as String?,
      transport: json['transport'] as String?,
    );
  }
}

enum MeshPlatformEventType { peerSeen, transportState, packetReceived }

class MeshPlatformEvent {
  const MeshPlatformEvent._({
    required this.type,
    this.peer,
    this.transportState,
    this.packet,
  });

  final MeshPlatformEventType type;
  final MeshPeerObservation? peer;
  final MeshTransportSnapshot? transportState;
  final MeshInboundPacket? packet;

  factory MeshPlatformEvent.fromPlatformMap(Map<dynamic, dynamic> json) {
    final eventType = (json['type'] as String? ?? 'peer_seen').toLowerCase();
    return switch (eventType) {
      'transport_state' => MeshPlatformEvent._(
        type: MeshPlatformEventType.transportState,
        transportState: MeshTransportSnapshot.fromPlatformMap(json),
      ),
      'packet_received' => MeshPlatformEvent._(
        type: MeshPlatformEventType.packetReceived,
        packet: MeshInboundPacket.fromPlatformMap(json),
      ),
      _ => MeshPlatformEvent._(
        type: MeshPlatformEventType.peerSeen,
        peer: MeshPeerObservation.fromPlatformMap(json),
      ),
    };
  }
}

class MeshPacketSendResult {
  const MeshPacketSendResult({
    required this.sentEndpointIds,
    required this.attemptedPeerCount,
    this.transport,
  });

  final List<String> sentEndpointIds;
  final int attemptedPeerCount;
  final String? transport;

  factory MeshPacketSendResult.fromJson(Map<dynamic, dynamic>? json) {
    final payload = json ?? const {};
    return MeshPacketSendResult(
      sentEndpointIds: (payload['sentEndpointIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      attemptedPeerCount:
          (payload['attemptedPeerCount'] as num?)?.toInt() ?? 0,
      transport: payload['transport'] as String?,
    );
  }

  factory MeshPacketSendResult.empty([String? transport]) {
    return MeshPacketSendResult(
      sentEndpointIds: const [],
      attemptedPeerCount: 0,
      transport: transport,
    );
  }
}

abstract class MeshPlatformService {
  Stream<MeshPlatformEvent> get events;

  Future<MeshPlatformCapabilities> getCapabilities();

  Future<bool> startDiscovery({
    required String localDeviceId,
    required bool isGateway,
  });

  Future<MeshPacketSendResult> sendPacket({
    required Map<String, dynamic> packet,
    required String preferredTransport,
    List<String> excludeEndpointIds = const [],
  });

  Future<void> stopDiscovery();

  void dispose() {}
}

class NoopMeshPlatformService implements MeshPlatformService {
  const NoopMeshPlatformService();

  @override
  Stream<MeshPlatformEvent> get events => const Stream<MeshPlatformEvent>.empty();

  @override
  Future<MeshPlatformCapabilities> getCapabilities() async {
    return MeshPlatformCapabilities.unsupported(
      'Native mesh discovery is only available on supported Android hardware.',
    );
  }

  @override
  Future<bool> startDiscovery({
    required String localDeviceId,
    required bool isGateway,
  }) async => false;

  @override
  Future<MeshPacketSendResult> sendPacket({
    required Map<String, dynamic> packet,
    required String preferredTransport,
    List<String> excludeEndpointIds = const [],
  }) async {
    return MeshPacketSendResult.empty(preferredTransport);
  }

  @override
  Future<void> stopDiscovery() async {}

  @override
  void dispose() {}
}

// Bridges native peer discovery and packet transport into Dart without leaking platform-specific session details upstream.
class MethodChannelMeshPlatformService implements MeshPlatformService {
  MethodChannelMeshPlatformService() {
    _bindEvents();
  }

  static const MethodChannel _controlChannel = MethodChannel(
    'dispatch_mobile/mesh_control',
  );
  static const EventChannel _eventsChannel = EventChannel(
    'dispatch_mobile/mesh_events',
  );

  final StreamController<MeshPlatformEvent> _eventController =
      StreamController<MeshPlatformEvent>.broadcast();
  StreamSubscription<dynamic>? _nativeSubscription;

  @override
  Stream<MeshPlatformEvent> get events => _eventController.stream;

  @override
  Future<MeshPlatformCapabilities> getCapabilities() async {
    if (kIsWeb || !Platform.isAndroid) {
      return MeshPlatformCapabilities.unsupported(
        'Native mesh transport currently ships with Android-host integrations only.',
      );
    }

    try {
      final json = await _controlChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getCapabilities',
      );
      if (json == null) {
        return MeshPlatformCapabilities.unsupported(
          'Native mesh transport bridge is unavailable on this build.',
        );
      }
      return MeshPlatformCapabilities.fromJson(json);
    } on MissingPluginException {
      return MeshPlatformCapabilities.unsupported(
        'Native mesh transport bridge is unavailable on this build.',
      );
    } on PlatformException catch (error) {
      return MeshPlatformCapabilities.unsupported(error.message);
    }
  }

  @override
  Future<bool> startDiscovery({
    required String localDeviceId,
    required bool isGateway,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      return false;
    }
    try {
      final result = await _controlChannel.invokeMethod<bool>('startDiscovery', {
        'localDeviceId': localDeviceId,
        'isGateway': isGateway,
      });
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<MeshPacketSendResult> sendPacket({
    required Map<String, dynamic> packet,
    required String preferredTransport,
    List<String> excludeEndpointIds = const [],
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      return MeshPacketSendResult.empty(preferredTransport);
    }

    try {
      final response = await _controlChannel.invokeMethod<Map<dynamic, dynamic>>(
        'sendPacket',
        {
          'packet': packet,
          'preferredTransport': preferredTransport,
          'excludeEndpointIds': excludeEndpointIds,
        },
      );
      return MeshPacketSendResult.fromJson(response);
    } on MissingPluginException {
      return MeshPacketSendResult.empty(preferredTransport);
    } on PlatformException {
      return MeshPacketSendResult.empty(preferredTransport);
    }
  }

  @override
  Future<void> stopDiscovery() async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }
    try {
      await _controlChannel.invokeMethod<void>('stopDiscovery');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  @override
  void dispose() {
    _nativeSubscription?.cancel();
    _eventController.close();
  }

  void _bindEvents() {
    _nativeSubscription = _eventsChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map<dynamic, dynamic>) {
          _eventController.add(MeshPlatformEvent.fromPlatformMap(event));
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }
}

DateTime? _readObservedAt(dynamic raw) {
  final millis = switch (raw) {
    int value => value,
    num value => value.toInt(),
    _ => null,
  };
  if (millis == null) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
}
