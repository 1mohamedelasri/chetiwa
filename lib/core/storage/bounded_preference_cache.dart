import 'package:shared_preferences/shared_preferences.dart';

/// Keeps a small LRU index for large values stored in SharedPreferences.
///
/// This is deliberately metadata only: cache entries keep their current format
/// and corrupted indexes can safely be rebuilt on the next write.
final class BoundedPreferenceCache {
  const BoundedPreferenceCache._();

  static Future<void> touch(
    SharedPreferences preferences, {
    required String namespace,
    required String key,
    required int maxEntries,
  }) async {
    final indexKey = '$namespace:index';
    final entries =
        List<String>.from(
            preferences.getStringList(indexKey) ?? const <String>[],
          )
          ..remove(key)
          ..add(key);
    while (entries.length > maxEntries) {
      await preferences.remove(entries.removeAt(0));
    }
    await preferences.setStringList(indexKey, entries);
  }

  static Future<void> forget(
    SharedPreferences preferences, {
    required String namespace,
    required String key,
  }) async {
    await preferences.remove(key);
    final indexKey = '$namespace:index';
    final entries = List<String>.from(
      preferences.getStringList(indexKey) ?? const <String>[],
    )..remove(key);
    await preferences.setStringList(indexKey, entries);
  }
}
