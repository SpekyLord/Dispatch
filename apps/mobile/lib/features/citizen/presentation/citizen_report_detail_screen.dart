import 'dart:async';

import 'package:dispatch_mobile/core/i18n/app_strings.dart';
import 'package:dispatch_mobile/core/i18n/locale_action_button.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
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
      'pending' => dc.statusPending,
      'accepted' => dc.statusAccepted,
      'responding' => dc.statusResponding,
      'resolved' => dc.statusResolved,
      _ => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final reportTitle = strings.reportTitle(widget.reportId.substring(0, 8));

    return Scaffold(
      appBar: AppBar(
        title: Text(reportTitle),
        actions: const [LocaleActionButton()],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _report == null
              ? Center(child: Text(strings.reportNotFound))
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
                              strings
                                  .statusLabel(
                                    _report!['status'] as String? ?? 'pending',
                                  )
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
                              strings.categoryLabel(
                                _report!['category'] as String? ?? '',
                              ),
                              style: const TextStyle(fontSize: 11),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          if (_report!['is_escalated'] == true) ...[
                            const SizedBox(width: 8),
                            Chip(
                              label: Text(
                                strings.escalated.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.red,
                                ),
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
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: Colors.black54),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 8),
                      Text(
                        strings.severityValue(
                          _report!['severity'] as String? ?? 'medium',
                        ),
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.black45),
                      ),
                      if (_report!['latitude'] != null &&
                          _report!['longitude'] != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          strings.location,
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
                          strings.photos,
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
                        strings.statusHistory,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      if (_history.isEmpty)
                        Text(
                          strings.noStatusUpdatesYet,
                          style: const TextStyle(color: Colors.black45),
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
                                      strings.statusLabel(status).toUpperCase(),
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
                      if (_departmentResponses.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                          strings.departmentResponses,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        for (final response in _departmentResponses)
                          Builder(
                            builder: (context) {
                              final item = response as Map;
                              final action =
                                  item['action'] as String? ?? 'pending';
                              final departmentName =
                                  item['department_name'] as String? ??
                                      strings.unknownDepartment;
                              final actionColor = action == 'accepted'
                                  ? dc.statusResolved
                                  : action == 'declined'
                                      ? dc.statusError
                                      : dc.statusPending;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                      color: actionColor,
                                      width: 3,
                                    ),
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
                                            departmentName,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          strings
                                              .responseActionLabel(action)
                                              .toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: actionColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (item['notes'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          item['notes'] as String,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ),
                                    if (item['responded_at'] != null)
                                      Text(
                                        item['responded_at'] as String,
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
