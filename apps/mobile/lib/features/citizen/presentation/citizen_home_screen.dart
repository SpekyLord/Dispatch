// Citizen home — "The Calm Authority" mesh dashboard.
// Pixel-identical to the editorial design mockup: vertical bento stats,
// map preview, tonal activity feed, glassmorphic SOS + bottom nav.

import 'package:dispatch_mobile/core/i18n/app_strings.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:dispatch_mobile/features/citizen/presentation/citizen_feed_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_profile_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_report_detail_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/mesh_people_map_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/sos_screen.dart';
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
    // Auto-start mesh: initialize + begin discovery immediately.
    // If no peers are found the device stays as an origin node.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoStartMesh();
    });
  }

  Future<void> _autoStartMesh() async {
    try {
      final transport = ref.read(meshTransportProvider);
      await transport.initialize();
      if (!transport.isDiscovering) {
        await transport.startDiscovery();
      }
    } catch (_) {
      // Mesh may not be available on this platform — continue silently.
    }
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
          onRefresh: () async {
            _fetchReports();
            await _autoStartMesh();
          },
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              24,
              MediaQuery.of(context).padding.top + 16,
              24,
              180,
            ),
            children: [
              // ── Top App Bar ─────────────────────────────────────────
              const _DashboardAppBar(),
              const SizedBox(height: 20),

              // ── Status Banner ───────────────────────────────────────
              _StatusBanner(
                isOffline: transport.isMeshOnlyState,
                isDiscovering: transport.isDiscovering,
              ),
              const SizedBox(height: 24),

              // ── Bento Stats (vertical stack) ────────────────────────
              _BentoCard(
                label: 'TOTAL ACTIVE NODES',
                value: '${transport.peerCount}',
                badge: transport.connectedRelayPeerCount > 0
                    ? '+${transport.connectedRelayPeerCount}'
                    : null,
              ),
              const SizedBox(height: 16),
              _BentoCard(
                label: 'RECENT DISPATCHES',
                value: '${_reports.length}',
                trailingIcon: Icons.emergency_share,
                trailingIconColor: dc.error,
              ),
              const SizedBox(height: 16),
              _BentoCard(
                label: 'NETWORK RANGE',
                value: transport.estimatedReach > 1000
                    ? (transport.estimatedReach / 1000).toStringAsFixed(1)
                    : '${transport.estimatedReach}',
                unit: transport.estimatedReach > 1000 ? 'km' : 'm',
              ),
              const SizedBox(height: 24),

              // ── Map Preview ─────────────────────────────────────────
              _MapPreview(
                isDiscovering: transport.isDiscovering,
                estimatedReach: transport.estimatedReach,
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
                onViewLog: () => _onItemTapped(2),
              ),
            ],
          ),
        ),

        // ── Floating SOS Button ───────────────────────────────────
        Positioned(
          bottom: 96,
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
// Top App Bar — signal icon + title + sync button
// ═══════════════════════════════════════════════════════════════════════════

class _DashboardAppBar extends StatelessWidget {
  const _DashboardAppBar();

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
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {}, // sync handled by pull-to-refresh
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.sync,
                size: 24,
                color: isDark
                    ? dc.darkInk.withValues(alpha: 0.6)
                    : dc.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Status Banner — connectivity state with pulse halo
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
    final bg = isDark ? dc.darkSurfaceContainer : dc.primaryContainer;
    final textColor = isDark ? dc.darkInk : dc.onPrimaryContainer;

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
          SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _PulseHalo(color: isDark ? dc.darkPrimaryAccent : dc.primary),
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
// Bento Card — tall stat card, vertical stack layout
// p-8 (32px), rounded-[2rem] (32px), min-h 180px, text-5xl number
// ═══════════════════════════════════════════════════════════════════════════

class _BentoCard extends StatelessWidget {
  const _BentoCard({
    required this.label,
    required this.value,
    this.badge,
    this.unit,
    this.trailingIcon,
    this.trailingIconColor,
  });

  final String label;
  final String value;
  final String? badge;
  final String? unit;
  final IconData? trailingIcon;
  final Color? trailingIconColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? dc.darkSurface : dc.surfaceContainerLow;
    final textColor = isDark ? dc.darkInk : dc.onSurface;
    final labelColor = isDark ? dc.darkMutedInk : dc.onSurfaceVariant;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 180),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.5,
              color: labelColor,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2,
                  color: textColor,
                  height: 1.0,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
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
                const SizedBox(width: 8),
                Text(
                  unit!,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: labelColor,
                  ),
                ),
              ],
              if (trailingIcon != null) ...[
                const SizedBox(width: 8),
                Icon(
                  trailingIcon,
                  size: 24,
                  color: trailingIconColor ?? dc.error,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Map Preview — topographic-style container with scanning indicator
// rounded-[2.5rem] (40px), aspect-[16/9], surface-container-highest bg
// ═══════════════════════════════════════════════════════════════════════════

class _MapPreview extends StatelessWidget {
  const _MapPreview({
    required this.isDiscovering,
    required this.estimatedReach,
  });

  final bool isDiscovering;
  final int estimatedReach;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? dc.darkSurfaceContainerHigh : dc.surfaceContainerHighest;
    final overlayBg = isDark
        ? dc.darkSurface.withValues(alpha: 0.9)
        : dc.surface.withValues(alpha: 0.9);

    return ClipRRect(
      borderRadius: BorderRadius.circular(40),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(color: bg),
          child: Stack(
            children: [
              // Topographic pattern overlay
              CustomPaint(
                size: Size.infinite,
                painter: _TopographicPainter(isDark: isDark),
              ),
              // Gradient fade from bottom
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        (isDark ? dc.darkBackground : dc.background)
                            .withValues(alpha: 0.4),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // Scanning pill indicator
              Positioned(
                bottom: 24,
                left: 24,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: overlayBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ScanDot(
                        color: isDark ? dc.darkPrimaryAccent : dc.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isDiscovering
                            ? 'Scanning ${estimatedReach}m sector...'
                            : 'Mesh active — ${estimatedReach}m range',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark ? dc.darkInk : dc.onSurface,
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
}

/// Subtle topographic contour lines — mimics the editorial map aesthetic.
class _TopographicPainter extends CustomPainter {
  _TopographicPainter({required this.isDark});
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = isDark
          ? dc.darkMutedInk.withValues(alpha: 0.12)
          : dc.outlineVariant.withValues(alpha: 0.25);

    final cx = size.width * 0.55;
    final cy = size.height * 0.45;

    for (var i = 1; i <= 10; i++) {
      final rx = 30.0 + i * 28;
      final ry = 20.0 + i * 18;
      final rect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: rx * 2,
        height: ry * 2,
      );
      canvas.drawOval(rect, paint);
    }

    // Secondary contour cluster
    final cx2 = size.width * 0.2;
    final cy2 = size.height * 0.7;
    for (var i = 1; i <= 5; i++) {
      final rx = 15.0 + i * 20;
      final ry = 12.0 + i * 14;
      final rect = Rect.fromCenter(
        center: Offset(cx2, cy2),
        width: rx * 2,
        height: ry * 2,
      );
      canvas.drawOval(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TopographicPainter old) => isDark != old.isDark;
}

/// Pulsing dot for the scanning indicator.
class _ScanDot extends StatefulWidget {
  const _ScanDot({required this.color});
  final Color color;

  @override
  State<_ScanDot> createState() => _ScanDotState();
}

class _ScanDotState extends State<_ScanDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.5 + _ctrl.value * 0.5),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Recent Activity — alternating tonal backgrounds, no dividers
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

    // Alternating: white / light gray (matches mockup)
    final bg = useAltBackground
        ? (isDark ? dc.darkSurface : dc.surfaceContainerLow)
        : (isDark ? dc.darkSurfaceContainer : dc.surfaceContainerLowest);

    // Icon container uses opposite tone for contrast
    final iconBg = useAltBackground
        ? (isDark ? dc.darkSurfaceContainer : dc.surfaceContainerLowest)
        : (isDark ? dc.darkSurfaceContainerHigh : dc.surfaceContainerLow);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
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
// SOS Button — floating, primary gradient, ambient shadow
// Fixed bottom-24 (96px), max-w-xs (320px), rounded-[1.5rem] (24px)
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
              padding: const EdgeInsets.symmetric(vertical: 20),
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
