import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/services/session_storage.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCitizenProfileAuthService extends AuthService {
  bool logoutCalled = false;
  bool updateProfileMultipartCalled = false;
  bool lastRemoveProfilePicture = false;
  bool lastRemoveHeaderPhoto = false;

  Map<String, dynamic> _profile = {
    'id': 'citizen-user-1',
    'full_name': 'Sarah L.',
    'phone': '+15550082',
    'description': 'Coordinates the neighborhood river watch.',
    'profile_picture': '',
    'header_photo': '',
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
      'status': 'accepted',
      'created_at': DateTime.now()
          .subtract(const Duration(days: 2))
          .toIso8601String(),
    },
  ];

  @override
  Future<Map<String, dynamic>> getProfile() async => {'profile': _profile};

  @override
  Future<List<dynamic>> getReports({String? status, String? category}) async =>
      _reports;

  @override
  Future<Map<String, dynamic>> getNotifications() async {
    return {'notifications': const <Map<String, dynamic>>[], 'unread_count': 2};
  }

  @override
  Future<Map<String, dynamic>> updateProfileMultipart({
    String? fullName,
    String? phone,
    String? description,
    profilePicture,
    headerPhoto,
    bool removeProfilePicture = false,
    bool removeHeaderPhoto = false,
  }) async {
    updateProfileMultipartCalled = true;
    lastRemoveProfilePicture = removeProfilePicture;
    lastRemoveHeaderPhoto = removeHeaderPhoto;
    final nextProfile = <String, dynamic>{..._profile};
    if (fullName != null) {
      nextProfile['full_name'] = fullName;
    }
    if (phone != null) {
      nextProfile['phone'] = phone;
    }
    if (description != null) {
      nextProfile['description'] = description;
    }
    if (removeProfilePicture) {
      nextProfile['profile_picture'] = '';
    }
    if (removeHeaderPhoto) {
      nextProfile['header_photo'] = '';
    }
    _profile = nextProfile;
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
    required FakeCitizenProfileAuthService authService,
  }) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final transport = MeshTransportService(automaticLocationBeaconing: false);
    await transport.initialize();
    await transport.startDiscovery();

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
          realtimeServiceProvider.overrideWith((ref) => _FakeRealtimeService()),
        ],
        child: const MaterialApp(home: Scaffold(body: CitizenProfileScreen())),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('renders the citizen profile-first screen', (tester) async {
    final authService = FakeCitizenProfileAuthService();

    await pumpScreen(tester, authService: authService);
    await tester.scrollUntilVisible(
      find.text('QUICK LINKS'),
      250,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Citizen profile'), findsOneWidget);
    expect(find.text('Sarah L.'), findsOneWidget);
    expect(find.text('VERIFIED CITIZEN'), findsOneWidget);
    expect(
      find.text('Coordinates the neighborhood river watch.'),
      findsOneWidget,
    );
    expect(find.text('QUICK LINKS'), findsOneWidget);
  });

  testWidgets('opens the full-screen edit profile flow and saves updates', (
    tester,
  ) async {
    final authService = FakeCitizenProfileAuthService();

    await pumpScreen(tester, authService: authService);

    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Profile'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).at(0), 'Sarah Lopez');
    await tester.enterText(
      find.byType(EditableText).at(2),
      'Keeps the river watch team coordinated.',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(authService.updateProfileMultipartCalled, isTrue);
    expect(find.text('Sarah Lopez'), findsOneWidget);
    expect(
      find.text('Keeps the river watch team coordinated.'),
      findsOneWidget,
    );
  });

  testWidgets('signs the citizen out from the footer action', (tester) async {
    final authService = FakeCitizenProfileAuthService();

    await pumpScreen(tester, authService: authService);
    await tester.scrollUntilVisible(
      find.text('Sign out of Mesh'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // Ensure fully on-screen before tapping (sign-out button may be near edge)
    await Scrollable.ensureVisible(
      tester.element(find.text('Sign out of Mesh')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out of Mesh'));
    await tester.pumpAndSettle();

    expect(authService.logoutCalled, isTrue);
  });

  testWidgets(
    'remove profile picture flag is sent when user taps Remove',
    (tester) async {
      final authService = FakeCitizenProfileAuthService();
      authService._profile = {
        ...authService._profile,
        'profile_picture': 'https://example.com/pic.jpg',
      };

      await pumpScreen(tester, authService: authService);

      await tester.tap(find.text('Edit profile'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Profile'), findsOneWidget);

      // 'Remove' buttons: index 0 = header photo, index 1 = profile picture
      await tester.tap(find.text('Remove').at(1));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(authService.updateProfileMultipartCalled, isTrue);
      expect(authService.lastRemoveProfilePicture, isTrue);
    },
  );
}
