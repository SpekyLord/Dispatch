import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/sar_mode_service.dart';
import 'package:dispatch_mobile/core/services/session_storage.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/mesh/presentation/mesh_status_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLocationService extends LocationService {
  @override
  Future<LocationData?> getCurrentPosition() async => const LocationData(
    latitude: 14.601,
    longitude: 120.982,
    accuracyMeters: 5,
  );
}

class _FakeMeshStatusAuthService extends AuthService {
  _FakeMeshStatusAuthService() : super();

  int ingestCalls = 0;
  List<Map<String, dynamic>>? lastIngestedPackets;
  Map<String, dynamic>? lastTopologySnapshot;

  @override
  Future<List<Map<String, dynamic>>> getSurvivorSignals({
    String? status,
    String? detectionMethod,
  }) async {
    return const [];
  }

  @override
  Future<Map<String, dynamic>> getMeshLastSeen() async {
    return const {'devices': []};
  }

  @override
  Future<Map<String, dynamic>> ingestMeshPackets(
    List<Map<String, dynamic>> packets, {
    Map<String, dynamic>? topologySnapshot,
  }) async {
    ingestCalls += 1;
    lastIngestedPackets = packets;
    lastTopologySnapshot = topologySnapshot;
    return const {'acks': []};
  }
}

class _FakeSessionController extends SessionController {
  _FakeSessionController(SessionState state)
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

void main() {
  testWidgets(
    'mesh status refresh uploads topology snapshot even when queue is empty',
    (tester) async {
      final auth = _FakeMeshStatusAuthService();
      final transport = MeshTransportService(
        locationService: _FakeLocationService(),
        automaticLocationBeaconing: false,
      );
      addTearDown(transport.dispose);

      final sarController = SarModeController(
        transport: transport,
        locationService: _FakeLocationService(),
      );

      final sessionState = SessionState(
        accessToken: 'access-token',
        userId: 'user-1',
        email: 'dept@example.com',
        role: AppRole.department,
        fullName: 'Responder One',
        department: const DepartmentInfo(
          id: 'dept-1',
          name: 'Rescue Unit',
          type: 'rescue',
          verificationStatus: 'approved',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWithValue(auth),
            meshTransportProvider.overrideWithValue(transport),
            sessionControllerProvider.overrideWith(
              (ref) => _FakeSessionController(sessionState),
            ),
            sarModeControllerProvider.overrideWith((ref) => sarController),
          ],
          child: const MaterialApp(home: MeshStatusScreen()),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 250));

      await tester.tap(find.byTooltip('Refresh mesh status'));
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 250));

      expect(auth.ingestCalls, greaterThanOrEqualTo(1));
      expect(auth.lastIngestedPackets, isNotNull);
      expect(auth.lastIngestedPackets, isEmpty);
      expect(auth.lastTopologySnapshot, isNotNull);
      expect(
        auth.lastTopologySnapshot!['gateway'],
        isA<Map<String, dynamic>>(),
      );
    },
  );
}
