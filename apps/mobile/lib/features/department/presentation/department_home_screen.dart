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

class DepartmentHomeScreen extends ConsumerStatefulWidget {
  const DepartmentHomeScreen({super.key});

  @override
  ConsumerState<DepartmentHomeScreen> createState() =>
      _DepartmentHomeScreenState();
}

class _DepartmentHomeScreenState extends ConsumerState<DepartmentHomeScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchDepartment();
  }

  Future<void> _fetchDepartment() async {
    try {
      final authService = ref.read(authServiceProvider);
      final dept = await authService.getDepartmentProfile();
      ref.read(sessionControllerProvider.notifier).updateDepartment(dept);
    } catch (_) {}

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final dept = session.department;
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(
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
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.green.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            strings.verified,
            style: TextStyle(
              color: Colors.green.shade800,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          dept.name,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        _DeptDetails(dept: dept, strings: strings),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            leading: const Icon(Icons.assignment),
            title: Text(strings.incidentBoard),
            subtitle: Text(strings.incidentBoardSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const DepartmentReportBoardScreen(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.campaign),
            title: Text(strings.createPost),
            subtitle: Text(strings.createPostSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const DepartmentCreatePostScreen(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.assessment),
            title: Text(strings.damageAssessment),
            subtitle: Text(strings.damageAssessmentSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const DepartmentAssessmentScreen(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.newspaper),
            title: Text(strings.communityFeed),
            subtitle: Text(strings.communityFeedSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CitizenFeedScreen()),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.notifications),
            title: Text(strings.notifications),
            subtitle: Text(strings.notificationsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.forum_outlined),
            title: Text(strings.offlineComms),
            subtitle: Text(
              transport.unreadMeshMessageCount > 0
                  ? strings.unreadMeshMessages(transport.unreadMeshMessageCount)
                  : strings.meshPostsSubtitle,
            ),
            trailing: transport.unreadMeshMessageCount > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.brown.shade600,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${transport.unreadMeshMessageCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OfflineCommsScreen()),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(Icons.cell_tower, color: Colors.cyan.shade700),
            title: Text(strings.meshSar),
            subtitle: Text(strings.meshSarSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const MeshStatusScreen())),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(Icons.map_outlined, color: Colors.green.shade700),
            title: const Text('People & Mesh Map'),
            subtitle: const Text(
              'See live people pins, mesh nodes, and survivor signals.',
            ),
            trailing: const Icon(Icons.chevron_right),
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
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(Icons.explore, color: Colors.orange.shade700),
            title: const Text('Survivor Locator'),
            subtitle: const Text(
              'Track direction and estimated distance to a selected signal.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SurvivorCompassScreen(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(Icons.sos, color: Colors.red.shade700),
            title: Text(strings.emergencySos),
            subtitle: Text(strings.emergencySosSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SosScreen())),
          ),
        ),
      ],
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

