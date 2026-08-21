import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'coordinates.dart';
import 'device_location_provider.dart';
import 'location_repository.dart';
import 'location_preferences_store.dart';

final class OpenMeteoLocationRepository implements LocationRepository {
  const OpenMeteoLocationRepository({
    required http.Client client,
    required DeviceLocationProvider deviceLocationProvider,
  }) : _client = client,
       _deviceLocationProvider = deviceLocationProvider;

  final http.Client _client;
  final DeviceLocationProvider _deviceLocationProvider;

  @override
  Future<List<ChetiwaLocation>> search(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2) return const [];

    final uri = Uri.https(
      ApiConfig.openMeteoGeocodingHost,
      '/v1/search',
      <String, String>{
        'name': normalized,
        'count': '12',
        'language': 'fr',
        'format': 'json',
        if (ApiConfig.openMeteoApiKey.isNotEmpty)
          'apikey': ApiConfig.openMeteoApiKey,
      },
    );
    try {
      final response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw LocationException(
          'Recherche indisponible (${response.statusCode}).',
          issue: LocationIssue.searchUnavailable,
        );
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final results = decoded['results'] as List<dynamic>? ?? const [];
      return results
          .whereType<Map<String, dynamic>>()
          .map(_locationFromSearchResult)
          .whereType<ChetiwaLocation>()
          .toList(growable: false);
    } on LocationException {
      rethrow;
    } on Object {
      throw const LocationException(
        'Impossible de rechercher une ville pour le moment.',
        issue: LocationIssue.searchUnavailable,
      );
    }
  }

  @override
  Future<ChetiwaLocation> getCurrentLocation() async {
    final fix = await _deviceLocationProvider.getCurrentLocationFix();
    return _coordinateLocation(
      fix.coordinates,
      current: true,
      acquisition: fix.acquisition,
    );
  }

  @override
  Future<ChetiwaLocation> resolveCoordinates(Coordinates coordinates) async =>
      _coordinateLocation(coordinates);

  ChetiwaLocation _coordinateLocation(
    Coordinates coordinates, {
    bool current = false,
    LocationAcquisition acquisition = LocationAcquisition.selected,
  }) => ChetiwaLocation(
    city: current ? 'Ma position actuelle' : 'Point sélectionné',
    country: '',
    coordinates: coordinates,
    acquisition: acquisition,
  );

  @override
  Future<bool> openLocationRecovery(LocationRecoveryAction action) =>
      _deviceLocationProvider.openRecovery(action);

  @override
  Future<List<ChetiwaLocation>> getRecentLocations() async {
    return LocationPreferencesStore.getRecentLocations();
  }

  @override
  Future<void> remember(ChetiwaLocation location) async {
    return LocationPreferencesStore.remember(location);
  }

  @override
  Future<ChetiwaLocation?> getMainLocation() =>
      LocationPreferencesStore.getMainLocation();

  @override
  Future<void> setMainLocation(ChetiwaLocation location) =>
      LocationPreferencesStore.setMainLocation(location);

  @override
  Future<void> clearMainLocation() =>
      LocationPreferencesStore.clearMainLocation();

  @override
  Future<void> removeRecentLocation(ChetiwaLocation location) =>
      LocationPreferencesStore.removeRecentLocation(location);

  ChetiwaLocation? _locationFromSearchResult(Map<String, dynamic> json) {
    final name = json['name'] as String?;
    final latitude = (json['latitude'] as num?)?.toDouble();
    final longitude = (json['longitude'] as num?)?.toDouble();
    if (name == null || latitude == null || longitude == null) return null;
    return ChetiwaLocation(
      city: name,
      country: json['country'] as String? ?? '',
      administrativeArea: json['admin1'] as String?,
      coordinates: Coordinates(latitude: latitude, longitude: longitude),
    );
  }
}
