import 'package:chetiwa/app/app.dart';
import 'package:chetiwa/app/di/chetiwa_dependencies.dart';
import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/location/location_repository.dart';
import 'package:chetiwa/features/forecast/data/datasources/fixture_forecast_data_source.dart';
import 'package:chetiwa/features/forecast/data/repositories/fixture_forecast_repository.dart';
import 'package:chetiwa/features/radar/data/repositories/fixture_radar_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('handles permission, GPS and precision recovery states', (
    tester,
  ) async {
    final locations = _TestLocationRepository(
      currentLocation: const LocationException(
        'blocked',
        issue: LocationIssue.permissionBlocked,
        recoveryAction: LocationRecoveryAction.appSettings,
      ),
    );
    await _pumpApp(tester, locations);

    await _openLocationPicker(tester);
    await tester.tap(find.byKey(const Key('current-location-tile')));
    await tester.pump();

    expect(
      find.text('Localisation bloquée. Autorisez Chetiwa dans les réglages.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('open-location-settings-button')));
    await tester.pump();
    expect(locations.openedRecovery, LocationRecoveryAction.appSettings);
    await tester.tap(find.byTooltip('Fermer'));
    await tester.pumpAndSettle();

    locations.currentLocation = const LocationException(
      'disabled',
      issue: LocationIssue.serviceDisabled,
      recoveryAction: LocationRecoveryAction.locationSettings,
    );
    await _openLocationPicker(tester);
    await tester.tap(find.byKey(const Key('current-location-tile')));
    await tester.pump();

    expect(
      find.text('La localisation est désactivée sur cet appareil.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('open-location-settings-button')));
    await tester.pump();
    expect(locations.openedRecovery, LocationRecoveryAction.locationSettings);
    await tester.tap(find.byTooltip('Fermer'));
    await tester.pumpAndSettle();

    locations.currentLocation = const ChetiwaLocation(
      city: 'Position actuelle',
      country: '',
      coordinates: Coordinates(latitude: 48.85, longitude: 2.35),
      acquisition: LocationAcquisition.reducedAccuracy,
    );
    await _openLocationPicker(tester);
    await tester.tap(find.byKey(const Key('current-location-tile')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Position actuelle'), findsOneWidget);
    expect(
      find.text(
        'Position approximative utilisée. Activez la localisation précise pour améliorer le résultat.',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    locations.currentLocation = const ChetiwaLocation(
      city: 'Dernière position',
      country: '',
      coordinates: Coordinates(latitude: 48.85, longitude: 2.35),
      acquisition: LocationAcquisition.lastKnownPosition,
    );
    await _openLocationPicker(tester, locationLabel: 'Position actuelle');
    await tester.tap(find.byKey(const Key('current-location-tile')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Dernière position'), findsOneWidget);
    await _waitFor(
      tester,
      find.text(
        'Dernière position connue utilisée. Vérifiez votre GPS si le lieu semble incorrect.',
      ),
    );
  });
}

Future<void> _pumpApp(
  WidgetTester tester,
  _TestLocationRepository locations,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await tester.pumpWidget(
    ChetiwaApp(
      dependencies: ChetiwaDependencies.testing(
        forecastRepository: const FixtureForecastRepository(
          FixtureForecastDataSource(),
        ),
        radarRepository: const FixtureRadarRepository(),
        locationRepository: locations,
      ),
    ),
  );
  await _waitFor(tester, find.byKey(const Key('rain-chart')));
}

Future<void> _openLocationPicker(
  WidgetTester tester, {
  String locationLabel = 'Paris, France',
}) async {
  await tester.tap(find.text(locationLabel));
  final currentLocationTile = find.byKey(const Key('current-location-tile'));
  await _waitFor(tester, currentLocationTile);
  await tester.dragFrom(const Offset(195, 700), const Offset(0, -600));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    currentLocationTile,
    120,
    scrollable: find.byType(Scrollable).last,
  );
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsOneWidget);
}

final class _TestLocationRepository implements LocationRepository {
  _TestLocationRepository({required this.currentLocation});

  Object currentLocation;
  LocationRecoveryAction? openedRecovery;

  @override
  Future<void> clearMainLocation() async {}

  @override
  Future<ChetiwaLocation> getCurrentLocation() async {
    final value = currentLocation;
    if (value is LocationException) throw value;
    return value as ChetiwaLocation;
  }

  @override
  Future<ChetiwaLocation?> getMainLocation() async => null;

  @override
  Future<List<ChetiwaLocation>> getRecentLocations() async => const [];

  @override
  Future<bool> openLocationRecovery(LocationRecoveryAction action) async {
    openedRecovery = action;
    return true;
  }

  @override
  Future<void> remember(ChetiwaLocation location) async {}

  @override
  Future<void> removeRecentLocation(ChetiwaLocation location) async {}

  @override
  Future<ChetiwaLocation> resolveCoordinates(Coordinates coordinates) async =>
      ChetiwaLocation(
        city: 'Point sélectionné',
        country: '',
        coordinates: coordinates,
      );

  @override
  Future<List<ChetiwaLocation>> search(String query) async => const [];

  @override
  Future<void> setMainLocation(ChetiwaLocation location) async {}
}
