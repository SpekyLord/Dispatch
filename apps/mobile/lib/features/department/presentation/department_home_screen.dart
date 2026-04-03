import 'package:dispatch_mobile/core/i18n/app_strings.dart';
import 'package:dispatch_mobile/core/i18n/locale_action_button.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_feed_screen.dart';
import 'package:dispatch_mobile/features/department/presentation/department_assessment_screen.dart';
import 'package:dispatch_mobile/features/department/presentation/department_create_post_screen.dart';
import 'package:dispatch_mobile/features/department/presentation/department_report_board_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/mesh_people_map_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/mesh_status_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/survivor_compass_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/offline_comms_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/sos_screen.dart';
import 'package:dispatch_mobile/features/shared/presentation/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dispatch/apps/mobile/lib/features/shared/presentation/widgets/bottom_nav_bar.dart';
import 'package:dispatch/apps/mobile/lib/features/shared/presentation/widgets/card.dart';

const _warmBackground = Color(0xFFFDF7F2);
const _warmPanel = Color(0xFFFFF8F3);
const _warmBorder = Color(0xFFE7D1C6);
const _warmAccent = Color(0xFFA14B2F);
const _coolAccent = Color(0xFF1695D3);
const _deepText = Color(0xFF4E433D);
const _mutedText = Color(0xFF7A6B63);

class DepartmentHomeScreen extends StatefulWidget {
  const DepartmentHomeScreen({super.key});

  @override
  _DepartmentHomeScreenState createState() => _DepartmentHomeScreenState();
}

class _DepartmentHomeScreenState extends State<DepartmentHomeScreen> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    // Handle navigation
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final dept = session.department;
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      backgroundColor: _warmBackground,
      appBar: AppBar(
        backgroundColor: _warmBackground,
        surfaceTintColor: Colors.transparent,
        title: Text(strings.departmentTitle),
        actions: [
          const LocaleActionButton(),
          TextButton(
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).signOut(),
            child: Text(strings.signOut),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : dept == null
              ? Center(child: Text(strings.noDepartmentProfileFound))
              : _buildBody(context, dept, strings),
      bottomNavigationBar: AppBottomNavigationBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    DepartmentInfo dept,
    AppStrings strings,
  ) {
    if (dept.verificationStatus == 'pending') {
      return _PendingView(dept: dept, strings: strings);
    }
    if (dept.verificationStatus == 'rejected') {
      return _RejectedView(dept: dept, strings: strings);
    }
    return _ApprovedView(dept: dept, strings: strings);
  }
}

class _PendingView extends StatelessWidget {
  const _PendingView({required this.dept, required this.strings});

  final DepartmentInfo dept;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.hourglass_empty,
                size: 32,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              strings.awaitingVerification,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              strings.pendingDepartmentMessage(dept.name),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            _DeptDetails(dept: dept, strings: strings),
          ],
        ),
      ),
    );
  }
}

class _RejectedView extends ConsumerStatefulWidget {
  const _RejectedView({required this.dept, required this.strings});

  final DepartmentInfo dept;
  final AppStrings strings;

  @override
  ConsumerState<_RejectedView> createState() => _RejectedViewState();
}

class _RejectedViewState extends ConsumerState<_RejectedView> {
  bool _editing = false;
  bool _loading = false;
  String? _error;
  late TextEditingController _nameCtrl;
  late TextEditingController _contactCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _areaCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.dept.name);
    _contactCtrl = TextEditingController(text: widget.dept.contactNumber ?? '');
    _addressCtrl = TextEditingController(text: widget.dept.address ?? '');
    _areaCtrl = TextEditingController(
      text: widget.dept.areaOfResponsibility ?? '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _addressCtrl.dispose();
    _areaCtrl.dispose();
    super.dispose();
  }

  Future<void> _resubmit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final authService = ref.read(authServiceProvider);
      final updated = await authService.updateDepartmentProfile({
        'name': _nameCtrl.text.trim(),
        'contact_number': _contactCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'area_of_responsibility': _areaCtrl.text.trim(),
      });
      ref.read(sessionControllerProvider.notifier).updateDepartment(updated);
      if (mounted) {
        setState(() {
          _editing = false;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.red.shade100,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close, size: 32, color: Colors.red),
        ),
        const SizedBox(height: 16),
        Text(
          strings.registrationRejected,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (widget.dept.rejectionReason != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(
              strings.rejectionReason(widget.dept.rejectionReason!),
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (!_editing) ...[
          Text(
            strings.resubmitPrompt,
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => setState(() => _editing = true),
            child: Text(strings.editAndResubmit),
          ),
        ] else ...[
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: strings.organizationName,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contactCtrl,
            decoration: InputDecoration(
              labelText: strings.contactNumber,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressCtrl,
            decoration: InputDecoration(
              labelText: strings.address,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _areaCtrl,
            decoration: InputDecoration(
              labelText: strings.areaOfResponsibility,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _loading ? null : _resubmit,
                  child: Text(
                    _loading ? strings.submitting : strings.resubmit,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => setState(() => _editing = false),
                child: Text(strings.cancel),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ApprovedView extends ConsumerWidget {
  const _ApprovedView({required this.dept, required this.strings});

  final DepartmentInfo dept;
  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transport = ref.watch(meshTransportProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFA14B2F), Color(0xFF7B3A25), Color(0xFF425E72)],
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
                child: Text(
                  strings.verified,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                dept.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Run incident intake, publish advisories, track mesh movement, and jump into survivor guidance from the same mobile command surface.',
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
                  _HeroChip(label: 'Mesh role', value: transport.role.name.toUpperCase()),
                  _HeroChip(label: 'Relay peers', value: '${transport.connectedRelayPeerCount}'),
                  _HeroChip(label: 'Queued sync', value: '${transport.queueSize}'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _warmPanel,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _warmBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Department profile',
                style: TextStyle(
                  color: _deepText,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              _DeptDetails(dept: dept, strings: strings),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Quick actions',
          style: TextStyle(
            color: _deepText,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'These cards follow the same quick-action rhythm as the web dashboard, but stay tuned for thumb-first mobile use.',
          style: TextStyle(color: _mutedText, height: 1.45),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.05,
          children: [
            _DepartmentActionCard(
              icon: Icons.assignment,
              accent: _coolAccent,
              title: strings.incidentBoard,
              body: strings.incidentBoardSubtitle,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DepartmentReportBoardScreen(),
                ),
              ),
            ),
            _DepartmentActionCard(
              icon: Icons.campaign,
              accent: _warmAccent,
              title: strings.createPost,
              body: strings.createPostSubtitle,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DepartmentCreatePostScreen(),
                ),
              ),
            ),
            _DepartmentActionCard(
              icon: Icons.assessment,
              accent: const Color(0xFF397154),
              title: strings.damageAssessment,
              body: strings.damageAssessmentSubtitle,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DepartmentAssessmentScreen(),
                ),
              ),
            ),
            _DepartmentActionCard(
              icon: Icons.newspaper_outlined,
              accent: const Color(0xFF7B5E57),
              title: strings.communityFeed,
              body: strings.communityFeedSubtitle,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CitizenFeedScreen()),
              ),
            ),
            _DepartmentActionCard(
              icon: Icons.forum_outlined,
              accent: _warmAccent,
              title: strings.offlineComms,
              body: transport.unreadMeshMessageCount > 0
                  ? strings.unreadMeshMessages(transport.unreadMeshMessageCount)
                  : strings.meshPostsSubtitle,
              badgeLabel: transport.unreadMeshMessageCount > 0
                  ? '${transport.unreadMeshMessageCount}'
                  : null,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OfflineCommsScreen()),
              ),
            ),
            _DepartmentActionCard(
              icon: Icons.cell_tower,
              accent: _coolAccent,
              title: strings.meshSar,
              body: transport.transportStatusNote ?? strings.meshSarSubtitle,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MeshStatusScreen()),
              ),
            ),
            _DepartmentActionCard(
              icon: Icons.map_outlined,
              accent: const Color(0xFF397154),
              title: 'People & Mesh Map',
              body: 'See live people pins, mesh nodes, and survivor signals.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MeshPeopleMapScreen(
                    title: 'People & Mesh Map',
                    subtitle:
                        'Department visibility into people pins and survivor signals',
                    allowResolveActions: true,
                  ),
                ),
              ),
            ),
            _DepartmentActionCard(
              icon: Icons.explore,
              accent: const Color(0xFFD97757),
              title: 'Survivor Locator',
              body: 'Track direction and estimated distance to a selected signal.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SurvivorCompassScreen(),
                ),
              ),
            ),
            _DepartmentActionCard(
              icon: Icons.notifications_outlined,
              accent: const Color(0xFF7B5E57),
              title: strings.notifications,
              body: strings.notificationsSubtitle,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              ),
            ),
            _DepartmentActionCard(
              icon: Icons.sos,
              accent: const Color(0xFFB3261E),
              title: strings.emergencySos,
              body: strings.emergencySosSubtitle,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SosScreen()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label, required this.value});

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

class _DepartmentActionCard extends StatelessWidget {
  const _DepartmentActionCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.body,
    required this.onTap,
    this.badgeLabel,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String body;
  final String? badgeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _warmPanel,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _warmBorder),
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
                      color: _warmAccent,
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
                color: _deepText,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                body,
                style: const TextStyle(color: _mutedText, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeptDetails extends StatelessWidget {
  const _DeptDetails({required this.dept, required this.strings});

  final DepartmentInfo dept;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailRow(strings.type, dept.type),
          if (dept.contactNumber != null)
            _DetailRow(strings.contact, dept.contactNumber!),
          if (dept.address != null) _DetailRow(strings.address, dept.address!),
          if (dept.areaOfResponsibility != null)
            _DetailRow(strings.area, dept.areaOfResponsibility!),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

