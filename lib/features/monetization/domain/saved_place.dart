import '../../../core/location/coordinates.dart';

final class SavedPlace {
  const SavedPlace({
    required this.id,
    required this.name,
    required this.location,
  });

  final String id;
  final String name;
  final ChetiwaLocation location;
}
