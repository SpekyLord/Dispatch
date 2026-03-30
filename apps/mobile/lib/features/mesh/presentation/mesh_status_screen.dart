// Mesh status panel - shows current role, peer count, estimated reach,
// queue size, last sync time, and SAR mode controls for responders.

import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/sar_mode_service.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session_controller.dart';
import 'package:dispatch_mobile/core/state/session_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MeshStatusScreen extends ConsumerStatefulWidget {
  const MeshStatusScreen({super.key});

  @override
  ConsumerState<MeshStatusScreen> createState() => _MeshStatusScreenState();
}

class _MeshStatusScreenState extends ConsumerState<MeshStatusScreen> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final transport = ref.read(meshTransportProvider);
    await transport.initialize();
    ref.read(sarModeControllerProvider.notifier).refreshSubsystemStatus();
    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transport = ref.read(meshTransportProvider);
    final sarState = ref.watch(sarModeControllerProvider);
    final session = ref.watch(sessionControllerProvider);
    final canEnableSarMode =
        session.role == AppRole.department &&
        session.department?.verificationStatus == 'approved';

    return Scaffold(
      appBar: AppBar(title: const Text('Mesh Network')),
      body: !_initialized
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                transport.pruneStalePeers();
                ref
                    .read(sarModeControllerProvider.notifier)
                    .refreshSubsystemStatus();
                setState(() {});
              },
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  _buildRoleCard(theme, transport),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.people_outline,
                          value: '${transport.peerCount}',
                          label: 'Peers',
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.outbox,
                          value: '${transport.queueSize}',
                          label: 'Queue',
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.cell_tower,
                          value: '~${transport.estimatedReach}',
                          label: 'Reach',
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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
                              transport.lastSyncTime != null
                                  ? _formatTime(transport.lastSyncTime!)
                                  : 'Never',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SarModeCard(
                    canEnableSarMode: canEnableSarMode,
                    sarState: sarState,
                    isSosBeaconBroadcasting: transport.isSosBeaconBroadcasting,
                    onToggle: (value) {
                      ref
                          .read(sarModeControllerProvider.notifier)
                          .setSarModeEnabled(value);
                    },
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: Icon(
                        transport.isDiscovering
                            ? Icons.bluetooth_searching
                            : Icons.bluetooth,
                        color: transport.isDiscovering
                            ? Colors.blue
                            : Colors.grey,
                      ),
                      title: Text(
                        transport.isDiscovering
                            ? 'Discovering...'
                            : 'Start Discovery',
                      ),
                      subtitle: Text(
                        transport.isDiscovering
                            ? 'Scanning for nearby mesh devices'
                            : 'Tap to find nearby devices',
                      ),
                      trailing: Switch(
                        value: transport.isDiscovering,
                        onChanged: (value) async {
                          if (value) {
                            await transport.startDiscovery();
                          } else {
                            await transport.stopDiscovery();
                          }
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (transport.peers.isNotEmpty) ...[
                    Text(
                      'Nearby Peers',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...transport.peers.map(
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

  Widget _buildRoleCard(ThemeData theme, MeshTransportService transport) {
    final roleLabel = switch (transport.role) {
      MeshNodeRole.origin => 'Origin',
      MeshNodeRole.relay => 'Relay',
      MeshNodeRole.gateway => 'Gateway',
    };
    final roleIcon = switch (transport.role) {
      MeshNodeRole.origin => Icons.phone_android,
      MeshNodeRole.relay => Icons.swap_horiz,
      MeshNodeRole.gateway => Icons.cloud_upload,
    };
    final roleColor = switch (transport.role) {
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

  String _formatTime(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

class _SarModeCard extends StatelessWidget {
  const _SarModeCard({
    required this.canEnableSarMode,
    required this.sarState,
    required this.isSosBeaconBroadcasting,
    required this.onToggle,
  });

  final bool canEnableSarMode;
  final SarModeState sarState;
  final bool isSosBeaconBroadcasting;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final activeSignals = sarState.activeSignals;
    final subsystemActive = {
      ...sarState.subsystemActive,
      SarDetectionMethod.sosBeacon: isSosBeaconBroadcasting,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: sarState.isEnabled,
              onChanged: canEnableSarMode ? onToggle : null,
              title: const Text('SAR Mode'),
              subtitle: Text(
                canEnableSarMode
                    ? 'Enable passive survivor detection and the local SAR feed.'
                    : 'Only verified department responders can enable SAR Mode.',
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: subsystemActive.entries.map((entry) {
                final label = switch (entry.key) {
                  SarDetectionMethod.wifiProbe => 'Wi-Fi Probe',
                  SarDetectionMethod.blePassive => 'BLE Passive',
                  SarDetectionMethod.acoustic => 'Acoustic',
                  SarDetectionMethod.sosBeacon => 'SOS Beacon',
                };
                return Chip(
                  avatar: Icon(
                    entry.value
                        ? Icons.check_circle
                        : Icons.pause_circle_outline,
                    size: 16,
                    color: entry.value
                        ? Colors.green.shade700
                        : Colors.grey.shade600,
                  ),
                  label: Text(label),
                );
              }).toList(),
            ),
            if (sarState.isEnabled) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Text(
                  'Passive sensing is active. Device identifiers are anonymized before storage, raw audio never leaves the device, and continuous scanning will increase battery use.',
                  style: TextStyle(color: Colors.amber.shade900, fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'SAR Detection Feed',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (activeSignals.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'No survivor signals yet. Nearby BLE, Wi-Fi probe, acoustic, and SOS beacon detections will appear here once received.',
                ),
              )
            else
              ...activeSignals.map(
                (signal) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: signal.detectionMethod == SarDetectionMethod.sosBeacon
                      ? Colors.red.shade50
                      : null,
                  child: ListTile(
                    leading: Icon(
                      switch (signal.detectionMethod) {
                        SarDetectionMethod.wifiProbe => Icons.wifi_tethering,
                        SarDetectionMethod.blePassive =>
                          Icons.bluetooth_searching,
                        SarDetectionMethod.acoustic => Icons.graphic_eq,
                        SarDetectionMethod.sosBeacon => Icons.sos,
                      },
                      color:
                          signal.detectionMethod == SarDetectionMethod.sosBeacon
                          ? Colors.red.shade700
                          : Colors.blueGrey.shade700,
                    ),
                    title: Text(
                      '${signal.detectionMethod.wireValue.replaceAll('_', ' ')} • ${signal.estimatedDistanceMeters.toStringAsFixed(1)} m',
                    ),
                    subtitle: Text(
                      'Confidence ${(signal.confidence * 100).round()}% • ${signal.detectedDeviceIdentifier} • ${signal.isRelayed ? 'relayed ${signal.hopCount}/${signal.maxHops}' : 'local'}',
                    ),
                    trailing: Text(
                      _formatLastSeen(signal.lastSeenTimestamp),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
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

  static String _formatLastSeen(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m';
    }
    return '${diff.inHours}h';
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
