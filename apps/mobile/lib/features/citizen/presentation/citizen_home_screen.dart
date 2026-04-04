// Citizen home — editorial mesh dashboard with bento stats, activity feed,
// and glassmorphic SOS button. Follows "The Calm Authority" design system.

import 'package:dispatch_mobile/core/i18n/app_strings.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:dispatch_mobile/features/citizen/presentation/citizen_feed_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_profile_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_report_detail_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_report_form_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/mesh_people_map_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/mesh_status_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/offline_comms_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/sos_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/survivor_compass_screen.dart';
import 'package:dispatch_mobile/features/shared/presentation/notifications_screen.dart';
import 'package:dispatch_mobile/features/shared/presentation/widgets/bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CitizenHomeScreen extends ConsumerStatefulWidget {
  const CitizenHomeScreen({super.key});

  @override
  ConsumerState<CitizenHomeScreen> createState() => _CitizenHomeScreenState();
}

class _CitizenHomeScreenState extends ConsumerState<CitizenHomeScreen> {
  int _selectedIndex = 0;
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  Future<void> _fetchReports() async {
    setState(() => _loading = true);
    try {
      final authService = ref.read(authServiceProvider);
      final reports = await authService.getReports();
      if (mounted) {
        setState(() {
          _reports = reports.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _openReportForm() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CitizenReportFormScreen()),
    );
    if (result == true) {
      _fetchReports();
    }
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildDashboard(context),
      const MeshPeopleMapScreen(
        title: 'Mesh Map',
        subtitle: 'Nodes and signals',
        allowResolveActions: false,
      ),
      const CitizenFeedScreen(),
      const CitizenProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: dc.background,
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: AppBottomNavigationBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
      ),
    );
  }

  Widget _buildDashboard(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final transport = ref.watch(meshTransportProvider);

    return Stack(
      children: [
        RefreshIndicator(
          color: dc.primary,
          onRefresh: _fetchReports,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              24,
              MediaQuery.of(context).padding.top + 16,
              24,
              180, // room for SOS button + bottom nav
            ),
            children: [
              // ── Top App Bar (inline) ────────────────────────────────
              _DashboardAppBar(
                onSync: _fetchReports,
                onNotifications: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Status Banner ───────────────────────────────────────
              _StatusBanner(
                isOffline: transport.isMeshOnlyState,
                isDiscovering: transport.isDiscovering,
              ),
              const SizedBox(height: 24),

              // ── Network Health Bento Grid ───────────────────────────
              _BentoGrid(
                activeNodes: transport.peerCount,
                newNodes: transport.connectedRelayPeerCount,
                recentDispatches: _reports.length,
                networkRange: transport.estimatedReach,
              ),
              const SizedBox(height: 24),

              // ── Quick Actions Row ───────────────────────────────────
              _QuickActions(
                unreadCount: transport.unreadMeshMessageCount,
                onMesh: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MeshStatusScreen(),
                  ),
                ),
                onCompass: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SurvivorCompassScreen(
                      allowResolve: false,
                    ),
                  ),
                ),
                onOfflineComms: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const OfflineCommsScreen(),
                  ),
                ),
                onNewReport: _openReportForm,
              ),
              const SizedBox(height: 32),

              // ── Recent Activity ─────────────────────────────────────
              _RecentActivitySection(
                reports: _reports,
                loading: _loading,
                strings: strings,
                onReportTap: (report) async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CitizenReportDetailScreen(
                        reportId: report['id'] as String,
                      ),
                    ),
                  );
                  _fetchReports();
                },
                onViewLog: () {
                  // Switch to reports tab
                  _onItemTapped(2);
                },
              ),
            ],
          ),
        ),

        // ── Floating SOS Button ─────────────────────────────────────
        Positioned(
          bottom: 100,
          left: 0,
          right: 0,
          child: Center(
            child: _SosButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SosScreen()),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Dashboard App Bar — editorial clean, glassmorphic-style
// ═══════════════════════════════════════════════════════════════════════════

class _DashboardAppBar extends StatelessWidget {
  const _DashboardAppBar({
    required this.onSync,
    required this.onNotifications,
  });

  final VoidCallback onSync;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Icon(
          Icons.signal_cellular_alt,
          color: isDark ? dc.darkPrimaryAccent : dc.primary,
          size: 24,
        ),
        const SizedBox(width: 12),
        Text(
          'Mesh Network',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: isDark ? dc.darkInk : dc.onSurface,
          ),
        ),
        const Spacer(),
        _GlassIconButton(
          icon: Icons.notifications_outlined,
          onPressed: onNotifications,
        ),
        const SizedBox(width: 8),
        _GlassIconButton(
          icon: Icons.sync,
          onPressed: onSync,
        ),
      ],
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark
                ? dc.darkSurfaceContainer.withValues(alpha: 0.6)
                : dc.surfaceContainerHigh.withValues(alpha: 0.6),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isDark
                ? dc.darkInk.withValues(alpha: 0.6)
                : dc.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Status Banner — mesh connectivity status with pulse halo
// ═══════════════════════════════════════════════════════════════════════════

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.isOffline,
    required this.isDiscovering,
  });

  final bool isOffline;
  final bool isDiscovering;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? dc.darkSurfaceContainer
        : dc.primaryContainer;
    final textColor = isDark
        ? dc.darkInk
        : dc.onPrimaryContainer;

    final String title;
    final String subtitle;
    final IconData icon;

    if (isOffline) {
      title = 'Network Offline';
      subtitle = 'Mesh Communication Only';
      icon = Icons.cloud_off;
    } else if (isDiscovering) {
      title = 'Discovering Peers';
      subtitle = 'Scanning for nearby nodes...';
      icon = Icons.radar;
    } else {
      title = 'Network Active';
      subtitle = 'Connected to mesh network';
      icon = Icons.cloud_done_outlined;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          // Pulsing halo icon
          SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isOffline || isDiscovering)
                  _PulseHalo(
                    color: isDark ? dc.darkPrimaryAccent : dc.primary,
                  ),
                Icon(icon, color: isDark ? dc.darkPrimaryAccent : dc.primary),
              ],
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
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: textColor.withValues(alpha: 0.7),
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

class _PulseHalo extends StatefulWidget {
  const _PulseHalo({required this.color});
  final Color color;

  @override
  State<_PulseHalo> createState() => _PulseHaloState();
}

class _PulseHaloState extends State<_PulseHalo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.value;
        final scale = 0.95 + (value < 0.5 ? value : 1 - value) * 0.2;
        final opacity = 0.5 - (value < 0.5 ? value : 1 - value) * 0.6;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: opacity.clamp(0.0, 1.0)),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Bento Grid — 3-column network health stats
// ═══════════════════════════════════════════════════════════════════════════

class _BentoGrid extends StatelessWidget {
  const _BentoGrid({
    required this.activeNodes,
    required this.newNodes,
    required this.recentDispatches,
    required this.networkRange,
  });

  final int activeNodes;
  final int newNodes;
  final int recentDispatches;
  final int networkRange;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 12.0;
        final cardWidth = (constraints.maxWidth - spacing * 2) / 3;

        return Row(
          children: [
            _BentoCard(
              width: cardWidth,
              label: 'ACTIVE NODES',
              value: '$activeNodes',
              badge: newNodes > 0 ? '+$newNodes' : null,
            ),
            SizedBox(width: spacing),
            _BentoCard(
              width: cardWidth,
              label: 'DISPATCHES',
              value: '$recentDispatches',
              icon: Icons.emergency_share,
              iconColor: dc.error,
            ),
            SizedBox(width: spacing),
            _BentoCard(
              width: cardWidth,
              label: 'REACH',
              value: networkRange > 1000
                  ? (networkRange / 1000).toStringAsFixed(1)
                  : '$networkRange',
              unit: networkRange > 1000 ? 'km' : 'm',
            ),
          ],
        );
      },
    );
  }
}

class _BentoCard extends StatelessWidget {
  const _BentoCard({
    required this.width,
    required this.label,
    required this.value,
    this.badge,
    this.unit,
    this.icon,
    this.iconColor,
  });

  final double width;
  final String label;
  final String value;
  final String? badge;
  final String? unit;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? dc.darkSurface : dc.surfaceContainerLow;
    final textColor = isDark ? dc.darkInk : dc.onSurface;
    final labelColor = isDark ? dc.darkMutedInk : dc.onSurfaceVariant;

    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: labelColor,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -2,
                      color: textColor,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Text(
                  badge!,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? dc.darkPrimaryAccent : dc.primary,
                  ),
                ),
              ],
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit!,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: labelColor,
                  ),
                ),
              ],
              if (icon != null) ...[
                const SizedBox(width: 6),
                Icon(icon, size: 20, color: iconColor ?? dc.error),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Quick Actions — compact horizontal action chips
// ═══════════════════════════════════════════════════════════════════════════

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.unreadCount,
    required this.onMesh,
    required this.onCompass,
    required this.onOfflineComms,
    required this.onNewReport,
  });

  final int unreadCount;
  final VoidCallback onMesh;
  final VoidCallback onCompass;
  final VoidCallback onOfflineComms;
  final VoidCallback onNewReport;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _QuickChip(
            icon: Icons.cell_tower,
            label: 'Mesh Status',
            onTap: onMesh,
          ),
          const SizedBox(width: 10),
          _QuickChip(
            icon: Icons.explore_outlined,
            label: 'Locator',
            onTap: onCompass,
          ),
          const SizedBox(width: 10),
          _QuickChip(
            icon: Icons.forum_outlined,
            label: 'Comms',
            badge: unreadCount > 0 ? '$unreadCount' : null,
            onTap: onOfflineComms,
          ),
          const SizedBox(width: 10),
          _QuickChip(
            icon: Icons.add,
            label: 'New Report',
            isPrimary: true,
            onTap: onNewReport,
          ),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
    this.isPrimary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = isPrimary
        ? (isDark ? dc.darkPrimaryAccent.withValues(alpha: 0.15) : dc.primaryContainer)
        : (isDark ? dc.darkSurfaceContainer : dc.surfaceContainerLow);
    final fg = isPrimary
        ? (isDark ? dc.darkPrimaryAccent : dc.primary)
        : (isDark ? dc.darkInk : dc.onSurface);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? dc.darkPrimaryAccent : dc.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? dc.darkBackground : dc.onPrimary,
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
// Recent Activity — alternating tonal cards, no dividers
// ═══════════════════════════════════════════════════════════════════════════

class _RecentActivitySection extends StatelessWidget {
  const _RecentActivitySection({
    required this.reports,
    required this.loading,
    required this.strings,
    required this.onReportTap,
    required this.onViewLog,
  });

  final List<Map<String, dynamic>> reports;
  final bool loading;
  final AppStrings strings;
  final void Function(Map<String, dynamic>) onReportTap;
  final VoidCallback onViewLog;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Activity',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: isDark ? dc.darkInk : dc.onSurface,
              ),
            ),
            GestureDetector(
              onTap: onViewLog,
              child: Text(
                'View Log',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? dc.darkPrimaryAccent : dc.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: dc.primary),
            ),
          )
        else if (reports.isEmpty)
          _EmptyActivity()
        else
          ...reports.take(5).toList().asMap().entries.map((entry) {
            final index = entry.key;
            final report = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ActivityItem(
                report: report,
                strings: strings,
                useAltBackground: index.isOdd,
                onTap: () => onReportTap(report),
              ),
            );
          }),
      ],
    );
  }
}

class _ActivityItem extends StatelessWidget {
  const _ActivityItem({
    required this.report,
    required this.strings,
    required this.useAltBackground,
    required this.onTap,
  });

  final Map<String, dynamic> report;
  final AppStrings strings;
  final bool useAltBackground;
  final VoidCallback onTap;

  IconData _categoryIcon(String category) {
    return switch (category) {
      'fire' => Icons.local_fire_department,
      'flood' => Icons.water_drop,
      'medical' => Icons.medical_services,
      'road_accident' => Icons.car_crash,
      'earthquake' => Icons.vibration,
      _ => Icons.description_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = report['status'] as String? ?? 'pending';
    final categoryKey = report['category'] as String? ?? '';
    final description = report['description'] as String? ?? 'Report';

    final bg = useAltBackground
        ? (isDark ? dc.darkSurface : dc.surfaceContainerLow)
        : (isDark ? dc.darkSurfaceContainer : dc.surfaceContainerLowest);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDark
                      ? dc.darkSurfaceContainerHigh
                      : dc.surfaceContainerLow,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _categoryIcon(categoryKey),
                  size: 18,
                  color: isDark ? dc.darkMutedInk : dc.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? dc.darkInk : dc.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${strings.statusLabel(status)} • ${_formatTimeAgo(report['created_at'] as String?)}',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: isDark ? dc.darkMutedInk : dc.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: isDark
                    ? dc.darkMutedInk.withValues(alpha: 0.5)
                    : dc.outlineVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimeAgo(String? raw) {
    final parsed = DateTime.tryParse(raw ?? '');
    if (parsed == null) return '';
    final diff = DateTime.now().difference(parsed.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final local = parsed.toLocal();
    return '${_monthLabel(local.month)} ${local.day}';
  }

  String _monthLabel(int month) {
    const labels = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return labels[month - 1];
  }
}

class _EmptyActivity extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? dc.darkSurface : dc.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 32,
            color: isDark ? dc.darkMutedInk : dc.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No activity yet',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? dc.darkInk : dc.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your reports and mesh events will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: isDark ? dc.darkMutedInk : dc.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SOS Button — fixed floating, xl radius, ambient shadow
// ═══════════════════════════════════════════════════════════════════════════

class _SosButton extends StatelessWidget {
  const _SosButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [dc.primary, dc.primaryDim],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: dc.onSurface.withValues(alpha: 0.06),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: dc.primary.withValues(alpha: 0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sos, color: dc.onPrimary, size: 22),
                  SizedBox(width: 12),
                  Text(
                    'SEND SOS',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: dc.onPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
