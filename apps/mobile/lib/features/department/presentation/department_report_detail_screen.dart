import 'dart:async';

import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DepartmentReportDetailScreen extends ConsumerStatefulWidget {
  const DepartmentReportDetailScreen({required this.reportId, super.key});

  final String reportId;

  @override
  ConsumerState<DepartmentReportDetailScreen> createState() =>
      _DepartmentReportDetailScreenState();
}

class _DepartmentReportDetailScreenState
    extends ConsumerState<DepartmentReportDetailScreen> {
  Map<String, dynamic>? _report;
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _roster = [];
  List<RealtimeSubscriptionHandle> _subscriptions = [];
  bool _loading = true;
  bool _actionLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAll();
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
        eqColumn: 'id',
        eqValue: widget.reportId,
        onChange: () {
          if (mounted) {
            _fetchAll(showLoader: false);
          }
        },
      ),
      realtime.subscribeToTable(
        table: 'department_responses',
        eqColumn: 'report_id',
        eqValue: widget.reportId,
        onChange: () {
          if (mounted) {
            _fetchAll(showLoader: false);
          }
        },
      ),
      realtime.subscribeToTable(
        table: 'report_status_history',
        eqColumn: 'report_id',
        eqValue: widget.reportId,
        onChange: () {
          if (mounted) {
            _fetchAll(showLoader: false);
          }
        },
      ),
    ];
  }

  Future<void> _fetchAll({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() => _loading = true);
    }

    try {
      final auth = ref.read(authServiceProvider);
      final results = await Future.wait([
        auth.getReport(widget.reportId),
        auth.getReportResponses(widget.reportId),
      ]);

      final detail = results[0];
      final rosterData = results[1];

      if (mounted) {
        setState(() {
          _report = detail['report'] as Map<String, dynamic>?;
          _history =
              (detail['status_history'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          _roster =
              (rosterData['responses'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
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

  Future<void> _acceptReport() async {
    setState(() {
      _actionLoading = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).acceptReport(widget.reportId);
      await _fetchAll(showLoader: false);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _showDeclineDialog() async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline Report'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Reason (required)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, reasonCtrl.text.trim()),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;

    setState(() {
      _actionLoading = true;
      _error = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .declineReport(widget.reportId, declineReason: reason);
      await _fetchAll(showLoader: false);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() {
      _actionLoading = true;
      _error = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .updateReportStatus(widget.reportId, status: newStatus);
      await _fetchAll(showLoader: false);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _actionLoading = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report Detail')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _report == null
          ? const Center(child: Text('Report not found.'))
          : RefreshIndicator(
              onRefresh: () => _fetchAll(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
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
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  _buildHeader(),
                  const SizedBox(height: 16),
                  Text(
                    _report!['title'] as String? ?? '',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _report!['description'] as String? ?? '',
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 8),
                  if (_report!['address'] != null) ...[
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 14,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _report!['address'] as String,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_report!['image_urls'] != null &&
                      (_report!['image_urls'] as List).isNotEmpty) ...[
                    SizedBox(
                      height: 140,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: (_report!['image_urls'] as List).length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 8),
                        itemBuilder: (_, i) => ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            (_report!['image_urls'] as List)[i] as String,
                            height: 140,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _buildActions(),
                  const SizedBox(height: 24),
                  _buildRoster(),
                  const SizedBox(height: 24),
                  _buildHistory(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    final status = _report!['status'] as String? ?? 'pending';
    final severity = _report!['severity'] as String? ?? 'medium';
    final category = (_report!['category'] as String? ?? '').replaceAll(
      '_',
      ' ',
    );
    final isEscalated = _report!['is_escalated'] == true;

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        Chip(
          label: Text(
            status.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              color: _statusColor(status),
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: _statusColor(status).withAlpha(25),
          visualDensity: VisualDensity.compact,
        ),
        Chip(
          label: Text(category, style: const TextStyle(fontSize: 10)),
          visualDensity: VisualDensity.compact,
        ),
        Chip(
          label: Text(severity, style: const TextStyle(fontSize: 10)),
          visualDensity: VisualDensity.compact,
        ),
        if (isEscalated)
          Chip(
            label: Text(
              'ESCALATED',
              style: TextStyle(
                fontSize: 9,
                color: Colors.red.shade800,
                fontWeight: FontWeight.w700,
              ),
            ),
            backgroundColor: Colors.red.shade50,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Widget _buildActions() {
    final status = _report!['status'] as String? ?? 'pending';
    if (status == 'resolved') return const SizedBox.shrink();

    final ownResponse = _roster.cast<Map<String, dynamic>?>().firstWhere(
      (r) => r?['is_requesting_department'] == true,
      orElse: () => null,
    );
    final ownState = ownResponse?['state'] as String?;

    if (ownState == null || ownState == 'pending') {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _actionLoading ? null : _acceptReport,
              icon: const Icon(Icons.check_circle, size: 18),
              label: const Text('Accept'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _actionLoading ? null : _showDeclineDialog,
              icon: const Icon(Icons.cancel, size: 18),
              label: const Text('Decline'),
            ),
          ),
        ],
      );
    }

    if (ownState == 'accepted') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'You accepted this report',
            style: TextStyle(
              fontSize: 12,
              color: Colors.green.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (status == 'accepted')
            FilledButton.icon(
              onPressed: _actionLoading
                  ? null
                  : () => _updateStatus('responding'),
              icon: const Icon(Icons.directions_run, size: 18),
              label: const Text('Mark Responding'),
            ),
          if (status == 'responding')
            FilledButton.icon(
              onPressed: _actionLoading
                  ? null
                  : () => _updateStatus('resolved'),
              icon: const Icon(Icons.task_alt, size: 18),
              label: const Text('Mark Resolved'),
            ),
        ],
      );
    }

    return Text(
      'You declined this report.',
      style: TextStyle(
        fontSize: 12,
        color: Colors.red.shade700,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  Widget _buildRoster() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Department Responses',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (_roster.isEmpty)
          const Text(
            'No departments notified yet.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ..._roster.map((r) {
          final state = r['state'] as String? ?? 'pending';
          final isYou = r['is_requesting_department'] == true;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              dense: true,
              title: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: r['department_name'] as String? ?? 'Unknown',
                    ),
                    if (isYou)
                      const TextSpan(
                        text: ' (you)',
                        style: TextStyle(
                          color: Color(0xFFD97757),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              subtitle: r['decline_reason'] != null
                  ? Text(
                      'Reason: ${r['decline_reason']}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.red.shade700,
                      ),
                    )
                  : Text(
                      r['department_type'] as String? ?? '',
                      style: const TextStyle(fontSize: 11),
                    ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(
                    state == 'accepted'
                        ? 'accepted'
                        : state == 'declined'
                        ? 'pending'
                        : 'pending',
                  ).withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  state,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: state == 'accepted'
                        ? Colors.green
                        : state == 'declined'
                        ? Colors.red
                        : Colors.orange,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Status History',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (_history.isEmpty)
          const Text(
            'No status changes recorded.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ..._history.map((entry) {
          final newStatus = entry['new_status'] as String? ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 5, right: 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _statusColor(newStatus),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        newStatus.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _statusColor(newStatus),
                        ),
                      ),
                      if (entry['notes'] != null)
                        Text(
                          entry['notes'] as String,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      Text(
                        entry['created_at'] as String? ?? '',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
