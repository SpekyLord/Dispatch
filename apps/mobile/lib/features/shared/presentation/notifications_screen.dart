import 'dart:async';

import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  int _unreadCount = 0;
  RealtimeSubscriptionHandle? _subscription;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
    _subscription = ref
        .read(realtimeServiceProvider)
        .subscribeToTable(
          table: 'notifications',
          onChange: () {
            if (mounted) {
              _fetchNotifications(showLoader: false);
            }
          },
        );
  }

  @override
  void dispose() {
    final subscription = _subscription;
    if (subscription != null) {
      unawaited(subscription.dispose());
    }
    super.dispose();
  }

  Future<void> _fetchNotifications({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() => _loading = true);
    }
    try {
      final data = await ref.read(authServiceProvider).getNotifications();
      if (mounted) {
        setState(() {
          _notifications = (data['notifications'] as List)
              .cast<Map<String, dynamic>>();
          _unreadCount = data['unread_count'] as int? ?? 0;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && showLoader) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _markRead(String id) async {
    try {
      await ref.read(authServiceProvider).markNotificationRead(id);
      setState(() {
        final idx = _notifications.indexWhere((n) => n['id'] == id);
        if (idx >= 0) {
          _notifications[idx] = {..._notifications[idx], 'is_read': true};
          _unreadCount = (_unreadCount - 1).clamp(0, _unreadCount);
        }
      });
      await _fetchNotifications(showLoader: false);
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    try {
      await ref.read(authServiceProvider).markAllNotificationsRead();
      setState(() {
        _notifications = _notifications
            .map((n) => {...n, 'is_read': true})
            .toList();
        _unreadCount = 0;
      });
      await _fetchNotifications(showLoader: false);
    } catch (_) {}
  }

  IconData _typeIcon(String type) {
    return switch (type) {
      'new_report' => Icons.assignment,
      'report_update' => Icons.update,
      'verification_decision' => Icons.verified_user,
      'announcement' => Icons.campaign,
      _ => Icons.notifications,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
          ? const Center(child: Text('No notifications yet.'))
          : RefreshIndicator(
              onRefresh: () => _fetchNotifications(),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _notifications.length,
                itemBuilder: (context, index) {
                  final notification = _notifications[index];
                  final isRead = notification['is_read'] == true;
                  final type = notification['type'] as String? ?? '';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: isRead ? null : Colors.orange.shade50,
                    child: ListTile(
                      onTap: isRead
                          ? null
                          : () => _markRead(notification['id'] as String),
                      leading: CircleAvatar(
                        backgroundColor: isRead
                            ? Colors.grey.shade200
                            : Colors.orange.shade100,
                        child: Icon(
                          _typeIcon(type),
                          size: 20,
                          color: isRead ? Colors.grey : Colors.orange.shade800,
                        ),
                      ),
                      title: Text(
                        notification['title'] as String? ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isRead
                              ? FontWeight.normal
                              : FontWeight.w700,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          Text(
                            notification['message'] as String? ?? '',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            notification['created_at'] as String? ?? '',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      trailing: isRead
                          ? null
                          : Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFD97757),
                              ),
                            ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
