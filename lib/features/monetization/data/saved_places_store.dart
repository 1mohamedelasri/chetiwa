import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/location/coordinates.dart';
import '../domain/saved_place.dart';

final class SavedPlacesStore {
  const SavedPlacesStore();

  static const _key = 'monetization:saved_places:v1';

  Future<List<SavedPlace>> read() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(_fromJson)
          .toList(growable: false);
    } on Object {
      await preferences.remove(_key);
      return const [];
    }
  }

  Future<void> write(List<SavedPlace> places) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(places.map(_toJson).toList()));
  }

  Map<String, Object?> _toJson(SavedPlace place) => {
    'id': place.id,
    'name': place.name,
    'city': place.location.city,
    'country': place.location.country,
    'region': place.location.administrativeArea,
    'latitude': place.location.coordinates.latitude,
    'longitude': place.location.coordinates.longitude,
  };

  SavedPlace _fromJson(Map<String, dynamic> json) => SavedPlace(
    id: json['id'] as String,
    name: json['name'] as String,
    location: ChetiwaLocation(
      city: json['city'] as String,
      country: json['country'] as String? ?? '',
      administrativeArea: json['region'] as String?,
      coordinates: Coordinates(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      ),
    ),
  );
}
