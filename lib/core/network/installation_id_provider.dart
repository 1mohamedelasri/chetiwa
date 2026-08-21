import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

final class InstallationIdProvider {
  const InstallationIdProvider();

  static const _storageKey = 'privacy:installation_id:v1';

  Future<String> getOrCreate() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_storageKey);
    if (existing != null && _isValid(existing)) return existing;

    final random = Random.secure();
    final id = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    await preferences.setString(_storageKey, id);
    return id;
  }

  bool _isValid(String value) => RegExp(r'^[a-f0-9]{32}$').hasMatch(value);
}
