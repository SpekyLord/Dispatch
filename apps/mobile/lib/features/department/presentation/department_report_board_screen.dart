import 'dart:async';

import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/department/presentation/department_report_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DepartmentReportBoardScreen extends ConsumerStatefulWidget {
  const DepartmentReportBoardScreen({super.key});

  @override
  ConsumerState<DepartmentReportBoardScreen> createState() =>
      _DepartmentReportBoardScreenState();
}

class _DepartmentReportBoardScreenState
    extends ConsumerState<DepartmentReportBoardScreen> {
  List<Map<String, dynamic>> _reports = [];
  List<RealtimeSubscriptionHandle> _subscriptions = [];
  bool _loading = true;
  String? _statusFilter;
  String? _categoryFilter;

  @override
  void initState() {
    super.initState();
    _fetchReports();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.dispose());
    }
    super.dispose();
  }

  void _subscribeToRealtime() {
    final realtime = ref.read(realtimeServiceProvider);
    _subscriptions = [
      realtime.subscribeToTable(
        table: 'incident_reports',
        onChange: () {
          if (mounted) {
            _fetchReports(showLoader: false);
          }
        },
      ),
      realtime.subscribeToTable(
        table: 'department_responses',
        onChange: () {
          if (mounted) {
            _fetchReports(showLoader: false);
          }
        },
      ),
    ];
  }

  Future<void> _fetchReports({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() => _loading = true);
    }
    try {
      final authService = ref.read(authServiceProvider);
      final reports = await authService.getDepartmentReports(
        status: _statusFilter,
        category: _categoryFilter,
      );
      if (mounted) {
        setState(() {
          _reports = reports;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && showLoader) {
        setState(() => _loading = false);
      }
    }
  }

  Color _statusColor(String status) {
    return switch (status) {
      'pending' => Colors.orange,
      'accepted' => Colors.blue,
      'responding' => Colors.purple,
      'resolved' => Colors.green,
      _ => Colors.grey,
    };
  }

  Color _severityColor(String severity) {
    return switch (severity) {
      'low' => Colors.green,
      'medium' => Colors.yellow.shade800,
      'high' => Colors.orange,
      'critical' => Colors.red,
      _ => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Incident Board'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter by status',
            onSelected: (value) {
              setState(() => _statusFilter = value.isEmpty ? null : value);
              _fetchReports();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: '', child: Text('All statuses')),
              const PopupMenuItem(value: 'pending', child: Text('Pending')),
              const PopupMenuItem(value: 'accepted', child: Text('Accepted')),
              const PopupMenuItem(
                value: 'responding',
                child: Text('Responding'),
              ),
              const PopupMenuItem(value: 'resolved', child: Text('Resolved')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reports.isEmpty
          ? const Center(child: Text('No reports match the current filters.'))
          : RefreshIndicator(
              onRefresh: () => _fetchReports(),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _reports.length,
                itemBuilder: (context, index) {
                  final report = _reports[index];
                  final status = report['status'] as String? ?? 'pending';
                  final category = (report['category'] as String? ?? '')
                      .replaceAll('_', ' ');
                  final severity = report['severity'] as String? ?? 'medium';
                  final isEscalated = report['is_escalated'] == true;
                  final ownAction =
                      (report['current_response']
                              as Map<String, dynamic>?)?['action']
                          as String?;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => DepartmentReportDetailScreen(
                              reportId: report['id'] as String,
                            ),
                          ),
                        );
                        _fetchReports(showLoader: false);
                      },
                      title: Text(
                        (report['title'] as String?) ??
                            (report['description'] as String? ?? ''),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Chip(
                              label: Text(
                                category,
                                style: const TextStyle(fontSize: 10),
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _statusColor(status).withAlpha(30),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _statusColor(status),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _severityColor(severity).withAlpha(30),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                severity,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _severityColor(severity),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isEscalated)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'ESCALATED',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.red.shade800,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            if (ownAction != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: ownAction == 'accepted'
                                      ? Colors.green.shade50
                                      : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'You $ownAction',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: ownAction == 'accepted'
                                        ? Colors.green.shade800
                                        : Colors.red.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
