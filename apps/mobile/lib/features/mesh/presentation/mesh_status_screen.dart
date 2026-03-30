// Mesh status panel — shows current role, peer count, estimated reach,
// queue size, and last sync time.

import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:flutter/material.dart';

class MeshStatusScreen extends StatefulWidget {
  const MeshStatusScreen({super.key});

  @override
  State<MeshStatusScreen> createState() => _MeshStatusScreenState();
}

class _MeshStatusScreenState extends State<MeshStatusScreen> {
  final _transport = MeshTransportService();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _transport.initialize();
    if (mounted) setState(() => _initialized = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Mesh Network')),
      body: !_initialized
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                _transport.pruneStaleePeers();
                setState(() {});
              },
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  // role indicator
                  _buildRoleCard(theme),
                  const SizedBox(height: 16),

                  // stats grid
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.people_outline,
                          value: '${_transport.peerCount}',
                          label: 'Peers',
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.outbox,
                          value: '${_transport.queueSize}',
                          label: 'Queue',
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.cell_tower,
                          value: '~${_transport.estimatedReach}',
                          label: 'Reach',
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // last sync
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.sync, color: Colors.grey.shade600, size: 20),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Last Sync',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              _transport.lastSyncTime != null
                                  ? _formatTime(_transport.lastSyncTime!)
                                  : 'Never',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // discovery toggle
                  Card(
                    child: ListTile(
                      leading: Icon(
                        _transport.isDiscovering
                            ? Icons.bluetooth_searching
                            : Icons.bluetooth,
                        color: _transport.isDiscovering
                            ? Colors.blue
                            : Colors.grey,
                      ),
                      title: Text(
                        _transport.isDiscovering
                            ? 'Discovering...'
                            : 'Start Discovery',
                      ),
                      subtitle: Text(
                        _transport.isDiscovering
                            ? 'Scanning for nearby mesh devices'
                            : 'Tap to find nearby devices',
                      ),
                      trailing: Switch(
                        value: _transport.isDiscovering,
                        onChanged: (v) async {
                          if (v) {
                            await _transport.startDiscovery();
                          } else {
                            await _transport.stopDiscovery();
                          }
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // peer list
                  if (_transport.peers.isNotEmpty) ...[
                    Text(
                      'Nearby Peers',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._transport.peers.map(
                      (peer) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: peer.isGateway
                                ? Colors.green.shade100
                                : Colors.blue.shade100,
                            child: Icon(
                              peer.isGateway
                                  ? Icons.cloud_done
                                  : Icons.phone_android,
                              size: 20,
                              color: peer.isGateway
                                  ? Colors.green.shade700
                                  : Colors.blue.shade700,
                            ),
                          ),
                          title: Text(
                            peer.deviceName.isNotEmpty
                                ? peer.deviceName
                                : peer.endpointId.substring(0, 8),
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            peer.isGateway ? 'Gateway' : 'Relay',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          trailing: Text(
                            _formatTime(peer.lastSeen),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildRoleCard(ThemeData theme) {
    final roleLabel = switch (_transport.role) {
      MeshNodeRole.origin => 'Origin',
      MeshNodeRole.relay => 'Relay',
      MeshNodeRole.gateway => 'Gateway',
    };
    final roleIcon = switch (_transport.role) {
      MeshNodeRole.origin => Icons.phone_android,
      MeshNodeRole.relay => Icons.swap_horiz,
      MeshNodeRole.gateway => Icons.cloud_upload,
    };
    final roleColor = switch (_transport.role) {
      MeshNodeRole.origin => Colors.blue,
      MeshNodeRole.relay => Colors.orange,
      MeshNodeRole.gateway => Colors.green,
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: roleColor.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: roleColor.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: roleColor.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(roleIcon, color: roleColor.shade700, size: 24),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Node Role',
                style: TextStyle(
                  fontSize: 12,
                  color: roleColor.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                roleLabel,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: roleColor.shade800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, color: color.shade700, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: color.shade800,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
