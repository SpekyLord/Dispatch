import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

class DispatchOfflineTileRegion {
  const DispatchOfflineTileRegion({
    required this.name,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.cacheBudgetMegabytes,
    this.minimumZoom = 12,
    this.maximumZoom = 18,
  });

  final String name;
  final double centerLatitude;
  final double centerLongitude;
  final int minimumZoom;
  final int maximumZoom;
  final int cacheBudgetMegabytes;
}

const dispatchOfflineTileRegions = <DispatchOfflineTileRegion>[
  DispatchOfflineTileRegion(
    name: 'Metro Manila',
    centerLatitude: 14.5995,
    centerLongitude: 120.9842,
    cacheBudgetMegabytes: 140,
  ),
  DispatchOfflineTileRegion(
    name: 'Cebu',
    centerLatitude: 10.3157,
    centerLongitude: 123.8854,
    cacheBudgetMegabytes: 90,
  ),
  DispatchOfflineTileRegion(
    name: 'Davao',
    centerLatitude: 7.1907,
    centerLongitude: 125.4553,
    cacheBudgetMegabytes: 90,
  ),
  DispatchOfflineTileRegion(
    name: 'Iloilo',
    centerLatitude: 10.7202,
    centerLongitude: 122.5621,
    cacheBudgetMegabytes: 80,
  ),
  DispatchOfflineTileRegion(
    name: 'Tacloban',
    centerLatitude: 11.2449,
    centerLongitude: 125.004,
    cacheBudgetMegabytes: 100,
  ),
];

class DispatchNetworkFirstTileProvider extends TileProvider {
  DispatchNetworkFirstTileProvider({
    this.localTileRootPath,
    this.connectTimeout = const Duration(seconds: 5),
    this.receiveTimeout = const Duration(seconds: 8),
  });

  final String? localTileRootPath;
  final Duration connectTimeout;
  final Duration receiveTimeout;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) {
      return NetworkImage(getTileUrl(coordinates, options));
    }

    final networkUrl = getTileUrl(coordinates, options);
    final localPath = _buildLocalTilePath(coordinates, options);
    return _DispatchNetworkFirstImageProvider(
      networkUrl: networkUrl,
      localPath: localPath,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
    );
  }

  String? _buildLocalTilePath(TileCoordinates coordinates, TileLayer options) {
    final root = localTileRootPath;
    if (root == null || root.trim().isEmpty) {
      return null;
    }
    final zoom =
        (options.zoomOffset +
                (options.zoomReverse
                    ? options.maxZoom - coordinates.z.toDouble()
                    : coordinates.z.toDouble()))
            .round();
    return '$root\\$zoom\\${coordinates.x}\\${coordinates.y}.png';
  }
}

class _DispatchNetworkFirstImageProvider
    extends ImageProvider<_DispatchNetworkFirstImageProvider> {
  const _DispatchNetworkFirstImageProvider({
    required this.networkUrl,
    required this.localPath,
    required this.connectTimeout,
    required this.receiveTimeout,
  });

  final String networkUrl;
  final String? localPath;
  final Duration connectTimeout;
  final Duration receiveTimeout;

  @override
  Future<_DispatchNetworkFirstImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<_DispatchNetworkFirstImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _DispatchNetworkFirstImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadCodec(key, decode),
      scale: 1,
      debugLabel: networkUrl,
    );
  }

  Future<ui.Codec> _loadCodec(
    _DispatchNetworkFirstImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await _loadBytes();
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  Future<Uint8List> _loadBytes() async {
    try {
      final client = HttpClient()..connectionTimeout = connectTimeout;
      try {
        final request = await client.getUrl(Uri.parse(networkUrl));
        final response = await request.close().timeout(receiveTimeout);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final builder = BytesBuilder(copy: false);
          await for (final chunk in response) {
            builder.add(chunk);
          }
          final bytes = builder.takeBytes();
          if (bytes.isNotEmpty) {
            return bytes;
          }
        }
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      // Fall back to local cached tiles when the network path fails.
    }

    final localPath = this.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      final file = File(localPath);
      if (await file.exists()) {
        return file.readAsBytes();
      }
    }

    return TileProvider.transparentImage;
  }

  @override
  bool operator ==(Object other) {
    return other is _DispatchNetworkFirstImageProvider &&
        other.networkUrl == networkUrl &&
        other.localPath == localPath;
  }

  @override
  int get hashCode => Object.hash(networkUrl, localPath);
}
