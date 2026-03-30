import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Interactive map for selecting a location by tapping.
/// Returns the selected [LatLng] via [onLocationSelected].
class LocationPicker extends StatefulWidget {
  const LocationPicker({
    super.key,
    this.initialLatitude = 14.5995,
    this.initialLongitude = 120.9842,
    this.zoom = 13.0,
    this.height = 300,
    this.onLocationSelected,
  });

  final double initialLatitude;
  final double initialLongitude;
  final double zoom;
  final double height;
  final ValueChanged<LatLng>? onLocationSelected;

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  late LatLng _selected;

  @override
  void initState() {
    super.initState();
    _selected = LatLng(widget.initialLatitude, widget.initialLongitude);
  }

  void _handleTap(TapPosition tapPosition, LatLng point) {
    setState(() => _selected = point);
    widget.onLocationSelected?.call(point);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: _selected,
                initialZoom: widget.zoom,
                onTap: _handleTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.dispatch.mobile',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selected,
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
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_selected.latitude.toStringAsFixed(4)}, ${_selected.longitude.toStringAsFixed(4)}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
