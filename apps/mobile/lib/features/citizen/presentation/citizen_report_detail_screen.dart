import 'dart:async';

import 'package:dispatch_mobile/core/i18n/app_strings.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:dispatch_mobile/features/citizen/presentation/citizen_report_detail_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';

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
  CitizenReportTab _selectedTab = CitizenReportTab.overview;

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

  List<String> _evidenceUrls(Map<String, dynamic> report) {
    final raw = report['image_urls'];
    if (raw is List) {
      return raw
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return [raw.trim()];
    }
    return const <String>[];
  }

  List<CitizenTimelineEntry> _resolvedTimelineEntries(AppStrings strings) {
    return _timeline
        .whereType<Map>()
        .map((entry) {
          final type = (entry['type'] as String? ?? 'status_change').trim();
          if (type == 'department_response') {
            final action = (entry['action'] as String? ?? 'pending').trim();
            final detail =
                (entry['notes'] as String?)?.trim().isNotEmpty == true
                ? entry['notes'] as String
                : (entry['decline_reason'] as String?)?.trim().isNotEmpty == true
                ? entry['decline_reason'] as String
                : null;
            return CitizenTimelineEntry(
              type: type,
              timestamp: entry['timestamp'] as String?,
              headline:
                  (entry['department_name'] as String?)?.trim().isNotEmpty == true
                  ? entry['department_name'] as String
                  : strings.unknownDepartment,
              detail: detail,
              statusKey: action,
              tone: action == 'declined'
                  ? dc.statusError
                  : action == 'accepted'
                  ? dc.statusAccepted
                  : dc.statusResolved,
              action: action,
            );
          }

          final status = (entry['new_status'] as String? ?? 'pending').trim();
          final detail = (entry['notes'] as String?)?.trim();
          return CitizenTimelineEntry(
            type: type,
            timestamp: entry['timestamp'] as String?,
            headline: strings.statusLabel(status),
            detail: detail?.isEmpty == true ? null : detail,
            statusKey: status,
            tone: _statusColor(status),
          );
        })
        .toList(growable: false);
  }

  List<CitizenTimelineMilestone> _buildMilestones(AppStrings strings) {
    final report = _report;
    if (report == null) {
      return const <CitizenTimelineMilestone>[];
    }
    final entries = _resolvedTimelineEntries(strings);
    final reportStatus = (report['status'] as String? ?? 'pending').trim();
    final acceptedEntry = entries.where((entry) => entry.statusKey == 'accepted').firstOrNull;
    final respondingEntry = entries.where((entry) => entry.statusKey == 'responding').firstOrNull;
    final resolvedEntry = entries.where((entry) => entry.statusKey == 'resolved').firstOrNull;
    final completedStepIndex = reportStatus == 'resolved'
        ? 3
        : reportStatus == 'responding'
        ? 2
        : acceptedEntry != null || reportStatus == 'accepted'
        ? 1
        : 0;
    final currentIndex = reportStatus == 'resolved'
        ? 3
        : (completedStepIndex + 1).clamp(0, 3);

    final configs = [
      (
        key: 'pending',
        title: strings.statusLabel('pending'),
        description: 'Report submitted.',
        timestamp: report['created_at'] as String?,
      ),
      (
        key: 'accepted',
        title: strings.statusLabel('accepted'),
        description: acceptedEntry != null
            ? 'A department has accepted your report.'
            : 'Awaiting department acceptance.',
        timestamp: acceptedEntry?.timestamp,
      ),
      (
        key: 'responding',
        title: strings.statusLabel('responding'),
        description: respondingEntry != null
            ? 'Emergency responders are moving to the incident.'
            : 'Response team deployment pending.',
        timestamp: respondingEntry?.timestamp,
      ),
      (
        key: 'resolved',
        title: strings.statusLabel('resolved'),
        description: resolvedEntry != null
            ? 'This incident has been marked as resolved.'
            : 'Awaiting final resolution.',
        timestamp: resolvedEntry?.timestamp,
      ),
    ];

    return List<CitizenTimelineMilestone>.generate(configs.length, (index) {
      final config = configs[index];
      return CitizenTimelineMilestone(
        key: config.key,
        title: config.title,
        description: config.description,
        timestamp: config.timestamp,
        isComplete: reportStatus == 'resolved'
            ? index <= completedStepIndex
            : index < currentIndex,
        isCurrent: reportStatus != 'resolved' && index == currentIndex,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF7F2EA),
        body: Center(child: CircularProgressIndicator(color: dc.primary)),
      );
    }

    if (_report == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F2EA),
        body: Center(child: Text(strings.reportNotFound)),
      );
    }

    return CitizenReportDetailView(
      reportId: widget.reportId,
      report: _report!,
      selectedTab: _selectedTab,
      onTabSelected: (tab) => setState(() => _selectedTab = tab),
      onRefresh: () => _fetch(),
      onBack: () => Navigator.of(context).maybePop(),
      entries: _resolvedTimelineEntries(strings),
      milestones: _buildMilestones(strings),
      resolvedAddress: _report!['address']?.toString().trim().isNotEmpty == true
          ? _report!['address'] as String
          : (_geocodedAddress?.trim().isNotEmpty == true ? _geocodedAddress : null),
      coordinatesLabel: _coordinatesLabel().trim().isEmpty ? null : _coordinatesLabel(),
      evidenceUrls: _evidenceUrls(_report!),
      strings: strings,
    );
  }
}
