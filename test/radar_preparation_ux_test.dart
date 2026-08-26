import 'dart:async';

import 'package:chetiwa/app/app.dart';
import 'package:chetiwa/app/di/chetiwa_dependencies.dart';
import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/location/fixture_location_repository.dart';
import 'package:chetiwa/features/forecast/data/datasources/fixture_forecast_data_source.dart';
import 'package:chetiwa/features/forecast/data/repositories/fixture_forecast_repository.dart';
import 'package:chetiwa/features/radar/data/repositories/fixture_radar_repository.dart';
import 'package:chetiwa/features/radar/domain/entities/radar_frame.dart';
import 'package:chetiwa/features/radar/domain/repositories/radar_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Graph stays usable while Radar shows local preparation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final radar = _DelayedRadarRepository();
    await tester.pumpWidget(
      ChetiwaApp(
        dependencies: ChetiwaDependencies.testing(
          forecastRepository: const FixtureForecastRepository(
            FixtureForecastDataSource(),
          ),
          radarRepository: radar,
          locationRepository: const FixtureLocationRepository(),
        ),
      ),
    );
    await _loadFixture(tester);

    expect(find.byKey(const Key('rain-chart')), findsOneWidget);
    expect(find.byKey(const Key('radar-preparing-surface')), findsNothing);
    expect(
      find.byKey(const ValueKey('radar-warmup-deferred'), skipOffstage: false),
      findsOneWidget,
    );

    await tester.tap(find.text('Radar'));
    await tester.pump();
    expect(find.byKey(const Key('radar-preparing-surface')), findsOneWidget);
    expect(find.byKey(const Key('radar-preparation-progress')), findsOneWidget);
    expect(find.text('Préparation du radar…'), findsOneWidget);
    expect(find.byKey(const Key('adaptive-ad-banner-slot')), findsOneWidget);

    radar.complete();
    await _loadFixture(tester);
    expect(find.byKey(const Key('radar-preparing-surface')), findsNothing);
    expect(find.byKey(const Key('radar-city-pin')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _loadFixture(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

final class _DelayedRadarRepository implements RadarRepository {
  final _ready = Completer<void>();
  final _delegate = const FixtureRadarRepository();

  void complete() {
    if (!_ready.isCompleted) _ready.complete();
  }

  @override
  Future<CachedRadarFrames?> getCachedFrames(Coordinates coordinates) async =>
      null;

  @override
  Future<List<RadarFrame>> getFrames(Coordinates coordinates) async {
    await _ready.future;
    return _delegate.getFrames(coordinates);
  }
}
