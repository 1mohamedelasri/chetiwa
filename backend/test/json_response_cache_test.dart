import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:test/test.dart';

void main() {
  test('evicts the least recently used entry at its configured limit', () {
    final cache = JsonResponseCache(maxEntries: 2);
    final instant = DateTime.utc(2026, 8, 20);
    CachedJsonResponse entry(String value) =>
        CachedJsonResponse(body: value, etag: '"$value"', storedAt: instant);

    cache.write('a', entry('a'));
    cache.write('b', entry('b'));
    expect(cache.read('a'), isNotNull);
    cache.write('c', entry('c'));

    expect(cache.read('a'), isNotNull);
    expect(cache.read('b'), isNull);
    expect(cache.read('c'), isNotNull);
  });
}
