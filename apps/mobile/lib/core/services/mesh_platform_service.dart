import 'dart:async';
import 'dart:io';

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
    required this.deviceName,
    required this.isGateway,
    required this.observedAt,
  });

  final String endpointId;
  final String deviceName;
  final bool isGateway;
  final DateTime observedAt;

  factory MeshPeerObservation.fromPlatformMap(Map<dynamic, dynamic> json) {
    return MeshPeerObservation(
      endpointId: (json['endpointId'] as String?) ?? 'unknown-peer',
      deviceName: (json['deviceName'] as String?) ?? 'Dispatch Node',
      isGateway: json['isGateway'] == true,
      observedAt: _readObservedAt(json['timestamp']) ?? DateTime.now().toUtc(),
    );
  }
}

enum MeshPlatformEventType { peerSeen }

class MeshPlatformEvent {
  const MeshPlatformEvent._({required this.type, this.peer});

  final MeshPlatformEventType type;
  final MeshPeerObservation? peer;

  factory MeshPlatformEvent.fromPlatformMap(Map<dynamic, dynamic> json) {
    return MeshPlatformEvent._(
      type: MeshPlatformEventType.peerSeen,
      peer: MeshPeerObservation.fromPlatformMap(json),
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
  Future<void> stopDiscovery() async {}

  @override
  void dispose() {}
}

// Bridges native peer discovery into the Dart transport layer without leaking platform details upstream.
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
    if (!Platform.isAndroid) {
      return MeshPlatformCapabilities.unsupported(
        'Native mesh discovery currently ships with Android-host integrations only.',
      );
    }

    try {
      final json = await _controlChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getCapabilities',
      );
      if (json == null) {
        return MeshPlatformCapabilities.unsupported(
          'Native mesh discovery bridge is unavailable on this build.',
        );
      }
      return MeshPlatformCapabilities.fromJson(json);
    } on MissingPluginException {
      return MeshPlatformCapabilities.unsupported(
        'Native mesh discovery bridge is unavailable on this build.',
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
    if (!Platform.isAndroid) {
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
  Future<void> stopDiscovery() async {
    if (!Platform.isAndroid) {
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

DateTime? _readObservedAt(dynamic rawTimestamp) {
  if (rawTimestamp is int) {
    return DateTime.fromMillisecondsSinceEpoch(rawTimestamp).toUtc();
  }
  if (rawTimestamp is String) {
    return DateTime.tryParse(rawTimestamp)?.toUtc();
  }
  return null;
}



