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
}
