import 'package:dispatch_mobile/core/state/notification_inbox_controller.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:dispatch_mobile/features/citizen/presentation/citizen_profile_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_report_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

enum _NotificationReadFilter { all, unread, read }

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({
    super.key,
    this.embeddedInShell = false,
    this.onOpenProfile,
    this.onOpenFeed,
  });

  final bool embeddedInShell;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenFeed;

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final TextEditingController _searchController = TextEditingController();

  _NotificationReadFilter _readFilter = _NotificationReadFilter.all;
  String _typeFilter = 'all';
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filteredNotifications(
    List<Map<String, dynamic>> notifications,
  ) {
    final query = _searchQuery.trim().toLowerCase();
    return notifications.where((notification) {
      final isRead = notification['is_read'] == true;
      if (_readFilter == _NotificationReadFilter.unread && isRead) {
        return false;
      }
      if (_readFilter == _NotificationReadFilter.read && !isRead) {
        return false;
      }
      final type = (notification['type'] as String? ?? '').trim();
      if (_typeFilter != 'all' && type != _typeFilter) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final haystack = [
        notification['title'] ?? '',
        notification['message'] ?? '',
        notification['type'] ?? '',
        notification['reference_type'] ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
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

  Future<void> _handleTap(Map<String, dynamic> notification) async {
    final controller = ref.read(notificationInboxControllerProvider.notifier);
    final notificationId = (notification['id'] ?? '').toString();
    if (notificationId.isNotEmpty && notification['is_read'] != true) {
      await controller.markRead(notificationId);
    }

    final referenceType = (notification['reference_type'] as String? ?? '').trim();
    final referenceId = (notification['reference_id'] as String? ?? '').trim();
    if (!mounted) {
      return;
    }

    if (referenceType == 'report' && referenceId.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CitizenReportDetailScreen(reportId: referenceId),
        ),
      );
      return;
    }

    if (referenceType == 'department_feed_post' && widget.onOpenFeed != null) {
      widget.onOpenFeed!.call();
      return;
    }

    if (referenceType == 'department_feed_post') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Open the News tab to review the latest department post.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(notificationInboxControllerProvider);
    final controller = ref.read(notificationInboxControllerProvider.notifier);
    final notifications = _filteredNotifications(inbox.notifications);
    final availableTypes = <String>{
      'all',
      ...inbox.notifications
          .map((notification) => (notification['type'] as String? ?? '').trim())
          .where((type) => type.isNotEmpty),
    }.toList(growable: false);
    final groupedNotifications = _groupNotifications(notifications);
    final heroNotification = notifications.firstWhere(
      (notification) => notification['is_read'] != true,
      orElse: () => notifications.isEmpty
          ? const <String, dynamic>{}
          : notifications.first,
    );

    return Scaffold(
      backgroundColor: dc.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => controller.refresh(),
          color: dc.primary,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
            children: [
              _NotificationHeader(
                embeddedInShell: widget.embeddedInShell,
                onBack: widget.embeddedInShell
                    ? null
                    : () => Navigator.of(context).maybePop(),
                onOpenProfile: _openProfile,
              ),
              const SizedBox(height: 14),
              _OperationalAlertCard(
                notification: heroNotification,
                unreadCount: inbox.unreadCount,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _FilterChip(
                            label: 'All',
                            selected: _readFilter == _NotificationReadFilter.all,
                            onTap: () => setState(
                              () => _readFilter = _NotificationReadFilter.all,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Unread',
                            selected:
                                _readFilter == _NotificationReadFilter.unread,
                            onTap: () => setState(
                              () => _readFilter = _NotificationReadFilter.unread,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Read',
                            selected: _readFilter == _NotificationReadFilter.read,
                            onTap: () => setState(
                              () => _readFilter = _NotificationReadFilter.read,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (inbox.unreadCount > 0) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: controller.markAllRead,
                      child: const Text('Mark all read'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _SearchField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _searchQuery = value),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _RefreshButton(onTap: () => controller.refresh()),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    final type = availableTypes[index];
                    return _FilterChip(
                      label: type == 'all' ? 'Category' : _labelize(type),
                      selected: _typeFilter == type,
                      onTap: () => setState(() => _typeFilter = type),
                    );
                  },
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemCount: availableTypes.length,
                ),
              ),
              const SizedBox(height: 18),
              if (inbox.loading && inbox.notifications.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: CircularProgressIndicator(color: dc.primary),
                  ),
                )
              else if (inbox.notifications.isEmpty)
                const _EmptyStateCard(
                  title: 'No notifications yet.',
                  body: 'System alerts, report updates, and announcements will appear here.',
                )
              else if (notifications.isEmpty)
                const _EmptyStateCard(
                  title: 'No notifications match the current filters.',
                  body: 'Try another filter or search term to widen the inbox view.',
                )
              else
                for (final section in groupedNotifications.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      section.key,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF7A594A),
                        fontFamily: 'Georgia',
                      ),
                    ),
                  ),
                  for (final notification in section.value) ...[
                    _NotificationCard(
                      notification: notification,
                      onDelete: () => controller.deleteNotification(
                        (notification['id'] ?? '').toString(),
                      ),
                      onMarkRead: () => controller.markRead(
                        (notification['id'] ?? '').toString(),
                      ),
                      onTap: () => _handleTap(notification),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationHeader extends StatelessWidget {
  const _NotificationHeader({
    required this.embeddedInShell,
    required this.onOpenProfile,
    this.onBack,
  });

  final bool embeddedInShell;
  final VoidCallback? onBack;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack ?? () {},
          icon: Icon(
            embeddedInShell ? Icons.drag_handle_rounded : Icons.arrow_back_rounded,
            color: dc.primary,
          ),
          tooltip: embeddedInShell ? 'Notifications' : 'Back',
        ),
        const SizedBox(width: 2),
        const Expanded(
          child: Text(
            'Notifications',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: dc.primary,
              fontFamily: 'Georgia',
            ),
          ),
        ),
        _ProfileShortcut(onTap: onOpenProfile),
      ],
    );
  }
}

class _ProfileShortcut extends StatelessWidget {
  const _ProfileShortcut({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: dc.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: dc.warmBorder),
          ),
          child: const Icon(Icons.settings_outlined, color: dc.primary),
        ),
      ),
    );
  }
}

class _OperationalAlertCard extends StatelessWidget {
  const _OperationalAlertCard({
    required this.notification,
    required this.unreadCount,
  });

  final Map<String, dynamic> notification;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final title =
        (notification['title'] as String?)?.trim().isNotEmpty == true
        ? notification['title'] as String
        : 'Operational Alerts';
    final message =
        (notification['message'] as String?)?.trim().isNotEmpty == true
        ? notification['message'] as String
        : 'High-priority updates and report changes will surface here first.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4E9DF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7D6C8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF9F5B36),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.campaign_outlined, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'OPERATIONAL ALERTS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: Color(0xFFB06A49),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF7B5545),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: Color(0xFF8F7668),
                  ),
                ),
              ],
            ),
          ),
          if (unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE9D9),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$unreadCount new',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFA45B34),
                ),
              ),
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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: dc.warmBorder),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search_rounded, color: dc.onSurfaceVariant),
          hintText: 'Search notifications',
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: dc.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: dc.warmBorder),
          ),
          child: const Icon(Icons.tune_rounded, color: dc.primary),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? dc.primary : dc.surfaceContainerLow,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? dc.primary : dc.outlineVariant),
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
                color: selected ? dc.onPrimary : dc.onSurfaceVariant,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({required this.title, required this.body});

  final String title;
  final String body;

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
          const Icon(Icons.notifications_off_outlined, size: 38, color: dc.primary),
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
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onDelete,
    required this.onMarkRead,
    required this.onTap,
  });

  final Map<String, dynamic> notification;
  final VoidCallback onDelete;
  final VoidCallback onMarkRead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final type = (notification['type'] as String? ?? '').trim();
    final isRead = notification['is_read'] == true;
    final senderSeed =
        (notification['sender_name'] as String? ??
                notification['title'] as String? ??
                'G')
            .trim();
    final senderInitial = senderSeed.isEmpty
        ? 'G'
        : senderSeed.substring(0, 1).toUpperCase();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRead ? dc.surfaceContainerLowest : const Color(0xFFFFFBF8),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isRead ? dc.warmBorder : dc.primary.withValues(alpha: 0.16),
          ),
          boxShadow: !isRead
              ? const [
                  BoxShadow(
                    color: Color(0x0F9D5C34),
                    blurRadius: 14,
                    offset: Offset(0, 7),
                  ),
                ]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: isRead
                  ? const Color(0xFFF0ECE7)
                  : const Color(0xFFFFE7DA),
              child: Text(
                senderInitial,
                style: TextStyle(
                  color: isRead ? const Color(0xFF8C786D) : dc.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification['title'] as String? ?? '',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isRead ? FontWeight.w700 : FontWeight.w800,
                            color: dc.ink,
                          ),
                        ),
                      ),
                      Text(
                        _formatCardTime(notification['created_at'] as String? ?? ''),
                        style: const TextStyle(fontSize: 10, color: dc.mutedInk),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notification['message'] as String? ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: dc.mutedInk,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _TypePill(label: _labelize(type), color: _typeColor(type)),
                      if ((notification['reference_type'] as String? ?? '').trim().isNotEmpty)
                        _TypePill(
                          label: _referenceLabel(notification),
                          color: const Color(0xFFA78672),
                        ),
                      if (!isRead)
                        const _TypePill(label: 'NEW', color: dc.statusPending),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (!isRead)
                        TextButton(
                          onPressed: onMarkRead,
                          child: const Text('Mark read'),
                        ),
                      const Spacer(),
                      IconButton(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline_rounded),
                        tooltip: 'Delete notification',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.label, required this.color});

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
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

Map<String, List<Map<String, dynamic>>> _groupNotifications(
  List<Map<String, dynamic>> notifications,
) {
  final grouped = <String, List<Map<String, dynamic>>>{};
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  for (final notification in notifications) {
    final parsed = DateTime.tryParse(
      (notification['created_at'] as String? ?? '').trim(),
    )?.toLocal();
    final key = switch (parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day)) {
      final date when date == today => 'Today, ${DateFormat('MMMM d').format(today)}',
      final date when date == yesterday =>
        'Yesterday, ${DateFormat('MMMM d').format(yesterday)}',
      final date? => DateFormat('EEEE, MMMM d').format(date),
      null => 'Earlier Updates',
    };
    grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(notification);
  }

  return grouped;
}

String _referenceLabel(Map<String, dynamic> notification) {
  final referenceType = (notification['reference_type'] as String? ?? '').trim();
  final referenceId = (notification['reference_id'] as String? ?? '').trim();
  if (referenceType == 'report' && referenceId.isNotEmpty) {
    return 'REPORT #${referenceId.length <= 8 ? referenceId.toUpperCase() : referenceId.substring(0, 8).toUpperCase()}';
  }
  return _labelize(referenceType);
}

Color _typeColor(String type) {
  return switch (type) {
    'new_report' => const Color(0xFFB35E38),
    'report_update' => const Color(0xFF5D7C97),
    'verification_decision' => const Color(0xFF7D5EA1),
    'announcement' => const Color(0xFFA45B34),
    _ => const Color(0xFF8C786D),
  };
}

String _formatCardTime(String value) {
  final parsed = DateTime.tryParse(value)?.toLocal();
  if (parsed == null) {
    return value;
  }
  return DateFormat('hh:mm a').format(parsed);
}

String _labelize(String value) {
  return value
      .replaceAll('_', ' ')
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map(
        (part) =>
            '${part.substring(0, 1).toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}
