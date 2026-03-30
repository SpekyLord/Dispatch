import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/sar_mode_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final meshTransportProvider = Provider<MeshTransportService>((ref) {
  final transport = MeshTransportService();
  ref.onDispose(transport.dispose);
  return transport;
});

final sarModeControllerProvider =
    StateNotifierProvider<SarModeController, SarModeState>((ref) {
      return SarModeController(transport: ref.read(meshTransportProvider));
    });
