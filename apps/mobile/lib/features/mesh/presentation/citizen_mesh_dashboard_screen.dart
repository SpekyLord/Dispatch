import 'dart:async';

import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:dispatch_mobile/features/mesh/presentation/offline_comms_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/sos_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CitizenMeshDashboardScreen extends ConsumerStatefulWidget {
  const CitizenMeshDashboardScreen({super.key, this.onOpenMapTab});

  final VoidCallback? onOpenMapTab;

  @override
  ConsumerState<CitizenMeshDashboardScreen> createState() =>
      _CitizenMeshDashboardScreenState();
}

class _CitizenMeshDashboardScreenState
    extends ConsumerState<CitizenMeshDashboardScreen> {
  bool _ready = false;
  bool _refreshing = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh(initialLoad: true));
    _ticker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool initialLoad = false}) async {
    if (mounted) {
      setState(() {
        _refreshing = true;
      });
    }

    try {
      final transport = ref.read(meshTransportProvider);
      await transport.initialize();
      transport.pruneStalePeers();
      if (!transport.isDiscovering) {
        await transport.startDiscovery();
      }
      if (mounted) {
        setState(() {
          _ready = true;
        });
      }
    } catch (_) {
      if (mounted && initialLoad) {
        setState(() {
          _ready = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _openLog() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const OfflineCommsScreen()));
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openSos() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SosScreen()));
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final transport = ref.watch(meshTransportProvider);
    final activeNodes = transport.peerCount + 1;
    final recentDispatches = transport.inboxItems.length;
    final rangeDisplay = _rangeDisplay(transport);
    final activities = _buildActivities(transport);

    return Scaffold(
      backgroundColor: dc.background,
      body: !_ready
          ? const Center(child: CircularProgressIndicator(color: dc.primary))
          : SafeArea(
              bottom: false,
              child: RefreshIndicator(
                color: dc.primary,
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 140),
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.bar_chart_rounded,
                          color: dc.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Mesh Network',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _refreshing ? null : () => _refresh(),
                          icon: _refreshing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: dc.primary,
                                  ),
                                )
                              : const Icon(
                                  Icons.sync,
                                  color: dc.onSurfaceVariant,
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _StatusBanner(transport: transport),
                    const SizedBox(height: 34),
                    _MetricCard(
                      label: 'TOTAL ACTIVE NODES',
                      value: '$activeNodes',
                      suffix: transport.peerCount > 0
                          ? '+${transport.peerCount}'
                          : null,
                    ),
                    const SizedBox(height: 28),
                    _MetricCard(
                      label: 'RECENT DISPATCHES',
                      value: '$recentDispatches',
                      suffixIcon: recentDispatches > 0
                          ? Icons.wifi_tethering_rounded
                          : null,
                    ),
                    const SizedBox(height: 28),
                    _MetricCard(
                      label: 'NETWORK RANGE',
                      value: rangeDisplay.value,
                      trailingText: rangeDisplay.unit,
                    ),
                    const SizedBox(height: 36),
                    GestureDetector(
                      onTap: widget.onOpenMapTab,
                      child: _ScanMapCard(
                        scanningLabel: transport.peerCount > 0
                            ? 'Scanning ~${transport.estimatedReach}m sector...'
                            : 'Scanning for nearby nodes...',
                      ),
                    ),
                    const SizedBox(height: 34),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Recent Activity',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _openLog,
                          child: const Text(
                            'View Log',
                            style: TextStyle(
                              color: dc.primary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    for (final activity in activities) ...[
                      _ActivityCard(activity: activity),
                      const SizedBox(height: 14),
                    ],
                    const SizedBox(height: 16),
                    Center(
                      child: FilledButton(
                        onPressed: _openSos,
                        style: FilledButton.styleFrom(
                          backgroundColor: dc.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(300, 68),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'SOS',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.6,
                              ),
                            ),
                            SizedBox(width: 18),
                            Text(
                              'SEND SOS',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  ({String value, String? unit}) _rangeDisplay(MeshTransportService transport) {
    if (transport.peerCount == 0) return (value: '--', unit: null);
    final meters = transport.estimatedReach.clamp(50, 12000);
    if (meters >= 1000) {
      return (value: (meters / 1000).toStringAsFixed(1), unit: 'km');
    }
    return (value: '$meters', unit: 'm');
  }

  List<_DashboardActivity> _buildActivities(MeshTransportService transport) {
    final inbox = transport.inboxItems;
    return inbox.take(3).map(_activityFromInboxItem).toList(growable: false);
  }

  _DashboardActivity _activityFromInboxItem(MeshInboxItem item) {
    final title = (item.title ?? '').trim().isNotEmpty
        ? item.title!.trim()
        : item.itemType == 'mesh_post'
        ? 'Broadcast from ${item.authorDisplayName}'
        : 'New Message from ${item.authorDisplayName}';
    final subtitle = item.body.trim().isEmpty
        ? 'Mesh activity update'
        : item.body;
    return _DashboardActivity(
      icon: item.itemType == 'mesh_post'
          ? Icons.campaign_outlined
          : Icons.chat_bubble_outline_rounded,
      title: title,
      subtitle: subtitle,
      timeLabel: _timeAgo(item.createdAt),
    );
  }

  String _timeAgo(String rawDate) {
    final parsed = DateTime.tryParse(rawDate);
    if (parsed == null) {
      return 'now';
    }
    final diff = DateTime.now().difference(parsed.toLocal());
    if (diff.inMinutes < 1) {
      return 'now';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    }
    return '${diff.inDays}d ago';
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.transport});

  final MeshTransportService transport;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final String title;
    final String subtitle;

    if (!transport.isDiscovering) {
      icon = Icons.wifi_off_rounded;
      title = 'Mesh Offline';
      subtitle = 'Discovery not started';
    } else if (transport.peerCount > 0) {
      icon = Icons.hub_rounded;
      title = 'Mesh Active';
      final p = transport.peerCount;
      subtitle = '$p peer${p == 1 ? '' : 's'} connected';
    } else if (transport.hasNativeDiscovery) {
      icon = Icons.wifi_tethering_rounded;
      title = 'Mesh Scanning';
      subtitle = 'Looking for nearby nodes\u2026';
    } else {
      icon = Icons.wifi_off_rounded;
      title = 'Mesh Limited';
      subtitle = 'BLE unavailable \u2014 internet relay only';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: dc.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Color(0xFFF2E6D9),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: dc.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: dc.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: dc.primaryDim, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    this.suffix,
    this.trailingText,
    this.suffixIcon,
  });

  final String label;
  final String value;
  final String? suffix;
  final String? trailingText;
  final IconData? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 192,
      padding: const EdgeInsets.fromLTRB(34, 34, 34, 28),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: dc.onSurface.withValues(alpha: 0.03),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: dc.onSurfaceVariant,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.4,
            ),
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: dc.onSurface,
                  fontSize: 56,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    suffix!,
                    style: const TextStyle(
                      color: dc.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              if (suffixIcon != null) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Icon(suffixIcon, color: dc.primary, size: 20),
                ),
              ],
              if (trailingText != null) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    trailingText!,
                    style: const TextStyle(
                      color: dc.onSurfaceVariant,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ScanMapCard extends StatelessWidget {
  const _ScanMapCard({required this.scanningLabel});

  final String scanningLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 202,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: const LinearGradient(
          colors: [Color(0xFF7A7A7A), Color(0xFF676767)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _TopographyPainter())),
          Positioned(
            left: 24,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: dc.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    scanningLabel,
                    style: const TextStyle(
                      color: dc.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
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

class _TopographyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.08);

    for (var i = 0; i < 14; i++) {
      final path = Path();
      final startY = (size.height / 14) * i;
      path.moveTo(0, startY);
      for (double x = 0; x <= size.width; x += 18) {
        path.lineTo(
          x,
          startY +
              8 *
                  ((i.isEven ? 1 : -1) *
                      (0.5 - ((x / size.width) - 0.5).abs() * 1.4)),
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.activity});

  final _DashboardActivity activity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: dc.onSurface.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: dc.surfaceContainerLow,
              shape: BoxShape.circle,
            ),
            child: Icon(activity.icon, color: dc.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: dc.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${activity.subtitle} - ${activity.timeLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: dc.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(
            Icons.chevron_right_rounded,
            color: dc.outlineVariant,
            size: 24,
          ),
        ],
      ),
    );
  }
}

class _DashboardActivity {
  const _DashboardActivity({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.timeLabel,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String timeLabel;
}


