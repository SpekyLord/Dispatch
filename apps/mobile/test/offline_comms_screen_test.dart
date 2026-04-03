import 'dart:convert';

import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/mesh_inbox_storage.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/session_storage.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/mesh/presentation/offline_comms_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeOfflineCommsAuthService extends AuthService {
  FakeOfflineCommsAuthService({
    this.meshMessagesResponse = const {'messages': [], 'mesh_posts': []},
    this.reports = const [],
  }) : super();

  final Map<String, dynamic> meshMessagesResponse;
  final List<dynamic> reports;
  List<Map<String, dynamic>>? lastIngestedPackets;
  Map<String, dynamic>? lastTopologySnapshot;

  @override
  Future<Map<String, dynamic>> getMeshMessages({
    String? threadId,
    bool includePosts = false,
  }) async {
    return meshMessagesResponse;
  }

  @override
  Future<Map<String, dynamic>> ingestMeshPackets(
    List<Map<String, dynamic>> packets, {
    Map<String, dynamic>? topologySnapshot,
  }) async {
    lastIngestedPackets = packets;
    lastTopologySnapshot = topologySnapshot;
    return {
      'acks': packets
          .map((packet) => {'messageId': packet['messageId'] as String? ?? ''})
          .toList(growable: false),
    };
  }

  @override
  Future<List<dynamic>> getReports() async => reports;
}

class InMemoryMeshInboxStorage extends MeshInboxStorage {
  final List<Map<String, dynamic>> _items = [];

  @override
  Future<List<Map<String, dynamic>>> load() async {
    return _items.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  @override
  Future<void> save(List<Map<String, dynamic>> items) async {
    _items
      ..clear()
      ..addAll(items.map((item) => Map<String, dynamic>.from(item)));
  }

  @override
  Future<void> clear() async {
    _items.clear();
  }
}

class FakeSessionController extends SessionController {
  FakeSessionController(SessionState state)
    : super(_NoopSessionStorage(state), AuthService()) {
    this.state = state;
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

SessionState buildSession({required AppRole role, DepartmentInfo? department}) {
  return SessionState(
    accessToken: 'access-token',
    userId: 'user-1',
    email: 'user@example.com',
    role: role,
    fullName: role == AppRole.department ? 'Responder Aya' : 'Citizen Sam',
    department: department,
    offlineVerificationToken: _validOfflineToken(),
  );
}

String _validOfflineToken() {
  final header = base64Url
      .encode(utf8.encode('{"alg":"HS256","typ":"JWT"}'))
      .replaceAll('=', '');
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'exp': DateTime.utc(2038, 1, 1).millisecondsSinceEpoch ~/ 1000,
          }),
        ),
      )
      .replaceAll('=', '');
  return '$header.$payload.signature';
}

Future<void> pumpOfflineCommsScreen(
  WidgetTester tester, {
  required MeshTransportService transport,
  required AuthService authService,
  required SessionState sessionState,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(authService),
        meshTransportProvider.overrideWithValue(transport),
        sessionControllerProvider.overrideWith(
          (ref) => FakeSessionController(sessionState),
        ),
      ],
      child: const MaterialApp(home: OfflineCommsScreen()),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('renders the Offline Comms panel shell', (tester) async {
    final transport = MeshTransportService(
      inboxStorage: InMemoryMeshInboxStorage(),
    );
    addTearDown(transport.dispose);

    await pumpOfflineCommsScreen(
      tester,
      transport: transport,
      authService: FakeOfflineCommsAuthService(),
      sessionState: buildSession(
        role: AppRole.department,
        department: const DepartmentInfo(
          id: 'dept-1',
          name: 'Rescue Unit',
          type: 'rescue',
          verificationStatus: 'verified',
        ),
      ),
    );

    expect(find.text('Offline Comms'), findsOneWidget);
    expect(find.text('Mesh-Routed Communications'), findsOneWidget);
    expect(find.text('Compose'), findsOneWidget);
    expect(find.text('Broadcast'), findsOneWidget);
    expect(find.text('Mesh Post'), findsOneWidget);
  });

  testWidgets(
    'queues a broadcast mesh message from the Offline Comms composer',
    (tester) async {
      final transport = MeshTransportService(
        inboxStorage: InMemoryMeshInboxStorage(),
      );
      addTearDown(transport.dispose);

      await pumpOfflineCommsScreen(
        tester,
        transport: transport,
        authService: FakeOfflineCommsAuthService(),
        sessionState: buildSession(role: AppRole.citizen),
      );

      await tester.enterText(
        find.byType(TextField).first,
        'Medic team is heading toward the riverside shelter.',
      );
      final sendButton = find.byType(FilledButton).first;
      final composeButton = tester.widget<FilledButton>(sendButton);
      composeButton.onPressed!.call();
      await tester.pump();

      expect(transport.queueSize, 1);
      expect(
        transport.inboxItems.any(
          (item) =>
              item.body ==
              'Medic team is heading toward the riverside shelter.',
        ),
        isTrue,
      );
      expect(
        find.text(
          'Medic team is heading toward the riverside shelter.',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('sync uploads topology snapshot together with queued packets', (
    tester,
  ) async {
    final transport = MeshTransportService(
      inboxStorage: InMemoryMeshInboxStorage(),
    );
    addTearDown(transport.dispose);
    final auth = FakeOfflineCommsAuthService();
    final localFingerprint = MeshTransportService.anonymizeDeviceFingerprint(
      transport.localDeviceId,
    );
    transport.ingestServerLastSeen([
      {
        'message_id': 'local-beacon-1',
        'device_fingerprint': localFingerprint,
        'location': {'lat': 14.6123, 'lng': 120.9821, 'accuracyMeters': 6.0},
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
      },
    ]);

    await pumpOfflineCommsScreen(
      tester,
      transport: transport,
      authService: auth,
      sessionState: buildSession(role: AppRole.citizen),
    );

    await tester.enterText(
      find.byType(TextField).first,
      'Topology sync payload check.',
    );
    final sendButton = find.byType(FilledButton).first;
    final composeButton = tester.widget<FilledButton>(sendButton);
    composeButton.onPressed!.call();
    await tester.pump();

    await tester.tap(find.byTooltip('Sync queued packets'));
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 150));

    expect(auth.lastIngestedPackets, isNotNull);
    expect(auth.lastIngestedPackets, isNotEmpty);
    expect(auth.lastTopologySnapshot, isNotNull);
    expect(auth.lastTopologySnapshot!['gateway'], isA<Map<String, dynamic>>());
    expect(auth.lastTopologySnapshot!['nodes'], isA<List<dynamic>>());
  });
}
