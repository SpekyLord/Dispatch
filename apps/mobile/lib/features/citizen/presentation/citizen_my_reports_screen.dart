import 'dart:async';

import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:dispatch_mobile/features/citizen/presentation/citizen_profile_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_report_detail_screen.dart';
import 'package:dispatch_mobile/features/shared/presentation/location_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class CitizenMyReportsScreen extends ConsumerStatefulWidget {
  const CitizenMyReportsScreen({
    super.key,
    this.onOpenMapTab,
    this.onOpenProfile,
  });

  final VoidCallback? onOpenMapTab;
  final VoidCallback? onOpenProfile;

  @override
  ConsumerState<CitizenMyReportsScreen> createState() =>
      _CitizenMyReportsScreenState();
}

class _CitizenMyReportsScreenState extends ConsumerState<CitizenMyReportsScreen> {
  final _searchController = TextEditingController();
  final List<RealtimeSubscriptionHandle> _subscriptions =
      <RealtimeSubscriptionHandle>[];

  List<Map<String, dynamic>> _rows = const <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;
  String _query = '';
  String _status = 'all';
  String _category = 'all';

  @override
  void initState() {
    super.initState();
    _fetch();
    _subscribe();
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final subscription in _subscriptions) {
      unawaited(subscription.dispose());
    }
    super.dispose();
  }

  void _subscribe() {
    final realtime = ref.read(realtimeServiceProvider);
    _subscriptions.addAll([
      realtime.subscribeToTable(table: 'incident_reports', onChange: _refreshQuietly),
      realtime.subscribeToTable(table: 'report_status_history', onChange: _refreshQuietly),
      realtime.subscribeToTable(table: 'department_responses', onChange: _refreshQuietly),
      realtime.subscribeToTable(table: 'notifications', onChange: _refreshQuietly),
    ]);
  }

  void _refreshQuietly() {
    if (mounted) {
      unawaited(_fetch(showLoader: false));
    }
  }

  Future<void> _fetch({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows =
          (await ref.read(authServiceProvider).getReports()).cast<Map<String, dynamic>>();
      if (!mounted) {
        return;
      }
      setState(() {
        _rows = rows;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Unable to load your reports right now.';
      });
    }
  }

  List<_CitizenReportItem> get _reports {
    final query = _query.trim().toLowerCase();
    return _rows
        .map(_CitizenReportItem.fromJson)
        .where((report) {
          if (_status != 'all' && report.status != _status) {
            return false;
          }
          if (_category != 'all' && report.category != _category) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          final haystack = [
            report.id,
            report.title,
            report.description,
            report.categoryLabel,
            report.statusLabel,
            report.severityLabel,
            report.address ?? '',
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _openReport(_CitizenReportItem report) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CitizenReportDetailScreen(reportId: report.id),
      ),
    );
    await _fetch(showLoader: false);
  }

  Future<void> _openProfile() async {
    if (widget.onOpenProfile != null) {
      widget.onOpenProfile!.call();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CitizenProfileScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final avatarSeed = (session.fullName ?? session.email ?? 'Dispatch').trim();
    final avatarLabel = avatarSeed.isEmpty ? 'D' : avatarSeed.substring(0, 1).toUpperCase();
    final categories = <String>{
      'all',
      ..._rows.map(_CitizenReportItem.fromJson).map((row) => row.category),
    }.toList(growable: false);

    return Container(
      color: dc.background,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetch,
          color: dc.primary,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
            children: [
              Row(
                children: [
                  const Icon(Icons.assignment_outlined, color: dc.primary, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'MY REPORTS',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                        color: dc.ink,
                      ),
                    ),
                  ),
                  _ProfileShortcut(
                    profileInitial: avatarLabel,
                    onTap: _openProfile,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _ReportsHero(count: _reports.length),
              const SizedBox(height: 16),
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final value in const ['all', 'pending', 'accepted', 'responding', 'resolved']) ...[
                      _BoardChip(
                        label: value == 'all' ? 'All' : _titleCase(value),
                        selected: _status == value,
                        onTap: () => setState(() => _status = value),
                      ),
                      const SizedBox(width: 8),
                    ],
                    IconButton(
                      tooltip: 'Refresh reports',
                      onPressed: () => _fetch(showLoader: false),
                      icon: const Icon(Icons.refresh_rounded, color: dc.primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SearchField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    final value = categories[index];
                    return _BoardChip(
                      label: value == 'all'
                          ? 'All categories'
                          : _titleCase(value.replaceAll('_', ' ')),
                      selected: _category == value,
                      onTap: () => setState(() => _category = value),
                    );
                  },
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemCount: categories.length,
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                _InfoCard(icon: Icons.wifi_tethering_error_rounded, title: _error!, body: '')
              else if (_loading && _rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator(color: dc.primary)),
                )
              else if (_reports.isEmpty)
                _InfoCard(
                  icon: Icons.assignment_outlined,
                  title: 'No reports match this command view',
                  body: 'Submitted incidents will appear here with their latest status and response progress.',
                  actionLabel: widget.onOpenMapTab == null ? null : 'Open Mesh Map',
                  onAction: widget.onOpenMapTab,
                )
              else
                ..._reports.map(
                  (report) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _ReportBoardCard(report: report, onTap: () => _openReport(report)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CitizenReportItem {
  const _CitizenReportItem({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.status,
    required this.severity,
    required this.createdAt,
    required this.isEscalated,
    this.address,
    this.latitude,
    this.longitude,
  });

  factory _CitizenReportItem.fromJson(Map<String, dynamic> json) {
    final title = (json['title'] as String?)?.trim();
    final description = (json['description'] as String? ?? '').trim();
    return _CitizenReportItem(
      id: (json['id'] ?? '').toString(),
      title: (title == null || title.isEmpty)
          ? _deriveReportTitle(description, json['category'] as String?)
          : title,
      description: description,
      category: (json['category'] as String? ?? 'other').trim(),
      status: (json['status'] as String? ?? 'pending').trim(),
      severity: (json['severity'] as String? ?? 'medium').trim(),
      createdAt: (json['created_at'] as String? ?? '').trim(),
      isEscalated: json['is_escalated'] == true,
      address: (json['address'] as String?)?.trim(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }

  final String id;
  final String title;
  final String description;
  final String category;
  final String status;
  final String severity;
  final String createdAt;
  final bool isEscalated;
  final String? address;
  final double? latitude;
  final double? longitude;

  String get shortId => id.length <= 8 ? id : id.substring(0, 8);
  String get categoryLabel => _titleCase(category.replaceAll('_', ' '));
  String get statusLabel => _titleCase(status);
  String get severityLabel => _titleCase(severity);
  String get createdAtLabel => _formatDateTime(createdAt);
}

class _ProfileShortcut extends StatelessWidget {
  const _ProfileShortcut({
    required this.profileInitial,
    required this.onTap,
  });

  final String profileInitial;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: dc.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: dc.warmBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: dc.primaryDim,
                child: Text(
                  profileInitial,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.settings_outlined, color: dc.primary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportsHero extends StatelessWidget {
  const _ReportsHero({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFAE4F28),
            Color(0xFF8B4528),
            Color(0xFF4E6679),
          ],
          stops: [0, 0.52, 1],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(34),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A3A2418),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -16,
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            right: 54,
            bottom: -30,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.08),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.assignment_outlined, size: 15, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'REPORT TRACKER',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '$count visible',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.96),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'My Reports',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 33,
                  height: 1.02,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 184,
                height: 2,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 308),
                child: Text(
                  'Track submitted incidents, current response progress, and the latest status changes in one mobile command view.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: dc.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search_rounded, color: dc.onSurfaceVariant),
          hintText: 'Search reports',
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        ),
      ),
    );
  }
}

class _BoardChip extends StatelessWidget {
  const _BoardChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? dc.primary : dc.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? dc.primary : dc.warmBorder),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x269D5C34),
                      blurRadius: 14,
                      offset: Offset(0, 7),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_circle_rounded, size: 14, color: dc.onPrimary),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  letterSpacing: selected ? 0.4 : 0,
                  color: selected ? dc.onPrimary : dc.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: dc.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(icon, size: 38, color: dc.primary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: dc.ink,
            ),
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: dc.mutedInk,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.map_outlined),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportBoardCard extends StatelessWidget {
  const _ReportBoardCard({required this.report, required this.onTap});

  final _CitizenReportItem report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Ink(
        decoration: BoxDecoration(
          color: dc.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: dc.warmBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Row(
                children: [
                  _Pill(
                    label: report.severityLabel.toUpperCase(),
                    color: _severityColor(report.severity),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'LIVE REPORT FEED',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: dc.mutedInk,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '#${report.shortId}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: dc.mutedInk,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.title,
                          style: const TextStyle(
                            fontSize: 28,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                            color: dc.ink,
                            fontFamily: 'Georgia',
                          ),
                        ),
                        if (report.description.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            report.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: dc.mutedInk,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _MapCard(report: report),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: const Text(
                'PRIMARY LOCATION',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: dc.mutedInk,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 16, color: dc.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      (report.address ?? '').isNotEmpty
                          ? report.address!
                          : 'Location feed pending',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: dc.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Pill(label: report.categoryLabel.toUpperCase(), color: dc.categoryColor(report.category)),
                  _Pill(label: report.statusLabel.toUpperCase(), color: dc.statusColor(report.status)),
                  if (report.isEscalated)
                    const _Pill(label: 'ESCALATED', color: dc.statusError),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
              child: Row(
                children: [
                  Text(
                    report.createdAtLabel.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: dc.primary,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'VIEW INCIDENT DETAILS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: dc.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_rounded, size: 16, color: dc.primary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _MapCard extends StatelessWidget {
  const _MapCard({required this.report});

  final _CitizenReportItem report;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 98,
      height: 108,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (report.latitude != null && report.longitude != null)
              LocationMap(
                latitude: report.latitude!,
                longitude: report.longitude!,
                zoom: 14,
                height: 108,
              )
            else
              Container(
                color: const Color(0xFFE8DED4),
                alignment: Alignment.center,
                child: const Icon(Icons.map_outlined, color: dc.onSurfaceVariant),
              ),
            Positioned(
              right: 5,
              top: 8,
              child: RotatedBox(
                quarterTurns: 1,
                child: Text(
                  report.latitude != null && report.longitude != null
                      ? 'MAP FEED LIVE'
                      : 'MAP FEED PENDING',
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: Color(0xAA4A342B),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _deriveReportTitle(String description, String? category) {
  final lines = description
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.isNotEmpty) {
    return lines.first;
  }
  final fallback = category?.trim().isNotEmpty == true ? category! : 'report';
  return _titleCase(fallback.replaceAll('_', ' '));
}

String _titleCase(String value) {
  if (value.trim().isEmpty) {
    return value;
  }
  return value
      .split(RegExp(r'\s+'))
      .map((part) {
        final word = part.trim();
        if (word.isEmpty) {
          return word;
        }
        return '${word.substring(0, 1).toUpperCase()}${word.substring(1).toLowerCase()}';
      })
      .join(' ');
}

String _formatDateTime(String value) {
  final timestamp = DateTime.tryParse(value)?.toLocal();
  if (timestamp == null) {
    return value;
  }
  return DateFormat('MMM d, y • h:mm a').format(timestamp);
}

Color _severityColor(String severity) {
  return switch (severity) {
    'low' => dc.statusResolved,
    'medium' => dc.coolAccent,
    'high' => dc.statusPending,
    'critical' => dc.statusError,
    _ => dc.onSurfaceVariant,
  };
}
