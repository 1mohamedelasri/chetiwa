import 'package:chetiwa/core/storage/bounded_preference_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('evicts the least recently used cached preference', () async {
    SharedPreferences.setMockInitialValues({'a': 'one', 'b': 'two'});
    final preferences = await SharedPreferences.getInstance();

    await BoundedPreferenceCache.touch(
      preferences,
      namespace: 'test',
      key: 'a',
      maxEntries: 2,
    );
    await BoundedPreferenceCache.touch(
      preferences,
      namespace: 'test',
      key: 'b',
      maxEntries: 2,
    );
    await preferences.setString('c', 'three');
    await BoundedPreferenceCache.touch(
      preferences,
      namespace: 'test',
      key: 'c',
      maxEntries: 2,
    );

    expect(preferences.getString('a'), isNull);
    expect(preferences.getString('b'), 'two');
    expect(preferences.getString('c'), 'three');
  });
}
