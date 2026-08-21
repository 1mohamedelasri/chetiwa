import 'coordinates.dart';

abstract interface class LocationRepository {
  Future<List<ChetiwaLocation>> search(String query);

  Future<ChetiwaLocation> getCurrentLocation();

  /// Resolves a user-selected coordinate when the configured provider supports
  /// reverse geocoding. Implementations may return a clear coordinate label
  /// instead: choosing on the map must still work offline or without a proxy.
  Future<ChetiwaLocation> resolveCoordinates(Coordinates coordinates);

  Future<List<ChetiwaLocation>> getRecentLocations();

  Future<void> remember(ChetiwaLocation location);

  /// The free plan keeps one explicit, on-device default place.
  Future<ChetiwaLocation?> getMainLocation();

  Future<void> setMainLocation(ChetiwaLocation location);

  Future<void> clearMainLocation();

  Future<void> removeRecentLocation(ChetiwaLocation location);

  Future<bool> openLocationRecovery(LocationRecoveryAction action);
}

enum LocationRecoveryAction { locationSettings, appSettings }

enum LocationIssue {
  unknown,
  serviceDisabled,
  permissionDenied,
  permissionBlocked,
  unavailable,
  searchUnavailable,
}

final class LocationException implements Exception {
  const LocationException(
    this.message, {
    this.recoveryAction,
    this.issue = LocationIssue.unknown,
  });

  final String message;
  final LocationRecoveryAction? recoveryAction;
  final LocationIssue issue;

  @override
  String toString() => message;
}
