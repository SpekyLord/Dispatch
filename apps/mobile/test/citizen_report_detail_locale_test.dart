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

  @override
  RealtimeSubscriptionHandle subscribeToTable({
    required String table,
    String? eqColumn,
    Object? eqValue,
    required VoidCallback onChange,
  }) {
    return RealtimeSubscriptionHandle(() async {});
  }
}

class FakeCitizenReportAuthService extends AuthService {
  FakeCitizenReportAuthService() : super();

  @override
  Future<Map<String, dynamic>> getReport(String reportId) async {
    return {
      'report': {
        'id': reportId,
        'description': 'Residents reported rising floodwater near the bridge.',
        'category': 'flood',
        'severity': 'high',
        'status': 'pending',
        'address': 'Bridge Access Road',
        'is_escalated': true,
        'image_urls': <String>[],
      },
      'status_history': [
        {
          'new_status': 'pending',
          'notes': 'Report received.',
          'created_at': '2026-03-29T08:00:00Z',
        },
      ],
      'department_responses': [
        {
          'department_name': 'MDRRMO',
          'action': 'accepted',
          'notes': 'Rescue boat deployed.',
          'responded_at': '2026-03-29T08:10:00Z',
        },
      ],
    };
  }
}

void main() {
  testWidgets('citizen detail screen translates timeline labels and statuses', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWith(
            (ref) => FakeCitizenReportAuthService(),
          ),
          realtimeServiceProvider.overrideWith((ref) => FakeRealtimeService()),
        ],
        child: const MaterialApp(
          home: CitizenReportDetailScreen(reportId: 'report-12345'),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Status History'), findsOneWidget);
    expect(find.text('Department Responses'), findsOneWidget);
    expect(find.text('PENDING'), findsWidgets);
    expect(find.text('ACCEPTED'), findsWidgets);

    await tester.tap(find.byTooltip('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filipino'));
    await tester.pumpAndSettle();

    expect(find.text('Kasaysayan ng Status'), findsOneWidget);
    expect(find.text('Mga Tugon ng Departamento'), findsOneWidget);
    expect(find.text('NAKABINBIN'), findsWidgets);
    expect(find.text('TINANGGAP'), findsWidgets);
  });
}
