import 'package:flutter/material.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;

/// The free standard basemap used by Chetiwa.
///
/// OpenFreeMap serves MapLibre vector tiles, so this remains a regular
/// flutter_map child and can be composed with LibreWXR raster layers without
/// replacing the existing camera, gestures, markers, or radar cache.
final class OpenFreeMapLayer extends StatefulWidget {
  const OpenFreeMapLayer({
    this.fallbackColor = const Color(0xFF162B32),
    super.key,
  });

  static const attribution =
      'OpenFreeMap © OpenMapTiles · Data © OpenStreetMap';
  static const homepage = 'https://openfreemap.org/';
  static const styleUrl = 'https://tiles.openfreemap.org/styles/liberty';

  final Color fallbackColor;

  @override
  State<OpenFreeMapLayer> createState() => _OpenFreeMapLayerState();
}

final class _OpenFreeMapLayerState extends State<OpenFreeMapLayer> {
  late Future<vt.Style> _style = _readStyle();
  vt.Style? _loadedStyle;

  Future<vt.Style> _readStyle() async {
    final style = await vt.StyleReader(uri: OpenFreeMapLayer.styleUrl).read();
    if (mounted) {
      _loadedStyle = style;
    } else {
      // The network request may finish after Radar has been closed.
      style.dispose();
    }
    return style;
  }

  void _retry() {
    _loadedStyle?.dispose();
    _loadedStyle = null;
    setState(() => _style = _readStyle());
  }

  @override
  void dispose() {
    _loadedStyle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<vt.Style>(
    future: _style,
    builder: (context, snapshot) {
      final style = snapshot.data;
      if (style != null) {
        return vt.VectorTileLayer(
          key: const ValueKey('openfreemap-vector-layer'),
          theme: style.theme,
          tileProviders: style.providers,
          rasterSources: style.rasterSources,
          sprites: style.sprites,
          // Keep decoding away from the animation thread and bound both disk
          // and GPU memory on mid-range Android and iPhone devices.
          concurrency: 2,
          diskCacheMaximumSizeInBytes: 64 * 1024 * 1024,
          memoryCacheMaxBytes: 16 * 1024 * 1024,
          rasterCacheMaxBytes: 96 * 1024 * 1024,
          tileFadeDuration: const Duration(milliseconds: 120),
          labelFadeDuration: const Duration(milliseconds: 100),
        );
      }

      return ColoredBox(
        key: ValueKey(
          snapshot.hasError ? 'openfreemap-unavailable' : 'openfreemap-loading',
        ),
        color: widget.fallbackColor,
        child: snapshot.hasError
            ? Center(
                child: IconButton(
                  key: const Key('openfreemap-retry'),
                  tooltip: MaterialLocalizations.of(
                    context,
                  ).refreshIndicatorSemanticLabel,
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              )
            : null,
      );
    },
  );
}
