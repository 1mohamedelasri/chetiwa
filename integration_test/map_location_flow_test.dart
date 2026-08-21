import 'package:chetiwa/app/app.dart';
import 'package:chetiwa/app/di/chetiwa_dependencies.dart';
import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/location/location_repository.dart';
import 'package:chetiwa/core/time/weather_clock.dart';
import 'package:chetiwa/features/forecast/data/datasources/fixture_forecast_data_source.dart';
import 'package:chetiwa/features/forecast/data/repositories/fixture_forecast_repository.dart';
import 'package:chetiwa/features/radar/data/repositories/fixture_radar_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  testWidgets(
    'choosing a place on the map keeps Graph, Radar and Forecast aligned',
    (tester) async {
      final clock = FixedWeatherClock(DateTime.utc(2026, 8, 20, 12));
      final locations = _MapSelectionLocationRepository();
      final dependencies = ChetiwaDependencies.testing(
        weatherClock: clock,
        forecastRepository: FixtureForecastRepository(
          FixtureForecastDataSource(clock: clock),
        ),
        radarRepository: FixtureRadarRepository(clock: clock),
        locationRepository: locations,
      );

      await tester.pumpWidget(ChetiwaApp(dependencies: dependencies));
      await _waitFor(tester, find.byKey(const Key('rain-chart')));

      await tester.tap(find.text('Paris, France'));
      await _waitFor(tester, find.byKey(const Key('location-search-field')));
      await tester.dragFrom(const Offset(195, 700), const Offset(0, -600));
      await tester.pumpAndSettle();

      final chooseOnMap = find.byKey(const Key('choose-on-map-tile'));
      await tester.scrollUntilVisible(
        chooseOnMap,
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(chooseOnMap);
      await _waitFor(
        tester,
        find.byKey(const Key('confirm-map-location-button')),
      );
      await _waitForEnabled(
        tester,
        find.byKey(const Key('confirm-map-location-button')),
      );
      expect(find.text('Lieu carte test, France'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm-map-location-button')));
      await _waitFor(tester, find.byKey(const Key('rain-chart')));
      expect(locations.mainLocation?.label, 'Lieu carte test, France');
      expect(find.text('Lieu carte test, France'), findsOneWidget);

      await _activateNavigation(tester, 'Radar');
      await _waitFor(tester, find.byKey(const Key('radar-city-pin')));
      expect(find.text('Lieu carte test, France'), findsOneWidget);

      await _activateNavigation(tester, 'Prévisions');
      await _waitFor(tester, find.byKey(const Key('forecast-pane')));
      expect(find.text('Lieu carte test'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsOneWidget);
}

Future<void> _waitForEnabled(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (DateTime.now().isBefore(deadline)) {
    final button = tester.widget<FilledButton>(finder);
    if (button.onPressed != null) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(tester.widget<FilledButton>(finder).onPressed, isNotNull);
}

/// The compact navigation sits below the map canvas on small emulator
/// viewports. Trigger its real [InkWell] callback so this integration test
/// stays focused on the persisted location hand-off rather than viewport size.
Future<void> _activateNavigation(WidgetTester tester, String label) async {
  final inkWell = find.ancestor(
    of: find.text(label),
    matching: find.byType(InkWell),
  );
  expect(inkWell, findsOneWidget);
  tester.widget<InkWell>(inkWell).onTap!.call();
  await tester.pumpAndSettle();
}

final class _MapSelectionLocationRepository implements LocationRepository {
  ChetiwaLocation? mainLocation;
  final List<ChetiwaLocation> _recent = [];

  @override
  Future<void> clearMainLocation() async => mainLocation = null;

  @override
  Future<ChetiwaLocation> getCurrentLocation() async =>
      LocationCatalog.locations.first;

  @override
  Future<ChetiwaLocation?> getMainLocation() async => mainLocation;

  @override
  Future<List<ChetiwaLocation>> getRecentLocations() async =>
      List.unmodifiable(_recent);

  @override
  Future<bool> openLocationRecovery(LocationRecoveryAction action) async =>
      false;

  @override
  Future<void> remember(ChetiwaLocation location) async {
    _recent.removeWhere((item) => item.coordinates == location.coordinates);
    _recent.insert(0, location);
  }

  @override
  Future<void> removeRecentLocation(ChetiwaLocation location) async {
    _recent.removeWhere((item) => item.coordinates == location.coordinates);
  }

  @override
  Future<ChetiwaLocation> resolveCoordinates(Coordinates coordinates) async =>
      ChetiwaLocation(
        city: 'Lieu carte test',
        country: 'France',
        coordinates: coordinates,
      );

  @override
  Future<List<ChetiwaLocation>> search(String query) async => const [];

  @override
  Future<void> setMainLocation(ChetiwaLocation location) async {
    mainLocation = location;
  }
}
