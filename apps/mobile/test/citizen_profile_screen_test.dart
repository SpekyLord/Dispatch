import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/session_storage.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCitizenProfileAuthService extends AuthService {
  FakeCitizenProfileAuthService();

  bool logoutCalled = false;
  String? updatedFullName;
  String? updatedPhone;

  Map<String, dynamic> _profile = {
    'id': 'citizen-user-1',
    'full_name': 'Sarah L.',
    'phone': '+15550082',
    'avatar_url': '',
  };

  final List<Map<String, dynamic>> _reports = [
    {
      'id': 'r1',
      'status': 'resolved',
      'created_at': DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String(),
    },
    {
      'id': 'r2',
      'status': 'resolved',
      'created_at': DateTime.now()
          .subtract(const Duration(days: 2))
          .toIso8601String(),
    },
    {
      'id': 'r3',
      'status': 'accepted',
      'created_at': DateTime.now()
          .subtract(const Duration(days: 3))
          .toIso8601String(),
    },
    {
      'id': 'r4',
      'status': 'pending',
      'created_at': DateTime.now()
          .subtract(const Duration(days: 12))
          .toIso8601String(),
    },
  ];

  @override
  Future<Map<String, dynamic>> getProfile() async => {'profile': _profile};

  @override
  Future<List<dynamic>> getReports() async => _reports;

  @override
  Future<Map<String, dynamic>> updateProfile({
    String? fullName,
    String? phone,
  }) async {
    updatedFullName = fullName ?? updatedFullName;
    updatedPhone = phone ?? updatedPhone;
    _profile = {
      ..._profile,
      if (fullName != null) 'full_name': fullName,
      if (phone != null) 'phone': phone,
    };
    return {'profile': _profile};
  }

  @override
  Future<void> logout() async {
    logoutCalled = true;
  }
}

class _FakeSessionController extends SessionController {
  _FakeSessionController(AuthService authService)
    : super(
        _NoopSessionStorage(
          const SessionState(
            accessToken: 'token',
            userId: 'citizen-user-1',
            email: 'sarah@example.com',
            role: AppRole.citizen,
            fullName: 'Sarah L.',
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
  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeCitizenProfileAuthService authService,
    required MeshTransportService transport,
  }) async {
    await transport.initialize();
    await transport.startDiscovery();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(authService),
          sessionControllerProvider.overrideWith(
            (ref) => _FakeSessionController(authService),
          ),
          meshTransportProvider.overrideWithValue(transport),
        ],
        child: const MaterialApp(home: Scaffold(body: CitizenProfileScreen())),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'renders the redesigned citizen settings screen with live stats',
    (tester) async {
      final authService = FakeCitizenProfileAuthService();
      final transport = MeshTransportService(automaticLocationBeaconing: false);
      addTearDown(transport.dispose);

      await pumpScreen(tester, authService: authService, transport: transport);

      expect(find.text('Sarah L.'), findsOneWidget);
      expect(find.text('VERIFIED CITIZEN'), findsOneWidget);
    },
  );

  testWidgets('updates the citizen name through the profile action', (
    tester,
  ) async {
    final authService = FakeCitizenProfileAuthService();
    final transport = MeshTransportService(automaticLocationBeaconing: false);
    addTearDown(transport.dispose);

    await pumpScreen(tester, authService: authService, transport: transport);
    await tester.scrollUntilVisible(
      find.text('Change Name'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Change Name'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Sarah Lopez');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(authService.updatedFullName, 'Sarah Lopez');
    expect(find.text('Sarah Lopez'), findsOneWidget);
  });

  testWidgets('signs the citizen out from the footer action', (tester) async {
    final authService = FakeCitizenProfileAuthService();
    final transport = MeshTransportService(automaticLocationBeaconing: false);
    addTearDown(transport.dispose);

    await pumpScreen(tester, authService: authService, transport: transport);
    await tester.scrollUntilVisible(
      find.text('Sign out of Mesh'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Sign out of Mesh'));
    await tester.pumpAndSettle();

    expect(authService.logoutCalled, isTrue);
  });
}
