import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/sar_mode_service.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:dispatch_mobile/features/mesh/presentation/offline_comms_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/survivor_compass_screen.dart';
import 'package:dispatch_mobile/features/shared/presentation/dispatch_map_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Mesh Network – Interactive Map
// 1:1 editorial design: full-screen map, pulsing "You" node, network lines,
// node detail bottom sheet, floating action overlay.
// ═══════════════════════════════════════════════════════════════════════════

class MeshPeopleMapScreen extends ConsumerStatefulWidget {
  const MeshPeopleMapScreen({
    super.key,
    required this.title,
    required this.subtitle,
    this.allowResolveActions = false,
    this.allowCompassActions = true,
  });

  final String title;
  final String subtitle;
  final bool allowResolveActions;
  final bool allowCompassActions;

  @override
  ConsumerState<MeshPeopleMapScreen> createState() =>
      _MeshPeopleMapScreenState();
}

class _MeshPeopleMapScreenState extends ConsumerState<MeshPeopleMapScreen>
    with TickerProviderStateMixin {
  static const double _visibleNodeRangeMeters = 15;
  final MapController _mapController = MapController();
  StreamSubscription<LocationData>? _gpsSubscription;
  late final AnimationController _cameraMoveController;
  bool _loading = true;
  bool _hasUserInteracted = false;
  bool _mapReady = false;
  bool _livePositionRefreshInFlight = false;
  bool _pendingLivePositionRefresh = false;
  String? _resolvingSignalId;
  LatLng? _gpsCenter;
  double? _gpsAccuracyMeters;
  List<Map<String, dynamic>> _nodes = [];
  List<Map<String, dynamic>> _signals = [];
  List<Map<String, dynamic>> _devices = [];
  List<Map<String, dynamic>> _localPeers = [];
  List<Map<String, dynamic>> _reports = [];
  final List<RealtimeSubscriptionHandle> _realtimeHandles = [];

  /// Currently selected node for the bottom sheet.
  Map<String, dynamic>? _selectedNode;
  bool _locationTrailEnabled = true;

  @override
  void initState() {
    super.initState();
    _cameraMoveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    ref.read(meshTransportProvider).addListener(_handleTransportUpdated);
    _refresh();
    unawaited(_detectGpsCenter());
    unawaited(_loadLocalPeers());
    _startGpsWatch();
    _bindRealtime();
  }

  // ── Data fetching ────────────────────────────────────────────────────────

  void _bindRealtime() {
    final realtime = ref.read(realtimeServiceProvider);
    if (!realtime.isConfigured) {
      return;
    }

    _realtimeHandles.addAll([
      realtime.subscribeToTable(
        table: 'mesh_topology_nodes',
        onChange: () => unawaited(_refreshLivePositions()),
      ),
      realtime.subscribeToTable(
        table: 'survivor_signals',
        onChange: () => unawaited(_refresh()),
      ),
      realtime.subscribeToTable(
        table: 'device_location_trail',
        onChange: () => unawaited(_refreshLivePositions()),
      ),
      realtime.subscribeToTable(
        table: 'incident_reports',
        onChange: () => unawaited(_refresh()),
      ),
    ]);
  }

  void _handleTransportUpdated() {
    unawaited(_loadLocalPeers());
    if (_locationTrailEnabled) {
      unawaited(_hydrateTrailForSelectedNode());
    }
  }

  Future<void> _refreshLivePositions() async {
    if (_livePositionRefreshInFlight) {
      _pendingLivePositionRefresh = true;
      return;
    }

    _livePositionRefreshInFlight = true;
    try {
      final role = ref.read(sessionControllerProvider).role;
      final canAccessMeshOperatorFeeds =
          role == AppRole.department || role == AppRole.municipality;

      if (canAccessMeshOperatorFeeds) {
        try {
          final auth = ref.read(authServiceProvider);
          final topology = await auth.getMeshTopology();
          final lastSeen = await auth.getMeshLastSeen();
          ref.read(meshTransportProvider).ingestServerLastSeen(
                (lastSeen['devices'] as List<dynamic>? ?? const [])
                    .whereType<Map>()
                    .map((row) => Map<String, dynamic>.from(row))
                    .toList(growable: false),
              );
          if (!mounted) return;
          setState(() {
            _nodes = _dedupeLatestRows(
              (topology['nodes'] as List<dynamic>? ?? const [])
                  .whereType<Map>()
                  .map((row) => Map<String, dynamic>.from(row))
                  .toList(growable: false),
            );
            _devices = _dedupeLatestRows(
              (lastSeen['devices'] as List<dynamic>? ?? const [])
                  .whereType<Map>()
                  .map((row) => Map<String, dynamic>.from(row))
                  .toList(growable: false),
            );
          });
        } catch (_) {
          // Ignore transient live-position refresh errors and keep last map state.
        }
      }

      await _loadLocalPeers();
      if (_locationTrailEnabled) {
        await _hydrateTrailForSelectedNode();
      }
    } finally {
      _livePositionRefreshInFlight = false;
      if (_pendingLivePositionRefresh) {
        _pendingLivePositionRefresh = false;
        unawaited(_refreshLivePositions());
      }
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final role = ref.read(sessionControllerProvider).role;
    final canAccessMeshOperatorFeeds =
        role == AppRole.department || role == AppRole.municipality;

    if (!canAccessMeshOperatorFeeds) {
      if (mounted) {
        setState(() {
          _nodes = const [];
          _signals = const [];
          _devices = const [];
          _reports = const [];
          _loading = false;
        });
      }
      unawaited(_detectGpsCenter());
      unawaited(_loadLocalPeers());
      return;
    }

    try {
      final auth = ref.read(authServiceProvider);
      final topology = await auth.getMeshTopology();
      final survivorSignals = await auth.getSurvivorSignals(status: 'active');
      final lastSeen = await auth.getMeshLastSeen();
      final reports = await auth.getReports();
      ref.read(meshTransportProvider).ingestServerLastSeen(
            (lastSeen['devices'] as List<dynamic>? ?? const [])
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList(growable: false),
          );
      if (!mounted) return;
      final dedupedTopologyNodes = _dedupeLatestRows(
        (topology['nodes'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false),
      );
      final dedupedLastSeenDevices = _dedupeLatestRows(
        (lastSeen['devices'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false),
      );
      setState(() {
        _nodes = dedupedTopologyNodes;
        _signals = survivorSignals;
        _devices = dedupedLastSeenDevices;
        _reports = reports
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
        _loading = false;
      });
      _moveCameraToPreferredCenter();
      unawaited(_loadLocalPeers());
      if (_locationTrailEnabled) {
        unawaited(_hydrateTrailForSelectedNode());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    } finally {
      unawaited(_detectGpsCenter());
    }
  }

  Future<void> _loadLocalPeers() async {
    final transport = ref.read(meshTransportProvider);
    final snapshot = await transport.buildTopologySnapshot(
      includePeerPreviews: true,
    );
    if (!mounted || snapshot == null) return;
    final nodes = (snapshot['nodes'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    setState(() {
      _localPeers = nodes
          .where((n) => n['lat'] != null && n['lng'] != null)
          .map((n) {
            final metadata = n['metadata'] as Map<String, dynamic>? ?? const {};
            final nodeDeviceId = n['nodeDeviceId'] as String? ?? 'unknown-peer';
            final isApproximate = metadata['approximateLocation'] == true;
            final estimatedDistance =
                (metadata['estimatedDistanceMeters'] as num?)?.toDouble();
            return <String, dynamic>{
              'id': nodeDeviceId,
              'node_id': nodeDeviceId,
              'node_device_id': nodeDeviceId,
              'message_id': 'node:$nodeDeviceId',
              'device_fingerprint':
                  metadata['deviceFingerprint'] as String? ??
                      MeshTransportService.anonymizeDeviceFingerprint(
                        nodeDeviceId,
                      ),
              'name':
                  n['displayName'] ??
                  (isApproximate ? 'Nearby Dispatch Node' : 'Dispatch Node'),
              'lat': n['lat'],
              'lng': n['lng'],
              'last_seen': n['lastSeenTimestamp'] as String?,
              'metadata': metadata,
              'estimated_distance_meters': estimatedDistance,
              'device_model': isApproximate ? 'Awaiting GPS lock' : null,
              'role': isApproximate ? 'Nearby Mesh Relay' : 'Mesh Relay',
              'status':
                  (metadata['appState'] as String?) == 'discovered'
                      ? 'discovered'
                      : 'connected',
              'is_approximate': isApproximate,
            };
          })
          .toList();
    });
  }

  Future<void> _detectGpsCenter() async {
    final location =
        await ref.read(locationServiceProvider).getCurrentPosition();
    if (!mounted || location == null) return;
    final point = LatLng(location.latitude, location.longitude);
    final changed = _gpsCenter == null ||
        _gpsCenter!.latitude != point.latitude ||
        _gpsCenter!.longitude != point.longitude;
    final accuracyChanged =
        _gpsAccuracyMeters != location.accuracyMeters;
    if (accuracyChanged || changed) {
      setState(() {
        _gpsCenter = point;
        _gpsAccuracyMeters = location.accuracyMeters;
      });
    }
    if (!changed) return;
    _moveCameraToPreferredCenter();
  }

  void _startGpsWatch() {
    _gpsSubscription =
        ref.read(locationServiceProvider).watchPosition().listen((location) {
      if (!mounted) return;
      final nextCenter = LatLng(location.latitude, location.longitude);
      final currentCenter = _gpsCenter;
      if (currentCenter != null &&
          (currentCenter.latitude - nextCenter.latitude).abs() < 0.00005 &&
          (currentCenter.longitude - nextCenter.longitude).abs() < 0.00005 &&
          _gpsAccuracyMeters == location.accuracyMeters) {
        return;
      }
      setState(() {
        _gpsCenter = nextCenter;
        _gpsAccuracyMeters = location.accuracyMeters;
      });
      _moveCameraToPreferredCenter();
    });
  }

  LatLng _preferredCenter() {
    if (_gpsCenter != null) return _gpsCenter!;
    for (final row in [..._signals, ..._devices, ..._nodes, ..._localPeers, ..._reports]) {
      final point = _readPoint(row);
      if (point != null) return point;
    }
    return const LatLng(14.5995, 120.9842);
  }

  LatLng? _readPoint(Map<String, dynamic> row) {
    final coordinates = row['coordinates'];
    if (coordinates is List && coordinates.length >= 2) {
      final lng = (coordinates[0] as num?)?.toDouble();
      final lat = (coordinates[1] as num?)?.toDouble();
      if (lat != null && lng != null) return LatLng(lat, lng);
    }
    final lat = (row['lat'] as num?)?.toDouble();
    final lng = (row['lng'] as num?)?.toDouble();
    if (lat != null && lng != null) return LatLng(lat, lng);

    final location = row['location'] as Map<String, dynamic>?;
    final locationLat = (location?['lat'] as num?)?.toDouble();
    final locationLng = (location?['lng'] as num?)?.toDouble();
    if (locationLat != null && locationLng != null) {
      return LatLng(locationLat, locationLng);
    }

    final nodeLocation = row['node_location'] as Map<String, dynamic>?;
    final nodeLat = (nodeLocation?['lat'] as num?)?.toDouble() ??
        (nodeLocation?['latitude'] as num?)?.toDouble();
    final nodeLng = (nodeLocation?['lng'] as num?)?.toDouble() ??
        (nodeLocation?['longitude'] as num?)?.toDouble();
    if (nodeLat != null && nodeLng != null) return LatLng(nodeLat, nodeLng);

    return null;
  }

  void _moveCameraToPreferredCenter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady || _hasUserInteracted) return;
      try {
        _mapController.move(_preferredCenter(), _mapController.camera.zoom);
      } on StateError {
        // Map controller may not be attached yet.
      }
    });
  }

  void _handleMapReady() {
    _mapReady = true;
    _moveCameraToPreferredCenter();
  }

  void _handlePositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture || _hasUserInteracted) return;
    setState(() => _hasUserInteracted = true);
  }

  void _setOverlayActive(bool active) {
    ref.read(mapNodeOverlayActiveProvider.notifier).state = active;
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  String? _nodeDeviceId(Map<String, dynamic> node) {
    return node['node_device_id'] as String? ??
        node['node_id'] as String? ??
        node['device_id'] as String? ??
        node['id'] as String?;
  }

  String? _nodeFingerprint(Map<String, dynamic> node) {
    final metadata = node['metadata'] as Map<String, dynamic>?;
    return node['device_fingerprint'] as String? ??
        node['detected_device_identifier'] as String? ??
        metadata?['deviceFingerprint'] as String? ??
        (_nodeDeviceId(node) != null
            ? MeshTransportService.anonymizeDeviceFingerprint(
                _nodeDeviceId(node)!,
              )
            : null);
  }

  DateTime? _rowTimestamp(Map<String, dynamic> row) {
    final raw = row['last_seen'] as String? ??
        row['lastSeenTimestamp'] as String? ??
        row['updated_at'] as String? ??
        row['created_at'] as String? ??
        row['recorded_at'] as String? ??
        (row['metadata'] as Map<String, dynamic>?)?['recordedAt'] as String?;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }

  String? _rowIdentity(Map<String, dynamic> row) {
    final fingerprint = _nodeFingerprint(row);
    if (fingerprint != null && fingerprint.isNotEmpty) {
      return 'fp:$fingerprint';
    }

    final routingDeviceId = row['routing_device_id'] as String? ??
        row['routingDeviceId'] as String? ??
        row['origin_device_id'] as String? ??
        row['originDeviceId'] as String?;
    if (routingDeviceId != null && routingDeviceId.isNotEmpty) {
      return 'device:$routingDeviceId';
    }

    final nodeDeviceId = _nodeDeviceId(row);
    if (nodeDeviceId != null && nodeDeviceId.isNotEmpty) {
      return 'node:$nodeDeviceId';
    }

    return null;
  }

  List<Map<String, dynamic>> _dedupeLatestRows(
    List<Map<String, dynamic>> rows,
  ) {
    final latestByIdentity = <String, Map<String, dynamic>>{};
    final passthrough = <Map<String, dynamic>>[];

    for (final row in rows) {
      final identity = _rowIdentity(row);
      if (identity == null) {
        passthrough.add(row);
        continue;
      }

      final current = latestByIdentity[identity];
      if (current == null) {
        latestByIdentity[identity] = row;
        continue;
      }

      final currentTs = _rowTimestamp(current);
      final nextTs = _rowTimestamp(row);
      if (currentTs == null) {
        latestByIdentity[identity] = row;
        continue;
      }
      if (nextTs != null && nextTs.isAfter(currentTs)) {
        latestByIdentity[identity] = row;
      }
    }

    return [
      ...latestByIdentity.values,
      ...passthrough,
    ];
  }

  Set<String> _activeMarkerIdentities() {
    final identities = <String>{};
    for (final row in [..._nodes, ..._localPeers, ..._signals, ..._reports]) {
      final identity = _rowIdentity(row);
      if (identity != null && identity.isNotEmpty) {
        identities.add(identity);
      }
    }
    return identities;
  }

  Future<void> _hydrateTrailForSelectedNode() async {
    final selectedNode = _selectedNode;
    if (selectedNode == null) {
      return;
    }
    await _hydrateTrailForNode(selectedNode);
  }

  Future<void> _hydrateTrailForNode(Map<String, dynamic> node) async {
    final fingerprint = _nodeFingerprint(node);
    if (fingerprint == null || fingerprint.isEmpty) {
      return;
    }

    try {
      final response = await ref
          .read(authServiceProvider)
          .getMeshTrail(fingerprint, limit: 120);
      ref.read(meshTransportProvider).ingestServerTrail(
            fingerprint,
            (response['points'] as List<dynamic>? ?? const [])
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList(growable: false),
          );
    } catch (_) {}
  }

  void _openDirectThread(Map<String, dynamic> node) {
    final nodeDeviceId = _nodeDeviceId(node);
    if (nodeDeviceId == null) {
      return;
    }
    final transport = ref.read(meshTransportProvider);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OfflineCommsScreen(
          initialMode: 'direct',
          initialRecipientIdentifier: nodeDeviceId,
          initialRecipientLabel: _nodeTitle(node),
          initialThreadId: transport.directThreadIdForNode(nodeDeviceId),
        ),
      ),
    );
  }

  void _openCompassForNode(Map<String, dynamic> node) {
    final existingMessageId = node['message_id'] as String?;
    if (existingMessageId != null && !existingMessageId.startsWith('node:')) {
      unawaited(_hydrateTrailForNode(node));
      _openCompass(existingMessageId);
      return;
    }

    final point = _readPoint(node);
    final nodeDeviceId = _nodeDeviceId(node);
    if (point == null || nodeDeviceId == null) {
      return;
    }

    ref.read(sarModeControllerProvider.notifier).upsertExternalSignal(
          SurvivorSignalEvent(
            messageId: 'node:$nodeDeviceId',
            detectionMethod: SarDetectionMethod.blePassive,
            signalStrengthDbm: -62,
            estimatedDistanceMeters: _gpsCenter == null
                ? 0
                : const Distance().as(
                    LengthUnit.Meter,
                    _gpsCenter!,
                    point,
                  ),
            detectedDeviceIdentifier:
                _nodeFingerprint(node) ??
                    MeshTransportService.anonymizeDeviceFingerprint(
                      nodeDeviceId,
                    ),
            lastSeenTimestamp:
                DateTime.tryParse(node['last_seen'] as String? ?? '') ??
                    DateTime.now().toUtc(),
            nodeLocation: SarNodeLocation(
              lat: point.latitude,
              lng: point.longitude,
              accuracyMeters: 10,
            ),
            confidence: 0.82,
            acousticPatternMatched: AcousticPatternMatched.none,
          ),
          pin: true,
        );
    unawaited(_hydrateTrailForNode(node));
    _openCompass('node:$nodeDeviceId');
  }

  Future<void> _resolveSignal(String signalId) async {
    setState(() => _resolvingSignalId = signalId);
    try {
      await ref.read(authServiceProvider).resolveSurvivorSignal(signalId);
      await _refresh();
    } finally {
      if (mounted) setState(() => _resolvingSignalId = null);
    }
  }

  void _openCompass(String? messageId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SurvivorCompassScreen(
          initialTargetMessageId: messageId,
          allowResolve: widget.allowResolveActions,
        ),
      ),
    );
  }

  void _selectNode(Map<String, dynamic> node) {
    final point = _readPoint(node);
    final double zoom =
        _mapController.camera.zoom < 15.0 ? 15.0 : _mapController.camera.zoom;

    setState(() {
      _selectedNode = node;
      _hasUserInteracted = true;
    });
    _setOverlayActive(true);

    if (point == null) {
      return;
    }
    _animateCameraTo(
      _focusCenterForPoint(
        point,
        zoom: zoom,
        topInset: MediaQuery.of(context).padding.top,
        screenHeight: MediaQuery.of(context).size.height,
      ),
      zoom: zoom,
    );
  }

  void _dismissSelection() {
    setState(() => _selectedNode = null);
    _setOverlayActive(false);
  }

  void _focusOnUserLocation() {
    final gpsCenter = _gpsCenter;
    if (gpsCenter == null) {
      return;
    }
    setState(() => _hasUserInteracted = false);
    final double zoom =
        _mapController.camera.zoom < 15.0 ? 15.0 : _mapController.camera.zoom;
    _animateCameraTo(
      _focusCenterForPoint(
        gpsCenter,
        zoom: zoom,
        topInset: MediaQuery.of(context).padding.top,
        screenHeight: MediaQuery.of(context).size.height,
      ),
      zoom: zoom,
    );
  }

  LatLng _focusCenterForPoint(
    LatLng point, {
    required double zoom,
    required double topInset,
    required double screenHeight,
  }) {
    final targetY = topInset + 138;
    final centerY = screenHeight / 2;
    final pixelOffset = (centerY - targetY).clamp(0, screenHeight * 0.34);
    final degreesPerPixel = 360.0 / (256.0 * math.pow(2, zoom));
    final verticalOffsetDegrees = degreesPerPixel * pixelOffset;
    return LatLng(point.latitude - verticalOffsetDegrees, point.longitude);
  }

  void _animateCameraTo(LatLng targetCenter, {required double zoom}) {
    final startCenter = _mapController.camera.center;
    final startZoom = _mapController.camera.zoom;
    final curved = CurvedAnimation(
      parent: _cameraMoveController,
      curve: Curves.easeOutCubic,
    );
    final latTween = Tween<double>(
      begin: startCenter.latitude,
      end: targetCenter.latitude,
    );
    final lngTween = Tween<double>(
      begin: startCenter.longitude,
      end: targetCenter.longitude,
    );
    final zoomTween = Tween<double>(begin: startZoom, end: zoom);

    void listener() {
      final nextCenter = LatLng(
        latTween.evaluate(curved),
        lngTween.evaluate(curved),
      );
      try {
        _mapController.move(nextCenter, zoomTween.evaluate(curved));
      } on StateError {
        // Map controller may not be attached yet.
      }
    }

    _cameraMoveController
      ..stop()
      ..reset();
    _cameraMoveController.addListener(listener);
    _cameraMoveController.forward().whenCompleteOrCancel(() {
      _cameraMoveController.removeListener(listener);
    });
  }

  void _showMapNotice(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  Map<String, dynamic>? _buildSelfNode() {
    final gpsCenter = _gpsCenter;
    if (gpsCenter == null) {
      return null;
    }
    final session = ref.read(sessionControllerProvider);
    final roleLabel = switch (session.role) {
      AppRole.department => 'Department Responder',
      AppRole.municipality => 'Municipal Operator',
      AppRole.citizen || null => 'Citizen',
    };
    final displayName =
        session.fullName?.trim().isNotEmpty == true
            ? session.fullName!.trim()
            : session.email?.trim().isNotEmpty == true
            ? session.email!.trim()
            : 'You';

    return <String, dynamic>{
      'id': 'self:${session.userId ?? 'local'}',
      'message_id': 'self:${session.userId ?? 'local'}',
      'node_id': session.userId ?? 'local',
      'name': displayName,
      'role': roleLabel,
      'device_model': _gpsAccuracyMeters == null
          ? 'Live GPS'
          : 'Live GPS · ${_gpsAccuracyMeters!.round()}m accuracy',
      'status': 'connected',
      'last_seen': DateTime.now().toUtc().toIso8601String(),
      'lat': gpsCenter.latitude,
      'lng': gpsCenter.longitude,
      'estimated_distance_meters': 0,
      'is_self': true,
    };
  }

  bool _isSelfNode(Map<String, dynamic> node) => node['is_self'] == true;

  String? _selectionKey(Map<String, dynamic>? row) {
    if (row == null) return null;
    return row['message_id'] as String? ??
        row['id'] as String? ??
        row['node_id'] as String? ??
        row['node_device_id'] as String? ??
        row['device_fingerprint'] as String?;
  }

  bool _isSelectedNode(Map<String, dynamic> row) {
    return _selectionKey(row) != null &&
        _selectionKey(row) == _selectionKey(_selectedNode);
  }

  List<CircleMarker> _gpsCircles() {
    final gpsCenter = _gpsCenter;
    if (gpsCenter == null) {
      return const [];
    }

    return [
      CircleMarker(
        point: gpsCenter,
        radius: _visibleNodeRangeMeters,
        useRadiusInMeter: true,
        color: dc.primary.withValues(alpha: 0.09),
        borderStrokeWidth: 1.5,
        borderColor: dc.primary.withValues(alpha: 0.26),
      ),
      CircleMarker(
        point: gpsCenter,
        radius: 4.5,
        useRadiusInMeter: true,
        color: dc.primary.withValues(alpha: 0.16),
        borderStrokeWidth: 1,
        borderColor: dc.primary.withValues(alpha: 0.32),
      ),
    ];
  }

  bool _isWithinVisibleNodeRange(Map<String, dynamic> row) {
    if (_isSelfNode(row)) {
      return true;
    }
    final gpsCenter = _gpsCenter;
    final point = _readPoint(row);
    if (gpsCenter == null || point == null) {
      return true;
    }
    final meters = const Distance().as(LengthUnit.Meter, gpsCenter, point);
    return meters <= _visibleNodeRangeMeters;
  }

  // ── Markers ──────────────────────────────────────────────────────────────

  List<Marker> _markers() {
    final markers = <Marker>[];
    final gpsCenter = _gpsCenter;
    final selfNode = _buildSelfNode();
    final activeIdentities = _activeMarkerIdentities();

    // "You" marker — pulsing orange with label
    if (gpsCenter != null && selfNode != null) {
      markers.add(
        Marker(
          point: gpsCenter,
          width: 92,
          height: 72,
          alignment: Marker.computePixelAlignment(
            width: 92,
            height: 72,
            left: 46,
            top: 24,
          ),
          rotate: true,
          child: GestureDetector(
            onTap: () => _selectNode(selfNode),
            child: _YouMarker(
              accuracyMeters: _gpsAccuracyMeters,
              onSurfaceColor: Theme.of(context).brightness == Brightness.dark
                  ? dc.darkInk
                  : dc.ink,
              selected: _isSelectedNode(selfNode),
            ),
          ),
        ),
      );
    }

    // Mesh topology nodes
    for (final node in _nodes) {
      if (!_isWithinVisibleNodeRange(node)) continue;
      final point = _readPoint(node);
      if (point == null) continue;
      final nodeId = node['node_id'] as String? ??
          node['id'] as String? ??
          'Node';
      final hasLabel = node['label'] != null || node['name'] != null;
      final label = node['label'] as String? ??
          node['name'] as String? ??
          'Node #${nodeId.length > 3 ? nodeId.substring(nodeId.length - 3) : nodeId}';

      markers.add(
        Marker(
          point: point,
          width: hasLabel ? 132 : 36,
          height: hasLabel ? 64 : 36,
          rotate: true,
          child: GestureDetector(
            onTap: () => _selectNode(node),
            child: _NodeMarker(
              label: label,
              showLabel: true,
              selected: _isSelectedNode(node),
            ),
          ),
        ),
      );
    }

    // Survivor signals — small pulsing dots
    for (final signal in _signals) {
      if (!_isWithinVisibleNodeRange(signal)) continue;
      final point = _readPoint(signal);
      if (point == null) continue;
      markers.add(
        Marker(
          point: point,
          width: 40,
          height: 40,
          rotate: true,
          child: GestureDetector(
            onTap: () => _selectNode(signal),
            child: _SignalMarker(
              selected: _isSelectedNode(signal),
              color: dc.error,
            ),
          ),
        ),
      );
    }

    // BLE peer nodes — amber markers with label
    for (final peer in _localPeers) {
      if (!_isWithinVisibleNodeRange(peer)) continue;
      final point = _readPoint(peer);
      if (point == null) continue;
      final peerId = peer['node_id'] as String? ?? peer['id'] as String? ?? 'peer';
      final label = peer['name'] as String? ??
          'Node #${peerId.length > 3 ? peerId.substring(peerId.length - 3) : peerId}';
      markers.add(
        Marker(
          point: point,
          width: 132,
          height: 64,
          rotate: true,
          child: GestureDetector(
            onTap: () => _selectNode(peer),
            child: _NodeMarker(
              label: label,
              showLabel: true,
              isPeer: true,
              selected: _isSelectedNode(peer),
            ),
          ),
        ),
      );
    }
    // Incident reports - warning markers (tappable)
    for (final report in _reports) {
      if (!_isWithinVisibleNodeRange(report)) continue;
      final point = _readPoint(report);
      if (point == null) continue;
      markers.add(
        Marker(
          point: point,
          width: 44,
          height: 44,
          rotate: true,
          child: GestureDetector(
            onTap: () => _selectNode({
              ...report,
              'role': 'Incident Report',
              'status': report['status'] as String? ?? 'active',
              'name': report['title'] as String? ??
                  report['description'] as String? ??
                  'Incident Report',
            }),
            child: _AlertMarker(
              selected: _isSelectedNode(report),
            ),
          ),
        ),
      );
    }

    // Device last-seen locations — small gray dots
    for (final device in _devices) {
      if (!_isWithinVisibleNodeRange(device)) continue;
      final deviceIdentity = _rowIdentity(device);
      if (deviceIdentity != null && activeIdentities.contains(deviceIdentity)) {
        continue;
      }
      final point = _readPoint(device);
      if (point == null) continue;
      markers.add(
        Marker(
          point: point,
          width: 26,
          height: 26,
          rotate: true,
          child: GestureDetector(
            onTap: () => _selectNode(device),
            child: _SignalMarker(
              selected: _isSelectedNode(device),
              color: dc.secondaryDim.withValues(alpha: 0.8),
              size: 8,
              pulse: false,
            ),
          ),
        ),
      );
    }

    return markers;
  }

  // ── Network lines (polylines connecting nodes to user) ───────────────────

  List<Polyline> _networkLines() {
    final center = _gpsCenter;
    if (center == null) return const [];
    final lines = <Polyline>[];
    final allPoints = <LatLng>[];
    final seenIdentities = <String>{};

    for (final row in [..._nodes, ..._signals, ..._devices, ..._localPeers]) {
      if (!_isWithinVisibleNodeRange(row)) {
        continue;
      }
      final identity = _rowIdentity(row);
      if (identity != null && !seenIdentities.add(identity)) {
        continue;
      }
      final point = _readPoint(row);
      if (point != null) allPoints.add(point);
    }

    for (final point in allPoints) {
      lines.add(
        Polyline(
          points: [center, point],
          strokeWidth: 1.0,
          color: dc.secondary.withValues(alpha: 0.3),
        ),
      );
    }

    return lines;
  }

  // ── Selected node helpers ────────────────────────────────────────────────
  List<Polyline> _trailLines() {
    if (!_locationTrailEnabled || _selectedNode == null) {
      return const [];
    }
    final fingerprint = _nodeFingerprint(_selectedNode!);
    if (fingerprint == null || fingerprint.isEmpty) {
      return const [];
    }
    final trailPoints = ref
        .read(meshTransportProvider)
        .trailForDevice(fingerprint)
        .map((point) => LatLng(point.lat, point.lng))
        .toList(growable: false);
    if (trailPoints.length < 2) {
      return const [];
    }
    return [
      Polyline(
        points: trailPoints,
        strokeWidth: 3.5,
        color: dc.primary.withValues(alpha: 0.75),
      ),
    ];
  }

  String _nodeTitle(Map<String, dynamic> node) {
    if (_isSelfNode(node)) {
      final name = node['name'] as String? ?? 'You';
      return name == 'You' ? 'You' : 'You ($name)';
    }
    final label = node['label'] as String? ?? node['name'] as String?;
    final nodeId = node['node_id'] as String? ?? node['id'] as String?;
    if (label != null && nodeId != null) {
      return 'Node #${nodeId.length > 3 ? nodeId.substring(nodeId.length - 3) : nodeId} ($label)';
    }
    if (label != null) return label;
    if (nodeId != null) {
      return 'Node #${nodeId.length > 3 ? nodeId.substring(nodeId.length - 3) : nodeId}';
    }
    return 'Unknown Node';
  }

  String _nodeSubtitle(Map<String, dynamic> node) {
    if (_isSelfNode(node)) {
      final role = node['role'] as String? ?? 'Citizen';
      final device = node['device_model'] as String?;
      return device == null ? role : '$role • $device';
    }
    if (node['is_approximate'] == true) {
      final device = node['device_model'] as String?;
      return device == null
          ? 'Nearby discovery • Mesh Relay'
          : '$device • Mesh Relay';
    }
    final device = node['device_type'] as String? ??
        node['device_model'] as String? ??
        node['detected_device_identifier'] as String?;
    final role = node['role'] as String? ?? 'Mesh Relay';
    if (device != null) return '$device • $role';
    return role;
  }

  String _nodeDistance(Map<String, dynamic> node) {
    if (_isSelfNode(node)) {
      return '0m (You)';
    }
    final distance =
        (node['estimated_distance_meters'] as num?)?.toDouble();
    if (distance != null) {
      if (node['is_approximate'] == true) {
        return '~${distance.round()}m nearby';
      }
      if (distance >= 1000) {
        return '${(distance / 1000).toStringAsFixed(1)}km';
      }
      return '${distance.round()}m';
    }
    // Compute from GPS if available
    final point = _readPoint(node);
    if (point != null && _gpsCenter != null) {
      const d = Distance();
      final meters = d.as(LengthUnit.Meter, _gpsCenter!, point);
      if (node['is_approximate'] == true) {
        return '~${meters.round()}m nearby';
      }
      if (meters >= 1000) {
        return '${(meters / 1000).toStringAsFixed(1)}km';
      }
      return '${meters.round()}m';
    }
    return '—';
  }

  String _nodeLastSeen(Map<String, dynamic> node) {
    if (_isSelfNode(node)) {
      return _gpsAccuracyMeters == null
          ? 'Live now'
          : 'Live now · ±${_gpsAccuracyMeters!.round()}m';
    }
    final raw = node['last_seen'] as String? ??
        node['updated_at'] as String? ??
        node['created_at'] as String?;
    if (raw == null) return '—';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return '—';
    final diff = DateTime.now().difference(parsed.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  bool _isConnected(Map<String, dynamic> node) {
    if (_isSelfNode(node)) {
      return _gpsCenter != null;
    }
    final status = node['status'] as String?;
    if (status != null) return status == 'active' || status == 'connected';
    final lastSeen = node['last_seen'] as String? ?? node['updated_at'] as String?;
    if (lastSeen == null) return false;
    final parsed = DateTime.tryParse(lastSeen);
    if (parsed == null) return false;
    return DateTime.now().difference(parsed).inMinutes < 10;
  }

  @override
  void dispose() {
    _setOverlayActive(false);
    ref.read(meshTransportProvider).removeListener(_handleTransportUpdated);
    for (final handle in _realtimeHandles) {
      unawaited(handle.dispose());
    }
    _gpsSubscription?.cancel();
    _cameraMoveController.dispose();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final center = _preferredCenter();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gpsAvailable = _gpsCenter != null;
    final detailBottomOffset = 0.0;

    return Scaffold(
      backgroundColor: isDark ? dc.darkBackground : dc.background,
      body: Stack(
        children: [
          // ── Full-screen map ──────────────────────────────────────────
          Positioned.fill(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                      color: isDark ? dc.darkPrimaryAccent : dc.primary,
                    ),
                  )
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 15,
                      onMapReady: _handleMapReady,
                      onPositionChanged: _handlePositionChanged,
                      onTap: (tapPosition, point) => _dismissSelection(),
                    ),
                    children: [
                      ...buildDispatchMapTileLayers(),
                      // Dot grid overlay
                      _MapGridOverlay(isDark: isDark),
                      CircleLayer(circles: _gpsCircles()),
                      // Network connection lines
                      PolylineLayer(polylines: _networkLines()),
                      PolylineLayer(polylines: _trailLines()),
                      // Node markers
                      MarkerLayer(markers: _markers()),
                    ],
                  ),
          ),

          // ── Top Navigation Bar (glassmorphic) ───────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _MapAppBar(
              isDark: isDark,
              onSync: _loading ? null : _refresh,
              gpsLabel: gpsAvailable
                  ? _gpsAccuracyMeters == null
                        ? 'GPS live'
                        : 'GPS ${_gpsAccuracyMeters!.round()}m'
                  : 'GPS off',
            ),
          ),

          // ── Floating Action Overlay (right side) ────────────────────
          Positioned(
            right: 24,
            top: MediaQuery.of(context).padding.top + 72,
            child: _FloatingActions(
              isDark: isDark,
              onCompass: () => _openCompass(null),
              onMyLocation: _focusOnUserLocation,
              hasGpsLock: gpsAvailable,
            ),
          ),

          // ── Node Detail Bottom Sheet ────────────────────────────────
          Positioned(
            bottom: detailBottomOffset,
            left: 16,
            right: 16,
            child: IgnorePointer(
              ignoring: _selectedNode == null,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                reverseDuration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) {
                  final offset = Tween<Offset>(
                    begin: const Offset(0, 0.12),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                  );
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: offset, child: child),
                  );
                },
                child: _selectedNode == null
                    ? const SizedBox.shrink()
                    : _NodeDetailSheet(
                        key: ValueKey<String>(
                          _selectionKey(_selectedNode!) ?? 'selected-node',
                        ),
                        isDark: isDark,
                        title: _nodeTitle(_selectedNode!),
                        subtitle: _nodeSubtitle(_selectedNode!),
                        distance: _nodeDistance(_selectedNode!),
                        lastSeen: _nodeLastSeen(_selectedNode!),
                        isConnected: _isConnected(_selectedNode!),
                        locationTrailEnabled: _locationTrailEnabled,
                        onToggleTrail: (v) {
                          if (_isSelfNode(_selectedNode!)) {
                            _showMapNotice(
                              'Personal location trail is a placeholder for now.',
                            );
                            return;
                          }
                          setState(() => _locationTrailEnabled = v);
                        },
                        primaryActionLabel: _isSelfNode(_selectedNode!)
                            ? 'Center on My Position'
                            : 'Open Compass Locator',
                        onOpenCompass: () {
                          if (_isSelfNode(_selectedNode!)) {
                            _focusOnUserLocation();
                            _showMapNotice(
                              'Your live node is centered. More self tools are coming soon.',
                            );
                            return;
                          }
                          _openCompassForNode(_selectedNode!);
                        },
                        onChat: _isSelfNode(_selectedNode!)
                            ? null
                            : () => _openDirectThread(_selectedNode!),
                        allowResolve: widget.allowResolveActions &&
                            !_isSelfNode(_selectedNode!) &&
                            (_selectedNode!['message_id'] as String?) != null &&
                            !((_selectedNode!['message_id'] as String?)?.startsWith('node:') ?? false),
                        isResolving: _resolvingSignalId ==
                            (_selectedNode!['id'] as String?),
                        onResolve: _selectedNode!['id'] != null &&
                                (_selectedNode!['message_id'] as String?) != null &&
                                !((_selectedNode!['message_id'] as String?)?.startsWith('node:') ?? false)
                            ? () => _resolveSignal(_selectedNode!['id'] as String)
                            : null,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// "You" Marker — pulsing orange dot with label (matches design exactly)
// ═══════════════════════════════════════════════════════════════════════════

class _YouMarker extends StatefulWidget {
  const _YouMarker({
    this.accuracyMeters,
    required this.onSurfaceColor,
    this.selected = false,
  });

  final double? accuracyMeters;
  final Color onSurfaceColor;
  final bool selected;

  @override
  State<_YouMarker> createState() => _YouMarkerState();
}

class _YouMarkerState extends State<_YouMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (widget.selected)
                  const _PulsingHalo(
                    color: dc.primary,
                    minSize: 18,
                    maxSize: 38,
                  ),
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, child) {
                    final scale = 0.8 + _ctrl.value * 1.6;
                    final opacity = 0.5 * (1 - _ctrl.value);
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: dc.primary.withValues(
                            alpha: opacity.clamp(0.0, 1.0),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: dc.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: dc.surface, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: dc.onSurface.withValues(alpha: 0.12),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: dc.surfaceContainerLowest.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: dc.onSurface.withValues(alpha: 0.06),
                blurRadius: 4,
              ),
            ],
          ),
          child: Text(
            widget.accuracyMeters == null
                ? 'You'
                : 'You · ${widget.accuracyMeters!.round()}m',
            style: TextStyle(
              color: widget.onSurfaceColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _NodeMarker extends StatelessWidget {
  const _NodeMarker({
    required this.label,
    this.showLabel = false,
    this.isPeer = false,
    this.selected = false,
  });

  final String label;
  final bool showLabel;
  final bool isPeer;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final dotColor = isPeer ? Colors.amber : dc.secondary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (selected) _PulsingHalo(color: dotColor, minSize: 14, maxSize: 28),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: dc.surface, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: dc.onSurface.withValues(alpha: 0.08),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showLabel) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: dc.surfaceContainerLowest.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: dc.onSurface.withValues(alpha: 0.06),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.2,
                color: dc.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

class _SignalMarker extends StatelessWidget {
  const _SignalMarker({
    required this.selected,
    required this.color,
    this.size = 10,
    this.pulse = true,
  });

  final bool selected;
  final Color color;
  final double size;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final haloColor = pulse ? color : color.withValues(alpha: 0.55);
    return SizedBox(
      width: 40,
      height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
          if (pulse || selected)
            _PulsingHalo(
              color: haloColor,
              minSize: size + 4,
              maxSize: selected ? 34 : 24,
            ),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.92),
                width: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertMarker extends StatelessWidget {
  const _AlertMarker({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _PulsingHalo(
            color: dc.error,
            minSize: 18,
            maxSize: selected ? 36 : 28,
          ),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: dc.error,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(
              Icons.report_problem_outlined,
              color: Colors.white,
              size: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingHalo extends StatefulWidget {
  const _PulsingHalo({
    required this.color,
    required this.minSize,
    required this.maxSize,
  });

  final Color color;
  final double minSize;
  final double maxSize;

  @override
  State<_PulsingHalo> createState() => _PulsingHaloState();
}

class _PulsingHaloState extends State<_PulsingHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final progress = Curves.easeOut.transform(_controller.value);
          final size = widget.minSize +
              ((widget.maxSize - widget.minSize) * progress);
          final opacity = (0.28 * (1 - progress)).clamp(0.0, 0.28).toDouble();
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: opacity),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Map Grid Overlay — radial dot grid (matches the design's map-grid pattern)
// ═══════════════════════════════════════════════════════════════════════════

class _MapGridOverlay extends StatelessWidget {
  const _MapGridOverlay({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _DotGridPainter(isDark: isDark),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  _DotGridPainter({required this.isDark});
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isDark
          ? dc.darkMutedInk.withValues(alpha: 0.08)
          : const Color(0xFFEADFD2).withValues(alpha: 0.38);

    const spacing = 42.0;
    const radius = 1.1;

    for (var x = 0.0; x < size.width + spacing; x += spacing) {
      for (var y = 0.0; y < size.height + spacing; y += spacing) {
        final wave = math.sin((x * 0.012) + (y * 0.018)) * 5.5;
        canvas.drawCircle(Offset(x + wave, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter old) => isDark != old.isDark;
}

// ═══════════════════════════════════════════════════════════════════════════
// Top App Bar — glassmorphic, matches the fixed header design
// ═══════════════════════════════════════════════════════════════════════════

class _MapAppBar extends StatelessWidget {
  const _MapAppBar({
    required this.isDark,
    this.onSync,
    required this.gpsLabel,
  });

  final bool isDark;
  final VoidCallback? onSync;
  final String gpsLabel;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bg = isDark
        ? dc.darkBackground.withValues(alpha: 0.8)
        : const Color(0xFFFFFCF8).withValues(alpha: 0.94);
    final iconColor = isDark ? dc.darkPrimaryAccent : dc.primary;
    final titleColor = isDark ? dc.darkInk : dc.onSurface;
    final subtitleColor = isDark ? dc.darkMutedInk : dc.mutedInk;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.fromLTRB(18, topPadding + 10, 18, 14),
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              bottom: BorderSide(
                color: (isDark ? dc.darkBorder : const Color(0xFFEBDCCD))
                    .withValues(alpha: 0.45),
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: (isDark ? dc.darkSurfaceContainer : dc.primaryContainer)
                      .withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.location_on, color: iconColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dispatch',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'OPERATIONAL AWARENESS',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.7,
                        color: subtitleColor.withValues(alpha: 0.78),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Mesh Network',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: titleColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onSync,
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(Icons.sync, size: 22, color: iconColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (isDark ? dc.darkSurfaceContainer : dc.primaryContainer)
                              .withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      gpsLabel.toUpperCase(),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: isDark
                            ? dc.darkPrimaryAccent
                            : dc.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Floating Action Overlay — compass + layers buttons (right side)
// ═══════════════════════════════════════════════════════════════════════════

class _FloatingActions extends StatelessWidget {
  const _FloatingActions({
    required this.isDark,
    required this.onCompass,
    required this.onMyLocation,
    required this.hasGpsLock,
  });

  final bool isDark;
  final VoidCallback onCompass;
  final VoidCallback onMyLocation;
  final bool hasGpsLock;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FloatingActionButton(
          isDark: isDark,
          icon: Icons.explore,
          onTap: onCompass,
        ),
        const SizedBox(height: 12),
        _FloatingActionButton(
          isDark: isDark,
          icon: hasGpsLock ? Icons.my_location : Icons.location_disabled,
          onTap: onMyLocation,
        ),
      ],
    );
  }
}

class _FloatingActionButton extends StatelessWidget {
  const _FloatingActionButton({
    required this.isDark,
    required this.icon,
    required this.onTap,
  });

  final bool isDark;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? dc.darkSurface : const Color(0xFFFDF8F2),
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? dc.darkBorder.withValues(alpha: 0.7)
                  : const Color(0xFFEAD8C8),
            ),
            boxShadow: [
              BoxShadow(
                color: dc.onSurface.withValues(alpha: 0.1),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 24,
            color: isDark ? dc.darkMutedInk : dc.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Node Detail Bottom Sheet — minimalist overlay (matches design 1:1)
// Rounded 2rem, glassmorphic, drag handle, stats grid, toggle, CTA button
// ═══════════════════════════════════════════════════════════════════════════

class _NodeDetailSheet extends StatelessWidget {
  const _NodeDetailSheet({
    super.key,
    required this.isDark,
    required this.title,
    required this.subtitle,
    required this.distance,
    required this.lastSeen,
    required this.isConnected,
    required this.locationTrailEnabled,
    required this.onToggleTrail,
    required this.onOpenCompass,
    this.primaryActionLabel = 'Open Compass Locator',
    this.onChat,
    this.allowResolve = false,
    this.isResolving = false,
    this.onResolve,
  });

  final bool isDark;
  final String title;
  final String subtitle;
  final String distance;
  final String lastSeen;
  final bool isConnected;
  final bool locationTrailEnabled;
  final ValueChanged<bool> onToggleTrail;
  final VoidCallback onOpenCompass;
  final String primaryActionLabel;
  final VoidCallback? onChat;
  final bool allowResolve;
  final bool isResolving;
  final VoidCallback? onResolve;

  @override
  Widget build(BuildContext context) {
    final bg = isDark
        ? dc.darkSurface.withValues(alpha: 0.95)
        : const Color(0xFFFFFCF8).withValues(alpha: 0.98);
    final cardBg =
        isDark ? dc.darkSurfaceContainer : const Color(0xFFF4EFE8);
    final textColor = isDark ? dc.darkInk : dc.onSurface;
    final subtextColor = isDark ? dc.darkMutedInk : dc.onSurfaceVariant;
    final accentColor = isDark ? dc.darkPrimaryAccent : dc.primary;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 22),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(32),
            ),
            boxShadow: [
              BoxShadow(
                color: dc.onSurface.withValues(alpha: 0.12),
                blurRadius: 34,
                offset: const Offset(0, -6),
              ),
            ],
            border: Border.all(
              color: (isDark ? dc.darkBorder : const Color(0xFFE8DCCF))
                  .withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? dc.darkSurfaceContainerHigh
                      : dc.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 24),

              // Node info header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: isDark
                          ? dc.darkPrimaryAccent.withValues(alpha: 0.15)
                          : const Color(0xFFF7EBDD),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person,
                      size: 32,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontFamily: 'Georgia',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: subtextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Connection status badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? dc.darkPrimaryAccent.withValues(alpha: 0.15)
                          : const Color(0xFFF6E8DA),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isConnected ? 'MESH RELAY' : 'OFFLINE',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: isDark ? dc.darkPrimaryAccent : dc.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Stats grid: Distance + Last Seen
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      isDark: isDark,
                      label: 'DISTANCE',
                      value: distance,
                      bg: cardBg,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _StatCard(
                      isDark: isDark,
                      label: 'LAST SEEN',
                      value: lastSeen,
                      bg: cardBg,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Location Trail toggle
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(Icons.route, size: 24, color: subtextColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Turn on Location Trail',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: textColor,
                        ),
                      ),
                    ),
                    Switch(
                      value: locationTrailEnabled,
                      onChanged: onToggleTrail,
                      activeThumbColor: dc.surfaceContainerLowest,
                      activeTrackColor: accentColor,
                      inactiveThumbColor: dc.surfaceContainerLowest,
                      inactiveTrackColor: isDark
                          ? dc.darkSurfaceContainerHigh
                          : const Color(0xFFE3DDD6),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Chat button
              if (onChat != null)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onChat,
                    borderRadius: BorderRadius.circular(16),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: isDark
                            ? dc.darkSurfaceContainer
                            : dc.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: (isDark ? dc.darkPrimaryAccent : dc.primary)
                              .withValues(alpha: 0.4),
                        ),
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 20,
                              color: isDark ? dc.darkPrimaryAccent : dc.primary,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Chat via Mesh',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDark ? dc.darkPrimaryAccent : dc.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (onChat != null) const SizedBox(height: 12),

              // Open Compass Locator button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onOpenCompass,
                  borderRadius: BorderRadius.circular(16),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          isDark ? dc.darkPrimaryAccent : const Color(0xFFB45E2E),
                          isDark
                              ? dc.darkPrimaryAccent.withValues(alpha: 0.85)
                              : const Color(0xFFA34E22),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: (isDark ? dc.darkPrimaryAccent : dc.primary)
                              .withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.navigation,
                            size: 20,
                            color: isDark ? dc.onSurface : dc.onPrimary,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            primaryActionLabel,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isDark ? dc.onSurface : dc.onPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Resolve button (department/municipality only)
              if (allowResolve && onResolve != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: isResolving ? null : onResolve,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(
                        color: isDark ? dc.darkPrimaryAccent : dc.primary,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      isResolving ? 'Resolving...' : 'Mark as Resolved',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? dc.darkPrimaryAccent : dc.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Stat Card — used inside the bottom sheet for Distance / Last Seen
// ═══════════════════════════════════════════════════════════════════════════

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.isDark,
    required this.label,
    required this.value,
    required this.bg,
  });

  final bool isDark;
  final String label;
  final String value;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: isDark ? dc.darkMutedInk : dc.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? dc.darkInk : dc.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}


















