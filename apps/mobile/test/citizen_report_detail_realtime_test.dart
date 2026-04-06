import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_report_detail_screen.dart';
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

class FakeCitizenDetailAuthService extends AuthService {
  FakeCitizenDetailAuthService() : super();

  int fetchCount = 0;

  Map<String, dynamic> _report = {
    'id': 'report-12345',
    'description': 'Smoke seen near the public market.',
    'category': 'fire',
    'severity': 'medium',
    'status': 'pending',
    'address': 'Public Market',
    'is_escalated': false,
    'image_urls': <String>[],
  };

  List<dynamic> _history = [
    {
      'new_status': 'pending',
      'notes': 'Report received.',
      'created_at': '2026-03-29T05:00:00Z',
    },
  ];

  List<dynamic> _departmentResponses = const <dynamic>[];

  @override
  Future<Map<String, dynamic>> getReport(String reportId) async {
    fetchCount++;
    return {
      'report': _report,
      'status_history': _history,
      'department_responses': _departmentResponses,
    };
  }

  void moveToResponding() {
    _report = {..._report, 'status': 'responding'};
    _history = [
      ..._history,
      {
        'new_status': 'responding',
        'notes': 'Responders are now en route.',
        'created_at': '2026-03-29T05:04:00Z',
      },
    ];
  }

  void addDepartmentResponse() {
    _departmentResponses = [
      ..._departmentResponses,
      {
        'notes': 'Unit 3 is on scene.',
        'department_name': 'Fire Station 3',
        'action': 'accepted',
        'created_at': '2026-03-29T05:10:00Z',
      },
    ];
  }
}

void main() {
  testWidgets(
    'citizen detail screen refreshes when realtime status changes arrive',
    (tester) async {
      final auth = FakeCitizenDetailAuthService();
      final realtime = FakeRealtimeService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWith((ref) => auth),
            realtimeServiceProvider.overrideWith((ref) => realtime),
          ],
          child: const MaterialApp(
            home: CitizenReportDetailScreen(reportId: 'report-12345'),
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Report received.'), findsOneWidget);

      auth.moveToResponding();
      realtime.emit(
        'report_status_history',
        eqColumn: 'report_id',
        eqValue: 'report-12345',
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Responders are now en route.'), findsOneWidget);
      expect(find.text('RESPONDING'), findsWidgets);
    },
  );

  testWidgets(
    'citizen detail screen refreshes when department_responses event fires',
    (tester) async {
      final auth = FakeCitizenDetailAuthService();
      final realtime = FakeRealtimeService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWith((ref) => auth),
            realtimeServiceProvider.overrideWith((ref) => realtime),
          ],
          child: const MaterialApp(
            home: CitizenReportDetailScreen(reportId: 'report-12345'),
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Report received.'), findsOneWidget);

      auth.addDepartmentResponse();
      realtime.emit(
        'department_responses',
        eqColumn: 'report_id',
        eqValue: 'report-12345',
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Unit 3 is on scene.'), findsOneWidget);
    },
  );

  testWidgets(
    'citizen detail screen re-fetches when notifications event fires',
    (tester) async {
      final auth = FakeCitizenDetailAuthService();
      final realtime = FakeRealtimeService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWith((ref) => auth),
            realtimeServiceProvider.overrideWith((ref) => realtime),
          ],
          child: const MaterialApp(
            home: CitizenReportDetailScreen(reportId: 'report-12345'),
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      final countBeforeEvent = auth.fetchCount;

      realtime.emit('notifications');

      await tester.pump();
      await tester.pumpAndSettle();

      expect(auth.fetchCount, greaterThan(countBeforeEvent));
    },
  );
}
