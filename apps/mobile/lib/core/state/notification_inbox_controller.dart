import 'dart:async';

import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationInboxState {
  const NotificationInboxState({
    this.loading = false,
    this.notifications = const <Map<String, dynamic>>[],
    this.unreadCount = 0,
  });

  final bool loading;
  final List<Map<String, dynamic>> notifications;
  final int unreadCount;

  NotificationInboxState copyWith({
    bool? loading,
    List<Map<String, dynamic>>? notifications,
    int? unreadCount,
  }) {
    return NotificationInboxState(
      loading: loading ?? this.loading,
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

final notificationInboxControllerProvider =
    StateNotifierProvider<NotificationInboxController, NotificationInboxState>((
      ref,
    ) {
      final controller = NotificationInboxController(ref);
      ref.listen<String?>(
        sessionControllerProvider.select((state) => state.accessToken),
        (previous, next) {
          unawaited(controller.handleSessionChanged());
        },
        fireImmediately: true,
      );
      return controller;
    });

class NotificationInboxController
    extends StateNotifier<NotificationInboxState> {
  NotificationInboxController(this._ref)
    : super(const NotificationInboxState());

  final Ref _ref;
  RealtimeSubscriptionHandle? _subscription;

  Future<void> handleSessionChanged() async {
    final session = _ref.read(sessionControllerProvider);
    await _subscription?.dispose();
    _subscription = null;

    if (!session.isAuthenticated || session.accessToken == null) {
      state = const NotificationInboxState();
      return;
    }

    _subscription = _ref
        .read(realtimeServiceProvider)
        .subscribeToTable(
          table: 'notifications',
          onChange: () {
            unawaited(refresh(showLoader: false));
          },
        );
    await refresh();
  }

  Future<void> refresh({bool showLoader = true}) async {
    if (showLoader) {
      state = state.copyWith(loading: true);
    }

    try {
      final response = await _ref.read(authServiceProvider).getNotifications();
      if (!mounted) {
        return;
      }

      final notifications =
          (response['notifications'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false);
      final unreadCount =
          response['unread_count'] as int? ??
          notifications.where((item) => item['is_read'] != true).length;
      state = NotificationInboxState(
        loading: false,
        notifications: notifications,
        unreadCount: unreadCount,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(loading: false);
    }
  }

  Future<void> markRead(String notificationId) async {
    final previous = state;
    state = state.copyWith(
      notifications: [
        for (final notification in state.notifications)
          if (notification['id'] == notificationId)
            {...notification, 'is_read': true}
          else
            notification,
      ],
      unreadCount:
          state.notifications.any(
            (notification) =>
                notification['id'] == notificationId &&
                notification['is_read'] != true,
          )
          ? (state.unreadCount - 1).clamp(0, state.unreadCount)
          : state.unreadCount,
    );

    try {
      await _ref.read(authServiceProvider).markNotificationRead(notificationId);
      await refresh(showLoader: false);
    } catch (_) {
      if (mounted) {
        state = previous;
      }
    }
  }

  Future<void> markAllRead() async {
    final previous = state;
    state = state.copyWith(
      notifications: [
        for (final notification in state.notifications)
          {...notification, 'is_read': true},
      ],
      unreadCount: 0,
    );

    try {
      await _ref.read(authServiceProvider).markAllNotificationsRead();
      await refresh(showLoader: false);
    } catch (_) {
      if (mounted) {
        state = previous;
      }
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    final previous = state;
    Map<String, dynamic>? target;
    for (final notification in state.notifications) {
      if (notification['id'] == notificationId) {
        target = notification;
        break;
      }
    }
    state = state.copyWith(
      notifications: [
        for (final notification in state.notifications)
          if (notification['id'] != notificationId) notification,
      ],
      unreadCount: target != null && target['is_read'] != true
          ? (state.unreadCount - 1).clamp(0, state.unreadCount)
          : state.unreadCount,
    );

    try {
      await _ref.read(authServiceProvider).deleteNotification(notificationId);
      await refresh(showLoader: false);
    } catch (_) {
      if (mounted) {
        state = previous;
      }
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.dispose());
    super.dispose();
  }
}
