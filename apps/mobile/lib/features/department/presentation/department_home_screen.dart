// Department home — shows pending/rejected/approved view based on verification status.
// Rejected view has inline edit + resubmit form (API auto-moves back to pending).

import 'package:dispatch_mobile/core/state/session_controller.dart';
import 'package:dispatch_mobile/core/state/session_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DepartmentHomeScreen extends ConsumerStatefulWidget {
  const DepartmentHomeScreen({super.key});

  @override
  ConsumerState<DepartmentHomeScreen> createState() => _DepartmentHomeScreenState();
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
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final dept = session.department;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Department'),
        actions: [
          TextButton(
            onPressed: () => ref.read(sessionControllerProvider.notifier).signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : dept == null
              ? const Center(child: Text('No department profile found.'))
              : _buildBody(context, dept),
    );
  }

  Widget _buildBody(BuildContext context, DepartmentInfo dept) {
    if (dept.verificationStatus == 'pending') {
      return _PendingView(dept: dept);
    }
    if (dept.verificationStatus == 'rejected') {
      return _RejectedView(dept: dept);
    }
    return _ApprovedView(dept: dept);
  }
}

class _PendingView extends StatelessWidget {
  const _PendingView({required this.dept});
  final DepartmentInfo dept;

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
              decoration: BoxDecoration(color: Colors.orange.shade100, shape: BoxShape.circle),
              child: const Icon(Icons.hourglass_empty, size: 32, color: Colors.orange),
            ),
            const SizedBox(height: 20),
            Text('Awaiting Verification', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Your registration for ${dept.name} is pending municipality approval.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            _DeptDetails(dept: dept),
          ],
        ),
      ),
    );
  }
}

class _RejectedView extends ConsumerStatefulWidget {
  const _RejectedView({required this.dept});
  final DepartmentInfo dept;

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
    _areaCtrl = TextEditingController(text: widget.dept.areaOfResponsibility ?? '');
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
    setState(() { _loading = true; _error = null; });
    try {
      final authService = ref.read(authServiceProvider);
      final updated = await authService.updateDepartmentProfile({
        'name': _nameCtrl.text.trim(),
        'contact_number': _contactCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'area_of_responsibility': _areaCtrl.text.trim(),
      });
      ref.read(sessionControllerProvider.notifier).updateDepartment(updated);
      if (mounted) setState(() { _editing = false; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: Colors.red.shade100, shape: BoxShape.circle),
          child: const Icon(Icons.close, size: 32, color: Colors.red),
        ),
        const SizedBox(height: 16),
        Text('Registration Rejected', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (widget.dept.rejectionReason != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text('Reason: ${widget.dept.rejectionReason}', style: TextStyle(color: Colors.red.shade700)),
          ),
        ],
        const SizedBox(height: 20),
        if (!_editing) ...[
          Text('You can update your details and resubmit for verification.', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => setState(() => _editing = true),
            child: const Text('Edit & Resubmit'),
          ),
        ] else ...[
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ),
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Organization name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _contactCtrl, decoration: const InputDecoration(labelText: 'Contact number', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _addressCtrl, decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _areaCtrl, decoration: const InputDecoration(labelText: 'Area of responsibility', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _loading ? null : _resubmit,
                  child: Text(_loading ? 'Submitting...' : 'Resubmit'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => setState(() => _editing = false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ApprovedView extends StatelessWidget {
  const _ApprovedView({required this.dept});
  final DepartmentInfo dept;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(20)),
          child: Text('Verified', style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w600, fontSize: 12)),
        ),
        const SizedBox(height: 16),
        Text(dept.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        _DeptDetails(dept: dept),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            title: const Text('Incident Board'),
            subtitle: const Text('Accept/decline actions will be available in Phase 2.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
        ),
      ],
    );
  }
}

class _DeptDetails extends StatelessWidget {
  const _DeptDetails({required this.dept});
  final DepartmentInfo dept;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailRow('Type', dept.type),
          if (dept.contactNumber != null) _DetailRow('Contact', dept.contactNumber!),
          if (dept.address != null) _DetailRow('Address', dept.address!),
          if (dept.areaOfResponsibility != null) _DetailRow('Area', dept.areaOfResponsibility!),
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
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
