import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/shared/presentation/dispatch_map_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

class MunicipalityMeshMapScreen extends ConsumerStatefulWidget {
  const MunicipalityMeshMapScreen({super.key});

  @override
  ConsumerState<MunicipalityMeshMapScreen> createState() =>
      _MunicipalityMeshMapScreenState();
}

class _MunicipalityMeshMapScreenState
    extends ConsumerState<MunicipalityMeshMapScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _nodes = [];
  List<Map<String, dynamic>> _signals = [];
  List<Map<String, dynamic>> _devices = [];
  String? _resolvingSignalId;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final auth = ref.read(authServiceProvider);
      final topology = await auth.getMeshTopology();
      final survivorSignals = await auth.getSurvivorSignals();
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
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

  LatLng _initialCenter() {
    for (final row in [..._signals, ..._devices, ..._nodes]) {
      final point = _readPoint(row);
      if (point != null) {
        return point;
      }
    }
    return const LatLng(14.5995, 120.9842);
  }

  // The API returns slightly different geometry shapes per endpoint, so the
  // map uses one narrow parser to keep the screen resilient.
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

  List<Marker> _markers() {
    final markers = <Marker>[];
    for (final node in _nodes) {
      final point = _readPoint(node);
      if (point == null) continue;
      markers.add(
        Marker(
          point: point,
          width: 36,
          height: 36,
          child: const Icon(Icons.hub, color: Color(0xFF1695D3), size: 28),
        ),
      );
    }
    for (final signal in _signals) {
      final point = _readPoint(signal);
      if (point == null) continue;
      final resolved = signal['resolved'] == true;
      markers.add(
        Marker(
          point: point,
          width: 38,
          height: 38,
          child: Icon(
            resolved ? Icons.task_alt : Icons.sos,
            color: resolved ? const Color(0xFF8A7F79) : const Color(0xFFA14B2F),
            size: 30,
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
          width: 32,
          height: 32,
          child: const Icon(
            Icons.my_location,
            color: Color(0xFF397154),
            size: 24,
          ),
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final center = _initialCenter();
    final activeSignals = _signals
        .where((row) => row['resolved'] != true)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesh & SAR Map'),
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
                          const Text(
                            'Live topology snapshot',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_nodes.length} topology nodes, ${activeSignals.length} active survivor signals, and ${_devices.length} last-seen pins are layered on the same map.',
                          ),
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: SizedBox(
                              height: 320,
                              child: FlutterMap(
                                options: MapOptions(
                                  initialCenter: center,
                                  initialZoom: 13,
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
                                label: 'Topology nodes',
                                tone: Color(0xFF1695D3),
                              ),
                              _LegendPill(
                                icon: Icons.sos,
                                label: 'Survivor signals',
                                tone: Color(0xFFA14B2F),
                              ),
                              _LegendPill(
                                icon: Icons.my_location,
                                label: 'Last-seen devices',
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
                          if (activeSignals.isEmpty)
                            const Text('No active survivor signals right now.')
                          else
                            ...activeSignals.map(
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
                                              signal['detected_device_identifier']
                                                      as String? ??
                                                  signal['message_id']
                                                      as String? ??
                                                  'Signal',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          FilledButton.tonal(
                                            onPressed:
                                                _resolvingSignalId ==
                                                    signal['id']
                                                ? null
                                                : () => _resolveSignal(
                                                    signal['id'] as String,
                                                  ),
                                            child: Text(
                                              _resolvingSignalId == signal['id']
                                                  ? 'Resolving...'
                                                  : 'Resolve',
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${(signal['detection_method'] as String? ?? 'unknown').replaceAll('_', ' ')} | confidence ${(((signal['confidence'] as num?)?.toDouble() ?? 0) * 100).round()}% | hop ${signal['hop_count'] ?? 0}',
                                      ),
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
