import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
    final urls = TileViewport.visibleTileUrls(
      centerLatitude: 48.8566,
      centerLongitude: 2.3522,
      north: 50,
      south: 47,
      east: 4,
      west: 0,
      zoom: 7,
      templates: const ['https://tiles.test/{z}/{x}/{y}.png'],
      margin: 1,
      maxTiles: 4,
      maxZoom: 10,
    );

    expect(urls, hasLength(4));
    expect(urls.first, 'https://tiles.test/7/64/44.png');
  });

  test('Google tile provider validates and reuses a downloaded PNG', () async {
    final directory = await Directory.systemTemp.createTemp(
      'chetiwa-radar-cache-test-',
    );
    addTearDown(() => _deleteDirectoryEventually(directory));
    var requests = 0;
    final png = <int>[
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
    ];
    final cache = RadarTileCache.forTesting(
      client: MockClient((_) async {
        requests++;
        return http.Response.bytes(png, 200);
      }),
      directory: directory,
    )..beginSession();
    final provider = cache.providerFor('https://tiles.test/{z}/{x}/{y}.png');

    final first = await provider.getTile(64, 44, 7);
    final second = await provider.getTile(64, 44, 7);

    expect(first.data, png);
    expect(second.data, png);
    expect(requests, 1);
    expect(cache.readyTileCount.value, 1);
  });

  test('Google tile provider overzooms the correct native z10 tile', () async {
    final directory = await Directory.systemTemp.createTemp(
      'chetiwa-radar-overzoom-test-',
    );
    addTearDown(() => _deleteDirectoryEventually(directory));
    final png = await _solidPngTile();
    final requestedUrls = <String>[];
    final cache = RadarTileCache.forTesting(
      client: MockClient((request) async {
        requestedUrls.add(request.url.toString());
        return http.Response.bytes(png, 200);
      }),
      directory: directory,
    )..beginSession();
    final provider = cache.providerFor('https://tiles.test/{z}/{x}/{y}.png');

    final tile = await provider.getTile(2056, 1408, 12);

    expect(tile.data, isNotNull);
    expect(requestedUrls, ['https://tiles.test/10/514/352.png']);
    final codec = await ui.instantiateImageCodec(tile.data!);
    addTearDown(codec.dispose);
    final frame = await codec.getNextFrame();
    addTearDown(frame.image.dispose);
    expect(frame.image.width, 256);
    expect(frame.image.height, 256);
  });

  test(
    'overzoom crops the requested quadrant instead of repeating its parent',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'chetiwa-radar-overzoom-quadrant-test-',
      );
      addTearDown(() => _deleteDirectoryEventually(directory));
      final png = await _quadrantPngTile();
      final cache = RadarTileCache.forTesting(
        client: MockClient((_) async => http.Response.bytes(png, 200)),
        directory: directory,
      )..beginSession();

      final tile = await cache
          .providerFor('https://tiles.test/{z}/{x}/{y}.png')
          .getTile(201, 201, 11);

      final codec = await ui.instantiateImageCodec(tile.data!);
      addTearDown(codec.dispose);
      final frame = await codec.getNextFrame();
      addTearDown(frame.image.dispose);
      final pixels = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(pixels!.buffer.asUint8List().take(4), [255, 255, 0, 255]);
    },
  );

  test('Google tile provider retries one transient 502', () async {
    final directory = await Directory.systemTemp.createTemp(
      'chetiwa-radar-retry-test-',
    );
    addTearDown(() => _deleteDirectoryEventually(directory));
    final png = await _solidPngTile();
    var requests = 0;
    final cache = RadarTileCache.forTesting(
      client: MockClient((_) async {
        requests++;
        return requests == 1
            ? http.Response('<html>temporary 502</html>', 502)
            : http.Response.bytes(png, 200);
      }),
      directory: directory,
    )..beginSession();

    final tile = await cache
        .providerFor('https://tiles.test/{z}/{x}/{y}.png')
        .getTile(64, 44, 7);

    expect(tile.data, png);
    expect(requests, 2);
  });

  test(
    'Google tile provider retries an HTML body returned as HTTP 200',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'chetiwa-radar-html-200-test-',
      );
      addTearDown(() => _deleteDirectoryEventually(directory));
      final png = await _solidPngTile();
      var requests = 0;
      final cache = RadarTileCache.forTesting(
        client: MockClient((_) async {
          requests++;
          return requests == 1
              ? http.Response('<html>edge error</html>', 200)
              : http.Response.bytes(png, 200);
        }),
        directory: directory,
      )..beginSession();

      final tile = await cache
          .providerFor('https://tiles.test/{z}/{x}/{y}.png')
          .getTile(64, 44, 7);

      expect(tile.data, png);
      expect(requests, 2);
    },
  );

  test('prefetch warms current and next overzoomed frame fairly', () async {
    final directory = await Directory.systemTemp.createTemp(
      'chetiwa-radar-prefetch-test-',
    );
    addTearDown(() => _deleteDirectoryEventually(directory));
    final png = await _solidPngTile();
    final requestedUrls = <String>[];
    final cache = RadarTileCache.forTesting(
      client: MockClient((request) async {
        requestedUrls.add(request.url.toString());
        return http.Response.bytes(png, 200);
      }),
      directory: directory,
    )..beginSession();
    await cache
        .providerFor('https://tiles.test/current/{z}/{x}/{y}.png')
        .getTile(2056, 1408, 12);

    final ready = await cache.prefetchNextFrames(
      frameTemplates: const [
        'https://tiles.test/current/{z}/{x}/{y}.png',
        'https://tiles.test/next/{z}/{x}/{y}.png',
      ],
      maxFrames: 2,
      maxTiles: 2,
    );

    expect(ready, 2);
    expect(requestedUrls, [
      'https://tiles.test/current/10/514/352.png',
      'https://tiles.test/next/10/514/352.png',
    ]);
  });

  test('visible frame preparation warms the cross-fade overlay', () async {
    final directory = await Directory.systemTemp.createTemp(
      'chetiwa-radar-cross-fade-test-',
    );
    addTearDown(() => _deleteDirectoryEventually(directory));
    final png = await _solidPngTile();
    final requestedUrls = <String>[];
    final cache = RadarTileCache.forTesting(
      client: MockClient((request) async {
        requestedUrls.add(request.url.toString());
        return http.Response.bytes(png, 200);
      }),
      directory: directory,
    )..beginSession();

    await cache
        .providerFor('https://tiles.test/current/{z}/{x}/{y}.png')
        .getTile(2056, 1408, 12);
    final ready = await cache.prepareVisibleFrame(
      'https://tiles.test/incoming/{z}/{x}/{y}.png',
    );
    final incoming = await cache
        .providerFor('https://tiles.test/incoming/{z}/{x}/{y}.png')
        .getTile(2056, 1408, 12);

    expect(ready, 1);
    expect(incoming.data, isNotNull);
    expect(requestedUrls, [
      'https://tiles.test/current/10/514/352.png',
      'https://tiles.test/incoming/10/514/352.png',
    ]);
    expect(cache.readyTileCount.value, 2);
  });

  test('a new viewport discards queued tiles from the previous zoom', () async {
    final directory = await Directory.systemTemp.createTemp(
      'chetiwa-radar-viewport-priority-test-',
    );
    addTearDown(() => _deleteDirectoryEventually(directory));
    final png = await _solidPngTile();
    final responses = <Completer<http.Response>>[];
    final cache = RadarTileCache.forTesting(
      client: MockClient((_) {
        final response = Completer<http.Response>();
        responses.add(response);
        return response.future;
      }),
      directory: directory,
    )..beginSession();
    final provider = cache.providerFor('https://tiles.test/{z}/{x}/{y}.png');

    final activeOldViewport = [
      for (var x = 0; x < 6; x++) provider.getTile(x, 44, 7),
    ];
    final queuedOldViewport = provider.getTile(6, 44, 7);
    await _waitUntil(() => responses.length == 6);

    cache.beginViewport();
    expect((await queuedOldViewport).data, isNull);
    final currentViewport = provider.getTile(7, 44, 7);
    expect(responses, hasLength(6));

    responses.first.complete(http.Response.bytes(png, 200));
    await _waitUntil(() => responses.length == 7);
    for (final response in responses.skip(1)) {
      if (!response.isCompleted) {
        response.complete(http.Response.bytes(png, 200));
      }
    }

    expect((await currentViewport).data, isNotNull);
    await Future.wait(activeOldViewport);
  });

  test('Google tile provider does not retry a permanent 400', () async {
    final directory = await Directory.systemTemp.createTemp(
      'chetiwa-radar-permanent-error-test-',
    );
    addTearDown(() => _deleteDirectoryEventually(directory));
    var requests = 0;
    final cache = RadarTileCache.forTesting(
      client: MockClient((_) async {
        requests++;
        return http.Response('bad request', 400);
      }),
      directory: directory,
    )..beginSession();

    final tile = await cache
        .providerFor('https://tiles.test/{z}/{x}/{y}.png')
        .getTile(64, 44, 7);

    expect(tile.data, isNull);
    expect(requests, 1);
  });

  test('Google tile provider rejects an origin HTML error body', () async {
    final directory = await Directory.systemTemp.createTemp(
      'chetiwa-radar-invalid-test-',
    );
    addTearDown(() => _deleteDirectoryEventually(directory));
    final cache = RadarTileCache.forTesting(
      client: MockClient((_) async => http.Response('<html>502</html>', 502)),
      directory: directory,
    )..beginSession();

    final tile = await cache
        .providerFor('https://tiles.test/{z}/{x}/{y}.png')
        .getTile(64, 44, 7);

    expect(tile.data, isNull);
    expect(cache.readyTileCount.value, 0);
  });
}

Future<List<int>> _solidPngTile() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 256, 256),
    ui.Paint()..color = const ui.Color(0x88FF3344),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 256);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

Future<List<int>> _quadrantPngTile() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas
    ..drawRect(
      const ui.Rect.fromLTWH(0, 0, 128, 128),
      ui.Paint()..color = const ui.Color(0xFFFF0000),
    )
    ..drawRect(
      const ui.Rect.fromLTWH(128, 0, 128, 128),
      ui.Paint()..color = const ui.Color(0xFF00FF00),
    )
    ..drawRect(
      const ui.Rect.fromLTWH(0, 128, 128, 128),
      ui.Paint()..color = const ui.Color(0xFF0000FF),
    )
    ..drawRect(
      const ui.Rect.fromLTWH(128, 128, 128, 128),
      ui.Paint()..color = const ui.Color(0xFFFFFF00),
    );
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 256);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

Future<void> _deleteDirectoryEventually(Directory directory) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
  if (await directory.exists()) await directory.delete(recursive: true);
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}
