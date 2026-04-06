import 'dart:async';

import 'package:dispatch_mobile/core/i18n/app_strings.dart';
import 'package:dispatch_mobile/core/i18n/locale_action_button.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:dispatch_mobile/features/shared/presentation/location_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';

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
  List<dynamic> _timeline = [];
  List<RealtimeSubscriptionHandle> _subscriptions = [];
  bool _loading = true;
  String? _geocodedAddress;

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
      realtime.subscribeToTable(
        table: 'department_responses',
        eqColumn: 'report_id',
        eqValue: widget.reportId,
        onChange: () {
          if (mounted) {
            _fetch(showLoader: false);
          }
        },
      ),
      realtime.subscribeToTable(
        table: 'notifications',
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
          _timeline =
              data['timeline'] as List<dynamic>? ??
              _mergeLegacyTimeline(
                data['status_history'] as List<dynamic>? ?? const <dynamic>[],
                data['department_responses'] as List<dynamic>? ??
                    const <dynamic>[],
              );
          _loading = false;
        });
        final lat = (_report?['latitude'] as num?)?.toDouble();
        final lng = (_report?['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) unawaited(_reverseGeocode(lat, lng));
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

  List<Map<String, dynamic>> _mergeLegacyTimeline(
    List<dynamic> history,
    List<dynamic> responses,
  ) {
    final timeline = <Map<String, dynamic>>[];
    for (final entry in history.whereType<Map>()) {
      timeline.add({
        'type': 'status_change',
        'timestamp': entry['created_at'],
        'new_status': entry['new_status'] ?? entry['status'],
        'notes': entry['notes'] ?? entry['note'],
      });
    }
    for (final entry in responses.whereType<Map>()) {
      timeline.add({
        'type': 'department_response',
        'timestamp': entry['responded_at'] ?? entry['created_at'],
        'action': entry['action'],
        'department_name': entry['department_name'],
        'notes': entry['notes'],
        'decline_reason': entry['decline_reason'],
      });
    }
    timeline.sort(
      (left, right) => (left['timestamp'] ?? '').toString().compareTo(
        (right['timestamp'] ?? '').toString(),
      ),
    );
    return timeline;
  }

  String _formatTimestamp(String? value) {
    final parsed = DateTime.tryParse(value ?? '')?.toLocal();
    if (parsed == null) {
      return value ?? '';
    }
    return DateFormat('MMM d, y - h:mm a').format(parsed);
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final marks = await placemarkFromCoordinates(lat, lng);
      if (!mounted || marks.isEmpty) return;
      final p = marks.first;
      final parts = <String>[
        if ((p.street ?? '').isNotEmpty) p.street!,
        if ((p.locality ?? '').isNotEmpty) p.locality!,
        if ((p.country ?? '').isNotEmpty) p.country!,
      ];
      if (!mounted) return;
      setState(() => _geocodedAddress = parts.isEmpty ? null : parts.join(', '));
    } catch (_) {}
  }

  String _coordinatesLabel() {
    if (_geocodedAddress != null) return _geocodedAddress!;
    final latitude = (_report?['latitude'] as num?)?.toDouble();
    final longitude = (_report?['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null) {
      return '';
    }
    return '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
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
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.black54),
                          ),
                        ),
                      ],
                    ),
                  if ((_report!['address'] as String? ?? '').trim().isEmpty &&
                      _coordinatesLabel().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.pin_drop_outlined,
                            size: 14,
                            color: Colors.black54,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Pinned coordinates: ${_coordinatesLabel()}',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: Colors.black54),
                            ),
                          ),
                        ],
                      ),
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
                    if (_coordinatesLabel().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _coordinatesLabel(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black45,
                          ),
                        ),
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
                    'Live timeline',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  if (_timeline.isEmpty)
                    Text(
                      strings.noStatusUpdatesYet,
                      style: const TextStyle(color: Colors.black45),
                    )
                  else
                    for (var index = 0; index < _timeline.length; index++)
                      Builder(
                        builder: (context) {
                          final entry =
                              _timeline[index] as Map<String, dynamic>;
                          final type =
                              entry['type'] as String? ?? 'status_change';
                          final status =
                              (entry['new_status'] as String?) ??
                              (entry['action'] as String?) ??
                              'pending';
                          final tone = type == 'department_response'
                              ? ((entry['action'] as String? ?? '') ==
                                        'declined'
                                    ? dc.statusError
                                    : dc.statusResolved)
                              : _statusColor(status);
                          final headline = type == 'department_response'
                              ? ((entry['department_name'] as String?) ??
                                    strings.unknownDepartment)
                              : strings.statusLabel(status);
                          final detail =
                              (entry['notes'] as String?)?.trim().isNotEmpty ==
                                  true
                              ? entry['notes'] as String
                              : (entry['decline_reason'] as String?)
                                        ?.trim()
                                        .isNotEmpty ==
                                    true
                              ? entry['decline_reason'] as String
                              : null;

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                children: [
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: tone,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  if (index != _timeline.length - 1)
                                    Container(
                                      width: 2,
                                      height: 58,
                                      color: tone.withValues(alpha: 0.24),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        headline.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: tone,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      if (type == 'department_response')
                                        Text(
                                          strings
                                              .responseActionLabel(
                                                (entry['action'] as String?) ??
                                                    'pending',
                                              )
                                              .toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: tone,
                                          ),
                                        ),
                                      if (detail != null) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          detail,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      Text(
                                        _formatTimestamp(
                                          entry['timestamp'] as String?,
                                        ),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.black45,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                ],
              ),
            ),
    );
  }
}
