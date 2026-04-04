import 'dart:async';

import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/mesh/presentation/survivor_compass_screen.dart';
import 'package:dispatch_mobile/features/shared/presentation/dispatch_map_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

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
  bool _loading = true;
  bool _hasUserInteracted = false;
  bool _mapReady = false;
  String? _resolvingSignalId;
  LatLng? _gpsCenter;
  List<Map<String, dynamic>> _nodes = [];
  List<Map<String, dynamic>> _signals = [];
  List<Map<String, dynamic>> _devices = [];

  @override
  void initState() {
    super.initState();
    _refresh();
    unawaited(_detectGpsCenter());
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
          _loading = false;
        });
      }
      unawaited(_detectGpsCenter());
      return;
    }

    try {
      final auth = ref.read(authServiceProvider);
      final topology = await auth.getMeshTopology();
      final survivorSignals = await auth.getSurvivorSignals(status: 'active');
      final lastSeen = await auth.getMeshLastSeen();
      if (!mounted) {
        return;
      }
      setState(() {
        _nodes = (topology['nodes'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
        _signals = survivorSignals;
        _devices = (lastSeen['devices'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
        _loading = false;
      });
      _moveCameraToPreferredCenter();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
    } finally {
      unawaited(_detectGpsCenter());
    }
  }

  Future<void> _detectGpsCenter() async {
    final location = await ref
        .read(locationServiceProvider)
        .getCurrentPosition();
    if (!mounted || location == null) {
      return;
    }
    final point = LatLng(location.latitude, location.longitude);
    final changed =
        _gpsCenter == null ||
        _gpsCenter!.latitude != point.latitude ||
        _gpsCenter!.longitude != point.longitude;
    if (!changed) {
      return;
    }
    setState(() {
      _gpsCenter = point;
    });
    _moveCameraToPreferredCenter();
  }

  Future<void> _resolveSignal(String signalId) async {
    setState(() => _resolvingSignalId = signalId);
    try {
      await ref.read(authServiceProvider).resolveSurvivorSignal(signalId);
      await _refresh();
    } finally {
      if (mounted) {
        setState(() => _resolvingSignalId = null);
      }
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

  LatLng _preferredCenter() {
    final gpsCenter = _gpsCenter;
    if (gpsCenter != null) {
      return gpsCenter;
    }
    for (final row in [..._signals, ..._devices, ..._nodes]) {
      final point = _readPoint(row);
      if (point != null) {
        return point;
      }
    }
    return const LatLng(14.5995, 120.9842);
  }

  // Mesh endpoints return slightly different coordinate shapes, so one parser
  // keeps the shared map stable across roles and datasets.
  LatLng? _readPoint(Map<String, dynamic> row) {
    final coordinates = row['coordinates'];
    if (coordinates is List && coordinates.length >= 2) {
      final lng = (coordinates[0] as num?)?.toDouble();
      final lat = (coordinates[1] as num?)?.toDouble();
      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    }

    final lat = (row['lat'] as num?)?.toDouble();
    final lng = (row['lng'] as num?)?.toDouble();
    if (lat != null && lng != null) {
      return LatLng(lat, lng);
    }

    final location = row['location'] as Map<String, dynamic>?;
    final locationLat = (location?['lat'] as num?)?.toDouble();
    final locationLng = (location?['lng'] as num?)?.toDouble();
    if (locationLat != null && locationLng != null) {
      return LatLng(locationLat, locationLng);
    }

    final nodeLocation = row['node_location'] as Map<String, dynamic>?;
    final nodeLat =
        (nodeLocation?['lat'] as num?)?.toDouble() ??
        (nodeLocation?['latitude'] as num?)?.toDouble();
    final nodeLng =
        (nodeLocation?['lng'] as num?)?.toDouble() ??
        (nodeLocation?['longitude'] as num?)?.toDouble();
    if (nodeLat != null && nodeLng != null) {
      return LatLng(nodeLat, nodeLng);
    }

    return null;
  }

  void _moveCameraToPreferredCenter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady || _hasUserInteracted) {
        return;
      }
      try {
        _mapController.move(_preferredCenter(), _mapController.camera.zoom);
      } on StateError {
        // Map controller may not be attached yet during early rebuilds.
      }
    });
  }

  void _handleMapReady() {
    _mapReady = true;
    _moveCameraToPreferredCenter();
  }

  void _handlePositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture || _hasUserInteracted) {
      return;
    }
    setState(() {
      _hasUserInteracted = true;
    });
  }

  List<Marker> _markers() {
    final markers = <Marker>[];
    for (final node in _nodes) {
      final point = _readPoint(node);
      if (point == null) continue;
      markers.add(
        Marker(
          point: point,
          width: 38,
          height: 38,
          child: const Icon(Icons.hub, color: Color(0xFF1695D3), size: 30),
        ),
      );
    }
    for (final signal in _signals) {
      final point = _readPoint(signal);
      if (point == null) continue;
      markers.add(
        Marker(
          point: point,
          width: 40,
          height: 40,
          child: Icon(
            Icons.sos,
            color: widget.allowResolveActions
                ? const Color(0xFFA14B2F)
                : const Color(0xFFD97757),
            size: 32,
          ),
        ),
      );
    }
    for (final device in _devices) {
      final point = _readPoint(device);
      if (point == null) continue;
      markers.add(
        Marker(
          point: point,
          width: 34,
          height: 34,
          child: const Icon(
            Icons.my_location,
            color: Color(0xFF397154),
            size: 26,
          ),
        ),
      );
    }
    return markers;
  }

  String _signalLabel(Map<String, dynamic> signal) {
    return signal['detected_device_identifier'] as String? ??
        signal['message_id'] as String? ??
        'Signal';
  }

  String _signalMeta(Map<String, dynamic> signal) {
    final method = (signal['detection_method'] as String? ?? 'unknown')
        .replaceAll('_', ' ');
    final confidence = (((signal['confidence'] as num?)?.toDouble() ?? 0) * 100)
        .round();
    final hops = signal['hop_count'] ?? 0;
    final distance =
        ((signal['estimated_distance_meters'] as num?)?.toDouble() ?? 0)
            .toStringAsFixed(1);
    return '$method | confidence $confidence% | hop $hops | ~$distance m';
  }

  @override
  Widget build(BuildContext context) {
    final center = _preferredCenter();
    final viewerRole =
        ref.watch(sessionControllerProvider).role?.name ?? 'citizen';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.subtitle,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_nodes.length} mesh nodes, ${_signals.length} survivor signals, and ${_devices.length} live people pins are layered here for $viewerRole.',
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _StatPill(
                                label: 'Nodes',
                                value: '${_nodes.length}',
                              ),
                              _StatPill(
                                label: 'People',
                                value: '${_devices.length}',
                              ),
                              _StatPill(
                                label: 'Signals',
                                value: '${_signals.length}',
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: SizedBox(
                              height: 320,
                              child: FlutterMap(
                                mapController: _mapController,
                                options: MapOptions(
                                  initialCenter: center,
                                  initialZoom: 13,
                                  onMapReady: _handleMapReady,
                                  onPositionChanged: _handlePositionChanged,
                                ),
                                children: [
                                  ...buildDispatchMapTileLayers(),
                                  MarkerLayer(markers: _markers()),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: const [
                              _LegendPill(
                                icon: Icons.hub,
                                label: 'Mesh nodes',
                                tone: Color(0xFF1695D3),
                              ),
                              _LegendPill(
                                icon: Icons.sos,
                                label: 'Survivor signals',
                                tone: Color(0xFFA14B2F),
                              ),
                              _LegendPill(
                                icon: Icons.my_location,
                                label: 'People last seen',
                                tone: Color(0xFF397154),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Active survivor signals',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_signals.isEmpty)
                            const Text('No active survivor signals right now.')
                          else
                            ..._signals.map(
                              (signal) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF8F3),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFFE7D1C6),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              _signalLabel(signal),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          if (widget.allowCompassActions)
                                            FilledButton.tonal(
                                              onPressed: () => _openCompass(
                                                signal['message_id'] as String?,
                                              ),
                                              style: FilledButton.styleFrom(
                                                minimumSize: const Size(0, 40),
                                              ),
                                              child: const Text('Locator'),
                                            ),
                                          if (widget.allowResolveActions) ...[
                                            const SizedBox(width: 8),
                                            FilledButton(
                                              onPressed:
                                                  _resolvingSignalId ==
                                                      signal['id']
                                                  ? null
                                                  : () => _resolveSignal(
                                                      signal['id'] as String,
                                                    ),
                                              style: FilledButton.styleFrom(
                                                minimumSize: const Size(0, 40),
                                              ),
                                              child: Text(
                                                _resolvingSignalId ==
                                                        signal['id']
                                                    ? 'Resolving...'
                                                    : 'Resolve',
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(_signalMeta(signal)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7EADF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text(value),
        ],
      ),
    );
  }
}

class _LegendPill extends StatelessWidget {
  const _LegendPill({
    required this.icon,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}
