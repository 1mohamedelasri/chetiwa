import 'dart:async';
import 'dart:typed_data';

import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:test/test.dart';

void main() {
  test('tile cache evicts least recently used entries and respects bytes', () {
    final cache = TileResponseCache(maxEntries: 2, maxBytes: 4);
    CachedTileResponse tile(String value) => CachedTileResponse(
      bytes: Uint8List.fromList(value.codeUnits),
      etag: value,
      storedAt: DateTime.utc(2026, 8, 1),
    );

    cache.write('a', tile('aa'));
    cache.write('b', tile('bb'));
    expect(cache.read('a'), isNotNull);
    cache.write('c', tile('cc'));
    expect(cache.read('b'), isNull);
    expect(cache.read('a'), isNotNull);
    expect(cache.read('c'), isNotNull);
    expect(cache.bytes, 4);
  });

  test(
    'concurrent cold loads are coalesced into one origin operation',
    () async {
      final cache = TileResponseCache();
      final origin = Completer<CachedTileResponse>();
      var loads = 0;
      Future<CachedTileResponse> load() {
        loads++;
        return origin.future;
      }

      final first = cache.loadOnce('same-tile', load);
      final second = cache.loadOnce('same-tile', load);
      expect(loads, 1);
      expect(cache.inFlightCount, 1);

      origin.complete(
        CachedTileResponse(
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
          etag: 'etag',
          storedAt: DateTime.utc(2026, 8, 27),
        ),
      );
      final results = await Future.wait(<Future<TileLoadResult>>[
        first,
        second,
      ]);

      expect(results.first.joined, isFalse);
      expect(results.last.joined, isTrue);
      expect(results.first.entry, same(results.last.entry));
      expect(cache.inFlightCount, 0);
    },
  );
}
