import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:dispatch_mobile/features/citizen/presentation/citizen_feed_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/mesh_status_screen.dart';
import 'package:dispatch_mobile/features/municipality/presentation/municipality_analytics_screen.dart';
import 'package:dispatch_mobile/features/municipality/presentation/municipality_assessments_screen.dart';
import 'package:dispatch_mobile/features/municipality/presentation/municipality_departments_screen.dart';
import 'package:dispatch_mobile/features/municipality/presentation/municipality_escalated_reports_screen.dart';
import 'package:dispatch_mobile/features/municipality/presentation/municipality_mesh_map_screen.dart';
import 'package:dispatch_mobile/features/municipality/presentation/municipality_verification_screen.dart';
import 'package:dispatch_mobile/features/shared/presentation/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MunicipalityHomeScreen extends ConsumerStatefulWidget {
  const MunicipalityHomeScreen({super.key});

  @override
  ConsumerState<MunicipalityHomeScreen> createState() =>
      _MunicipalityHomeScreenState();
}

class _MunicipalityHomeScreenState
    extends ConsumerState<MunicipalityHomeScreen> {
  bool _loading = true;
  int _pendingDepartments = 0;
  int _totalDepartments = 0;
  int _unattendedReports = 0;
  int _last7Days = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final auth = ref.read(authServiceProvider);
      final pending = await auth.getMunicipalityPendingDepartments();
      final departments = await auth.getMunicipalityDepartments();
      final analytics = await auth.getMunicipalityAnalytics();
      if (!mounted) return;
      setState(() {
        _pendingDepartments = pending.length;
        _totalDepartments = departments.length;
        _unattendedReports = analytics['unattended_reports'] as int? ?? 0;
        _last7Days = analytics['last_7_days'] as int? ?? 0;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _open(Widget screen) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => screen)).then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Municipality Command'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.sync),
            tooltip: 'Refresh dashboard',
          ),
          IconButton(
            onPressed: () => _open(const NotificationsScreen()),
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Notifications',
          ),
          TextButton(
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    ...dc.heroGradient,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
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
                      'Municipality mobile dashboard',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Oversight on the move.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Review department approvals, escalations, assessments, mesh activity, and public alerts from the same mobile command surface.',
                    style: TextStyle(color: dc.chipFill, height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.05,
              children: [
                _MetricCard(
                  icon: Icons.pending_actions,
                  label: 'Pending verification',
                  value: _loading ? '...' : '$_pendingDepartments',
                  tone: dc.statusPending,
                  onTap: () => _open(const MunicipalityVerificationScreen()),
                ),
                _MetricCard(
                  icon: Icons.domain,
                  label: 'Departments',
                  value: _loading ? '...' : '$_totalDepartments',
                  tone: dc.coolAccent,
                  onTap: () => _open(const MunicipalityDepartmentsScreen()),
                ),
                _MetricCard(
                  icon: Icons.crisis_alert,
                  label: 'Unattended reports',
                  value: _loading ? '...' : '$_unattendedReports',
                  tone: dc.warmSeed,
                  onTap: () =>
                      _open(const MunicipalityEscalatedReportsScreen()),
                ),
                _MetricCard(
                  icon: Icons.analytics,
                  label: 'Reports in 7 days',
                  value: _loading ? '...' : '$_last7Days',
                  tone: dc.statusResolved,
                  onTap: () => _open(const MunicipalityAnalyticsScreen()),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Operations',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.fact_check_outlined,
              title: 'Verification queue',
              subtitle: 'Approve or reject pending department registrations.',
              onTap: () => _open(const MunicipalityVerificationScreen()),
            ),
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.groups_2_outlined,
              title: 'Departments list',
              subtitle: 'Review every department and its verification state.',
              onTap: () => _open(const MunicipalityDepartmentsScreen()),
            ),
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.summarize_outlined,
              title: 'Escalated reports',
              subtitle: 'Surface unattended incidents that need intervention.',
              onTap: () => _open(const MunicipalityEscalatedReportsScreen()),
            ),
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.assessment_outlined,
              title: 'Assessments',
              subtitle: 'Review field damage assessments across departments.',
              onTap: () => _open(const MunicipalityAssessmentsScreen()),
            ),
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.query_stats_outlined,
              title: 'Analytics',
              subtitle:
                  'Track totals, category mix, response timing, and activity.',
              onTap: () => _open(const MunicipalityAnalyticsScreen()),
            ),
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.hub_outlined,
              title: 'Mesh & SAR map',
              subtitle:
                  'Inspect topology nodes, survivor signals, and last-seen pins.',
              onTap: () => _open(const MunicipalityMeshMapScreen()),
            ),
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.cell_tower,
              title: 'Mesh status',
              subtitle: 'Open the shared mesh dashboard and relay controls.',
              onTap: () => _open(const MeshStatusScreen()),
            ),
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.newspaper_outlined,
              title: 'News feed',
              subtitle: 'Browse official posts from verified departments.',
              onTap: () => _open(const CitizenFeedScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: tone),
              ),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: dc.chipFill,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: dc.warmSeed),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
