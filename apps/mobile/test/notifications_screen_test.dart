import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/session_controller.dart';
import 'package:dispatch_mobile/features/shared/presentation/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRealtimeService extends RealtimeService {
  FakeRealtimeService()
      : super(
          config: const AppConfig(
            apiBaseUrl: '',
            supabaseAnonKey: '',
            supabaseUrl: '',
          ),
        );

  final Map<String, List<VoidCallback>> _listeners = {};

  @override
  RealtimeSubscriptionHandle subscribeToTable({
    required String table,
    String? eqColumn,
    Object? eqValue,
    required VoidCallback onChange,
  }) {
    final key = _subscriptionKey(table, eqColumn, eqValue);
    _listeners.putIfAbsent(key, () => []).add(onChange);
    return RealtimeSubscriptionHandle(() async {
      _listeners[key]?.remove(onChange);
    });
  }

  void emit(String table, {String? eqColumn, Object? eqValue}) {
    final callbacks = List<VoidCallback>.from(
      _listeners[_subscriptionKey(table, eqColumn, eqValue)] ?? const [],
    );
    for (final callback in callbacks) {
      callback();
    }
  }

  String _subscriptionKey(String table, String? eqColumn, Object? eqValue) {
    return '$table|${eqColumn ?? ''}|${eqValue ?? ''}';
  }
}

class FakeNotificationsAuthService extends AuthService {
  FakeNotificationsAuthService() : super();

  int markAllCalls = 0;

  List<Map<String, dynamic>> notifications = [
    {
      'id': 'notif-1',
      'type': 'report_update',
      'title': 'Responder assigned',
      'message': 'A responder has accepted your incident.',
      'is_read': false,
      'created_at': '2026-03-29T05:10:00Z',
    },
  ];

  @override
  Future<Map<String, dynamic>> getNotifications() async {
    return {
      'notifications': notifications,
      'unread_count': notifications.where((notification) => notification['is_read'] != true).length,
    };
  }

  @override
  Future<void> markAllNotificationsRead() async {
    markAllCalls += 1;
    notifications = notifications
        .map((notification) => {...notification, 'is_read': true})
        .toList();
  }
}

void main() {
  testWidgets('notifications can be marked read and refreshed by realtime events', (tester) async {
    final auth = FakeNotificationsAuthService();
    final realtime = FakeRealtimeService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          realtimeServiceProvider.overrideWithValue(realtime),
        ],
        child: const MaterialApp(home: NotificationsScreen()),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Responder assigned'), findsOneWidget);
    expect(find.text('Mark all read'), findsOneWidget);

    await tester.tap(find.text('Mark all read'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(auth.markAllCalls, 1);
    expect(find.text('Mark all read'), findsNothing);

    auth.notifications = [
      ...auth.notifications,
      {
        'id': 'notif-2',
        'type': 'announcement',
        'title': 'Flood advisory',
        'message': 'Water levels are rising near the river.',
        'is_read': false,
        'created_at': '2026-03-29T05:20:00Z',
      },
    ];

    realtime.emit('notifications');

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Flood advisory'), findsOneWidget);
    expect(find.text('Mark all read'), findsOneWidget);
  });
}
