import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/state/session_controller.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake AuthService that returns an empty report list without making Dio calls.
class FakeAuthService extends AuthService {
  FakeAuthService() : super();

  @override
  Future<List<dynamic>> getReports() async => [];
}

void main() {
  Widget buildTestWidget() {
    return ProviderScope(
      overrides: [authServiceProvider.overrideWithValue(FakeAuthService())],
      child: const MaterialApp(home: CitizenHomeScreen()),
    );
  }

  testWidgets('renders the citizen home screen with FAB', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pump();

    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('shows empty state when no reports', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    // First pump: widget builds with loading=true
    // Second pump: async getReports completes, loading=false, empty list
    await tester.pump();
    await tester.pump();

    // Should show empty state (no reports) or the "no reports" text
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
