import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/services/session_storage.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_department_profile_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_feed_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeFeedAuthService extends AuthService {
  int reactionCalls = 0;
  int commentCalls = 0;

  final Map<String, dynamic> _post = {
    'id': 'post-1',
    'title': 'Flood advisory',
    'content': 'Water levels are rising near the river.',
    'category': 'alert',
    'created_at': '2026-03-29T05:00:00Z',
    'reaction': 0,
    'comment_count': 0,
    'liked_by_me': false,
    'is_pinned': true,
    'image_urls': <String>[],
    'attachments': <String>[],
    'uploader': 'dept-1',
    'department': {
      'name': 'City Emergency',
      'description': 'Official city emergency department.',
      'profile_picture': null,
    },
  };

  final Map<String, dynamic> _report = {
    'id': 'report-1',
    'description': 'Fire near the market.',
    'category': 'fire',
    'severity': 'high',
    'status': 'pending',
    'address': 'Public Market',
    'is_escalated': false,
    'image_urls': <String>[],
  };

  @override
  Future<Map<String, dynamic>> getCitizenMeshFeedSnapshot() async {
    return {
      'posts': [_post],
      'reports': [_report],
      'mesh_messages': const <Map<String, dynamic>>[],
      'mesh_posts': const <Map<String, dynamic>>[],
      'topology_nodes': const <Map<String, dynamic>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> getMeshMessages({
    String? threadId,
    bool includePosts = false,
  }) async {
    return {'messages': const <Map<String, dynamic>>[]};
  }

  @override
  Future<Map<String, dynamic>> getMeshTopology() async {
    return {'nodes': const <Map<String, dynamic>>[]};
  }

  @override
  Future<Map<String, dynamic>> toggleFeedReaction(String postId) async {
    reactionCalls++;
    return {..._post, 'liked_by_me': true, 'reaction': 1};
  }

  @override
  Future<List<Map<String, dynamic>>> getFeedComments(String postId) async {
    return const <Map<String, dynamic>>[];
  }

  @override
  Future<Map<String, dynamic>> createFeedComment(
    String postId, {
    required String comment,
  }) async {
    commentCalls++;
    return {
      'id': 'comment-1',
      'comment': comment,
      'user_name': 'Test User',
      'created_at': '2026-03-29T06:00:00Z',
    };
  }

  @override
  Future<Map<String, dynamic>> getDepartmentPublicProfile(
    String uploaderId,
  ) async {
    return {
      'department': {
        'id': uploaderId,
        'name': 'City Emergency',
        'description': 'Official city emergency department.',
        'profile_picture': null,
      },
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getFeedPosts({
    String? category,
    String? uploader,
  }) async {
    return const <Map<String, dynamic>>[];
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

const _kFakeSession = SessionState(
  accessToken: 'token',
  userId: 'citizen-1',
  email: 'citizen@example.com',
  role: AppRole.citizen,
  fullName: 'Citizen One',
);

class _FakeSessionController extends SessionController {
  _FakeSessionController(AuthService authService)
    : super(_NoopSessionStorage(_kFakeSession), authService) {
    // Pre-populate state synchronously so _isCitizen is true on first frame.
    state = _kFakeSession;
  }
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<void> _pumpFeedScreen(
  WidgetTester tester, {
  required _FakeFeedAuthService auth,
}) async {
  tester.view.physicalSize = const Size(430, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final transport = MeshTransportService(automaticLocationBeaconing: false);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWith((ref) => auth),
        sessionControllerProvider.overrideWith(
          (ref) => _FakeSessionController(auth),
        ),
        realtimeServiceProvider.overrideWith((ref) => _FakeRealtimeService()),
        meshTransportProvider.overrideWith((ref) {
          ref.onDispose(() {}); // suppress framework double-dispose
          return transport;
        }),
      ],
      child: const MaterialApp(
        home: Scaffold(body: CitizenFeedScreen()),
      ),
    ),
  );

  await tester.pump();
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  testWidgets(
    'Feed renders News segment by default with post card',
    (tester) async {
      final auth = _FakeFeedAuthService();
      await _pumpFeedScreen(tester, auth: auth);

      expect(find.text('News'), findsOneWidget);
      expect(find.text('My Reports'), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Flood advisory'), findsOneWidget);
    },
  );

  testWidgets(
    'Tapping My Reports segment shows report list',
    (tester) async {
      final auth = _FakeFeedAuthService();
      await _pumpFeedScreen(tester, auth: auth);

      await tester.tap(find.text('My Reports'));
      await tester.pumpAndSettle();

      expect(find.text('Flood advisory'), findsNothing);
      // Report card renders with status label and category label (title-cased)
      expect(find.text('Pending'), findsWidgets);
      expect(find.text('Fire'), findsWidgets);
    },
  );

  testWidgets(
    'Reaction toggle calls toggleFeedReaction and updates icon',
    (tester) async {
      final auth = _FakeFeedAuthService();
      await _pumpFeedScreen(tester, auth: auth);

      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await tester.pumpAndSettle();

      expect(auth.reactionCalls, 1);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    },
  );

  testWidgets(
    'Comment icon opens sheet and posting calls createFeedComment',
    (tester) async {
      final auth = _FakeFeedAuthService();
      await _pumpFeedScreen(tester, auth: auth);

      await tester.tap(find.byIcon(Icons.mode_comment_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Comments'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Add a comment'),
        'Great update, thank you!',
      );
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(auth.commentCalls, 1);
    },
  );

  testWidgets(
    'Tapping publisher name navigates to CitizenDepartmentProfileScreen',
    (tester) async {
      final auth = _FakeFeedAuthService();
      await _pumpFeedScreen(tester, auth: auth);

      await tester.tap(find.text('City Emergency'));
      await tester.pumpAndSettle();

      expect(find.byType(CitizenDepartmentProfileScreen), findsOneWidget);
    },
  );
}
