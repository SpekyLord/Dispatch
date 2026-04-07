import 'package:dispatch_mobile/core/i18n/app_strings.dart';
import 'package:dispatch_mobile/core/i18n/locale_action_button.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:dispatch_mobile/features/shared/presentation/location_map.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum CitizenReportTab { overview, timeline, map, assets }

class CitizenTimelineEntry {
  const CitizenTimelineEntry({
    required this.type,
    required this.timestamp,
    required this.headline,
    required this.detail,
    required this.statusKey,
    required this.tone,
    this.action,
  });

  final String type;
  final String? timestamp;
  final String headline;
  final String? detail;
  final String statusKey;
  final Color tone;
  final String? action;
}

class CitizenTimelineMilestone {
  const CitizenTimelineMilestone({
    required this.key,
    required this.title,
    required this.description,
    required this.timestamp,
    required this.isComplete,
    required this.isCurrent,
  });

  final String key;
  final String title;
  final String description;
  final String? timestamp;
  final bool isComplete;
  final bool isCurrent;
}

class CitizenReportDetailView extends StatefulWidget {
  const CitizenReportDetailView({
    required this.reportId,
    required this.report,
    required this.selectedTab,
    required this.onTabSelected,
    required this.onRefresh,
    required this.onBack,
    required this.entries,
    required this.milestones,
    required this.resolvedAddress,
    required this.coordinatesLabel,
    required this.evidenceUrls,
    required this.strings,
    super.key,
  });

  final String reportId;
  final Map<String, dynamic> report;
  final CitizenReportTab selectedTab;
  final ValueChanged<CitizenReportTab> onTabSelected;
  final Future<void> Function() onRefresh;
  final VoidCallback onBack;
  final List<CitizenTimelineEntry> entries;
  final List<CitizenTimelineMilestone> milestones;
  final String? resolvedAddress;
  final String? coordinatesLabel;
  final List<String> evidenceUrls;
  final AppStrings strings;

  @override
  State<CitizenReportDetailView> createState() => _CitizenReportDetailViewState();
}

class _CitizenReportDetailViewState extends State<CitizenReportDetailView> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _timelineKey = GlobalKey();

  @override
  void didUpdateWidget(covariant CitizenReportDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTab != widget.selectedTab) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleTabSelection());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleTabSelection() async {
    if (!mounted) {
      return;
    }

    switch (widget.selectedTab) {
      case CitizenReportTab.overview:
        if (_scrollController.hasClients) {
          await _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          );
        }
        break;
      case CitizenReportTab.timeline:
        final context = _timelineKey.currentContext;
        if (context != null) {
          await Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
            alignment: 0.45,
          );
        }
        break;
      case CitizenReportTab.map:
      case CitizenReportTab.assets:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.strings.reportTitle(widget.reportId.substring(0, 8));
    final selectedTab = widget.selectedTab;
    final showOverviewFlow =
        selectedTab == CitizenReportTab.overview ||
        selectedTab == CitizenReportTab.timeline;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F2EA),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _DetailHeader(
              onBack: widget.onBack,
              title: 'Incident #${widget.reportId.substring(0, 8)}',
            ),
            Expanded(
              child: RefreshIndicator(
                color: dc.primary,
                onRefresh: widget.onRefresh,
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
                  children: [
                    Text('CURRENT LOG', style: _sectionLabelStyle()),
                    const SizedBox(height: 4),
                    Text(title, style: _titleStyle()),
                    const SizedBox(height: 18),
                    _HeroMapCard(
                      address: widget.resolvedAddress,
                      coordinatesLabel: widget.coordinatesLabel,
                      hasLocation:
                          (widget.report['latitude'] as num?) != null &&
                          (widget.report['longitude'] as num?) != null,
                      latitude: (widget.report['latitude'] as num?)?.toDouble(),
                      longitude: (widget.report['longitude'] as num?)?.toDouble(),
                      statusLabel: widget.strings
                          .statusLabel(
                            (widget.report['status'] as String? ?? 'pending'),
                          )
                          .toUpperCase(),
                    ),
                    const SizedBox(height: 18),
                    if (showOverviewFlow) ...[
                      _OverviewTab(
                        report: widget.report,
                        strings: widget.strings,
                        resolvedAddress: widget.resolvedAddress,
                        coordinatesLabel: widget.coordinatesLabel,
                      ),
                      const SizedBox(height: 18),
                      KeyedSubtree(
                        key: _timelineKey,
                        child: _TimelineSection(
                          milestones: widget.milestones,
                        ),
                      ),
                    ] else if (selectedTab == CitizenReportTab.map)
                      _MapTab(
                        report: widget.report,
                        strings: widget.strings,
                        resolvedAddress: widget.resolvedAddress,
                        coordinatesLabel: widget.coordinatesLabel,
                      )
                    else
                      _AssetsTab(evidenceUrls: widget.evidenceUrls),
                  ],
                ),
              ),
            ),
            _BottomTabBar(
              selectedTab: selectedTab,
              onTabSelected: widget.onTabSelected,
            ),
          ],
        ),
      ),
    );
  }
}

TextStyle _sectionLabelStyle() {
  return TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w800,
    letterSpacing: 2,
    color: dc.primary.withValues(alpha: 0.85),
  );
}

TextStyle _titleStyle() {
  return const TextStyle(
    fontSize: 22,
    height: 1.05,
    fontWeight: FontWeight.w700,
    fontFamily: 'Georgia',
    color: Color(0xFF2F211C),
  );
}

IconData categoryIcon(String category) => switch (category) {
  'fire' => Icons.local_fire_department_outlined,
  'flood' => Icons.water_drop_outlined,
  'earthquake' => Icons.vibration_outlined,
  'road_accident' => Icons.car_crash_outlined,
  'medical' => Icons.medical_services_outlined,
  'structural' => Icons.foundation_outlined,
  _ => Icons.report_problem_outlined,
};

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.onBack, required this.title});

  final VoidCallback onBack;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F2EA),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF6F3B1F)),
            ),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Georgia',
                  color: Color(0xFF6F3B1F),
                ),
              ),
            ),
            const LocaleActionButton(),
            IconButton(onPressed: null, icon: const Icon(Icons.more_vert_rounded)),
          ],
        ),
      ),
    );
  }
}

class _HeroMapCard extends StatelessWidget {
  const _HeroMapCard({
    required this.statusLabel,
    required this.hasLocation,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.coordinatesLabel,
  });

  final String statusLabel;
  final bool hasLocation;
  final double? latitude;
  final double? longitude;
  final String? address;
  final String? coordinatesLabel;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 240,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasLocation && latitude != null && longitude != null)
              LocationMap(
                latitude: latitude!,
                longitude: longitude!,
                zoom: 15,
                height: 240,
              )
            else
              Container(
                color: const Color(0xFFE5DED6),
                alignment: Alignment.center,
                child: const Icon(Icons.map_outlined, size: 42, color: dc.onSurfaceVariant),
              ),
            Positioned(
              left: 14,
              top: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6F3B1F),
                  ),
                ),
              ),
            ),
            if ((address ?? coordinatesLabel)?.isNotEmpty == true)
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    address ?? coordinatesLabel!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF7),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SeverityPill extends StatelessWidget {
  const _SeverityPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFECE8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.priority_high_rounded, size: 14, color: dc.statusError),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: dc.statusError,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: dc.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: dc.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: Color(0xFF2F211C),
                ),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: const TextStyle(fontSize: 12, color: dc.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.report,
    required this.strings,
    required this.resolvedAddress,
    required this.coordinatesLabel,
  });

  final Map<String, dynamic> report;
  final AppStrings strings;
  final String? resolvedAddress;
  final String? coordinatesLabel;

  @override
  Widget build(BuildContext context) {
    final severity = (report['severity'] as String? ?? 'medium').trim();
    final category = (report['category'] as String? ?? 'other').trim();
    final address = resolvedAddress ?? 'Location pending';

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('INCIDENT TYPE', style: _sectionLabelStyle())),
              _SeverityPill(label: strings.severityLabel(severity)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(categoryIcon(category), color: dc.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.categoryLabel(category),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Georgia',
                    color: Color(0xFF2F211C),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFE8DDD2)),
          const SizedBox(height: 14),
          _InfoRow(
            icon: Icons.location_on_outlined,
            label: strings.location.toUpperCase(),
            title: address,
            subtitle: coordinatesLabel,
          ),
          const SizedBox(height: 14),
          _InfoRow(
            icon: Icons.watch_later_outlined,
            label: 'TIMESTAMP',
            title: _formatFullTimestamp(report['created_at'] as String?),
          ),
          const SizedBox(height: 18),
          Text('ORIGINAL DESCRIPTION', style: _sectionLabelStyle()),
          const SizedBox(height: 8),
          Text(
            (report['description'] as String?)?.trim().isNotEmpty == true
                ? report['description'] as String
                : 'No incident description provided.',
            style: const TextStyle(fontSize: 14, height: 1.5, color: dc.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _MapTab extends StatelessWidget {
  const _MapTab({
    required this.report,
    required this.strings,
    required this.resolvedAddress,
    required this.coordinatesLabel,
  });

  final Map<String, dynamic> report;
  final AppStrings strings;
  final String? resolvedAddress;
  final String? coordinatesLabel;

  @override
  Widget build(BuildContext context) {
    final latitude = (report['latitude'] as num?)?.toDouble();
    final longitude = (report['longitude'] as num?)?.toDouble();

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Map',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'Georgia',
              color: Color(0xFF2F211C),
            ),
          ),
          const SizedBox(height: 14),
          if (latitude != null && longitude != null) ...[
            LocationMap(latitude: latitude, longitude: longitude, zoom: 15, height: 320),
            const SizedBox(height: 14),
            _InfoRow(
              icon: Icons.pin_drop_outlined,
              label: strings.location.toUpperCase(),
              title: resolvedAddress ?? 'Pinned coordinates',
              subtitle: coordinatesLabel,
            ),
          ] else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFF4ECE3),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                'No GPS coordinates were attached to this report.',
                style: TextStyle(fontSize: 14, color: dc.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _AssetsTab extends StatelessWidget {
  const _AssetsTab({required this.evidenceUrls});

  final List<String> evidenceUrls;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Assets',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'Georgia',
              color: Color(0xFF2F211C),
            ),
          ),
          const SizedBox(height: 14),
          if (evidenceUrls.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFF4ECE3),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                'No evidence assets were attached to this report.',
                style: TextStyle(fontSize: 14, color: dc.onSurfaceVariant),
              ),
            )
          else
            GridView.builder(
              itemCount: evidenceUrls.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.network(
                    evidenceUrls[index],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFFF4ECE3),
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined, color: dc.onSurfaceVariant),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

String _formatFullTimestamp(String? value) {
  final parsed = DateTime.tryParse(value ?? '')?.toLocal();
  if (parsed == null) {
    return value ?? '';
  }
  return DateFormat('MMMM d, y, h:mm a').format(parsed);
}

class _TimelineSection extends StatelessWidget {
  const _TimelineSection({
    required this.milestones,
  });

  final List<CitizenTimelineMilestone> milestones;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Report Timeline',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'Georgia',
              color: Color(0xFF2F211C),
            ),
          ),
          const SizedBox(height: 16),
          for (var index = 0; index < milestones.length; index++) ...[
            _MilestoneTile(milestone: milestones[index], index: index),
            if (index != milestones.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _BottomTabBar extends StatelessWidget {
  const _BottomTabBar({
    required this.selectedTab,
    required this.onTabSelected,
  });

  final CitizenReportTab selectedTab;
  final ValueChanged<CitizenReportTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (CitizenReportTab.overview, Icons.description_outlined, 'Overview'),
      (CitizenReportTab.timeline, Icons.show_chart_rounded, 'Timeline'),
      (CitizenReportTab.map, Icons.map_outlined, 'Map'),
      (CitizenReportTab.assets, Icons.auto_awesome_motion_outlined, 'Assets'),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF7F2EA),
        border: Border(top: BorderSide(color: Color(0xFFE6DBD0))),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: InkWell(
                onTap: () => onTabSelected(item.$1),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.$2,
                        size: 20,
                        color: selectedTab == item.$1 ? dc.primary : dc.onSurfaceVariant,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.$3,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: selectedTab == item.$1 ? FontWeight.w800 : FontWeight.w600,
                          color: selectedTab == item.$1 ? dc.primary : dc.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MilestoneTile extends StatelessWidget {
  const _MilestoneTile({required this.milestone, required this.index});

  final CitizenTimelineMilestone milestone;
  final int index;

  @override
  Widget build(BuildContext context) {
    final tone = milestone.isComplete || milestone.isCurrent
        ? dc.primary
        : const Color(0xFFD4C5B8);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: milestone.isCurrent ? const Color(0xFFFFF2EB) : const Color(0xFFF8F3EE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: milestone.isComplete ? tone : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: tone),
            ),
            child: Center(
              child: milestone.isComplete
                  ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                  : Text(
                      '${index + 1}'.padLeft(2, '0'),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: tone,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  milestone.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2F211C),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  milestone.description,
                  style: const TextStyle(fontSize: 13, height: 1.4, color: dc.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Text(
                  milestone.timestamp == null
                      ? '--'
                      : DateFormat('MMM d, h:mm a').format(
                          DateTime.parse(milestone.timestamp!).toLocal(),
                        ),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: dc.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineEntryTile extends StatelessWidget {
  const _TimelineEntryTile({
    required this.entry,
    required this.isLast,
    required this.formatTimestamp,
    required this.strings,
  });

  final CitizenTimelineEntry entry;
  final bool isLast;
  final String Function(String?) formatTimestamp;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final actionLabel = entry.action == null
        ? null
        : strings.responseActionLabel(entry.action!).toUpperCase();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: entry.tone, shape: BoxShape.circle),
            ),
            if (!isLast)
              Container(width: 2, height: 64, color: entry.tone.withValues(alpha: 0.22)),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F3EE),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.headline.toUpperCase(),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: entry.tone),
                ),
                if (actionLabel != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    actionLabel,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: entry.tone),
                  ),
                ],
                if (entry.detail != null && entry.detail!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    entry.detail!,
                    style: const TextStyle(fontSize: 13, height: 1.4, color: dc.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  formatTimestamp(entry.timestamp),
                  style: const TextStyle(fontSize: 11, color: dc.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
