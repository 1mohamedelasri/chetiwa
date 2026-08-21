import '../network/chetiwa_api_client.dart';
import 'coordinates.dart';
import 'device_location_provider.dart';
import 'location_repository.dart';
import 'location_preferences_store.dart';

final class ChetiwaLocationRepository implements LocationRepository {
  const ChetiwaLocationRepository({
    required ChetiwaApiClient api,
    required DeviceLocationProvider deviceLocationProvider,
  }) : _api = api,
       _deviceLocationProvider = deviceLocationProvider;

  final ChetiwaApiClient _api;
  final DeviceLocationProvider _deviceLocationProvider;

  @override
  Future<List<ChetiwaLocation>> search(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2) return const [];
    try {
      final data = await _api.getData(
        '/v1/locations/search',
        query: <String, String>{
          'q': normalized,
          'count': '12',
          'language': 'fr',
        },
      );
      return (data['locations'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_locationFromApi)
          .whereType<ChetiwaLocation>()
          .toList(growable: false);
    } on ChetiwaApiException catch (error) {
      throw LocationException(
        error.message,
        issue: LocationIssue.searchUnavailable,
      );
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
    return _resolveCoordinates(
      fix.coordinates,
      fallbackName: 'Ma position actuelle',
      acquisition: fix.acquisition,
    );
  }

  @override
  Future<ChetiwaLocation> resolveCoordinates(Coordinates coordinates) =>
      _resolveCoordinates(coordinates, fallbackName: 'Point sélectionné');

  Future<ChetiwaLocation> _resolveCoordinates(
    Coordinates coordinates, {
    required String fallbackName,
    LocationAcquisition acquisition = LocationAcquisition.selected,
  }) async {
    try {
      final data = await _api.getData(
        '/v1/locations/reverse',
        query: <String, String>{
          'latitude': coordinates.latitude.toString(),
          'longitude': coordinates.longitude.toString(),
          'language': 'fr',
        },
      );
      final raw = data['location'];
      if (raw is Map<String, dynamic>) {
        final location = _locationFromApi(raw);
        if (location != null) return location;
      }
    } on ChetiwaApiException {
      // Weather still works at raw GPS coordinates when reverse geocoding is
      // unavailable or not configured on the backend.
    }
    return ChetiwaLocation(
      city: fallbackName,
      country: '',
      coordinates: coordinates,
      acquisition: acquisition,
    );
  }

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

  ChetiwaLocation? _locationFromApi(Map<String, dynamic> json) {
    final name = json['name'] as String?;
    final latitude = (json['latitude'] as num?)?.toDouble();
    final longitude = (json['longitude'] as num?)?.toDouble();
    if (name == null || latitude == null || longitude == null) return null;
    return ChetiwaLocation(
      city: name,
      country: json['country'] as String? ?? '',
      administrativeArea: json['administrativeArea'] as String?,
      coordinates: Coordinates(latitude: latitude, longitude: longitude),
    );
  }
}
