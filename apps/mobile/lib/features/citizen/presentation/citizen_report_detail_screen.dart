import 'dart:async';

import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/shared/presentation/location_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CitizenReportDetailScreen extends ConsumerStatefulWidget {
  const CitizenReportDetailScreen({required this.reportId, super.key});

  final String reportId;

  @override
  ConsumerState<CitizenReportDetailScreen> createState() =>
      _CitizenReportDetailScreenState();
}

class _CitizenReportDetailScreenState
    extends ConsumerState<CitizenReportDetailScreen> {
  Map<String, dynamic>? _report;
  List<dynamic> _history = [];
  List<dynamic> _departmentResponses = [];
  List<RealtimeSubscriptionHandle> _subscriptions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
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
            _fetch(showLoader: false);
          }
        },
      ),
      realtime.subscribeToTable(
        table: 'report_status_history',
        eqColumn: 'report_id',
        eqValue: widget.reportId,
        onChange: () {
          if (mounted) {
            _fetch(showLoader: false);
          }
        },
      ),
    ];
  }

  Future<void> _fetch({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() => _loading = true);
    }

    try {
      final authService = ref.read(authServiceProvider);
      final data = await authService.getReport(widget.reportId);
      if (mounted) {
        setState(() {
          _report = data['report'] as Map<String, dynamic>?;
          _history = data['status_history'] as List<dynamic>? ?? [];
          _departmentResponses =
              data['department_responses'] as List<dynamic>? ?? [];
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Report #${widget.reportId.substring(0, 8)}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _report == null
          ? const Center(child: Text('Report not found.'))
          : RefreshIndicator(
              onRefresh: () => _fetch(),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(
                            _report!['status'] as String? ?? 'pending',
                          ).withAlpha(30),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          (_report!['status'] as String? ?? 'pending')
                              .toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _statusColor(
                              _report!['status'] as String? ?? 'pending',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(
                          (_report!['category'] as String? ?? '').replaceAll(
                            '_',
                            ' ',
                          ),
                          style: const TextStyle(fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      if (_report!['is_escalated'] == true) ...[
                        const SizedBox(width: 8),
                        Chip(
                          label: const Text(
                            'ESCALATED',
                            style: TextStyle(fontSize: 11, color: Colors.red),
                          ),
                          color: const WidgetStatePropertyAll(
                            Color(0x20FF0000),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _report!['description'] as String? ?? '',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  if (_report!['address'] != null)
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 14,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _report!['address'] as String,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.black54),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Severity: ${_report!['severity'] ?? 'medium'}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.black45),
                  ),
                  if (_report!['latitude'] != null &&
                      _report!['longitude'] != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Location',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    LocationMap(
                      latitude: (_report!['latitude'] as num).toDouble(),
                      longitude: (_report!['longitude'] as num).toDouble(),
                      zoom: 15.0,
                    ),
                  ],
                  if ((_report!['image_urls'] as List?)?.isNotEmpty ==
                      true) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Photos',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 120,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final url in (_report!['image_urls'] as List))
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  url as String,
                                  width: 120,
                                  height: 120,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Status History',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  if (_history.isEmpty)
                    const Text(
                      'No status updates yet.',
                      style: TextStyle(color: Colors.black45),
                    )
                  else
                    for (final entry in _history)
                      Builder(
                        builder: (context) {
                          final historyEntry = entry as Map;
                          final status =
                              (historyEntry['new_status'] as String?) ??
                              (historyEntry['status'] as String?) ??
                              '';
                          final note =
                              historyEntry['notes'] ?? historyEntry['note'];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: _statusColor(status),
                                  width: 3,
                                ),
                              ),
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _statusColor(status),
                                  ),
                                ),
                                if (note != null)
                                  Text(
                                    note as String,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                Text(
                                  historyEntry['created_at'] as String? ?? '',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.black45,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  // Department responses section (Phase 3)
                  if (_departmentResponses.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Department Responses',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    for (final resp in _departmentResponses)
                      Builder(
                        builder: (ctx) {
                          final r = resp as Map;
                          final action = r['action'] as String? ?? 'pending';
                          final deptName =
                              r['department_name'] as String? ?? 'Unknown';
                          final actionColor = action == 'accepted'
                              ? Colors.green
                              : action == 'declined'
                              ? Colors.red
                              : Colors.orange;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(color: actionColor, width: 3),
                              ),
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        deptName,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      action.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: actionColor,
                                      ),
                                    ),
                                  ],
                                ),
                                if (r['notes'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      r['notes'] as String,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ),
                                if (r['responded_at'] != null)
                                  Text(
                                    r['responded_at'] as String,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.black38,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}
