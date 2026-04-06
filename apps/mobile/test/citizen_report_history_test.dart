import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/session_storage.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCitizenHomeAuthService extends AuthService {
  @override
  Future<Map<String, dynamic>> getCitizenMeshFeedSnapshot() async {
    return {
      'posts': const <Map<String, dynamic>>[],
      'reports': const <Map<String, dynamic>>[],
      'mesh_messages': const <Map<String, dynamic>>[],
      'mesh_posts': const <Map<String, dynamic>>[],
      'topology_nodes': const <Map<String, dynamic>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> getNotifications() async {
    return {
      'notifications': const <Map<String, dynamic>>[],
      'unread_count': 0,
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
  Future<void> pumpScreen(WidgetTester tester) async {
    final authService = _FakeCitizenHomeAuthService();
    final transport = MeshTransportService(automaticLocationBeaconing: false);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWith((ref) => authService),
          sessionControllerProvider.overrideWith(
            (ref) => _FakeSessionController(authService),
          ),
          meshTransportProvider.overrideWith((ref) {
            ref.onDispose(() {}); // suppress framework double-dispose
            return transport;
          }),
        ],
        child: const MaterialApp(home: CitizenHomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('renders the current citizen shell tabs', (tester) async {
    await pumpScreen(tester);

    expect(find.text('MESH'), findsOneWidget);
    expect(find.text('MAP'), findsOneWidget);
    expect(find.text('FEED'), findsOneWidget);
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('Submit\nReport'), findsOneWidget);
  });

  testWidgets('opens the feed tab from the current tabbed shell', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('FEED'));
    await tester.pumpAndSettle();

    expect(find.text('Citizen feed'), findsOneWidget);
    expect(find.text('News'), findsOneWidget);
    expect(find.text('My Reports'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);
  });
}
