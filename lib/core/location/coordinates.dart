import 'package:equatable/equatable.dart';

final class Coordinates extends Equatable {
  const Coordinates({required this.latitude, required this.longitude});

  static const paris = Coordinates(latitude: 48.8566, longitude: 2.3522);

  final double latitude;
  final double longitude;

  @override
  List<Object> get props => [latitude, longitude];
}

final class ChetiwaLocation extends Equatable {
  const ChetiwaLocation({
    required this.city,
    required this.country,
    required this.coordinates,
    this.administrativeArea,
    this.acquisition = LocationAcquisition.selected,
  });

  final String city;
  final String country;
  final Coordinates coordinates;
  final String? administrativeArea;
  final LocationAcquisition acquisition;

  bool get usesLastKnownPosition =>
      acquisition == LocationAcquisition.lastKnownPosition;

  bool get hasReducedAccuracy =>
      acquisition == LocationAcquisition.reducedAccuracy;

  bool get isCurrentDevicePosition =>
      acquisition != LocationAcquisition.selected;

  String get label => country.isEmpty ? city : '$city, $country';

  String get details {
    final region = administrativeArea?.trim();
    if (region == null || region.isEmpty || region == country) return country;
    return country.isEmpty ? region : '$region · $country';
  }

  @override
  List<Object?> get props => [
    city,
    country,
    coordinates,
    administrativeArea,
    acquisition,
  ];
}

enum LocationAcquisition {
  selected,
  precise,
  reducedAccuracy,
  lastKnownPosition,
}

abstract final class LocationCatalog {
  static const locations = <ChetiwaLocation>[
    ChetiwaLocation(
      city: 'Paris',
      country: 'France',
      coordinates: Coordinates.paris,
    ),
    ChetiwaLocation(
      city: 'Clichy',
      country: 'France',
      coordinates: Coordinates(latitude: 48.9045, longitude: 2.3069),
    ),
    ChetiwaLocation(
      city: 'Lyon',
      country: 'France',
      coordinates: Coordinates(latitude: 45.7640, longitude: 4.8357),
    ),
    ChetiwaLocation(
      city: 'Marseille',
      country: 'France',
      coordinates: Coordinates(latitude: 43.2965, longitude: 5.3698),
    ),
    ChetiwaLocation(
      city: 'Lille',
      country: 'France',
      coordinates: Coordinates(latitude: 50.6292, longitude: 3.0573),
    ),
    ChetiwaLocation(
      city: 'Bordeaux',
      country: 'France',
      coordinates: Coordinates(latitude: 44.8378, longitude: -0.5792),
    ),
    ChetiwaLocation(
      city: 'London',
      country: 'Royaume-Uni',
      coordinates: Coordinates(latitude: 51.5072, longitude: -0.1276),
    ),
    ChetiwaLocation(
      city: 'Bruxelles',
      country: 'Belgique',
      coordinates: Coordinates(latitude: 50.8503, longitude: 4.3517),
    ),
    ChetiwaLocation(
      city: 'Montréal',
      country: 'Canada',
      coordinates: Coordinates(latitude: 45.5019, longitude: -73.5674),
    ),
    ChetiwaLocation(
      city: 'New York',
      country: 'États-Unis',
      coordinates: Coordinates(latitude: 40.7128, longitude: -74.0060),
    ),
    ChetiwaLocation(
      city: 'Casablanca',
      country: 'Maroc',
      coordinates: Coordinates(latitude: 33.5731, longitude: -7.5898),
    ),
    ChetiwaLocation(
      city: 'Dubaï',
      country: 'Émirats arabes unis',
      coordinates: Coordinates(latitude: 25.2048, longitude: 55.2708),
    ),
    ChetiwaLocation(
      city: 'Tokyo',
      country: 'Japon',
      coordinates: Coordinates(latitude: 35.6762, longitude: 139.6503),
    ),
    ChetiwaLocation(
      city: 'Sydney',
      country: 'Australie',
      coordinates: Coordinates(latitude: -33.8688, longitude: 151.2093),
    ),
  ];

  static ChetiwaLocation forCoordinates(Coordinates coordinates) =>
      locations.firstWhere(
        (location) => location.coordinates == coordinates,
        orElse: () => ChetiwaLocation(
          city: 'Position sélectionnée',
          country: '',
          coordinates: coordinates,
        ),
      );
}
