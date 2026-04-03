import 'package:dispatch_mobile/core/state/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MunicipalityVerificationScreen extends ConsumerStatefulWidget {
  const MunicipalityVerificationScreen({super.key});

  @override
  ConsumerState<MunicipalityVerificationScreen> createState() =>
      _MunicipalityVerificationScreenState();
}

class _MunicipalityVerificationScreenState
    extends ConsumerState<MunicipalityVerificationScreen> {
  List<Map<String, dynamic>> _departments = [];
  bool _loading = true;
  String? _activeDepartmentId;

  @override
  void initState() {
    super.initState();
    _fetchPending();
  }

  Future<void> _fetchPending() async {
    setState(() => _loading = true);
    try {
      final departments = await ref
          .read(authServiceProvider)
          .getMunicipalityPendingDepartments();
      if (!mounted) return;
      setState(() {
        _departments = departments;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _approve(String departmentId) async {
    setState(() => _activeDepartmentId = departmentId);
    try {
      await ref
          .read(authServiceProvider)
          .verifyDepartment(departmentId, action: 'approved');
      if (!mounted) return;
      setState(() {
        _departments.removeWhere((item) => item['id'] == departmentId);
      });
    } finally {
      if (mounted) {
        setState(() => _activeDepartmentId = null);
      }
    }
  }

  Future<void> _reject(String departmentId) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject department'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Explain what needs to be corrected.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) {
      return;
    }

    setState(() => _activeDepartmentId = departmentId);
    try {
      await ref
          .read(authServiceProvider)
          .verifyDepartment(
            departmentId,
            action: 'rejected',
            rejectionReason: reason,
          );
      if (!mounted) return;
      setState(() {
        _departments.removeWhere((item) => item['id'] == departmentId);
      });
    } finally {
      if (mounted) {
        setState(() => _activeDepartmentId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verification Queue')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _departments.isEmpty
          ? const Center(child: Text('No departments pending verification.'))
          : RefreshIndicator(
              onRefresh: _fetchPending,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _departments.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final department = _departments[index];
                  final busy = _activeDepartmentId == department['id'];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      department['name'] as String? ??
                                          'Department',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      (department['type'] as String? ?? 'other')
                                          .replaceAll('_', ' '),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                              const Chip(label: Text('Pending')),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if ((department['contact_number'] as String?)
                                  ?.isNotEmpty ==
                              true)
                            _DetailRow(
                              icon: Icons.call_outlined,
                              label: department['contact_number'] as String,
                            ),
                          if ((department['address'] as String?)?.isNotEmpty ==
                              true)
                            _DetailRow(
                              icon: Icons.location_on_outlined,
                              label: department['address'] as String,
                            ),
                          if ((department['area_of_responsibility'] as String?)
                                  ?.isNotEmpty ==
                              true)
                            _DetailRow(
                              icon: Icons.map_outlined,
                              label:
                                  department['area_of_responsibility']
                                      as String,
                            ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: busy
                                      ? null
                                      : () => _approve(
                                          department['id'] as String,
                                        ),
                                  child: Text(
                                    busy ? 'Processing...' : 'Approve',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: busy
                                      ? null
                                      : () =>
                                            _reject(department['id'] as String),
                                  child: const Text('Reject'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFA14B2F)),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
