import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_my_reports_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_report_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMyReportsAuthService extends AuthService {
  _FakeMyReportsAuthService({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Future<List<dynamic>> getReports({String? status, String? category}) async {
    return rows;
  }

  @override
  Future<Map<String, dynamic>> getReport(String reportId) async {
    final report = rows.firstWhere((row) => row['id'] == reportId);
    return {'report': report, 'timeline': const <Map<String, dynamic>>[]};
  }

  @override
  Future<Map<String, dynamic>> getNotifications() async {
    return {
      'notifications': const <Map<String, dynamic>>[],
      'unread_count': 0,
    };
  }
}

class _FakeRealtimeService extends RealtimeService {
  _FakeRealtimeService()
      : super(
          config: const AppConfig(
            apiBaseUrl: '',
            supabaseAnonKey: '',
            supabaseUrl: '',
          ),
        );

  @override
  RealtimeSubscriptionHandle subscribeToTable({
    required String table,
    String? eqColumn,
    Object? eqValue,
    required VoidCallback onChange,
  }) {
    return RealtimeSubscriptionHandle.noop();
  }
}

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required AuthService authService,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWith((ref) => authService),
          realtimeServiceProvider.overrideWith((ref) => _FakeRealtimeService()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CitizenMyReportsScreen()),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('renders report cards, filters, and opens report detail', (tester) async {
    final auth = _FakeMyReportsAuthService(
      rows: [
        {
          'id': 'report-1',
          'title': 'Large Structural Fire',
          'description': 'Fire near the public market.',
          'category': 'fire',
          'severity': 'critical',
          'status': 'accepted',
          'address': 'Arlegui Street, Manila, Philippines',
          'created_at': '2026-04-07T08:45:00Z',
          'latitude': 14.5995,
          'longitude': 120.9842,
        },
        {
          'id': 'report-2',
          'title': 'Flash Flood Advisory',
          'description': 'Flooding reported near the bridge.',
          'category': 'flood',
          'severity': 'high',
          'status': 'pending',
          'address': 'España, Manila',
          'created_at': '2026-04-07T08:44:00Z',
        },
      ],
    );

    await pumpScreen(tester, authService: auth);

    expect(find.text('MY REPORTS'), findsOneWidget);
    expect(find.text('Large Structural Fire'), findsOneWidget);

    await tester.tap(find.text('Accepted'));
    await tester.pumpAndSettle();

    expect(find.text('Large Structural Fire'), findsOneWidget);
    expect(find.text('Flash Flood Advisory'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Structural');
    await tester.pumpAndSettle();

    expect(find.text('Large Structural Fire'), findsOneWidget);

    await tester.tap(find.text('Large Structural Fire'));
    await tester.pumpAndSettle();

    expect(find.byType(CitizenReportDetailScreen), findsOneWidget);
  });

  testWidgets('shows empty state when no reports match filters', (tester) async {
    final auth = _FakeMyReportsAuthService(
      rows: [
        {
          'id': 'report-1',
          'title': 'Medical Need',
          'description': 'Need supplies.',
          'category': 'medical',
          'severity': 'medium',
          'status': 'pending',
          'created_at': '2026-04-07T08:45:00Z',
        },
      ],
    );

    await pumpScreen(tester, authService: auth);

    await tester.tap(find.text('Resolved'));
    await tester.pumpAndSettle();

    expect(find.text('No reports match this command view'), findsOneWidget);
  });
}
