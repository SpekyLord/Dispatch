// Citizen home - report list with pull-to-refresh, FAB for new report.

import 'package:dispatch_mobile/core/i18n/app_strings.dart';
import 'package:dispatch_mobile/core/i18n/locale_action_button.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dispatch_mobile/features/shared/presentation/widgets/bottom_nav_bar.dart';


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

  String _titleForIndex(int index, AppStrings strings) {
    return switch (index) {
      0 => strings.myReports,
      1 => strings.feed,
      2 => strings.profile,
      _ => strings.myReports,
    };
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);

    final pages = [
      _buildHomePage(context),
      const CitizenFeedScreen(),
      const CitizenProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: dc.warmBackground,
      appBar: AppBar(
        backgroundColor: dc.warmBackground,
        surfaceTintColor: Colors.transparent,
        title: Text(_titleForIndex(_selectedIndex, strings)),
        actions: [
          const LocaleActionButton(),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: strings.notifications,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: strings.signOut,
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              backgroundColor: dc.warmSeed,
              foregroundColor: Colors.white,
              onPressed: _openReportForm,
              icon: const Icon(Icons.add),
              label: Text(strings.newReport),
            )
          : null,
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: AppBottomNavigationBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
      ),
    );
  }

  Widget _buildHomePage(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final transport = ref.watch(meshTransportProvider);

    return RefreshIndicator(
      color: dc.warmSeed,
      onRefresh: _fetchReports,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          _CitizenHero(
            reportCount: _reports.length,
            queueCount: transport.queueSize,
            reachCount: transport.estimatedReach,
          ),
          const SizedBox(height: 18),
          _QuickActionRow(
            unreadCount: transport.unreadMeshMessageCount,
            onFeed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CitizenFeedScreen()),
            ),
            onMesh: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MeshStatusScreen()),
            ),
            onMap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const MeshPeopleMapScreen(
                  title: 'People & Mesh Map',
                  subtitle:
                      'Citizen visibility into people pins and survivor signals',
                  allowResolveActions: false,
                ),
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
              MaterialPageRoute(builder: (_) => const OfflineCommsScreen()),
            ),
            onSos: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SosScreen()),
            ),
          ),
          const SizedBox(height: 18),
          _SectionHeader(
            eyebrow: 'Citizen dashboard',
            title: 'Recent reports',
            body: _reports.isEmpty
                ? 'Your incident reports will appear here with the same status-chip rhythm used across the web dashboard.'
                : '${_reports.length} report${_reports.length == 1 ? '' : 's'} currently tracked from this account.',
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_reports.isEmpty)
            _EmptyReportsPanel(onCreateReport: _openReportForm)
          else
            ..._reports.map(
              (report) => _ReportCard(
                report: report,
                strings: strings,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CitizenReportDetailScreen(
                        reportId: report['id'] as String,
                      ),
                    ),
                  );
                  _fetchReports();
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _CitizenHero extends StatelessWidget {
  const _CitizenHero({
    required this.reportCount,
    required this.queueCount,
    required this.reachCount,
  });

  final int reportCount;
  final int queueCount;
  final int reachCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: dc.heroGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Citizen Command View',
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
            'Track reports, open the people map, and keep mesh updates close even when the network drops.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'The mobile dashboard now mirrors the web rhythm more closely: a warm command header, quick actions up front, and report cards with clear status chips underneath.',
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
              _HeroPill(label: 'Reports', value: '$reportCount'),
              _HeroPill(label: 'Queued mesh', value: '$queueCount'),
              _HeroPill(label: 'Reach', value: '~$reachCount'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 116),
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
              color: Colors.white.withValues(alpha: 0.74),
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
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionRow extends StatelessWidget {
  const _QuickActionRow({
    required this.unreadCount,
    required this.onFeed,
    required this.onMesh,
    required this.onMap,
    required this.onCompass,
    required this.onOfflineComms,
    required this.onSos,
  });

  final int unreadCount;
  final VoidCallback onFeed;
  final VoidCallback onMesh;
  final VoidCallback onMap;
  final VoidCallback onCompass;
  final VoidCallback onOfflineComms;
  final VoidCallback onSos;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.88,
      children: [
        _ActionCard(
          icon: Icons.cell_tower,
          accent: dc.coolAccent,
          title: 'Mesh status',
          body: 'Review discovery, reach, and relay health.',
          onTap: onMesh,
        ),
        _ActionCard(
          icon: Icons.map_outlined,
          accent: dc.statusResolved,
          title: 'People map',
          body: 'See nearby people pins, survivor signals, and mesh nodes.',
          onTap: onMap,
        ),
        _ActionCard(
          icon: Icons.explore_outlined,
          accent: dc.statusPending,
          title: 'Survivor locator',
          body: 'Open compass guidance with direction and estimated meters.',
          onTap: onCompass,
        ),
        _ActionCard(
          icon: Icons.forum_outlined,
          accent: dc.warmSeed,
          title: 'Offline comms',
          body: 'Keep mesh messages and queued updates in one inbox.',
          badgeLabel: unreadCount > 0 ? '$unreadCount' : null,
          tooltip: 'Offline Comms',
          onTap: onOfflineComms,
        ),
        _ActionCard(
          icon: Icons.newspaper_outlined,
          accent: dc.statusResponding,
          title: 'Community feed',
          body: 'Browse public response updates and advisories.',
          onTap: onFeed,
        ),
        _ActionCard(
          icon: Icons.sos,
          accent: dc.statusError,
          title: 'Emergency SOS',
          body: 'Broadcast a distress packet with rapid beacon support.',
          onTap: onSos,
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.body,
    required this.onTap,
    this.badgeLabel,
    this.tooltip,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String body;
  final String? badgeLabel;
  final String? tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final card = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: dc.warmSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: dc.warmBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14131110),
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: accent),
                ),
                const Spacer(),
                if (badgeLabel != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: dc.warmSeed,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badgeLabel!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: dc.ink,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Flexible(
              child: Text(
                body,
                style: const TextStyle(color: dc.mutedInk, fontSize: 13, height: 1.4),
                overflow: TextOverflow.ellipsis,
                maxLines: 3,
              ),
            ),
          ],
        ),
      ),
    );
    if ((tooltip ?? '').isEmpty) {
      return card;
    }
    return Tooltip(message: tooltip!, child: card);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    required this.body,
  });

  final String eyebrow;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: const TextStyle(
            color: dc.warmSeed,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: const TextStyle(
            color: dc.ink,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(body, style: const TextStyle(color: dc.mutedInk, height: 1.45)),
      ],
    );
  }
}

class _EmptyReportsPanel extends StatelessWidget {
  const _EmptyReportsPanel({required this.onCreateReport});

  final VoidCallback onCreateReport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: dc.warmSurface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: dc.warmBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: dc.chipFill,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.description_outlined, color: dc.warmSeed),
          ),
          const SizedBox(height: 16),
          const Text(
            'No reports yet',
            style: TextStyle(
              color: dc.ink,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create your first report to start tracking status, response routing, and nearby mesh visibility from the same dashboard.',
            style: TextStyle(color: dc.mutedInk, height: 1.45),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onCreateReport,
            style: FilledButton.styleFrom(
              backgroundColor: dc.warmSeed,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.add),
            label: const Text('Create report'),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.strings,
    required this.onTap,
  });

  final Map<String, dynamic> report;
  final AppStrings strings;
  final VoidCallback onTap;

  Color _statusColor(String status) => dc.statusColor(status);

  IconData _categoryIcon(String category) {
    return switch (category) {
      'fire' => Icons.local_fire_department,
      'flood' => Icons.water_drop,
      'medical' => Icons.medical_services,
      'road_accident' => Icons.car_crash,
      'earthquake' => Icons.vibration,
      _ => Icons.crisis_alert,
    };
  }

  @override
  Widget build(BuildContext context) {
    final status = report['status'] as String? ?? 'pending';
    final categoryKey = report['category'] as String? ?? '';
    final accent = _statusColor(status);
    final category = strings.categoryLabel(categoryKey);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: dc.warmSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: dc.warmBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14131110),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(_categoryIcon(categoryKey), color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              report['description'] as String? ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: dc.ink,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              strings.statusLabel(status),
                              style: TextStyle(
                                color: accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _MetaChip(label: category),
                          _MetaChip(
                            label: strings.severityLabel(
                              report['severity'] as String? ?? 'medium',
                            ),
                          ),
                          if ((report['address'] as String?)?.isNotEmpty == true)
                            _MetaChip(label: report['address'] as String),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _formatTimestamp(report['created_at'] as String?),
                        style: const TextStyle(
                          color: dc.mutedInk,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: dc.mutedInk),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(String? raw) {
    final parsed = DateTime.tryParse(raw ?? '');
    if (parsed == null) {
      return 'Time unavailable';
    }
    final local = parsed.toLocal();
    final month = _monthLabel(local.month);
    final minutes = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    final hour = local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
    return '$month ${local.day} | $hour:$minutes $period';
  }

  String _monthLabel(int month) {
    const labels = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return labels[month - 1];
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: dc.chipFill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: dc.mutedInk,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

