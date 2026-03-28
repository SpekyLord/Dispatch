import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/session_controller.dart';
import 'package:dispatch_mobile/features/department/presentation/department_report_detail_screen.dart';
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

class FakeDepartmentAuthService extends AuthService {
  FakeDepartmentAuthService() : super();

  int acceptCalls = 0;
  final List<String> updatedStatuses = [];

  Map<String, dynamic> _report = {
    'id': 'report-12345',
    'title': 'Factory Fire',
    'description': 'Heavy smoke coming from the loading bay.',
    'category': 'fire',
    'severity': 'high',
    'status': 'pending',
    'address': 'Industrial Road',
    'is_escalated': false,
    'image_urls': <String>[],
  };

  List<Map<String, dynamic>> _history = [
    {
      'new_status': 'pending',
      'notes': 'Report created.',
      'created_at': '2026-03-29T05:00:00Z',
    },
  ];

  List<Map<String, dynamic>> _responses = [
    {
      'department_name': 'BFP Alpha',
      'department_type': 'fire',
      'state': 'pending',
      'is_requesting_department': true,
    },
  ];

  @override
  Future<Map<String, dynamic>> getReport(String reportId) async {
    return {
      'report': _report,
      'status_history': _history,
    };
  }

  @override
  Future<Map<String, dynamic>> getReportResponses(String reportId) async {
    return {'responses': _responses};
  }

  @override
  Future<Map<String, dynamic>> acceptReport(String reportId, {String? notes}) async {
    acceptCalls += 1;
    _report = {..._report, 'status': 'accepted'};
    _responses = [
      {
        'department_name': 'BFP Alpha',
        'department_type': 'fire',
        'state': 'accepted',
        'is_requesting_department': true,
      },
    ];
    _history = [
      ..._history,
      {
        'new_status': 'accepted',
        'notes': 'Department accepted the incident.',
        'created_at': '2026-03-29T05:02:00Z',
      },
    ];
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> updateReportStatus(
    String reportId, {
    required String status,
    String? notes,
  }) async {
    updatedStatuses.add(status);
    _report = {..._report, 'status': status};
    _history = [
      ..._history,
      {
        'new_status': status,
        'notes': 'Status changed to $status.',
        'created_at': '2026-03-29T05:05:00Z',
      },
    ];
    return {'ok': true};
  }
}

void main() {
  testWidgets('department can accept a report and move it to responding', (tester) async {
    final auth = FakeDepartmentAuthService();
    final realtime = FakeRealtimeService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          realtimeServiceProvider.overrideWithValue(realtime),
        ],
        child: const MaterialApp(
          home: DepartmentReportDetailScreen(reportId: 'report-12345'),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Factory Fire'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(auth.acceptCalls, 1);
    expect(find.text('You accepted this report'), findsOneWidget);
    expect(find.text('Mark Responding'), findsOneWidget);

    await tester.tap(find.text('Mark Responding'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(auth.updatedStatuses, ['responding']);
    expect(find.text('Mark Resolved'), findsOneWidget);
  });
}
