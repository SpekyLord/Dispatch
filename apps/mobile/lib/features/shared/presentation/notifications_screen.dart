import 'package:dispatch_mobile/core/state/notification_inbox_controller.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:dispatch_mobile/features/citizen/presentation/citizen_report_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _NotificationReadFilter { all, unread, read }

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

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
    return notifications
        .where((notification) {
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
          final query = _searchQuery.trim().toLowerCase();
          if (query.isEmpty) {
            return true;
          }
          final haystack = [
            notification['title'] ?? '',
            notification['message'] ?? '',
            notification['type'] ?? '',
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _handleTap(Map<String, dynamic> notification) async {
    final controller = ref.read(notificationInboxControllerProvider.notifier);
    final notificationId = (notification['id'] ?? '').toString();
    if (notificationId.isNotEmpty && notification['is_read'] != true) {
      await controller.markRead(notificationId);
    }

    final referenceType = (notification['reference_type'] as String? ?? '')
        .trim();
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

    if (referenceType == 'department_feed_post') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open the News tab to review the latest department post.',
          ),
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

    return Scaffold(
      backgroundColor: dc.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (inbox.unreadCount > 0)
            TextButton(
              onPressed: controller.markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => controller.refresh(),
        color: dc.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: dc.heroGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Response inbox',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${inbox.unreadCount} unread - ${inbox.notifications.length} total',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: dc.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search notifications',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
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
                    selected: _readFilter == _NotificationReadFilter.unread,
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
            const SizedBox(height: 10),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final type = availableTypes[index];
                  return _FilterChip(
                    label: type == 'all' ? 'All types' : _labelize(type),
                    selected: _typeFilter == type,
                    onTap: () => setState(() => _typeFilter = type),
                  );
                },
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemCount: availableTypes.length,
              ),
            ),
            const SizedBox(height: 16),
            if (inbox.loading && inbox.notifications.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: CircularProgressIndicator(color: dc.primary),
                ),
              )
            else if (notifications.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: dc.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text(
                  'No notifications match the current filters.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: dc.mutedInk),
                ),
              )
            else
              for (final notification in notifications) ...[
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? dc.primaryContainer : dc.surfaceContainerLow,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? dc.primary : dc.outlineVariant),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? dc.onPrimaryContainer : dc.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
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

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isRead ? dc.surfaceContainerLowest : dc.primaryContainer,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isRead ? dc.warmBorder : dc.primary.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: isRead
                  ? dc.surfaceContainerHigh
                  : dc.primary.withValues(alpha: 0.18),
              child: Icon(
                _typeIcon(type),
                color: isRead ? dc.mutedInk : dc.primary,
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
                            fontWeight: isRead
                                ? FontWeight.w700
                                : FontWeight.w800,
                            color: dc.ink,
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: dc.statusPending,
                            shape: BoxShape.circle,
                          ),
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
                  Row(
                    children: [
                      Text(
                        _labelize(type),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: dc.primary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        (notification['created_at'] as String? ?? '')
                            .replaceFirst('T', ' ')
                            .replaceFirst('Z', ''),
                        style: const TextStyle(
                          fontSize: 11,
                          color: dc.mutedInk,
                        ),
                      ),
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

IconData _typeIcon(String type) {
  return switch (type) {
    'new_report' => Icons.assignment_outlined,
    'report_update' => Icons.update_rounded,
    'verification_decision' => Icons.verified_outlined,
    'announcement' => Icons.campaign_outlined,
    _ => Icons.notifications_none_rounded,
  };
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
