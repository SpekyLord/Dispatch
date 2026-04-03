import 'package:dispatch_mobile/core/state/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MunicipalityDepartmentsScreen extends ConsumerStatefulWidget {
  const MunicipalityDepartmentsScreen({super.key});

  @override
  ConsumerState<MunicipalityDepartmentsScreen> createState() =>
      _MunicipalityDepartmentsScreenState();
}

class _MunicipalityDepartmentsScreenState
    extends ConsumerState<MunicipalityDepartmentsScreen> {
  List<Map<String, dynamic>> _departments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchDepartments();
  }

  Future<void> _fetchDepartments() async {
    setState(() => _loading = true);
    try {
      final departments = await ref
          .read(authServiceProvider)
          .getMunicipalityDepartments();
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

  Color _statusColor(String status) {
    return switch (status) {
      'approved' => const Color(0xFF397154),
      'rejected' => const Color(0xFFD97757),
      _ => const Color(0xFFA14B2F),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Departments')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchDepartments,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _departments.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final department = _departments[index];
                  final status =
                      department['verification_status'] as String? ?? 'pending';
                  final accent = _statusColor(status);
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
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if ((department['contact_number'] as String?)
                                  ?.isNotEmpty ==
                              true)
                            _DepartmentMeta(
                              icon: Icons.call_outlined,
                              value: department['contact_number'] as String,
                            ),
                          if ((department['address'] as String?)?.isNotEmpty ==
                              true)
                            _DepartmentMeta(
                              icon: Icons.location_on_outlined,
                              value: department['address'] as String,
                            ),
                          if ((department['area_of_responsibility'] as String?)
                                  ?.isNotEmpty ==
                              true)
                            _DepartmentMeta(
                              icon: Icons.map_outlined,
                              value:
                                  department['area_of_responsibility']
                                      as String,
                            ),
                          if ((department['rejection_reason'] as String?)
                                  ?.isNotEmpty ==
                              true) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF1EB),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                'Rejection reason: ${department['rejection_reason']}',
                              ),
                            ),
                          ],
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

class _DepartmentMeta extends StatelessWidget {
  const _DepartmentMeta({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFA14B2F)),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
