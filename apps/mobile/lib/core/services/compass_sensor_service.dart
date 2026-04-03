import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CompassHeadingSample {
  const CompassHeadingSample({
    required this.headingDegrees,
    required this.accuracy,
    required this.recordedAt,
    this.source = 'platform',
  });

  final double headingDegrees;
  final double accuracy;
  final DateTime recordedAt;
  final String source;
}

class CompassSensorService {
  CompassSensorService({Stream<CompassHeadingSample>? headingStream})
    : _overrideStream = headingStream;

  static const EventChannel _channel = EventChannel(
    'dispatch_mobile/compass_heading',
  );

  final Stream<CompassHeadingSample>? _overrideStream;
  Stream<CompassHeadingSample>? _cachedStream;

  Stream<CompassHeadingSample> watchHeading() {
    final overrideStream = _overrideStream;
    if (overrideStream != null) {
      return overrideStream;
    }
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return const Stream<CompassHeadingSample>.empty();
    }

    return _cachedStream ??= _channel
        .receiveBroadcastStream()
        .map((event) {
          final map = Map<String, dynamic>.from(event as Map);
          return CompassHeadingSample(
            headingDegrees: normalizeHeading(
              (map['heading'] as num?)?.toDouble() ?? 0,
            ),
            accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0,
            recordedAt: DateTime.fromMillisecondsSinceEpoch(
              (map['timestamp'] as num?)?.toInt() ??
                  DateTime.now().millisecondsSinceEpoch,
              isUtc: true,
            ),
            source: map['source'] as String? ?? 'platform',
          );
        })
        .handleError((Object error, StackTrace stackTrace) {})
        .asBroadcastStream();
  }

  static double normalizeHeading(double degrees) {
    final normalized = degrees % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }
}

final compassSensorProvider = Provider<CompassSensorService>(
  (ref) => CompassSensorService(),
);
