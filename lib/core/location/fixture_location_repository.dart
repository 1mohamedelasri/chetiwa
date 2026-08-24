import 'coordinates.dart';
import 'location_repository.dart';

final class FixtureLocationRepository implements LocationRepository {
  const FixtureLocationRepository({this.mainLocation});

  final ChetiwaLocation? mainLocation;

  @override
  Future<ChetiwaLocation> getCurrentLocation() async =>
      LocationCatalog.locations.first;

  @override
  Future<ChetiwaLocation> resolveCoordinates(Coordinates coordinates) async =>
      LocationCatalog.forCoordinates(coordinates);

  @override
  Future<List<ChetiwaLocation>> getRecentLocations() async => const [];

  @override
  Future<void> remember(ChetiwaLocation location) async {}

  @override
  Future<ChetiwaLocation?> getMainLocation() async => mainLocation;

  @override
  Future<void> setMainLocation(ChetiwaLocation location) async {}

  @override
  Future<void> clearMainLocation() async {}

  @override
  Future<void> removeRecentLocation(ChetiwaLocation location) async {}

  @override
  Future<bool> openLocationRecovery(LocationRecoveryAction action) async =>
      false;

  @override
  Future<List<ChetiwaLocation>> search(String query) async {
    final normalized = query.trim().toLowerCase();
    return LocationCatalog.locations
        .where(
          (location) =>
              location.city.toLowerCase().contains(normalized) ||
              location.country.toLowerCase().contains(normalized),
        )
        .toList(growable: false);
  }
}
