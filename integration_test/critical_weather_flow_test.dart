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
    'selecting a city keeps Graph, Radar and Forecast on the same place',
    (tester) async {
      final clock = FixedWeatherClock(DateTime.utc(2026, 8, 20, 12));
      final locations = _MemoryLocationRepository();
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
      expect(find.text('Paris, France'), findsOneWidget);

      await tester.tap(find.text('Paris, France'));
      await _waitFor(tester, find.byKey(const Key('location-search-field')));
      await tester.enterText(
        find.byKey(const Key('location-search-field')),
        'Tokyo',
      );
      await tester.pump(const Duration(milliseconds: 400));
      final tokyoResult = find.text('Tokyo').last;
      await _waitFor(tester, tokyoResult);
      await tester.tap(tokyoResult);
      await _waitFor(tester, find.text('Tokyo, Japon'));

      expect(locations.mainLocation?.label, 'Tokyo, Japon');
      expect(find.byKey(const Key('rain-chart')), findsOneWidget);

      await tester.tap(find.text('Radar'));
      await _waitFor(tester, find.byKey(const Key('radar-city-pin')));
      expect(find.text('Tokyo, Japon'), findsOneWidget);

      await tester.tap(find.text('Prévisions'));
      await _waitFor(tester, find.byKey(const Key('forecast-pane')));
      expect(find.text('Tokyo'), findsOneWidget);

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

final class _MemoryLocationRepository implements LocationRepository {
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
      LocationCatalog.forCoordinates(coordinates);

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

  @override
  Future<void> setMainLocation(ChetiwaLocation location) async {
    mainLocation = location;
  }
}
