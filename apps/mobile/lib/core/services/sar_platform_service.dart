import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

const String sarSosServiceUuid = '6f53a7fb-3258-4d8f-bf1d-6cf36442f0e0';

class SarPlatformCapabilities {
  const SarPlatformCapabilities({
    required this.wifiProbeSupported,
    required this.blePassiveSupported,
    required this.acousticSupported,
    required this.sosBeaconSupported,
    this.wifiProbeNote,
    this.blePassiveNote,
    this.acousticNote,
    this.sosBeaconNote,
  });

  final bool wifiProbeSupported;
  final bool blePassiveSupported;
  final bool acousticSupported;
  final bool sosBeaconSupported;
  final String? wifiProbeNote;
  final String? blePassiveNote;
  final String? acousticNote;
  final String? sosBeaconNote;

  factory SarPlatformCapabilities.fromJson(Map<dynamic, dynamic> json) {
    return SarPlatformCapabilities(
      wifiProbeSupported: json['wifiProbeSupported'] == true,
      blePassiveSupported: json['blePassiveSupported'] == true,
      acousticSupported: json['acousticSupported'] == true,
      sosBeaconSupported: json['sosBeaconSupported'] == true,
      wifiProbeNote: json['wifiProbeNote'] as String?,
      blePassiveNote: json['blePassiveNote'] as String?,
      acousticNote: json['acousticNote'] as String?,
      sosBeaconNote: json['sosBeaconNote'] as String?,
    );
  }

  factory SarPlatformCapabilities.unsupported([String? note]) {
    return SarPlatformCapabilities(
      wifiProbeSupported: false,
      blePassiveSupported: false,
      acousticSupported: false,
      sosBeaconSupported: false,
      wifiProbeNote: note,
      blePassiveNote: note,
      acousticNote: note,
      sosBeaconNote: note,
    );
  }
}

class WifiProbeObservation {
  const WifiProbeObservation({
    required this.deviceIdentifier,
    required this.signalStrengthDbm,
    this.observedAt,
  });

  final String deviceIdentifier;
  final int signalStrengthDbm;
  final DateTime? observedAt;

  factory WifiProbeObservation.fromPlatformMap(Map<dynamic, dynamic> json) {
    return WifiProbeObservation(
      deviceIdentifier:
          (json['deviceIdentifier'] as String?) ??
          (json['macAddress'] as String?) ??
          'UNKNOWN',
      signalStrengthDbm:
          (json['signalStrengthDbm'] as num?)?.toInt() ??
          (json['rssi'] as num?)?.toInt() ??
          -95,
      observedAt: _readObservedAt(json['timestamp']),
    );
  }
}

class BlePassiveScanSample {
  const BlePassiveScanSample({
    required this.deviceIdentifier,
    required this.signalStrengthDbm,
    required this.isSosBeacon,
    this.observedAt,
  });

  final String deviceIdentifier;
  final int signalStrengthDbm;
  final bool isSosBeacon;
  final DateTime? observedAt;

  factory BlePassiveScanSample.fromPlatformMap(Map<dynamic, dynamic> json) {
    return BlePassiveScanSample(
      deviceIdentifier:
          (json['beaconIdentifier'] as String?) ??
          (json['deviceIdentifier'] as String?) ??
          (json['address'] as String?) ??
          'UNKNOWN',
      signalStrengthDbm:
          (json['signalStrengthDbm'] as num?)?.toInt() ??
          (json['rssi'] as num?)?.toInt() ??
          -95,
      isSosBeacon: json['isSosBeacon'] == true,
      observedAt: _readObservedAt(json['timestamp']),
    );
  }
}

class AcousticWindowSummary {
  const AcousticWindowSummary({
    required this.peakDb,
    required this.repeatedImpacts,
    required this.voiceBandPresent,
    required this.anomalyDetected,
    this.observedAt,
  });

  final double peakDb;
  final bool repeatedImpacts;
  final bool voiceBandPresent;
  final bool anomalyDetected;
  final DateTime? observedAt;

  factory AcousticWindowSummary.fromPlatformMap(Map<dynamic, dynamic> json) {
    return AcousticWindowSummary(
      peakDb: (json['peakDb'] as num?)?.toDouble() ?? 0,
      repeatedImpacts: json['repeatedImpacts'] == true,
      voiceBandPresent: json['voiceBandPresent'] == true,
      anomalyDetected: json['anomalyDetected'] == true,
      observedAt: _readObservedAt(json['timestamp']),
    );
  }
}

enum SarPlatformEventType { wifiProbe, blePassive, acoustic }

class SarPlatformEvent {
  const SarPlatformEvent._({
    required this.type,
    this.wifiProbe,
    this.blePassive,
    this.acoustic,
  });

  final SarPlatformEventType type;
  final WifiProbeObservation? wifiProbe;
  final BlePassiveScanSample? blePassive;
  final AcousticWindowSummary? acoustic;

  factory SarPlatformEvent.fromPlatformMap(Map<dynamic, dynamic> json) {
    final type = json['type'] as String? ?? '';
    return switch (type) {
      'wifi_probe' => SarPlatformEvent._(
        type: SarPlatformEventType.wifiProbe,
        wifiProbe: WifiProbeObservation.fromPlatformMap(json),
      ),
      'acoustic_window' => SarPlatformEvent._(
        type: SarPlatformEventType.acoustic,
        acoustic: AcousticWindowSummary.fromPlatformMap(json),
      ),
      _ => SarPlatformEvent._(
        type: SarPlatformEventType.blePassive,
        blePassive: BlePassiveScanSample.fromPlatformMap(json),
      ),
    };
  }
}

abstract class SarPlatformService {
  Stream<SarPlatformEvent> get events;

  Future<SarPlatformCapabilities> getCapabilities();

  Future<bool> startBlePassiveScan();

  Future<void> stopBlePassiveScan();

  Future<bool> startAcousticSampling();

  Future<void> stopAcousticSampling();

  Future<bool> startSosBeaconBroadcast({required String deviceId});

  Future<void> stopSosBeaconBroadcast();

  void dispose() {}
}

class NoopSarPlatformService implements SarPlatformService {
  const NoopSarPlatformService();

  @override
  Stream<SarPlatformEvent> get events => const Stream<SarPlatformEvent>.empty();

  @override
  Future<SarPlatformCapabilities> getCapabilities() async {
    return SarPlatformCapabilities.unsupported(
      'Passive sensing is only available on supported mobile hardware.',
    );
  }

  @override
  Future<bool> startAcousticSampling() async => false;

  @override
  Future<bool> startBlePassiveScan() async => false;

  @override
  Future<bool> startSosBeaconBroadcast({required String deviceId}) async =>
      false;

  @override
  Future<void> stopAcousticSampling() async {}

  @override
  Future<void> stopBlePassiveScan() async {}

  @override
  Future<void> stopSosBeaconBroadcast() async {}

  @override
  void dispose() {}
}

class MethodChannelSarPlatformService implements SarPlatformService {
  MethodChannelSarPlatformService() {
    _bindEvents();
  }

  static const MethodChannel _controlChannel = MethodChannel(
    'dispatch_mobile/sar_control',
  );
  static const EventChannel _eventsChannel = EventChannel(
    'dispatch_mobile/sar_events',
  );

  final StreamController<SarPlatformEvent> _eventController =
      StreamController<SarPlatformEvent>.broadcast();
  StreamSubscription<dynamic>? _nativeSubscription;

  @override
  Stream<SarPlatformEvent> get events => _eventController.stream;

  @override
  Future<SarPlatformCapabilities> getCapabilities() async {
    if (!Platform.isAndroid) {
      return SarPlatformCapabilities.unsupported(
        'Passive sensing currently ships with Android-host integrations only.',
      );
    }

    try {
      final json = await _controlChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getCapabilities',
      );
      if (json == null) {
        return SarPlatformCapabilities.unsupported(
          'Passive sensing bridge is unavailable on this build.',
        );
      }
      return SarPlatformCapabilities.fromJson(json);
    } on MissingPluginException {
      return SarPlatformCapabilities.unsupported(
        'Passive sensing bridge is unavailable on this build.',
      );
    } on PlatformException catch (error) {
      return SarPlatformCapabilities.unsupported(error.message);
    }
  }

  @override
  Future<bool> startAcousticSampling() async {
    return _invokeBool('startAcousticSampling');
  }

  @override
  Future<bool> startBlePassiveScan() async {
    return _invokeBool('startBlePassiveScan');
  }

  @override
  Future<bool> startSosBeaconBroadcast({required String deviceId}) async {
    return _invokeBool('startSosBeaconBroadcast', <String, dynamic>{
      'deviceId': deviceId,
    });
  }

  @override
  Future<void> stopAcousticSampling() async {
    await _invokeVoid('stopAcousticSampling');
  }

  @override
  Future<void> stopBlePassiveScan() async {
    await _invokeVoid('stopBlePassiveScan');
  }

  @override
  Future<void> stopSosBeaconBroadcast() async {
    await _invokeVoid('stopSosBeaconBroadcast');
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
          _eventController.add(SarPlatformEvent.fromPlatformMap(event));
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  Future<bool> _invokeBool(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      final result = await _controlChannel.invokeMethod<bool>(
        method,
        arguments,
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> _invokeVoid(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _controlChannel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}

DateTime? _readObservedAt(dynamic rawTimestamp) {
  if (rawTimestamp is int) {
    return DateTime.fromMillisecondsSinceEpoch(
      rawTimestamp,
      isUtc: false,
    ).toUtc();
  }
  if (rawTimestamp is String) {
    return DateTime.tryParse(rawTimestamp)?.toUtc();
  }
  return null;
}
