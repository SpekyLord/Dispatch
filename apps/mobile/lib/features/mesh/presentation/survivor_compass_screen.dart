import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/compass_sensor_service.dart';
import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/services/sar_mode_service.dart';
import 'package:dispatch_mobile/core/services/survivor_compass_service.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:dispatch_mobile/features/mesh/presentation/mesh_people_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Snapshot of an interactive-map node, passed into [SurvivorCompassScreen]
/// so the compass has an immediate position to render and a stable identity
/// to keep refreshing as the node moves.
class CompassTargetSeed {
  const CompassTargetSeed({
    required this.messageId,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    required this.lastSeenAt,
    this.accuracyMeters,
    this.deviceFingerprint,
    this.nodeDeviceId,
    this.role,
    this.isCitizen = false,
    this.citizenUserId,
  });

  final String messageId;
  final String displayName;
  final double latitude;
  final double longitude;
  final DateTime lastSeenAt;
  final double? accuracyMeters;
  final String? deviceFingerprint;
  final String? nodeDeviceId;
  final String? role;
  final bool isCitizen;
  final String? citizenUserId;
}

// ═══════════════════════════════════════════════════════════════════════════
// Compass Locator — Mesh Network
// Editorial design: glassmorphic nav, precision compass, tonal layering
// ═══════════════════════════════════════════════════════════════════════════

class SurvivorCompassScreen extends ConsumerStatefulWidget {
  const SurvivorCompassScreen({
    super.key,
    this.initialTargetMessageId,
    this.initialTargetSeed,
    this.showMiniMap = true,
    this.allowResolve = true,
  });

  final String? initialTargetMessageId;
  final CompassTargetSeed? initialTargetSeed;
  final bool showMiniMap;
  final bool allowResolve;

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
  Timer? _liveRefreshTimer;
  CompassTargetSeed? _targetSeed;
  CompassHeadingSample? _headingSample;
  LocationData? _rescuerLocation;
  bool _bootstrapping = true;
  bool _resolving = false;
  bool _pulseActive = false;
  DateTime? _lastHapticAt;
  final List<RealtimeSubscriptionHandle> _realtimeHandles = [];

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _targetSeed = widget.initialTargetSeed;

    // Seed the SAR controller synchronously so the compass renders the
    // selected node's position immediately, without waiting for a BLE beacon.
    final seed = _targetSeed;
    if (seed != null) {
      ref
          .read(sarModeControllerProvider.notifier)
          .upsertExternalSignal(_signalFromSeed(seed), pin: true);
    }

    final initialTargetMessageId =
        widget.initialTargetMessageId ?? seed?.messageId;
    if (initialTargetMessageId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(sarModeControllerProvider.notifier)
            .pinTarget(initialTargetMessageId);
        _refreshActiveTargetLocation();
      });
    }

    // Listen to transport updates for real-time target location changes
    ref.read(meshTransportProvider).addListener(_handleTransportUpdate);

    // Periodic refresh ensures the compass keeps tracking the target even if
    // the transport listener never fires (e.g. citizen presence updates,
    // throttled beacon batches, or stale BLE drops).
    _liveRefreshTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _refreshActiveTargetLocation(),
    );

    unawaited(_bindSensors());
    _bindRealtime();
    unawaited(Future<void>.microtask(() => _hydrateSignals(silent: true)));
  }

  @override
  void dispose() {
    ref.read(meshTransportProvider).removeListener(_handleTransportUpdate);
    _liveRefreshTimer?.cancel();
    _resolutionController.dispose();
    unawaited(_headingSub?.cancel());
    unawaited(_locationSub?.cancel());
    for (final handle in _realtimeHandles) {
      unawaited(handle.dispose());
    }
    _pulseController.dispose();
    super.dispose();
  }

  void _handleTransportUpdate() {
    if (!mounted) return;
    // Re-inject peer locations into SAR controller so compass tracks live positions
    _refreshActiveTargetLocation();
    _syncPulseState();
  }

  /// Refreshes the active target's position by consulting every available
  /// data source in priority order. Designed to be safe to call repeatedly:
  /// it never throws and only triggers a SAR upsert when something actually
  /// changed, so the compass keeps following the target as it moves.
  void _refreshActiveTargetLocation() {
    if (!mounted) return;
    final sarController = ref.read(sarModeControllerProvider.notifier);
    final target = ref.read(sarModeControllerProvider).activeTarget;
    if (target == null) return;

    final live = _resolveLiveLocationForTarget(target);
    if (live == null) return;

    // Skip churning the SAR controller when nothing meaningfully changed.
    final unchanged = live.latitude == target.nodeLocation.lat &&
        live.longitude == target.nodeLocation.lng &&
        live.lastSeenAt.isAtSameMomentAs(target.lastSeenTimestamp);
    if (unchanged) return;

    final distanceMeters = _rescuerLocation != null
        ? _computeDistance(
            _rescuerLocation!.latitude,
            _rescuerLocation!.longitude,
            live.latitude,
            live.longitude,
          )
        : target.estimatedDistanceMeters;

    sarController.upsertExternalSignal(
      SurvivorSignalEvent(
        messageId: target.messageId,
        detectionMethod: target.detectionMethod,
        signalStrengthDbm: target.signalStrengthDbm,
        estimatedDistanceMeters: distanceMeters,
        detectedDeviceIdentifier: target.detectedDeviceIdentifier,
        lastSeenTimestamp: live.lastSeenAt,
        nodeLocation: SarNodeLocation(
          lat: live.latitude,
          lng: live.longitude,
          accuracyMeters: live.accuracyMeters ?? target.nodeLocation.accuracyMeters,
        ),
        confidence: target.confidence,
        acousticPatternMatched: target.acousticPatternMatched,
      ),
      pin: true,
    );
    if (mounted) setState(() {});
  }

  /// Tries every known data source to locate [target] right now. Returns
  /// `null` only if no source has any fix at all (in which case the existing
  /// SAR position stays put rather than being wiped).
  _LiveTargetFix? _resolveLiveLocationForTarget(SurvivorSignalEvent target) {
    // 1. BLE transport last-seen by device fingerprint.
    final fingerprint = target.detectedDeviceIdentifier;
    if (fingerprint.isNotEmpty) {
      final transport = ref.read(meshTransportProvider);
      final lastSeen = transport.lastSeenForDevice(fingerprint);
      if (lastSeen != null) {
        return _LiveTargetFix(
          latitude: lastSeen.lat,
          longitude: lastSeen.lng,
          accuracyMeters: lastSeen.accuracyMeters,
          lastSeenAt: lastSeen.recordedAt,
        );
      }
    }

    // 2. Citizen nearby presence (geo-shared citizens often have no BLE).
    final seed = _targetSeed;
    if (seed != null && seed.isCitizen) {
      final presence = ref.read(citizenNearbyPresenceControllerProvider);
      for (final pin in presence.nearbyUsers) {
        final matchesUser =
            seed.citizenUserId != null && pin.userId == seed.citizenUserId;
        final matchesDevice = seed.nodeDeviceId != null &&
            pin.meshDeviceId == seed.nodeDeviceId;
        if (matchesUser || matchesDevice) {
          return _LiveTargetFix(
            latitude: pin.latitude,
            longitude: pin.longitude,
            accuracyMeters: pin.accuracyMeters,
            lastSeenAt: pin.lastSeenAt,
          );
        }
      }
    }

    return null;
  }

  /// Builds a SAR signal from a freshly-tapped map node so the compass has
  /// something to render the moment the screen mounts.
  SurvivorSignalEvent _signalFromSeed(CompassTargetSeed seed) {
    final distanceMeters = _rescuerLocation != null
        ? _computeDistance(
            _rescuerLocation!.latitude,
            _rescuerLocation!.longitude,
            seed.latitude,
            seed.longitude,
          )
        : 0.0;
    return SurvivorSignalEvent(
      messageId: seed.messageId,
      detectionMethod: SarDetectionMethod.blePassive,
      signalStrengthDbm: -62,
      estimatedDistanceMeters: distanceMeters,
      detectedDeviceIdentifier: seed.deviceFingerprint ??
          (seed.nodeDeviceId != null
              ? MeshTransportService.anonymizeDeviceFingerprint(seed.nodeDeviceId!)
              : ''),
      lastSeenTimestamp: seed.lastSeenAt,
      nodeLocation: SarNodeLocation(
        lat: seed.latitude,
        lng: seed.longitude,
        accuracyMeters: seed.accuracyMeters ?? 10,
      ),
      confidence: 0.85,
      acousticPatternMatched: AcousticPatternMatched.none,
    );
  }

  double _computeDistance(
    double lat1, double lng1, double lat2, double lng2,
  ) {
    const degToRad = math.pi / 180;
    const earthRadiusM = 6371000.0;
    final dLat = (lat2 - lat1) * degToRad;
    final dLng = (lng2 - lng1) * degToRad;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * degToRad) *
            math.cos(lat2 * degToRad) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusM * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  // ── Sensor & data management ─────────────────────────────────────────────

  Future<void> _bindSensors() async {
    final locationService = ref.read(locationServiceProvider);
    final currentLocation = await locationService.getCurrentPosition();
    if (mounted && currentLocation != null) {
      setState(() => _rescuerLocation = currentLocation);
      _syncPulseState();
    }

    _headingSub =
        ref.read(compassSensorProvider).watchHeading().listen((sample) {
      if (!mounted) return;
      setState(() => _headingSample = sample);
      _syncPulseState();
    });

    _locationSub = locationService.watchPosition().listen((location) {
      if (!mounted) return;
      setState(() => _rescuerLocation = location);
      _syncPulseState();
    });

    if (mounted) setState(() => _bootstrapping = false);
  }

  void _bindRealtime() {
    final realtime = ref.read(realtimeServiceProvider);
    if (!realtime.isConfigured) {
      return;
    }

    _realtimeHandles.addAll([
      realtime.subscribeToTable(
        table: 'survivor_signals',
        onChange: () => unawaited(_hydrateSignals(silent: true)),
      ),
      realtime.subscribeToTable(
        table: 'device_location_trail',
        onChange: () => unawaited(_hydrateSignals(silent: true)),
      ),
      realtime.subscribeToTable(
        table: 'mesh_topology_nodes',
        onChange: () => unawaited(_hydrateSignals(silent: true)),
      ),
    ]);
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
      if (mounted) setState(() {});
    } catch (_) {
      if (!silent && mounted) {
        _showSnack(
          'Live survivor sync is unavailable right now. '
          'Local SAR detections are still visible.',
        );
      }
    }

    // Inject local BLE peers as trackable signals so the compass can target them
    // even when there are no active SOS/survivor events from the server.
    try {
      final transport = ref.read(meshTransportProvider);
      final snapshot = await transport.buildTopologySnapshot();
      if (snapshot == null || !mounted) return;
      final sarController = ref.read(sarModeControllerProvider.notifier);
      final nodes = (snapshot['nodes'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      for (final node in nodes) {
        final lat = (node['lat'] as num?)?.toDouble();
        final lng = (node['lng'] as num?)?.toDouble();
        final deviceId = node['nodeDeviceId'] as String?;
        if (lat == null || lng == null || deviceId == null) continue;

        final metadata = node['metadata'];
        final metadataMap = metadata is Map<String, dynamic>
            ? metadata
            : metadata is Map
                ? Map<String, dynamic>.from(metadata)
                : const <String, dynamic>{};
        final fingerprint =
            (metadataMap['deviceFingerprint'] as String?) ??
            MeshTransportService.anonymizeDeviceFingerprint(deviceId);

        sarController.upsertExternalSignal(
          SurvivorSignalEvent(
            messageId: 'node:' + deviceId,
            detectionMethod: SarDetectionMethod.blePassive,
            signalStrengthDbm: -62,
            estimatedDistanceMeters: 0,
            detectedDeviceIdentifier: fingerprint,
            lastSeenTimestamp: DateTime.now().toUtc(),
            nodeLocation: SarNodeLocation(
              lat: lat,
              lng: lng,
              accuracyMeters: 10,
            ),
            confidence: 0.82,
            acousticPatternMatched: AcousticPatternMatched.none,
          ),
        );
      }
      if (mounted) setState(() {});
    } catch (_) {
      // BLE peer injection is best-effort; ignore errors.
    }
  }

  Future<void> _hydrateTrailForActiveTarget({
    AuthService? authOverride,
    String? deviceFingerprint,
  }) async {
    final fingerprint = deviceFingerprint ??
        ref
            .read(sarModeControllerProvider)
            .activeTarget
            ?.detectedDeviceIdentifier;
    if (fingerprint == null || fingerprint.isEmpty) return;

    try {
      final AuthService auth = authOverride ?? ref.read(authServiceProvider);
      final trailResponse = await auth.getMeshTrail(fingerprint, limit: 120);
      final points =
          (trailResponse['points'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>();
      ref.read(meshTransportProvider).ingestServerTrail(fingerprint, points);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _handleRefresh() async {
    final currentLocation =
        await ref.read(locationServiceProvider).getCurrentPosition();
    if (mounted && currentLocation != null) {
      setState(() => _rescuerLocation = currentLocation);
      _syncPulseState();
    }
    await _hydrateSignals();
  }

  void _handlePinTarget(String messageId) {
    ref.read(sarModeControllerProvider.notifier).pinTarget(messageId);
    final signals = ref.read(sarModeControllerProvider).activeSignals;
    for (final signal in signals) {
      if (signal.messageId == messageId) {
        unawaited(_hydrateTrailForActiveTarget(
          deviceFingerprint: signal.detectedDeviceIdentifier,
        ));
        break;
      }
    }
    _syncPulseState();
  }

  Future<void> _markLocated(SurvivorSignalEvent target) async {
    if (_resolving) return;
    setState(() => _resolving = true);

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
          'This signal has not reached the server yet. '
          'The resolve note was added to the mesh queue for relay.',
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
        'Offline or API unavailable. '
        'The resolve note was added to the mesh queue for relay.',
      );
    } finally {
      if (mounted) setState(() => _resolving = false);
      _syncPulseState();
    }
  }

  // ── Pulse & haptic ───────────────────────────────────────────────────────

  void _syncPulseState() {
    final location = _rescuerLocation;
    final target = ref.read(sarModeControllerProvider).activeTarget;

    // Always keep pulse animating for the ambient ripple effect
    if (!_pulseController.isAnimating) {
      _pulseController.repeat();
    }

    if (location == null || target == null) {
      if (_pulseActive && mounted) {
        setState(() => _pulseActive = false);
      }
      return;
    }

    final snapshot = SurvivorCompassService.buildSnapshot(
      rescuerLocation: location,
      headingDegrees: _headingSample?.headingDegrees ?? 0,
      target: target,
      peers: ref.read(meshTransportProvider).peers,
    );

    if (snapshot.shouldPulse != _pulseActive && mounted) {
      setState(() => _pulseActive = snapshot.shouldPulse);
      if (snapshot.shouldPulse) {
        _emitHaptic(const Duration(milliseconds: 1), impact: true);
      }
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

  // ── Action handlers ──────────────────────────────────────────────────────

  void _handlePingNode() {
    HapticFeedback.heavyImpact();
    _showSnack('Pinging node\u2026');
  }

  void _handleViewOnMap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MeshPeopleMapScreen(
          title: 'Mesh Network',
          subtitle: 'Interactive Map',
          allowResolveActions: widget.allowResolve,
          allowCompassActions: false,
        ),
      ),
    );
  }

  void _handleOpenResolve(SurvivorSignalEvent target) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ResolveSheet(
        target: target,
        controller: _resolutionController,
        resolving: _resolving,
        onResolve: () {
          Navigator.of(ctx).pop();
          _markLocated(target);
        },
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sarState = ref.watch(sarModeControllerProvider);
    final transport = ref.watch(meshTransportProvider);
    final target = sarState.activeTarget;
    final snapshot = target != null && _rescuerLocation != null
        ? SurvivorCompassService.buildSnapshot(
            rescuerLocation: _rescuerLocation!,
            headingDegrees: _headingSample?.headingDegrees ?? 0,
            target: target,
            peers: transport.peers,
          )
        : null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? dc.darkBackground : dc.background,
      body: Stack(
        children: [
          // ── Main scrollable content ──
          RefreshIndicator(
            color: dc.primary,
            onRefresh: _handleRefresh,
            child: ListView(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 64 + 32,
                bottom: MediaQuery.of(context).padding.bottom + 96,
                left: 24,
                right: 24,
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 512),
                    child: Column(
                      children: [
                        _StatusBanner(
                          target: target,
                          snapshot: snapshot,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 32),
                        _DirectionalBanner(
                          snapshot: snapshot,
                          bootstrapping: _bootstrapping,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 48),
                        _PrecisionCompass(
                          relativeTurnDegrees: snapshot?.relativeTurnDegrees,
                          distanceMeters:
                              snapshot?.distanceToDetectionNodeMeters,
                          shouldPulse: _pulseActive,
                          pulseController: _pulseController,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 48),
                        _NodeStatus(target: target, isDark: isDark),
                        const SizedBox(height: 48),
                        _ActionButtons(
                          onPingNode:
                              target != null ? _handlePingNode : null,
                          onViewOnMap: _handleViewOnMap,
                          isDark: isDark,
                        ),
                        if (sarState.activeSignals.isNotEmpty) ...[
                          const SizedBox(height: 48),
                          _TargetBoard(
                            activeTargetMessageId:
                                sarState.activeTargetMessageId,
                            onPinTarget: _handlePinTarget,
                            signals: sarState.activeSignals,
                            allowResolve: widget.allowResolve,
                            onResolve: _handleOpenResolve,
                            isDark: isDark,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Glassmorphic top nav ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _CompassAppBar(
              onBack: () => Navigator.of(context).pop(),
              onSync: () => unawaited(_handleRefresh()),
              isDark: isDark,
            ),
          ),

          // ── Fixed bottom status footer ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _StatusFooter(
              hasLocation: _rescuerLocation != null,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Glassmorphic App Bar
// ═══════════════════════════════════════════════════════════════════════════

class _CompassAppBar extends StatelessWidget {
  const _CompassAppBar({
    required this.onBack,
    required this.onSync,
    required this.isDark,
  });

  final VoidCallback onBack;
  final VoidCallback onSync;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: topPad + 64,
          padding: EdgeInsets.only(top: topPad, left: 24, right: 24),
          color: (isDark ? dc.darkBackground : dc.surfaceContainerLow)
              .withValues(alpha: 0.8),
          child: Row(
            children: [
              _NavButton(
                icon: Icons.arrow_back,
                onTap: onBack,
                isDark: isDark,
              ),
              const SizedBox(width: 16),
              Text(
                'Mesh Network',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 24,
                  letterSpacing: -0.5,
                  color: isDark ? dc.darkPrimaryAccent : dc.primary,
                ),
              ),
              const Spacer(),
              _NavButton(
                icon: Icons.sync,
                onTap: onSync,
                isDark: isDark,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.onTap,
    required this.isDark,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Icon(icon, color: isDark ? dc.darkInk : dc.onSurface),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Status Banner — Current Target + Signal Strength
// ═══════════════════════════════════════════════════════════════════════════

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.target,
    required this.snapshot,
    required this.isDark,
  });

  final SurvivorSignalEvent? target;
  final SurvivorCompassSnapshot? snapshot;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final nodeLabel = _formatNodeLabel(target);
    final signalLabel = _signalLabel(snapshot?.confidenceBand);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? dc.darkSurfaceContainer : dc.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CURRENT TARGET',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.2,
                    color: (isDark ? dc.darkInk : dc.onPrimaryContainer)
                        .withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  nodeLabel,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? dc.darkInk : dc.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? dc.darkSurface
                  : dc.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (target != null)
                  const _PingDot()
                else
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? dc.darkMutedInk : dc.outlineVariant,
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  signalLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? dc.darkInk : dc.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Animated ping dot (matches Tailwind animate-ping) ──────────────────

class _PingDot extends StatefulWidget {
  const _PingDot();

  @override
  State<_PingDot> createState() => _PingDotState();
}

class _PingDotState extends State<_PingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) => Container(
              width: 8 + _ctrl.value * 8,
              height: 8 + _ctrl.value * 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dc.primary.withValues(alpha: 0.75 * (1 - _ctrl.value)),
              ),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: dc.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Directional Guidance Banner
// ═══════════════════════════════════════════════════════════════════════════

class _DirectionalBanner extends StatelessWidget {
  const _DirectionalBanner({
    required this.snapshot,
    required this.bootstrapping,
    required this.isDark,
  });

  final SurvivorCompassSnapshot? snapshot;
  final bool bootstrapping;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = snapshot != null
        ? _turnGuidance(snapshot!.relativeTurnDegrees)
        : bootstrapping
            ? (Icons.sensors, 'Acquiring heading\u2026')
            : (Icons.radar, 'Select a signal to track');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      decoration: BoxDecoration(
        color: isDark ? dc.darkInk : dc.onSurface,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 15,
            offset: Offset(0, 10),
            spreadRadius: -3,
          ),
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 6,
            offset: Offset(0, 4),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: isDark ? dc.darkPrimaryAccent : dc.primaryFixed,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: 18,
                letterSpacing: -0.3,
                color: isDark
                    ? dc.darkBackground
                    : dc.surfaceContainerLowest,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static (IconData, String) _turnGuidance(double degrees) {
    final abs = degrees.abs();
    if (abs < 10) return (Icons.straight, 'Continue Straight');
    if (degrees < 0) {
      if (abs < 35) return (Icons.turn_slight_left, 'Turn Slightly Left');
      if (abs < 100) return (Icons.turn_left, 'Turn Left');
      if (abs < 160) return (Icons.turn_sharp_left, 'Turn Sharp Left');
      return (Icons.u_turn_left, 'Turn Around');
    }
    if (abs < 35) return (Icons.turn_slight_right, 'Turn Slightly Right');
    if (abs < 100) return (Icons.turn_right, 'Turn Right');
    if (abs < 160) return (Icons.turn_sharp_right, 'Turn Sharp Right');
    return (Icons.u_turn_right, 'Turn Around');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Minimalist Precision Compass
// ═══════════════════════════════════════════════════════════════════════════

class _PrecisionCompass extends StatelessWidget {
  const _PrecisionCompass({
    required this.relativeTurnDegrees,
    required this.distanceMeters,
    required this.shouldPulse,
    required this.pulseController,
    required this.isDark,
  });

  final double? relativeTurnDegrees;
  final double? distanceMeters;
  final bool shouldPulse;
  final AnimationController pulseController;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final angle = (relativeTurnDegrees ?? 0) * math.pi / 180;
    final (distValue, distUnit) = _formatDistance(distanceMeters);
    final ringColor = isDark ? dc.darkBorder : dc.outlineVariant;
    final primaryColor = isDark ? dc.darkPrimaryAccent : dc.primary;

    // Proximity-based intensity: closer = faster & brighter pulsation
    final proximityFactor = distanceMeters != null
        ? (1.0 - (distanceMeters! / 500).clamp(0.0, 1.0))
        : 0.0;

    return Center(
      child: SizedBox(
        width: 288,
        height: 288,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Dynamic locator ripples — always visible, intensity scales with proximity
            AnimatedBuilder(
              animation: pulseController,
              builder: (_, _) {
                final emphasis = shouldPulse ? 1.0 : 0.3 + proximityFactor * 0.4;
                final wave = pulseController.value;
                final rippleCount = distanceMeters != null ? 4 : 3;
                final baseWidth = shouldPulse
                    ? 2.2 + proximityFactor * 1.8
                    : 1.2 + proximityFactor * 0.8;
                return Stack(
                  alignment: Alignment.center,
                  children: List.generate(rippleCount, (index) {
                    final phaseOffset = index / rippleCount;
                    final progress = (wave + phaseOffset) % 1.0;
                    final size = 140 + (progress * 110);
                    final opacity = ((1 - progress) * (0.12 + 0.22 * emphasis))
                        .clamp(0.03, 0.40)
                        .toDouble();
                    return Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: primaryColor.withValues(alpha: opacity),
                          width: baseWidth * (1.0 - progress * 0.3),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),

            // Rotating directional arrow ──
            Transform.rotate(
              angle: angle,
              child: SizedBox(
                width: 288,
                height: 288,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: -16,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: CustomPaint(
                          size: const Size(48, 42),
                          painter:
                              _TriangleArrowPainter(color: primaryColor),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Center core (stationary) ──
            Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                color: isDark
                    ? dc.darkSurface
                    : dc.surfaceContainerLowest,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? dc.darkBorder : dc.surfaceVariant,
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                    blurRadius: 50,
                    offset: const Offset(0, 25),
                    spreadRadius: -12,
                  ),
                ],
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: distValue,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 56,
                              fontWeight: FontWeight.w900,
                              height: 1,
                              letterSpacing: -3,
                              color: isDark ? dc.darkInk : dc.onSurface,
                            ),
                          ),
                          TextSpan(
                            text: distUnit,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: (isDark ? dc.darkInk : dc.onSurface)
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static (String, String) _formatDistance(double? meters) {
    if (meters == null) return ('--', 'm');
    if (meters >= 1000) {
      return ((meters / 1000).toStringAsFixed(1), 'km');
    }
    if (meters >= 10) return ('${meters.round()}', 'm');
    return (meters.toStringAsFixed(1), 'm');
  }
}

// ── Filled triangle arrow for compass ──────────────────────────────────

class _TriangleArrowPainter extends CustomPainter {
  _TriangleArrowPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TriangleArrowPainter old) => old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════
// Approaching Node Status
// ═══════════════════════════════════════════════════════════════════════════

class _NodeStatus extends StatelessWidget {
  const _NodeStatus({required this.target, required this.isDark});

  final SurvivorSignalEvent? target;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final nodeLabel = _formatNodeLabel(target);

    return Column(
      children: [
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              color: isDark ? dc.darkMutedInk : dc.onSurfaceVariant,
            ),
            children: [
              const TextSpan(text: 'Approaching '),
              TextSpan(
                text: nodeLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDark ? dc.darkInk : dc.onSurface,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (target != null)
          Text(
            'Lat: ${target!.nodeLocation.lat.toStringAsFixed(4)}\u00b0 '
            '${target!.nodeLocation.lat >= 0 ? 'N' : 'S'} | '
            'Long: ${target!.nodeLocation.lng.abs().toStringAsFixed(4)}\u00b0 '
            '${target!.nodeLocation.lng >= 0 ? 'E' : 'W'}',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? dc.darkMutedInk : dc.outline,
            ),
            textAlign: TextAlign.center,
          )
        else
          Text(
            'No target pinned',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? dc.darkMutedInk : dc.outline,
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Critical Action Buttons — Ping Node + View on Map
// ═══════════════════════════════════════════════════════════════════════════

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.onPingNode,
    required this.onViewOnMap,
    required this.isDark,
  });

  final VoidCallback? onPingNode;
  final VoidCallback onViewOnMap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final hasTarget = onPingNode != null;

    return Column(
      children: [
        // ── Primary CTA: Ping Node ──
        Material(
          color: hasTarget
              ? (isDark ? dc.darkPrimaryAccent : dc.primary)
              : (isDark ? dc.darkBorder : dc.outlineVariant),
          borderRadius: BorderRadius.circular(12),
          elevation: hasTarget ? 8 : 0,
          shadowColor: Colors.black26,
          child: InkWell(
            onTap: onPingNode,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.volume_up,
                    color: hasTarget
                        ? (isDark ? dc.darkBackground : dc.onPrimary)
                        : (isDark ? dc.darkMutedInk : dc.outline),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Ping Node',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: hasTarget
                          ? (isDark ? dc.darkBackground : dc.onPrimary)
                          : (isDark ? dc.darkMutedInk : dc.outline),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Secondary: View on Map ──
        Material(
          color: isDark
              ? dc.darkSurfaceContainerHigh
              : dc.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onViewOnMap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.map_outlined,
                    color: isDark
                        ? dc.darkInk
                        : dc.onSecondaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'View on Map',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? dc.darkInk
                          : dc.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Status Footer — Battery + GPS indicators
// ═══════════════════════════════════════════════════════════════════════════

class _StatusFooter extends StatelessWidget {
  const _StatusFooter({required this.hasLocation, required this.isDark});

  final bool hasLocation;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return IgnorePointer(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          bottom: bottomPad + 24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 512),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatusPill(
                  icon: Icons.battery_charging_full,
                  label: 'Active',
                  isDark: isDark,
                ),
                _StatusPill(
                  icon: Icons.satellite_alt,
                  label: hasLocation ? 'GPS ACTIVE' : 'GPS SEARCHING',
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:
                (isDark ? dc.darkSurface : dc.surfaceContainerLowest)
                    .withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
            border: Border.all(
              color: (isDark ? dc.darkBorder : dc.surfaceVariant)
                  .withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isDark ? dc.darkPrimaryAccent : dc.primary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark ? dc.darkInk : dc.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Target Board — Survivor signal selection (below the fold)
// ═══════════════════════════════════════════════════════════════════════════

class _TargetBoard extends StatelessWidget {
  const _TargetBoard({
    required this.activeTargetMessageId,
    required this.onPinTarget,
    required this.signals,
    required this.allowResolve,
    required this.onResolve,
    required this.isDark,
  });

  final String? activeTargetMessageId;
  final ValueChanged<String> onPinTarget;
  final List<SurvivorSignalEvent> signals;
  final bool allowResolve;
  final void Function(SurvivorSignalEvent) onResolve;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? dc.darkSurface : dc.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Survivor Signals',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? dc.darkInk : dc.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pin a signal to track it with the compass.',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? dc.darkMutedInk : dc.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          if (signals.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? dc.darkSurfaceContainer
                    : dc.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.wifi_find,
                    size: 32,
                    color:
                        isDark ? dc.darkMutedInk : dc.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No signals yet',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? dc.darkInk : dc.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Survivor signals will appear here once detected.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? dc.darkMutedInk
                          : dc.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
            ...signals.map((signal) {
              final isPinned =
                  signal.messageId == activeTargetMessageId;
              final resolved = signal.isResolved;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isPinned
                      ? (isDark
                          ? dc.darkSurfaceContainerHigh
                          : dc.primaryContainer)
                      : (isDark
                          ? dc.darkSurfaceContainer
                          : dc.surfaceContainerLowest),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: resolved
                                ? dc.statusResolved.withValues(alpha: 0.15)
                                : (isDark
                                        ? dc.darkPrimaryAccent
                                        : dc.primary)
                                    .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _signalIcon(signal.detectionMethod),
                            size: 20,
                            color: resolved
                                ? dc.statusResolved
                                : (isDark
                                    ? dc.darkPrimaryAccent
                                    : dc.primary),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatNodeLabel(signal),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? dc.darkInk
                                      : dc.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${signal.estimatedDistanceMeters.toStringAsFixed(1)} m \u00b7 '
                                '${(signal.confidence * 100).round()}% conf',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? dc.darkMutedInk
                                      : dc.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (resolved)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  dc.statusResolved.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Resolved',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: dc.statusResolved,
                              ),
                            ),
                          )
                        else
                          FilledButton(
                            onPressed: () =>
                                onPinTarget(signal.messageId),
                            style: FilledButton.styleFrom(
                              backgroundColor: isPinned
                                  ? (isDark
                                      ? dc.darkPrimaryAccent
                                      : dc.primary)
                                  : (isDark
                                      ? dc.darkSurfaceContainerHigh
                                      : dc.secondaryContainer),
                              foregroundColor: isPinned
                                  ? (isDark
                                      ? dc.darkBackground
                                      : dc.onPrimary)
                                  : (isDark
                                      ? dc.darkInk
                                      : dc.onSecondaryContainer),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                            ),
                            child: Text(
                              isPinned ? 'Tracked' : 'Track',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (allowResolve && isPinned && !resolved) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => onResolve(signal),
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 16,
                          ),
                          label: const Text('Mark as Located'),
                          style: TextButton.styleFrom(
                            foregroundColor: isDark
                                ? dc.darkPrimaryAccent
                                : dc.primary,
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
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

  static IconData _signalIcon(SarDetectionMethod method) {
    return switch (method) {
      SarDetectionMethod.wifiProbe => Icons.wifi_tethering,
      SarDetectionMethod.blePassive => Icons.bluetooth_searching,
      SarDetectionMethod.acoustic => Icons.graphic_eq,
      SarDetectionMethod.sosBeacon => Icons.sos,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Resolve Bottom Sheet
// ═══════════════════════════════════════════════════════════════════════════

class _ResolveSheet extends StatelessWidget {
  const _ResolveSheet({
    required this.target,
    required this.controller,
    required this.resolving,
    required this.onResolve,
  });

  final SurvivorSignalEvent target;
  final TextEditingController controller;
  final bool resolving;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? dc.darkSurface : dc.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: dc.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Resolve Signal',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark ? dc.darkInk : dc.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              target.isResolutionQueued
                  ? 'A resolve is already queued. Submitting again '
                      'will update the note.'
                  : 'Add a note when the survivor is found or '
                      'the signal is resolved.',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? dc.darkMutedInk : dc.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                hintText:
                    'Example: survivor located near collapsed stairwell',
                filled: true,
                fillColor: isDark
                    ? dc.darkSurfaceContainer
                    : dc.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: resolving ? null : onResolve,
                style: FilledButton.styleFrom(
                  backgroundColor:
                      isDark ? dc.darkPrimaryAccent : dc.primary,
                  foregroundColor:
                      isDark ? dc.darkBackground : dc.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: resolving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  resolving ? 'Syncing\u2026' : 'Mark Located',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

String _formatNodeLabel(SurvivorSignalEvent? target) {
  if (target == null) return 'None';

  if (target.messageId.startsWith('node:')) {
    final nodeId = target.messageId.substring(5);
    final digits = nodeId.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 3) {
      return 'Node #${digits.substring(digits.length - 3)}';
    }

    final cleaned = nodeId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (cleaned.isNotEmpty) {
      final suffix = cleaned.length <= 6
          ? cleaned.toUpperCase()
          : cleaned.substring(cleaned.length - 6).toUpperCase();
      return 'Node $suffix';
    }
  }

  final id = target.detectedDeviceIdentifier;
  final digits = id.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length >= 3) {
    return 'Node #${digits.substring(digits.length - 3)}';
  }
  final cleaned = id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (cleaned.isNotEmpty) {
    final suffix = cleaned.length <= 4
        ? cleaned.toUpperCase()
        : cleaned.substring(cleaned.length - 4).toUpperCase();
    return 'Node #$suffix';
  }
  return 'Node #???';
}

String _signalLabel(SurvivorCompassConfidenceBand? band) {
  if (band == null) return 'Scanning';
  return switch (band) {
    SurvivorCompassConfidenceBand.directLock => 'Strong Signal',
    SurvivorCompassConfidenceBand.relayAssist => 'Moderate Signal',
    SurvivorCompassConfidenceBand.broadSearch => 'Weak Signal',
  };
}

/// Snapshot of the freshest known position for a target, gathered from any
/// available source (BLE last-seen, citizen presence, etc.).
class _LiveTargetFix {
  const _LiveTargetFix({
    required this.latitude,
    required this.longitude,
    required this.lastSeenAt,
    this.accuracyMeters,
  });

  final double latitude;
  final double longitude;
  final DateTime lastSeenAt;
  final double? accuracyMeters;
}









