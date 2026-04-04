import 'dart:async';

import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/sar_mode_service.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/mesh/presentation/mesh_people_map_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/survivor_compass_screen.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MeshStatusScreen extends ConsumerStatefulWidget {
  const MeshStatusScreen({super.key});

  @override
  ConsumerState<MeshStatusScreen> createState() => _MeshStatusScreenState();
}

class _MeshStatusScreenState extends ConsumerState<MeshStatusScreen> {
  bool _initialized = false;
  bool _refreshingSignals = false;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    final transport = ref.read(meshTransportProvider);
    await transport.initialize();
    await ref.read(sarModeControllerProvider.notifier).refreshSubsystemStatus();
    await _hydrateSignals(silent: true);
    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  Future<void> _hydrateSignals({bool silent = false}) async {
    final session = ref.read(sessionControllerProvider);
    final canFetchSarSignals =
        session.accessToken != null &&
        session.role != AppRole.citizen &&
        session.role != null;

    if (!canFetchSarSignals) {
      return;
    }

    if (mounted) {
      setState(() => _refreshingSignals = true);
    }

    try {
      final auth = ref.read(authServiceProvider);
      final rows = await auth.getSurvivorSignals(status: 'active');
      ref.read(sarModeControllerProvider.notifier).ingestServerSignals(rows);

      final lastSeenResponse = await auth.getMeshLastSeen();
      final devices =
          (lastSeenResponse['devices'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>();
      ref.read(meshTransportProvider).ingestServerLastSeen(devices);
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Live survivor sync is unavailable right now. Local SAR detections are still shown.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _refreshingSignals = false);
      }
    }
  }

  Future<void> _handleRefresh() async {
    final transport = ref.read(meshTransportProvider);
    final session = ref.read(sessionControllerProvider);
    transport.pruneStalePeers();
    await ref.read(sarModeControllerProvider.notifier).refreshSubsystemStatus();
    if (session.accessToken != null) {
      try {
        await ref
            .read(meshGatewaySyncServiceProvider)
            .sync(
              operatorRole: session.role?.name,
              departmentId: session.department?.id,
              departmentName: session.department?.name,
              displayName:
                  session.fullName ?? session.department?.name ?? session.email,
            );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Gateway sync failed. Topology upload will retry on the next sync.',
              ),
            ),
          );
        }
      }
    }
    await _hydrateSignals();
    if (mounted) {
      setState(() {});
    }
  }

  void _openCompass([String? messageId]) {
    final allowResolve =
        ref.read(sessionControllerProvider).role != AppRole.citizen;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SurvivorCompassScreen(
          initialTargetMessageId: messageId,
          allowResolve: allowResolve,
        ),
      ),
    );
  }

  void _openPeopleMap() {
    final session = ref.read(sessionControllerProvider);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MeshPeopleMapScreen(
          title: 'People & Mesh Map',
          subtitle: session.role == AppRole.citizen
              ? 'Citizen visibility into live people pins and survivor signals'
              : 'Responder visibility into live people pins and survivor signals',
          allowResolveActions: session.role != AppRole.citizen,
          allowCompassActions: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transport = ref.read(meshTransportProvider);
    final sarState = ref.watch(sarModeControllerProvider);
    final session = ref.watch(sessionControllerProvider);
    final canEnableSarMode =
        session.role == AppRole.department &&
        session.department?.verificationStatus == 'approved';
    final canReviewSignals =
        session.accessToken != null && session.role != AppRole.citizen;
    final canOpenCompass =
        canReviewSignals && sarState.activeSignals.isNotEmpty;

    return Scaffold(
      backgroundColor: dc.warmBackground,
      appBar: AppBar(
        title: const Text('Mesh Network'),
        backgroundColor: dc.warmBackground,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: _refreshingSignals
                ? null
                : () => unawaited(_handleRefresh()),
            icon: const Icon(Icons.sync),
            tooltip: 'Refresh mesh status',
          ),
        ],
      ),
      body: !_initialized
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: dc.warmSeed,
              onRefresh: _handleRefresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          ...dc.heroGradient,
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
                            'Offline Relay / SAR Bulletin',
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
                          'Coordinate the local mesh and jump straight into survivor tracking when a strong signal appears.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          canReviewSignals
                              ? 'This panel keeps discovery, relay health, and SAR detections in one place so responders do not need to bounce between generic utility screens.'
                              : 'Citizens can review mesh reach, discovery, and sync state here, while SAR controls remain reserved for verified responder accounts.',
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
                              label: 'Node role',
                              value: _roleLabel(transport.role),
                            ),
                            _HeroStat(
                              label: 'Nearby peers',
                              value: '${transport.peerCount}',
                            ),
                            _HeroStat(
                              label: 'SAR signals',
                              value: '${sarState.activeSignals.length}',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.people_outline,
                          value: '${transport.peerCount}',
                          label: 'Peers',
                          accent: dc.coolAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.outbox,
                          value: '${transport.queueSize}',
                          label: 'Queue',
                          accent: dc.warmSeed,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.radar,
                          value: '~${transport.estimatedReach}',
                          label: 'Reach',
                          accent: dc.statusResolved,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _InfoStrip(
                    icon: Icons.sync,
                    title: 'Last sync',
                    body: transport.lastSyncTime != null
                        ? _formatTime(transport.lastSyncTime!)
                        : 'No gateway sync has completed yet.',
                    trailing: _refreshingSignals
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                  ),
                  const SizedBox(height: 18),
                  _RoleCard(transport: transport),
                  const SizedBox(height: 18),
                  _DiscoveryCard(
                    discovering: transport.isDiscovering,
                    onChanged: (value) async {
                      if (value) {
                        await transport.startDiscovery();
                      } else {
                        await transport.stopDiscovery();
                      }
                      if (mounted) {
                        setState(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 18),
                  _PeopleMapPanel(onOpenMap: _openPeopleMap),
                  const SizedBox(height: 18),
                  _SarModePanel(
                    activeTarget: sarState.activeTarget,
                    canEnableSarMode: canEnableSarMode,
                    canOpenCompass: canOpenCompass,
                    canReviewSignals: canReviewSignals,
                    onCompassPressed: canOpenCompass
                        ? () => _openCompass(sarState.activeTarget?.messageId)
                        : null,
                    onOpenSignal: (messageId) {
                      ref
                          .read(sarModeControllerProvider.notifier)
                          .pinTarget(messageId);
                      _openCompass(messageId);
                    },
                    onToggle: (value) {
                      unawaited(
                        ref
                            .read(sarModeControllerProvider.notifier)
                            .setSarModeEnabled(value),
                      );
                    },
                    sarState: sarState,
                    sosBeaconBroadcasting: transport.isSosBeaconBroadcasting,
                    lastSeenLookup: transport.lastSeenForDevice,
                  ),
                  const SizedBox(height: 18),
                  if (transport.peers.isNotEmpty)
                    _PeerBoard(peers: transport.peers)
                  else
                    const _EmptyPanel(
                      icon: Icons.bluetooth_searching,
                      title: 'No peers discovered yet',
                      body:
                          'Start discovery to refresh the local mesh roster and estimate reach before sending a gateway-bound batch.',
                    ),
                ],
              ),
            ),
    );
  }

  static String _roleLabel(MeshNodeRole role) {
    return switch (role) {
      MeshNodeRole.origin => 'Origin',
      MeshNodeRole.relay => 'Relay',
      MeshNodeRole.gateway => 'Gateway',
    };
  }

  static String _formatTime(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }
    return '${diff.inHours}h ago';
  }

  static String _formatCoordinates(double lat, double lng) {
    return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
  }

  static String _appStateLabel(String appState) {
    return appState.replaceAll('_', ' ');
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
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dc.warmSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dc.warmBorder),
      ),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: dc.ink,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: dc.mutedInk,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({
    required this.icon,
    required this.title,
    required this.body,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dc.warmSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: dc.warmBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: dc.chipFill,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: dc.warmSeed),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: dc.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(color: dc.mutedInk)),
              ],
            ),
          ),
          trailing ?? const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.transport});

  final MeshTransportService transport;

  @override
  Widget build(BuildContext context) {
    final roleLabel = _MeshStatusScreenState._roleLabel(transport.role);
    final roleIcon = switch (transport.role) {
      MeshNodeRole.origin => Icons.phone_android,
      MeshNodeRole.relay => Icons.swap_horiz,
      MeshNodeRole.gateway => Icons.cloud_done,
    };
    final accent = switch (transport.role) {
      MeshNodeRole.origin => dc.coolAccent,
      MeshNodeRole.relay => dc.warmSeed,
      MeshNodeRole.gateway => dc.statusResolved,
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dc.warmSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: dc.warmBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(roleIcon, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current node role',
                  style: TextStyle(
                    color: dc.mutedInk,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  roleLabel,
                  style: const TextStyle(
                    color: dc.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
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

class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({required this.discovering, required this.onChanged});

  final bool discovering;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dc.warmSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: dc.warmBorder),
      ),
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: discovering,
            onChanged: onChanged,
            title: const Text(
              'Device discovery',
              style: TextStyle(color: dc.ink, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              discovering
                  ? 'Scanning for nearby relay and gateway peers.'
                  : 'Start BLE discovery to refresh the local mesh roster.',
              style: const TextStyle(color: dc.mutedInk),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeopleMapPanel extends StatelessWidget {
  const _PeopleMapPanel({required this.onOpenMap});

  final VoidCallback onOpenMap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dc.warmSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: dc.warmBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: dc.chipFill,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.map_outlined, color: dc.warmSeed),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'People & mesh map',
                  style: TextStyle(
                    color: dc.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Open the shared mobile map to see people pins, mesh nodes, and survivor signals in one place.',
                  style: TextStyle(color: dc.mutedInk, height: 1.45),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onOpenMap,
            style: FilledButton.styleFrom(
              backgroundColor: dc.warmSeed,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
            ),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open'),
          ),
        ],
      ),
    );
  }
}

class _SarModePanel extends StatelessWidget {
  const _SarModePanel({
    required this.activeTarget,
    required this.canEnableSarMode,
    required this.canOpenCompass,
    required this.canReviewSignals,
    required this.onCompassPressed,
    required this.onOpenSignal,
    required this.onToggle,
    required this.sarState,
    required this.sosBeaconBroadcasting,
    required this.lastSeenLookup,
  });

  final SurvivorSignalEvent? activeTarget;
  final bool canEnableSarMode;
  final bool canOpenCompass;
  final bool canReviewSignals;
  final VoidCallback? onCompassPressed;
  final ValueChanged<String> onOpenSignal;
  final ValueChanged<bool> onToggle;
  final SarModeState sarState;
  final bool sosBeaconBroadcasting;
  final DeviceLocationTrailPoint? Function(String deviceFingerprint)
  lastSeenLookup;

  @override
  Widget build(BuildContext context) {
    final activeSignals = sarState.activeSignals;
    final subsystemActive = {
      ...sarState.subsystemActive,
      SarDetectionMethod.sosBeacon: sosBeaconBroadcasting,
    };
    final subsystemSupported = sarState.subsystemSupported;
    final subsystemNotes = sarState.subsystemNotes;
    final liveInputs = <String>[
      if (subsystemActive[SarDetectionMethod.blePassive] == true)
        'BLE passive scan',
      if (subsystemActive[SarDetectionMethod.acoustic] == true)
        'microphone summary windows',
      if (subsystemActive[SarDetectionMethod.sosBeacon] == true)
        'SOS beacon advertising',
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dc.warmSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: dc.warmBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'SAR mode',
                  style: TextStyle(
                    color: dc.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (canOpenCompass)
                FilledButton.icon(
                  onPressed: onCompassPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: dc.warmSeed,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 44),
                  ),
                  icon: const Icon(Icons.explore),
                  label: const Text('Open compass'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            canEnableSarMode
                ? 'Enable passive sensing, review relayed survivor signals, and jump into compass guidance from the same responder workflow.'
                : canReviewSignals
                ? 'Only verified department responders can enable passive sensing, but citizens, departments, and municipalities can still review synced survivor signals here.'
                : 'SAR controls stay locked for non-responder accounts.',
            style: const TextStyle(color: dc.mutedInk, height: 1.45),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: sarState.isEnabled,
            onChanged: canEnableSarMode ? onToggle : null,
            title: const Text(
              'Passive survivor detection',
              style: TextStyle(color: dc.ink, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              canEnableSarMode
                  ? 'BLE and acoustic sensing can run locally, while Wi-Fi probe sniffing stays unavailable on standard mobile app sandboxes.'
                  : 'Verification approval is required before SAR Mode can be enabled on this device.',
              style: const TextStyle(color: dc.mutedInk),
            ),
          ),
          const SizedBox(height: 8),
          ...subsystemActive.entries.map((entry) {
            final label = switch (entry.key) {
              SarDetectionMethod.wifiProbe => 'Wi-Fi probe',
              SarDetectionMethod.blePassive => 'BLE passive',
              SarDetectionMethod.acoustic => 'Acoustic',
              SarDetectionMethod.sosBeacon => 'SOS beacon',
            };
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SubsystemStatusCard(
                label: label,
                active: entry.value,
                supported: subsystemSupported[entry.key] ?? false,
                note: subsystemNotes[entry.key],
              ),
            );
          }),
          if (sarState.isEnabled) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: dc.chipFill,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                liveInputs.isEmpty
                    ? 'Passive sensing is armed, but this device still needs the required Nearby Devices or Microphone permission before live inputs can start. Identifiers stay anonymized and raw audio never leaves the device.'
                    : '${liveInputs.join(', ')} ${liveInputs.length == 1 ? 'is' : 'are'} active. Identifiers are anonymized before storage, raw audio never leaves the device, and continuous sensing increases battery use during a sweep.',
                style: const TextStyle(color: dc.mutedInk, height: 1.45),
              ),
            ),
          ],
          if (activeTarget != null) ...[
            const SizedBox(height: 14),
            _ActiveTargetCard(
              signal: activeTarget!,
              onPressed: onCompassPressed,
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'Survivor signal feed',
            style: TextStyle(
              color: dc.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (activeSignals.isEmpty)
            const _EmptyPanel(
              icon: Icons.radar,
              title: 'No survivor signals yet',
              body:
                  'Nearby BLE, acoustic, and SOS beacon detections will appear here once received or synced from the server.',
            )
          else
            ...activeSignals.map(
              (signal) => _SignalCard(
                pinned: signal.messageId == sarState.activeTargetMessageId,
                canOpenCompass: canOpenCompass,
                signal: signal,
                lastSeenBeacon: lastSeenLookup(signal.detectedDeviceIdentifier),
                onOpen: signal.isResolved
                    ? null
                    : () => onOpenSignal(signal.messageId),
              ),
            ),
        ],
      ),
    );
  }
}

class _SubsystemStatusCard extends StatelessWidget {
  const _SubsystemStatusCard({
    required this.label,
    required this.active,
    required this.supported,
    this.note,
  });

  final String label;
  final bool active;
  final bool supported;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final accent = !supported
        ? dc.mutedInk
        : active
        ? dc.statusResolved
        : dc.coolAccent;
    final status = !supported
        ? 'Unavailable'
        : active
        ? 'Live now'
        : 'Ready';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active ? dc.statusResolved.withValues(alpha: 0.2) : dc.warmBorder,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              !supported
                  ? Icons.block
                  : active
                  ? Icons.radar
                  : Icons.settings_input_component_outlined,
              color: accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: dc.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if ((note ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    note!,
                    style: const TextStyle(color: dc.mutedInk, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveTargetCard extends StatelessWidget {
  const _ActiveTargetCard({required this.signal, this.onPressed});

  final SurvivorSignalEvent signal;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dc.coolAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.explore, color: dc.coolAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Pinned target: ${signal.detectedDeviceIdentifier}',
              style: const TextStyle(
                color: dc.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(onPressed: onPressed, child: const Text('Compass')),
        ],
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({
    required this.pinned,
    required this.canOpenCompass,
    required this.signal,
    required this.onOpen,
    this.lastSeenBeacon,
  });

  final bool pinned;
  final bool canOpenCompass;
  final SurvivorSignalEvent signal;
  final VoidCallback? onOpen;
  final DeviceLocationTrailPoint? lastSeenBeacon;

  @override
  Widget build(BuildContext context) {
    final title = switch (signal.detectionMethod) {
      SarDetectionMethod.wifiProbe => 'Wi-Fi probe',
      SarDetectionMethod.blePassive => 'BLE passive',
      SarDetectionMethod.acoustic => 'Acoustic',
      SarDetectionMethod.sosBeacon => 'SOS beacon',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pinned ? dc.chipFill : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pinned ? dc.warmSeed : dc.warmBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$title | ${signal.estimatedDistanceMeters.toStringAsFixed(1)} m',
                  style: const TextStyle(
                    color: dc.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (signal.isResolved)
                const Chip(label: Text('Resolved'))
              else if (canOpenCompass)
                FilledButton(
                  onPressed: onOpen,
                  style: FilledButton.styleFrom(
                    backgroundColor: pinned ? dc.warmSeed : dc.coolAccent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 40),
                  ),
                  child: Text(pinned ? 'Compass' : 'Track'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${signal.detectedDeviceIdentifier} | Confidence ${(signal.confidence * 100).round()}% | ${signal.isRelayed ? 'relayed ${signal.hopCount}/${signal.maxHops}' : 'local'}',
            style: const TextStyle(color: dc.mutedInk, height: 1.45),
          ),
          const SizedBox(height: 8),
          Text(
            _MeshStatusScreenState._formatTime(signal.lastSeenTimestamp),
            style: const TextStyle(color: dc.mutedInk, fontSize: 12),
          ),
          if (lastSeenBeacon != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: dc.chipFill,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Last Seen beacon ${_MeshStatusScreenState._formatTime(lastSeenBeacon!.recordedAt)}',
                    style: const TextStyle(
                      color: dc.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _MeshStatusScreenState._formatCoordinates(
                      lastSeenBeacon!.lat,
                      lastSeenBeacon!.lng,
                    ),
                    style: const TextStyle(color: dc.mutedInk),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'State ${_MeshStatusScreenState._appStateLabel(lastSeenBeacon!.appState)}${lastSeenBeacon!.batteryPct == null ? '' : ' | Battery ${lastSeenBeacon!.batteryPct}%'}',
                    style: const TextStyle(color: dc.mutedInk),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PeerBoard extends StatelessWidget {
  const _PeerBoard({required this.peers});

  final List<MeshPeer> peers;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dc.warmSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: dc.warmBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nearby peers',
            style: TextStyle(
              color: dc.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ...peers.map(
            (peer) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: dc.warmBorder),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: peer.isGateway
                        ? dc.statusResolved.withValues(alpha: 0.15)
                        : dc.coolAccent.withValues(alpha: 0.15),
                    child: Icon(
                      peer.isGateway ? Icons.cloud_done : Icons.phone_android,
                      color: peer.isGateway
                          ? dc.statusResolved
                          : dc.coolAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          peer.deviceName.isNotEmpty
                              ? peer.deviceName
                              : peer.endpointId.substring(0, 8),
                          style: const TextStyle(
                            color: dc.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          peer.isConnected
                              ? 'Connected ${peer.transport ?? 'relay'} peer'
                              : (peer.isGateway
                                    ? 'Gateway peer'
                                    : 'Relay peer'),
                          style: const TextStyle(color: dc.mutedInk),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _MeshStatusScreenState._formatTime(peer.lastSeen),
                    style: const TextStyle(color: dc.mutedInk, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
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
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dc.warmSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: dc.warmBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: dc.chipFill,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: dc.warmSeed),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: dc.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(color: dc.mutedInk, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
