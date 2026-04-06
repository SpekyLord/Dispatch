import 'dart:async';
import 'dart:ui';

import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
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

class _MeshPeopleMapScreenState extends ConsumerState<MeshPeopleMapScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<LocationData>? _gpsSubscription;
  bool _loading = true;
  bool _hasUserInteracted = false;
  bool _mapReady = false;
  String? _resolvingSignalId;
  LatLng? _gpsCenter;
  List<Map<String, dynamic>> _nodes = [];
  List<Map<String, dynamic>> _signals = [];
  List<Map<String, dynamic>> _devices = [];
  List<Map<String, dynamic>> _localPeers = [];

  /// Currently selected node for the bottom sheet.
  Map<String, dynamic>? _selectedNode;
  bool _locationTrailEnabled = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    unawaited(_detectGpsCenter());
    unawaited(_loadLocalPeers());
    _startGpsWatch();
  }

  // ── Data fetching ────────────────────────────────────────────────────────

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
      if (!mounted) return;
      setState(() {
        _nodes = (topology['nodes'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
        _signals = survivorSignals;
        _devices = (lastSeen['devices'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
        _loading = false;
      });
      _moveCameraToPreferredCenter();
      unawaited(_loadLocalPeers());
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    } finally {
      unawaited(_detectGpsCenter());
    }
  }

  Future<void> _loadLocalPeers() async {
    final transport = ref.read(meshTransportProvider);
    final snapshot = await transport.buildTopologySnapshot();
    if (!mounted || snapshot == null) return;
    final nodes = (snapshot['nodes'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    setState(() {
      _localPeers = nodes
          .where((n) => n['lat'] != null && n['lng'] != null)
          .map((n) => <String, dynamic>{
                'id': n['nodeDeviceId'],
                'node_id': n['nodeDeviceId'],
                'name': n['displayName'] ?? 'Dispatch Node',
                'lat': n['lat'],
                'lng': n['lng'],
                'last_seen': n['lastSeenTimestamp'] != null
                    ? DateTime.fromMillisecondsSinceEpoch(
                        (n['lastSeenTimestamp'] as num).toInt(),
                        isUtc: true,
                      ).toIso8601String()
                    : null,
                'role': 'Mesh Relay',
                'status': 'connected',
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
    if (!changed) return;
    setState(() => _gpsCenter = point);
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
          (currentCenter.longitude - nextCenter.longitude).abs() < 0.00005) {
        return;
      }
      setState(() => _gpsCenter = nextCenter);
      _moveCameraToPreferredCenter();
    });
  }

  LatLng _preferredCenter() {
    if (_gpsCenter != null) return _gpsCenter!;
    for (final row in [..._signals, ..._devices, ..._nodes, ..._localPeers]) {
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

  // ── Actions ──────────────────────────────────────────────────────────────

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
    setState(() => _selectedNode = node);
  }

  void _dismissSelection() {
    setState(() => _selectedNode = null);
  }

  // ── Markers ──────────────────────────────────────────────────────────────

  List<Marker> _markers() {
    final markers = <Marker>[];
    final gpsCenter = _gpsCenter;

    // "You" marker — pulsing orange with label
    if (gpsCenter != null) {
      markers.add(
        Marker(
          point: gpsCenter,
          width: 80,
          height: 60,
          child: GestureDetector(
            onTap: _dismissSelection,
            child: const _YouMarker(),
          ),
        ),
      );
    }

    // Mesh topology nodes
    for (final node in _nodes) {
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
          width: hasLabel ? 120 : 20,
          height: hasLabel ? 50 : 20,
          child: GestureDetector(
            onTap: () => _selectNode(node),
            child: _NodeMarker(label: label, showLabel: true),
          ),
        ),
      );
    }

    // Survivor signals — small pulsing dots
    for (final signal in _signals) {
      final point = _readPoint(signal);
      if (point == null) continue;
      markers.add(
        Marker(
          point: point,
          width: 20,
          height: 20,
          child: GestureDetector(
            onTap: () => _selectNode(signal),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: dc.error,
                shape: BoxShape.circle,
                border: Border.all(color: dc.surface, width: 2),
              ),
            ),
          ),
        ),
      );
    }

    // BLE peer nodes — amber markers with label
    for (final peer in _localPeers) {
      final point = _readPoint(peer);
      if (point == null) continue;
      final peerId = peer['node_id'] as String? ?? peer['id'] as String? ?? 'peer';
      final label = peer['name'] as String? ??
          'Node #${peerId.length > 3 ? peerId.substring(peerId.length - 3) : peerId}';
      markers.add(
        Marker(
          point: point,
          width: 120,
          height: 50,
          child: GestureDetector(
            onTap: () => _selectNode(peer),
            child: _NodeMarker(label: label, showLabel: true, isPeer: true),
          ),
        ),
      );
    }

    // Device last-seen locations — small gray dots
    for (final device in _devices) {
      final point = _readPoint(device);
      if (point == null) continue;
      markers.add(
        Marker(
          point: point,
          width: 14,
          height: 14,
          child: GestureDetector(
            onTap: () => _selectNode(device),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dc.secondaryDim.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
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

    for (final row in [..._nodes, ..._signals, ..._devices, ..._localPeers]) {
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

  String _nodeTitle(Map<String, dynamic> node) {
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
    final device = node['device_type'] as String? ??
        node['device_model'] as String? ??
        node['detected_device_identifier'] as String?;
    final role = node['role'] as String? ?? 'Mesh Relay';
    if (device != null) return '$device • $role';
    return role;
  }

  String _nodeDistance(Map<String, dynamic> node) {
    final distance =
        (node['estimated_distance_meters'] as num?)?.toDouble();
    if (distance != null) {
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
      if (meters >= 1000) {
        return '${(meters / 1000).toStringAsFixed(1)}km';
      }
      return '${meters.round()}m';
    }
    return '—';
  }

  String _nodeLastSeen(Map<String, dynamic> node) {
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
    _gpsSubscription?.cancel();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final center = _preferredCenter();
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                      // Network connection lines
                      PolylineLayer(polylines: _networkLines()),
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
            ),
          ),

          // ── Floating Action Overlay (right side) ────────────────────
          Positioned(
            right: 24,
            top: MediaQuery.of(context).padding.top + 72,
            child: _FloatingActions(
              isDark: isDark,
              onCompass: () => _openCompass(null),
              onLayers: () {
                // Recenter on user
                setState(() => _hasUserInteracted = false);
                _moveCameraToPreferredCenter();
              },
            ),
          ),

          // ── Node Detail Bottom Sheet ────────────────────────────────
          if (_selectedNode != null)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: _NodeDetailSheet(
                isDark: isDark,
                title: _nodeTitle(_selectedNode!),
                subtitle: _nodeSubtitle(_selectedNode!),
                distance: _nodeDistance(_selectedNode!),
                lastSeen: _nodeLastSeen(_selectedNode!),
                isConnected: _isConnected(_selectedNode!),
                locationTrailEnabled: _locationTrailEnabled,
                onToggleTrail: (v) =>
                    setState(() => _locationTrailEnabled = v),
                onOpenCompass: () => _openCompass(
                  _selectedNode!['message_id'] as String?,
                ),
                onChat: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const OfflineCommsScreen(),
                  ),
                ),
                allowResolve: widget.allowResolveActions,
                isResolving: _resolvingSignalId ==
                    (_selectedNode!['id'] as String?),
                onResolve: _selectedNode!['id'] != null
                    ? () =>
                        _resolveSignal(_selectedNode!['id'] as String)
                    : null,
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
  const _YouMarker();

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
          width: 32,
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Pulsing halo ring
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
                        color: dc.primary.withValues(alpha: opacity.clamp(0.0, 1.0)),
                      ),
                    ),
                  );
                },
              ),
              // Center dot
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
            'You',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: dc.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Node Marker — small dot with optional label
// ═══════════════════════════════════════════════════════════════════════════

class _NodeMarker extends StatelessWidget {
  const _NodeMarker({required this.label, this.showLabel = false, this.isPeer = false});

  final String label;
  final bool showLabel;
  final bool isPeer;

  @override
  Widget build(BuildContext context) {
    final dotColor = isPeer ? Colors.amber : dc.secondary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
          : dc.secondaryContainer.withValues(alpha: 0.4);

    const spacing = 40.0;
    const radius = 1.0;

    for (var x = 0.0; x < size.width; x += spacing) {
      for (var y = 0.0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
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
  const _MapAppBar({required this.isDark, this.onSync});

  final bool isDark;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bg = isDark
        ? dc.darkBackground.withValues(alpha: 0.8)
        : dc.surfaceContainerLow.withValues(alpha: 0.8);
    final iconColor = isDark ? dc.darkPrimaryAccent : dc.primary;
    final titleColor = isDark ? dc.darkInk : dc.onSurface;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.fromLTRB(24, topPadding + 12, 24, 12),
          decoration: BoxDecoration(color: bg),
          child: Row(
            children: [
              Icon(Icons.signal_cellular_alt, color: iconColor, size: 24),
              const SizedBox(width: 12),
              Text(
                'Mesh Network',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: titleColor,
                ),
              ),
              const Spacer(),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onSync,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.sync, size: 24, color: iconColor),
                  ),
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
// Floating Action Overlay — compass + layers buttons (right side)
// ═══════════════════════════════════════════════════════════════════════════

class _FloatingActions extends StatelessWidget {
  const _FloatingActions({
    required this.isDark,
    required this.onCompass,
    required this.onLayers,
  });

  final bool isDark;
  final VoidCallback onCompass;
  final VoidCallback onLayers;

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
          icon: Icons.layers,
          onTap: onLayers,
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
      color: isDark ? dc.darkSurface : dc.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: dc.onSurface.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
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
    required this.isDark,
    required this.title,
    required this.subtitle,
    required this.distance,
    required this.lastSeen,
    required this.isConnected,
    required this.locationTrailEnabled,
    required this.onToggleTrail,
    required this.onOpenCompass,
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
  final VoidCallback? onChat;
  final bool allowResolve;
  final bool isResolving;
  final VoidCallback? onResolve;

  @override
  Widget build(BuildContext context) {
    final bg = isDark
        ? dc.darkSurface.withValues(alpha: 0.95)
        : dc.surfaceContainerLowest.withValues(alpha: 0.95);
    final cardBg = isDark ? dc.darkSurfaceContainer : dc.surfaceContainerLow;
    final textColor = isDark ? dc.darkInk : dc.onSurface;
    final subtextColor = isDark ? dc.darkMutedInk : dc.onSurfaceVariant;
    final accentColor = isDark ? dc.darkPrimaryAccent : dc.primary;

    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: dc.onSurface.withValues(alpha: 0.08),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(
              color: (isDark ? dc.darkBorder : dc.outlineVariant)
                  .withValues(alpha: 0.1),
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
                          : dc.primaryContainer,
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
                            fontFamily: 'Inter',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
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
                          : dc.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isConnected ? 'CONNECTED' : 'OFFLINE',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
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
                          : dc.surfaceContainerHigh,
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
                          isDark ? dc.darkPrimaryAccent : dc.primary,
                          isDark
                              ? dc.darkPrimaryAccent.withValues(alpha: 0.85)
                              : dc.primaryDim,
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
                            'Open Compass Locator',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
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
        borderRadius: BorderRadius.circular(16),
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
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? dc.darkInk : dc.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
