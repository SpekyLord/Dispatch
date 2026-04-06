import 'package:dispatch_mobile/core/state/citizen_ble_chat_session_controller.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/citizen_nearby_presence_controller.dart';
import 'package:dispatch_mobile/core/state/citizen_location_trail_controller.dart';
import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/mesh_gateway_sync_service.dart';
import 'package:dispatch_mobile/core/services/mesh_inbox_storage.dart';
import 'package:dispatch_mobile/core/services/mesh_platform_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/sar_mode_service.dart';
import 'package:dispatch_mobile/core/services/sar_platform_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final meshInboxStorageProvider = Provider<MeshInboxStorage>((ref) {
  return MeshInboxStorage();
});

final meshPlatformServiceProvider = Provider<MeshPlatformService>((ref) {
  final service = MethodChannelMeshPlatformService();
  ref.onDispose(service.dispose);
  return service;
});

final meshTransportProvider = ChangeNotifierProvider<MeshTransportService>((
  ref,
) {
  final transport = MeshTransportService(
    inboxStorage: ref.read(meshInboxStorageProvider),
    locationService: ref.read(locationServiceProvider),
    platform: ref.read(meshPlatformServiceProvider),
  );
  ref.onDispose(transport.dispose);
  return transport;
});

final meshGatewaySyncServiceProvider = Provider<MeshGatewaySyncService>((ref) {
  return MeshGatewaySyncService(
    authService: ref.read(authServiceProvider),
    transport: ref.read(meshTransportProvider),
  );
});

final sarPlatformServiceProvider = Provider<SarPlatformService>((ref) {
  final service = MethodChannelSarPlatformService();
  ref.onDispose(service.dispose);
  return service;
});

final sarModeControllerProvider =
    StateNotifierProvider<SarModeController, SarModeState>((ref) {
      return SarModeController(
        transport: ref.read(meshTransportProvider),
        locationService: ref.read(locationServiceProvider),
        platform: ref.read(sarPlatformServiceProvider),
      );
    });

final citizenLocationTrailControllerProvider =
    StateNotifierProvider<
      CitizenLocationTrailController,
      CitizenLocationTrailState
    >((ref) {
      return CitizenLocationTrailController(
        locationService: ref.read(locationServiceProvider),
      );
    });

final citizenNearbyPresenceControllerProvider =
    StateNotifierProvider<
      CitizenNearbyPresenceController,
      CitizenNearbyPresenceState
    >((ref) {
      return CitizenNearbyPresenceController(
        authService: ref.read(authServiceProvider),
        realtimeService: ref.read(realtimeServiceProvider),
        transport: ref.read(meshTransportProvider),
      );
    });

final citizenBleChatSessionControllerProvider =
    StateNotifierProvider<
      CitizenBleChatSessionController,
      CitizenBleChatSessionState
    >((ref) {
      return CitizenBleChatSessionController(
        authService: ref.read(authServiceProvider),
        realtimeService: ref.read(realtimeServiceProvider),
        transport: ref.read(meshTransportProvider),
      );
    });

final mapNodeOverlayActiveProvider = StateProvider<bool>((ref) => false);
