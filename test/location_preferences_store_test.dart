import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/location/location_preferences_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('persists the principal place and recent places', () async {
    const paris = ChetiwaLocation(
      city: 'Paris',
      country: 'France',
      coordinates: Coordinates(latitude: 48.8566, longitude: 2.3522),
    );

    await LocationPreferencesStore.setMainLocation(paris);
    await LocationPreferencesStore.remember(paris);

    expect(
      (await LocationPreferencesStore.getMainLocation())?.label,
      'Paris, France',
    );
    expect(
      (await LocationPreferencesStore.getRecentLocations()).single.label,
      'Paris, France',
    );
  });

  test('persists and restores the last map viewport independently', () async {
    const coordinates = Coordinates(latitude: 50.9375, longitude: 6.9603);

    await LocationPreferencesStore.setMapView(
      coordinates: coordinates,
      zoom: 10.5,
    );

    final saved = await LocationPreferencesStore.getMapView();
    expect(saved?.coordinates, coordinates);
    expect(saved?.zoom, 10.5);
  });
}
