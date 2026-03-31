import 'dart:async';
import 'dart:math' as math;

import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/compass_sensor_service.dart';
import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/sar_mode_service.dart';
import 'package:dispatch_mobile/core/services/survivor_compass_service.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/shared/presentation/dispatch_map_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

const _warmBackground = Color(0xFFFDF7F2);
const _warmPanel = Color(0xFFFFF8F3);
const _warmBorder = Color(0xFFE7D1C6);
const _warmAccent = Color(0xFFA14B2F);
const _coolAccent = Color(0xFF1695D3);
const _deepText = Color(0xFF4E433D);
const _mutedText = Color(0xFF7A6B63);

class SurvivorCompassScreen extends ConsumerStatefulWidget {
  const SurvivorCompassScreen({
    super.key,
    this.initialTargetMessageId,
    this.showMiniMap = true,
  });

  final String? initialTargetMessageId;
  final bool showMiniMap;

  @override
  ConsumerState<SurvivorCompassScreen> createState() =>
      _SurvivorCompassScreenState();
}

class _SurvivorCompassScreenState extends ConsumerState<SurvivorCompassScreen>
    with SingleTickerProviderStateMixin {
  final _resolutionController = TextEditingController();
  StreamSubscription<CompassHeadingSample>? _headingSub;
  StreamSubscription<LocationData>? _locationSub;
  late final AnimationController _pulseController;
  CompassHeadingSample? _headingSample;
  LocationData? _rescuerLocation;
  bool _bootstrapping = true;
  bool _resolving = false;
  bool _pulseActive = false;
  DateTime? _lastHapticAt;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    final initialTargetMessageId = widget.initialTargetMessageId;
    if (initialTargetMessageId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ref
            .read(sarModeControllerProvider.notifier)
            .pinTarget(initialTargetMessageId);
      });
    }
    unawaited(_bindSensors());
    unawaited(Future<void>.microtask(() => _hydrateSignals(silent: true)));
  }

  Future<void> _bindSensors() async {
    final locationService = ref.read(locationServiceProvider);
    final currentLocation = await locationService.getCurrentPosition();
    if (mounted && currentLocation != null) {
      setState(() {
        _rescuerLocation = currentLocation;
      });
      _syncPulseState();
    }

    _headingSub = ref.read(compassSensorProvider).watchHeading().listen((
      sample,
    ) {
      if (!mounted) {
        return;
      }
      setState(() {
        _headingSample = sample;
      });
      _syncPulseState();
    });

    _locationSub = locationService.watchPosition().listen((location) {
      if (!mounted) {
        return;
      }
      setState(() {
        _rescuerLocation = location;
      });
      _syncPulseState();
    });

    if (mounted) {
      setState(() {
        _bootstrapping = false;
      });
    }
  }

  Future<void> _hydrateSignals({bool silent = false}) async {
    try {
      final auth = ref.read(authServiceProvider);
      final rows = await auth.getSurvivorSignals(status: 'active');
      ref.read(sarModeControllerProvider.notifier).ingestServerSignals(rows);

      final lastSeenResponse = await auth.getMeshLastSeen();
      final devices =
          (lastSeenResponse['devices'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>();
      ref.read(meshTransportProvider).ingestServerLastSeen(devices);
      await _hydrateTrailForActiveTarget(authOverride: auth);
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      if (!silent && mounted) {
        _showSnack(
          'Live survivor sync is unavailable right now. Local SAR detections are still visible.',
        );
      }
    }
  }

  Future<void> _hydrateTrailForActiveTarget({
    AuthService? authOverride,
    String? deviceFingerprint,
  }) async {
    final fingerprint =
        deviceFingerprint ??
        ref.read(sarModeControllerProvider).activeTarget?.detectedDeviceIdentifier;
    if (fingerprint == null || fingerprint.isEmpty) {
      return;
    }

    try {
      final AuthService auth = authOverride ?? ref.read(authServiceProvider);
      final trailResponse = await auth.getMeshTrail(
        fingerprint,
        limit: 120,
      );
      final points =
          (trailResponse['points'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>();
      ref.read(meshTransportProvider).ingestServerTrail(fingerprint, points);
      if (mounted) {
        setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _handleRefresh() async {
    final currentLocation = await ref
        .read(locationServiceProvider)
        .getCurrentPosition();
    if (mounted && currentLocation != null) {
      setState(() {
        _rescuerLocation = currentLocation;
      });
      _syncPulseState();
    }
    await _hydrateSignals();
  }

  void _handlePinTarget(String messageId) {
    ref.read(sarModeControllerProvider.notifier).pinTarget(messageId);
    final signals = ref.read(sarModeControllerProvider).activeSignals;
    for (final signal in signals) {
      if (signal.messageId == messageId) {
        unawaited(
          _hydrateTrailForActiveTarget(
            deviceFingerprint: signal.detectedDeviceIdentifier,
          ),
        );
        break;
      }
    }
    _syncPulseState();
  }

  Future<void> _markLocated(SurvivorSignalEvent target) async {
    if (_resolving) {
      return;
    }

    setState(() {
      _resolving = true;
    });

    final note = _resolutionController.text.trim();
    final controller = ref.read(sarModeControllerProvider.notifier);
    final responderId = ref.read(sessionControllerProvider).userId;

    try {
      final rows = await ref.read(authServiceProvider).getSurvivorSignals();
      controller.ingestServerSignals(rows);
      var signalId = target.serverSignalId;
      for (final row in rows) {
        if ((row['message_id'] as String?) == target.messageId) {
          signalId = row['id'] as String?;
          break;
        }
      }

      if (signalId == null) {
        controller.queueSurvivorResolution(
          signal: target,
          note: note,
          resolvedByUserId: responderId,
        );
        _resolutionController.clear();
        _showSnack(
          'This signal has not reached the server yet. The resolve note was added to the mesh queue for relay.',
        );
        return;
      }

      final resolved = await ref
          .read(authServiceProvider)
          .resolveSurvivorSignal(signalId, note: note);
      controller.ingestServerSignals([resolved]);
      controller.markSignalResolved(
        target.messageId,
        serverSignalId: signalId,
        note: note,
      );
      _resolutionController.clear();
      _showSnack('Signal marked as located and synced to the responder feed.');
    } catch (_) {
      controller.queueSurvivorResolution(
        signal: target,
        note: note,
        resolvedByUserId: responderId,
      );
      _resolutionController.clear();
      _showSnack(
        'Offline or API unavailable. The resolve note was added to the mesh queue for relay.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _resolving = false;
        });
      }
      _syncPulseState();
    }
  }

  void _syncPulseState() {
    final location = _rescuerLocation;
    final target = ref.read(sarModeControllerProvider).activeTarget;
    if (location == null || target == null) {
      if (_pulseActive) {
        setState(() {
          _pulseActive = false;
        });
        _pulseController.stop();
        _pulseController.value = 0;
      }
      return;
    }

    final snapshot = SurvivorCompassService.buildSnapshot(
      rescuerLocation: location,
      headingDegrees: _headingSample?.headingDegrees ?? 0,
      target: target,
      peers: ref.read(meshTransportProvider).peers,
    );

    if (snapshot.shouldPulse != _pulseActive) {
      if (!mounted) {
        return;
      }
      setState(() {
        _pulseActive = snapshot.shouldPulse;
      });
      if (snapshot.shouldPulse) {
        _pulseController.repeat(reverse: true);
        _emitHaptic(const Duration(milliseconds: 1), impact: true);
      } else {
        _pulseController.stop();
        _pulseController.value = 0;
      }
      return;
    }

    if (snapshot.shouldPulse) {
      _emitHaptic(const Duration(milliseconds: 1200), impact: false);
    }
  }

  void _emitHaptic(Duration minimumGap, {required bool impact}) {
    final now = DateTime.now();
    final lastHapticAt = _lastHapticAt;
    if (lastHapticAt != null && now.difference(lastHapticAt) < minimumGap) {
      return;
    }
    _lastHapticAt = now;
    if (impact) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _resolutionController.dispose();
    unawaited(_headingSub?.cancel());
    unawaited(_locationSub?.cancel());
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sarState = ref.watch(sarModeControllerProvider);
    final transport = ref.read(meshTransportProvider);
    final target = sarState.activeTarget;
    final snapshot = target != null && _rescuerLocation != null
        ? SurvivorCompassService.buildSnapshot(
            rescuerLocation: _rescuerLocation!,
            headingDegrees: _headingSample?.headingDegrees ?? 0,
            target: target,
            peers: transport.peers,
          )
        : null;
    final trailPoints = target == null
        ? const <DeviceLocationTrailPoint>[]
        : transport.trailForDevice(target.detectedDeviceIdentifier);

    return Scaffold(
      backgroundColor: _warmBackground,
      appBar: AppBar(
        title: const Text('Survivor Compass'),
        backgroundColor: _warmBackground,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: () => unawaited(_handleRefresh()),
            icon: const Icon(Icons.sync),
            tooltip: 'Refresh survivor feed',
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _warmAccent,
        onRefresh: _handleRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFA14B2F),
                    Color(0xFF7B3A25),
                    Color(0xFF425E72),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26131110),
                    blurRadius: 24,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'SAR Mode / Mobile Compass',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Close in on the strongest survivor trail without leaving the mesh workflow.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    target == null
                        ? 'Pin a survivor signal from the SAR feed to start bearing guidance.'
                        : 'Compass updates live from device heading, GPS position, and the selected survivor signal.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _HeroStat(
                        label: 'Tracked target',
                        value: target == null
                            ? 'None'
                            : target.detectedDeviceIdentifier,
                      ),
                      _HeroStat(
                        label: 'Nearby peers',
                        value: '${transport.peerCount}',
                      ),
                      _HeroStat(
                        label: 'Heading source',
                        value: _headingSample?.source ?? 'Awaiting sensor',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_bootstrapping && _rescuerLocation == null)
              const _InfoCard(
                icon: Icons.sensors,
                title: 'Initializing sensors',
                body:
                    'Loading location and heading inputs for the survivor compass.',
              )
            else if (target == null)
              const _InfoCard(
                icon: Icons.radar,
                title: 'No active target selected',
                body:
                    'Open the SAR feed, pick the strongest survivor signal, then return here to start bearing guidance.',
              )
            else ...[
              _CompassSummaryCard(
                headingSample: _headingSample,
                pulseActive: _pulseActive,
                pulseController: _pulseController,
                snapshot: snapshot,
                target: target,
              ),
              if (snapshot != null && widget.showMiniMap) ...[
                const SizedBox(height: 18),
                _CompassMapCard(
                  snapshot: snapshot,
                  target: target,
                  trailPoints: trailPoints,
                ),
              ],
              const SizedBox(height: 18),
              _ResolveSignalCard(
                controller: _resolutionController,
                onResolve: _resolving ? null : () => _markLocated(target),
                resolving: _resolving,
                target: target,
              ),
            ],
            const SizedBox(height: 18),
            _TargetBoard(
              activeTargetMessageId: sarState.activeTargetMessageId,
              onPinTarget: _handlePinTarget,
              signals: sarState.activeSignals,
              lastSeenLookup: transport.lastSeenForDevice,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _warmPanel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _warmBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF7EADF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: _warmAccent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _deepText,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(color: _mutedText, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompassSummaryCard extends StatelessWidget {
  const _CompassSummaryCard({
    required this.headingSample,
    required this.pulseActive,
    required this.pulseController,
    required this.snapshot,
    required this.target,
  });

  final CompassHeadingSample? headingSample;
  final bool pulseActive;
  final AnimationController pulseController;
  final SurvivorCompassSnapshot? snapshot;
  final SurvivorSignalEvent target;

  @override
  Widget build(BuildContext context) {
    final band = snapshot == null
        ? SurvivorCompassConfidenceBand.broadSearch
        : snapshot!.confidenceBand;
    final turnLabel = snapshot == null
        ? 'Turn guidance unavailable'
        : _turnLabel(snapshot!.relativeTurnDegrees);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _warmPanel,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _warmBorder),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 280,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 252,
                  height: 252,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFF4EB), Color(0xFFF2E7DE)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    border: Border.all(color: _warmBorder, width: 1.5),
                  ),
                ),
                if (pulseActive)
                  AnimatedBuilder(
                    animation: pulseController,
                    builder: (context, child) {
                      final scale = 1 + (pulseController.value * 0.35);
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 164,
                          height: 164,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _warmAccent.withValues(
                                alpha: 0.28 - pulseController.value * 0.12,
                              ),
                              width: 3,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                const Positioned(top: 20, child: _DialLabel(label: 'N')),
                const Positioned(right: 24, child: _DialLabel(label: 'E')),
                const Positioned(bottom: 20, child: _DialLabel(label: 'S')),
                const Positioned(left: 24, child: _DialLabel(label: 'W')),
                Transform.rotate(
                  angle: ((snapshot?.relativeTurnDegrees ?? 0) * math.pi) / 180,
                  child: Icon(
                    Icons.navigation,
                    size: 122,
                    color: pulseActive ? _warmAccent : _coolAccent,
                  ),
                ),
                Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: _deepText,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            snapshot == null
                ? 'Waiting for survivor location'
                : '${snapshot!.distanceToDetectionNodeMeters.toStringAsFixed(1)} m',
            style: const TextStyle(
              color: _deepText,
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            pulseActive
                ? 'Proximity pulse active'
                : 'Distance to detection node',
            style: const TextStyle(
              color: _mutedText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricChip(
                icon: Icons.explore,
                label: snapshot == null
                    ? 'Bearing unavailable'
                    : 'Bearing ${snapshot!.targetCardinalLabel}',
              ),
              _MetricChip(icon: Icons.turn_right, label: turnLabel),
              _MetricChip(
                icon: Icons.radar,
                label:
                    'Search radius ${target.estimatedDistanceMeters.toStringAsFixed(1)} m',
              ),
              _MetricChip(
                icon: Icons.my_location,
                label: headingSample == null
                    ? 'Awaiting sensor heading'
                    : 'Heading ${headingSample!.headingDegrees.toStringAsFixed(0)} deg',
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF7EADF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  SurvivorCompassService.confidenceBandLabel(band),
                  style: const TextStyle(
                    color: _deepText,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  SurvivorCompassService.confidenceBandBody(band),
                  style: const TextStyle(color: _mutedText, height: 1.5),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _MetricChip(
                      icon: Icons.bluetooth_searching,
                      label: _signalMethodLabel(target.detectionMethod),
                    ),
                    _MetricChip(
                      icon: Icons.network_ping,
                      label: target.isRelayed
                          ? '${target.hopCount} hops'
                          : 'Direct detection',
                    ),
                    _MetricChip(
                      icon: Icons.verified,
                      label: 'Confidence ${(target.confidence * 100).round()}%',
                    ),
                    if (target.isResolutionQueued)
                      const _MetricChip(
                        icon: Icons.schedule_send,
                        label: 'Resolve queued for mesh',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _signalMethodLabel(SarDetectionMethod method) {
    return switch (method) {
      SarDetectionMethod.wifiProbe => 'Wi-Fi probe',
      SarDetectionMethod.blePassive => 'BLE passive',
      SarDetectionMethod.acoustic => 'Acoustic',
      SarDetectionMethod.sosBeacon => 'SOS beacon',
    };
  }

  static String _turnLabel(double relativeTurnDegrees) {
    final magnitude = relativeTurnDegrees.abs().round();
    if (magnitude < 8) {
      return 'On heading';
    }
    return relativeTurnDegrees > 0
        ? 'Turn $magnitude deg right'
        : 'Turn $magnitude deg left';
  }
}

class _DialLabel extends StatelessWidget {
  const _DialLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(color: _deepText, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _warmBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _warmAccent),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: _deepText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompassMapCard extends StatelessWidget {
  const _CompassMapCard({
    required this.snapshot,
    required this.target,
    required this.trailPoints,
  });

  final SurvivorCompassSnapshot snapshot;
  final SurvivorSignalEvent target;
  final List<DeviceLocationTrailPoint> trailPoints;

  @override
  Widget build(BuildContext context) {
    final mapCenter = LatLng(
      (snapshot.rescuerPoint.latitude + snapshot.targetPoint.latitude) / 2,
      (snapshot.rescuerPoint.longitude + snapshot.targetPoint.longitude) / 2,
    );

    final peerMarkers = snapshot.peerPreviewPoints
        .map(
          (point) => Marker(
            point: point,
            width: 18,
            height: 18,
            child: Container(
              decoration: BoxDecoration(
                color: _deepText.withValues(alpha: 0.75),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        )
        .toList();
    final trailLatLngs = trailPoints
        .map((point) => LatLng(point.lat, point.lng))
        .toList(growable: false);
    final staleCutoff = DateTime.now().subtract(const Duration(minutes: 10));
    final recentTrail = trailPoints
        .where((point) => point.recordedAt.isAfter(staleCutoff))
        .map((point) => LatLng(point.lat, point.lng))
        .toList(growable: false);
    final trailMarkers = trailPoints
        .map(
          (point) => Marker(
            point: LatLng(point.lat, point.lng),
            width: 16,
            height: 16,
            child: _TrailDot(
              faded: point.recordedAt.isBefore(staleCutoff),
            ),
          ),
        )
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _warmPanel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _warmBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Search map inset',
            style: TextStyle(
              color: _deepText,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Peer dots are rendered as a local proximity ring until peer GPS coordinates are added to mesh sync uploads.',
            style: TextStyle(color: _mutedText, height: 1.45),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 240,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: mapCenter,
                  initialZoom: 17,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  ...buildDispatchMapTileLayers(),
                  PolylineLayer(
                    polylines: [
                      if (trailLatLngs.length >= 2)
                        Polyline(
                          points: trailLatLngs,
                          strokeWidth: 5,
                          color: _warmAccent.withValues(alpha: 0.18),
                        ),
                      if (recentTrail.length >= 2)
                        Polyline(
                          points: recentTrail,
                          strokeWidth: 4,
                          color: _warmAccent.withValues(alpha: 0.72),
                        ),
                      Polyline(
                        points: [snapshot.rescuerPoint, snapshot.targetPoint],
                        strokeWidth: 4,
                        color: _coolAccent.withValues(alpha: 0.85),
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: snapshot.rescuerPoint,
                        width: 54,
                        height: 54,
                        child: _MapMarker(
                          color: _coolAccent,
                          icon: Icons.navigation,
                          label: 'You',
                        ),
                      ),
                      Marker(
                        point: snapshot.targetPoint,
                        width: 54,
                        height: 54,
                        child: _MapMarker(
                          color: _warmAccent,
                          icon: Icons.sos,
                          label: 'Target',
                        ),
                      ),
                      ...peerMarkers,
                      ...trailMarkers,
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricChip(
                icon: Icons.route,
                label:
                    'Detection ${_CompassSummaryCard._signalMethodLabel(target.detectionMethod)}',
              ),
              _MetricChip(
                icon: Icons.people_alt_outlined,
                label: '${snapshot.peerPreviewPoints.length} nearby peers',
              ),
              if (trailPoints.isNotEmpty)
                _MetricChip(
                  icon: Icons.timeline,
                  label: '${trailPoints.length} trail points',
                ),
              if (trailPoints.isNotEmpty)
                _MetricChip(
                  icon: Icons.history,
                  label:
                      'Last beacon ${_TargetBoard._formatLastSeen(trailPoints.last.recordedAt)}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrailDot extends StatelessWidget {
  const _TrailDot({required this.faded});

  final bool faded;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: faded
            ? _warmAccent.withValues(alpha: 0.28)
            : _warmAccent.withValues(alpha: 0.82),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
    );
  }
}

class _MapMarker extends StatelessWidget {
  const _MapMarker({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: _deepText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ResolveSignalCard extends StatelessWidget {
  const _ResolveSignalCard({
    required this.controller,
    required this.onResolve,
    required this.resolving,
    required this.target,
  });

  final TextEditingController controller;
  final VoidCallback? onResolve;
  final bool resolving;
  final SurvivorSignalEvent target;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _warmPanel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _warmBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resolve this survivor signal',
            style: TextStyle(
              color: _deepText,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            target.isResolutionQueued
                ? 'A previous resolve action is already queued through the mesh. Updating it here will add a fresh relay packet with the latest note.'
                : 'Add a short note when the rescuer confirms the location, transfer, or false positive outcome.',
            style: const TextStyle(color: _mutedText, height: 1.45),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Example: survivor located near collapsed stairwell',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onResolve,
              style: FilledButton.styleFrom(
                backgroundColor: _warmAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              icon: resolving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(
                resolving ? 'Syncing resolve note...' : 'Mark located',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetBoard extends StatelessWidget {
  const _TargetBoard({
    required this.activeTargetMessageId,
    required this.onPinTarget,
    required this.signals,
    required this.lastSeenLookup,
  });

  final String? activeTargetMessageId;
  final ValueChanged<String> onPinTarget;
  final List<SurvivorSignalEvent> signals;
  final DeviceLocationTrailPoint? Function(String deviceFingerprint) lastSeenLookup;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _warmPanel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _warmBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Active survivor feed',
            style: TextStyle(
              color: _deepText,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Pin a single signal at a time so the compass can hold a stable target while the rest of the feed continues updating.',
            style: TextStyle(color: _mutedText, height: 1.45),
          ),
          const SizedBox(height: 14),
          if (signals.isEmpty)
            const _InfoCard(
              icon: Icons.wifi_find,
              title: 'No survivor signals yet',
              body:
                  'Passive SAR detections and relayed survivor packets will appear here once the local mesh receives them.',
            )
          else
            ...signals.map((signal) {
              final isPinned = signal.messageId == activeTargetMessageId;
              final resolved = signal.isResolved;
              final lastSeenBeacon = lastSeenLookup(
                signal.detectedDeviceIdentifier,
              );
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isPinned ? const Color(0xFFF7EADF) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isPinned ? _warmAccent : _warmBorder,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: resolved
                                ? const Color(0xFFE6F1E8)
                                : const Color(0xFFDCE8F3),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            switch (signal.detectionMethod) {
                              SarDetectionMethod.wifiProbe =>
                                Icons.wifi_tethering,
                              SarDetectionMethod.blePassive =>
                                Icons.bluetooth_searching,
                              SarDetectionMethod.acoustic => Icons.graphic_eq,
                              SarDetectionMethod.sosBeacon => Icons.sos,
                            },
                            color: resolved
                                ? const Color(0xFF397154)
                                : _coolAccent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                signal.detectedDeviceIdentifier,
                                style: const TextStyle(
                                  color: _deepText,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_CompassSummaryCard._signalMethodLabel(signal.detectionMethod)} | ${signal.estimatedDistanceMeters.toStringAsFixed(1)} m search radius | ${_formatLastSeen(signal.lastSeenTimestamp)}',
                                style: const TextStyle(
                                  color: _mutedText,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton(
                          onPressed: resolved
                              ? null
                              : () => onPinTarget(signal.messageId),
                          style: FilledButton.styleFrom(
                            backgroundColor: isPinned
                                ? _warmAccent
                                : _coolAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(isPinned ? 'Tracked' : 'Track'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MetricChip(
                          icon: Icons.verified,
                          label:
                              'Confidence ${(signal.confidence * 100).round()}%',
                        ),
                        _MetricChip(
                          icon: Icons.route,
                          label: signal.isRelayed
                              ? '${signal.hopCount}/${signal.maxHops} hops'
                              : 'Direct detection',
                        ),
                        if (resolved)
                          const _MetricChip(
                            icon: Icons.task_alt,
                            label: 'Resolved',
                          ),
                        if (signal.isResolutionQueued)
                          const _MetricChip(
                            icon: Icons.schedule_send,
                            label: 'Resolve queued for mesh',
                          ),
                      ],
                    ),
                    if (lastSeenBeacon != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7EADF),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Last Seen beacon ${_formatLastSeen(lastSeenBeacon.recordedAt)}',
                              style: const TextStyle(
                                color: _deepText,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${lastSeenBeacon.lat.toStringAsFixed(4)}, ${lastSeenBeacon.lng.toStringAsFixed(4)}',
                              style: const TextStyle(color: _mutedText),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "State ${lastSeenBeacon.appState.replaceAll('_', ' ')}${lastSeenBeacon.batteryPct == null ? '' : ' | Battery ${lastSeenBeacon.batteryPct}%'}",
                              style: const TextStyle(color: _mutedText),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if ((signal.resolutionNote ?? '').isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        signal.resolutionNote!,
                        style: const TextStyle(color: _mutedText, height: 1.45),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  static String _formatLastSeen(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }
    return '${diff.inHours}h ago';
  }
}



