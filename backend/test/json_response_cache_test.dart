import 'dart:async';

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

  test(
    'shares pending refreshes and allows retry after their failure',
    () async {
      final cache = JsonResponseCache();
      final origin = Completer<CachedJsonResponse>();
      var loads = 0;
      Future<CachedJsonResponse> load() {
        loads++;
        return origin.future;
      }

      final first = cache.loadOnce('forecast', load);
      final second = cache.loadOnce('forecast', load);
      final firstFailure = expectLater(first, throwsStateError);
      final secondFailure = expectLater(second, throwsStateError);
      expect(loads, 1);
      origin.completeError(StateError('provider unavailable'));
      await Future.wait([firstFailure, secondFailure]);

      final recovered = await cache.loadOnce(
        'forecast',
        () async => CachedJsonResponse(
          body: '{}',
          etag: 'recovered',
          storedAt: DateTime.utc(2026, 9, 19),
        ),
      );
      expect(recovered.joined, isFalse);
      expect(recovered.entry.etag, 'recovered');
    },
  );
}
