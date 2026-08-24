import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:chetiwa/features/radar/data/cache/radar_tile_cache.dart';

void main() {
  test('rejects non-image bytes before platform decoding', () {
    expect(
      RadarTileCache.isSupportedImageBytes(<int>[60, 104, 116, 109, 108]),
      isFalse,
    );
    expect(
      RadarTileCache.isSupportedImageBytes(<int>[
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0,
        0,
        0,
        0,
      ]),
      isTrue,
    );
  });

  test('metrics expose cache hit rate and unique tiles per session', () {
    final metrics = RadarTileMetrics();
    metrics.beginSession();
    metrics.recordCacheLookup('tile-a', hit: true);
    metrics.recordCacheLookup('tile-b', hit: false);
    metrics.recordDownload('tile-b', 128);
    metrics.recordDownload('tile-b', 128);

    final snapshot = metrics.snapshot();
    expect(snapshot.cacheHits, 1);
    expect(snapshot.cacheMisses, 1);
    expect(snapshot.cacheHitRate, 0.5);
    expect(snapshot.downloadedBytes, 256);
    expect(snapshot.downloadedTiles, 2);
    expect(snapshot.sessionTiles, 2);
  });

  test('first ready tile does not wait for a slow sibling', () async {
    final slow = Completer<bool>();

    final result = await RadarTileCache.firstReady([
      Future<bool>.delayed(const Duration(milliseconds: 5), () => true),
      slow.future,
    ]);

    expect(result, isTrue);
    slow.complete(false);
  });

  test('viewport prioritizes the tile under the map center', () {
    final camera = MapCamera(
      crs: const Epsg3857(),
      center: const LatLng(48.8566, 2.3522),
      zoom: 7,
      rotation: 0,
      nonRotatedSize: const Size(390, 500),
    );

    final urls = TileViewport.visibleTileUrls(
      camera,
      const ['https://tiles.test/{z}/{x}/{y}.png'],
      margin: 1,
      maxTiles: 4,
      maxZoom: 10,
    );

    expect(urls, hasLength(4));
    expect(urls.first, 'https://tiles.test/7/64/44.png');
  });
}
