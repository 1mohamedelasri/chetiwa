import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'coordinates.dart';

/// Small on-device store for places deliberately saved by the user.
///
/// It never stores a GPS lookup named "Ma position actuelle": current location
/// is an on-demand action, not a background-tracked place.
abstract final class LocationPreferencesStore {
  static const _mainKey = 'locations:main:v1';
  static const _recentKey = 'locations:recent:v1';
  static const _maximumRecentLocations = 5;

  static Future<ChetiwaLocation?> getMainLocation() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_mainKey);
    if (encoded == null) return null;
    try {
      return _fromJson(jsonDecode(encoded) as Map<String, dynamic>);
    } on Object {
      await preferences.remove(_mainKey);
      return null;
    }
  }

  static Future<void> setMainLocation(ChetiwaLocation location) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_mainKey, jsonEncode(_toJson(location)));
  }

  static Future<void> clearMainLocation() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_mainKey);
  }

  static Future<List<ChetiwaLocation>> getRecentLocations() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_recentKey);
    if (encoded == null) return const [];
    try {
      final values = jsonDecode(encoded) as List<dynamic>;
      return values
          .whereType<Map<String, dynamic>>()
          .map(_fromJson)
          .toList(growable: false);
    } on Object {
      await preferences.remove(_recentKey);
      return const [];
    }
  }

  static Future<void> remember(ChetiwaLocation location) async {
    if (location.country.isEmpty) return;
    final recent = await getRecentLocations();
    final updated = <ChetiwaLocation>[
      location,
      ...recent.where((item) => item.coordinates != location.coordinates),
    ].take(_maximumRecentLocations).toList(growable: false);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _recentKey,
      jsonEncode(updated.map(_toJson).toList(growable: false)),
    );
  }

  static Future<void> removeRecentLocation(ChetiwaLocation location) async {
    final updated = (await getRecentLocations())
        .where((item) => item.coordinates != location.coordinates)
        .toList(growable: false);
    final preferences = await SharedPreferences.getInstance();
    if (updated.isEmpty) {
      await preferences.remove(_recentKey);
    } else {
      await preferences.setString(
        _recentKey,
        jsonEncode(updated.map(_toJson).toList(growable: false)),
      );
    }
  }

  static Map<String, dynamic> _toJson(ChetiwaLocation location) =>
      <String, dynamic>{
        'city': location.city,
        'country': location.country,
        'administrative_area': location.administrativeArea,
        'latitude': location.coordinates.latitude,
        'longitude': location.coordinates.longitude,
      };

  static ChetiwaLocation _fromJson(Map<String, dynamic> json) =>
      ChetiwaLocation(
        city: json['city'] as String,
        country: json['country'] as String? ?? '',
        administrativeArea: json['administrative_area'] as String?,
        coordinates: Coordinates(
          latitude: (json['latitude'] as num).toDouble(),
          longitude: (json['longitude'] as num).toDouble(),
        ),
      );
}
