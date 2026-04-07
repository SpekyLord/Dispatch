import 'package:dispatch_mobile/features/shared/presentation/dispatch_network_first_tile_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

const dispatchOfflineTileCacheBudgetMegabytes = 500;
const dispatchOfflineTileLocalRootPath = String.fromEnvironment(
  'DISPATCH_OFFLINE_TILE_ROOT',
  defaultValue: '',
);

// Skip remote tiles in widget tests so map-heavy screens stay quiet and deterministic.
List<Widget> buildDispatchMapTileLayers() {
  final bindingName = WidgetsBinding.instance.runtimeType.toString();
  if (bindingName.contains('TestWidgetsFlutterBinding')) {
    return const [];
  }
  return [
    TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.dispatch.mobile',
      tileProvider: DispatchNetworkFirstTileProvider(
        localTileRootPath: dispatchOfflineTileLocalRootPath.isEmpty
            ? null
            : dispatchOfflineTileLocalRootPath,
      ),
      minZoom: dispatchOfflineTileRegions
          .map((region) => region.minimumZoom)
          .reduce((left, right) => left < right ? left : right)
          .toDouble(),
      maxZoom: dispatchOfflineTileRegions
          .map((region) => region.maximumZoom)
          .reduce((left, right) => left > right ? left : right)
          .toDouble(),
      panBuffer: kIsWeb ? 1 : 2,
    ),
  ];
}
