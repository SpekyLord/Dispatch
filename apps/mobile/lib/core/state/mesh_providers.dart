import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/mesh_inbox_storage.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/sar_mode_service.dart';
import 'package:dispatch_mobile/core/services/sar_platform_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final meshInboxStorageProvider = Provider<MeshInboxStorage>((ref) {
  return MeshInboxStorage();
});

final meshTransportProvider = Provider<MeshTransportService>((ref) {
  final transport = MeshTransportService(
    inboxStorage: ref.read(meshInboxStorageProvider),
    locationService: ref.read(locationServiceProvider),
  );
  ref.onDispose(transport.dispose);
  return transport;
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
