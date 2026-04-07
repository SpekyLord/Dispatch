import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_report_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
    return RealtimeSubscriptionHandle(() async {});
  }
}

class _FakeDetailAuthService extends AuthService {
  _FakeDetailAuthService({required this.report});

  final Map<String, dynamic> report;

  @override
  Future<Map<String, dynamic>> getReport(String reportId) async {
    return {
      'report': report,
      'status_history': const [
        {
          'new_status': 'pending',
          'notes': 'Report received.',
          'created_at': '2026-04-06T08:14:26Z',
        },
      ],
      'department_responses': const [
        {
          'department_name': 'MDRRMO',
          'action': 'accepted',
          'notes': 'Validation dispatched.',
          'responded_at': '2026-04-06T08:20:00Z',
        },
      ],
    };
  }
}

void main() {
  testWidgets('renders overview first and switches across local tabs', (
    tester,
  ) async {
    final auth = _FakeDetailAuthService(
      report: {
        'id': 'report-12345',
        'description': 'Residents reported smoke near the market.',
        'category': 'fire',
        'severity': 'high',
        'status': 'accepted',
        'address': 'Quintin Salas Street, Iloilo City, Philippines',
        'latitude': 10.7442,
        'longitude': 122.5590,
        'image_urls': const ['https://example.com/evidence-1.jpg'],
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWith((ref) => auth),
          realtimeServiceProvider.overrideWith((ref) => _FakeRealtimeService()),
        ],
        child: const MaterialApp(
          home: CitizenReportDetailScreen(reportId: 'report-12345'),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Fire'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('INCIDENT TYPE', skipOffstage: false), findsOneWidget);

    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();
    expect(find.text('Report Timeline'), findsOneWidget);
    expect(find.text('Accepted'), findsOneWidget);
    expect(find.text('INCIDENT TYPE', skipOffstage: false), findsOneWidget);

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    expect(find.text('Map'), findsWidgets);
    expect(
      find.text('Quintin Salas Street, Iloilo City, Philippines'),
      findsWidgets,
    );

    await tester.tap(find.text('Assets'));
    await tester.pumpAndSettle();
    expect(find.text('Assets'), findsWidgets);
  });

  testWidgets('shows empty states when map coordinates and assets are missing', (
    tester,
  ) async {
    final auth = _FakeDetailAuthService(
      report: {
        'id': 'report-empty-1',
        'description': 'No coordinates captured.',
        'category': 'other',
        'severity': 'medium',
        'status': 'pending',
        'address': '',
        'image_urls': const <String>[],
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWith((ref) => auth),
          realtimeServiceProvider.overrideWith((ref) => _FakeRealtimeService()),
        ],
        child: const MaterialApp(
          home: CitizenReportDetailScreen(reportId: 'report-empty-1'),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    expect(find.text('No GPS coordinates were attached to this report.'), findsOneWidget);

    await tester.tap(find.text('Assets'));
    await tester.pumpAndSettle();
    expect(find.text('No evidence assets were attached to this report.'), findsOneWidget);
  });
}
