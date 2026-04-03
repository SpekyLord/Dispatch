import 'package:dispatch_mobile/features/shared/presentation/dispatch_map_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Read-only map display with a single marker.
/// Mirrors the web LocationMap component.
class LocationMap extends StatelessWidget {
  const LocationMap({
    super.key,
    this.latitude = 14.5995,
    this.longitude = 120.9842,
    this.zoom = 13.0,
    this.height = 200,
  });

  final double latitude;
  final double longitude;
  final double zoom;
  final double height;

  @override
  Widget build(BuildContext context) {
    final center = LatLng(latitude, longitude);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: zoom,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            ...buildDispatchMapTileLayers(),
            MarkerLayer(
              markers: [
                Marker(
                  point: center,
                  width: 40,
                  height: 40,
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 40,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
