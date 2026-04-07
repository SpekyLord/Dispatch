import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/services/session_storage.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_report_detail_screen.dart';
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
  int markAllCalls = 0;
  int deleteCalls = 0;

  List<Map<String, dynamic>> notifications = [
    {
      'id': 'notif-1',
      'type': 'report_update',
      'title': 'Responder assigned',
      'message': 'A responder has accepted your incident.',
      'is_read': false,
      'created_at': '2026-03-29T05:10:00Z',
      'reference_type': 'report',
      'reference_id': 'report-1',
    },
    {
      'id': 'notif-2',
      'type': 'announcement',
      'title': 'Flood advisory',
      'message': 'Water levels are rising near the river.',
      'is_read': true,
      'created_at': '2026-03-29T05:20:00Z',
      'reference_type': 'department_feed_post',
      'reference_id': '',
    },
  ];

  @override
  Future<Map<String, dynamic>> getNotifications() async {
    return {
      'notifications': notifications,
      'unread_count': notifications
          .where((notification) => notification['is_read'] != true)
          .length,
    };
  }

  @override
  Future<void> markAllNotificationsRead() async {
    markAllCalls += 1;
    notifications = notifications
        .map((notification) => {...notification, 'is_read': true})
        .toList();
  }

  @override
  Future<void> markNotificationRead(String notificationId) async {
    notifications = [
      for (final notification in notifications)
        if (notification['id'] == notificationId)
          {...notification, 'is_read': true}
        else
          notification,
    ];
  }

  @override
  Future<void> deleteNotification(String notificationId) async {
    deleteCalls += 1;
    notifications = [
      for (final notification in notifications)
        if (notification['id'] != notificationId) notification,
    ];
  }

  @override
  Future<Map<String, dynamic>> getReport(String reportId) async {
    return {
      'report': {
        'id': reportId,
        'category': 'flood',
        'status': 'responding',
        'severity': 'high',
        'description': 'Responders are on the way.',
      },
      'timeline': const <Map<String, dynamic>>[],
    };
  }
}

class _FakeSessionController extends SessionController {
  _FakeSessionController(AuthService authService)
      : super(
          _NoopSessionStorage(
            const SessionState(
              accessToken: 'token',
              userId: 'citizen-1',
              email: 'citizen@example.com',
              role: AppRole.citizen,
              fullName: 'Citizen One',
            ),
          ),
          authService,
        );
}

class _NoopSessionStorage extends SessionStorage {
  _NoopSessionStorage(this._state);

  final SessionState _state;

  @override
  Future<void> clear() async {}

  @override
  Future<SessionState> load() async => _state;

  @override
  Future<void> save(SessionState state) async {}
}

void main() {
  testWidgets(
    'notifications support filters, mark-all-read, delete, and realtime refresh',
    (tester) async {
      final auth = FakeNotificationsAuthService();
      final realtime = FakeRealtimeService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWith((ref) => auth),
            sessionControllerProvider.overrideWith(
              (ref) => _FakeSessionController(auth),
            ),
            realtimeServiceProvider.overrideWith((ref) => realtime),
          ],
          child: const MaterialApp(home: NotificationsScreen()),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.textContaining('March 29'), findsOneWidget);
      expect(find.text('Responder assigned'), findsNWidgets(2));
      expect(find.text('Flood advisory'), findsOneWidget);
      expect(find.text('Mark all read'), findsOneWidget);

      await tester.tap(find.text('Unread'));
      await tester.pumpAndSettle();
      expect(find.text('Responder assigned'), findsNWidgets(2));
      expect(find.text('Flood advisory'), findsNothing);

      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();
      expect(auth.markAllCalls, 1);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
      await tester.pumpAndSettle();
      expect(auth.deleteCalls, 1);

      auth.notifications = [
        ...auth.notifications,
        {
          'id': 'notif-3',
          'type': 'announcement',
          'title': 'Shelter update',
          'message': 'The high school gym is now open.',
          'is_read': false,
          'created_at': '2026-03-29T05:30:00Z',
          'reference_type': 'department_feed_post',
          'reference_id': '',
        },
      ];

      realtime.emit('notifications');
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Shelter update'), findsNWidgets(2));
    },
  );

  testWidgets(
    'tapping a report notification navigates to CitizenReportDetailScreen',
    (tester) async {
      final auth = FakeNotificationsAuthService();
      final realtime = FakeRealtimeService();

      auth.notifications = [
        {
          'id': 'notif-report',
          'type': 'report_update',
          'title': 'Your report was accepted',
          'message': 'A responder has been assigned.',
          'is_read': false,
          'created_at': '2026-03-29T06:00:00Z',
          'reference_type': 'report',
          'reference_id': 'report-99',
        },
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWith((ref) => auth),
            sessionControllerProvider.overrideWith(
              (ref) => _FakeSessionController(auth),
            ),
            realtimeServiceProvider.overrideWith((ref) => realtime),
          ],
          child: const MaterialApp(home: NotificationsScreen()),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Your report was accepted'), findsNWidgets(2));

      await tester.tap(find.text('Your report was accepted').last);
      await tester.pumpAndSettle();

      expect(find.byType(CitizenReportDetailScreen), findsOneWidget);
    },
  );
}
