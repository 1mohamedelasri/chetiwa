import 'package:flutter_test/flutter_test.dart';

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
}
