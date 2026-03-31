import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

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
    ),
  ];
}
