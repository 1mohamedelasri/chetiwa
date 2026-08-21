import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/time/weather_clock.dart';
import 'package:chetiwa/features/forecast/application/graph_horizon_cubit.dart';
import 'package:chetiwa/features/forecast/data/datasources/fixture_forecast_data_source.dart';
import 'package:chetiwa/features/forecast/domain/entities/forecast.dart';
import 'package:chetiwa/features/forecast/domain/services/forecast_snapshot_builder.dart';
import 'package:chetiwa/features/forecast/presentation/widgets/forecast_pane.dart';
import 'package:chetiwa/features/forecast/presentation/widgets/graph_pane.dart';
import 'package:chetiwa/features/forecast/presentation/widgets/weather_chrome.dart';
import 'package:chetiwa/features/radar/application/radar_bloc.dart';
import 'package:chetiwa/features/radar/domain/entities/radar_frame.dart';
import 'package:chetiwa/features/radar/presentation/widgets/radar_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _WorldTimeCase = ({
  String city,
  String timeZone,
  DateTime instantUtc,
  DateTime expectedWallTime,
  int expectedOffsetSeconds,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cases = <_WorldTimeCase>[
    (
      city: 'Honolulu, États-Unis',
      timeZone: 'Pacific/Honolulu',
      instantUtc: DateTime.utc(2026, 8, 20, 2, 15),
      expectedWallTime: DateTime(2026, 8, 19, 16, 15),
      expectedOffsetSeconds: -10 * 60 * 60,
    ),
    (
      city: 'New York, États-Unis',
      timeZone: 'America/New_York',
      instantUtc: DateTime.utc(2026, 8, 20, 2, 15),
      expectedWallTime: DateTime(2026, 8, 19, 22, 15),
      expectedOffsetSeconds: -4 * 60 * 60,
    ),
    (
      city: 'Paris, France',
      timeZone: 'Europe/Paris',
      instantUtc: DateTime.utc(2026, 8, 20, 22, 15),
      expectedWallTime: DateTime(2026, 8, 21, 0, 15),
      expectedOffsetSeconds: 2 * 60 * 60,
    ),
    (
      city: 'Dubaï, Émirats arabes unis',
      timeZone: 'Asia/Dubai',
      instantUtc: DateTime.utc(2026, 8, 20, 20, 15),
      expectedWallTime: DateTime(2026, 8, 21, 0, 15),
      expectedOffsetSeconds: 4 * 60 * 60,
    ),
    (
      city: 'Katmandou, Népal',
      timeZone: 'Asia/Kathmandu',
      instantUtc: DateTime.utc(2026, 8, 20, 20, 15),
      expectedWallTime: DateTime(2026, 8, 21, 2),
      expectedOffsetSeconds: 5 * 60 * 60 + 45 * 60,
    ),
    (
      city: 'Tokyo, Japon',
      timeZone: 'Asia/Tokyo',
      instantUtc: DateTime.utc(2026, 8, 20, 20, 15),
      expectedWallTime: DateTime(2026, 8, 21, 5, 15),
      expectedOffsetSeconds: 9 * 60 * 60,
    ),
    (
      city: 'Sydney, Australie',
      timeZone: 'Australia/Sydney',
      instantUtc: DateTime.utc(2026, 8, 20, 20, 15),
      expectedWallTime: DateTime(2026, 8, 21, 6, 15),
      expectedOffsetSeconds: 10 * 60 * 60,
    ),
    (
      city: 'Auckland, Nouvelle-Zélande',
      timeZone: 'Pacific/Auckland',
      instantUtc: DateTime.utc(2026, 8, 20, 20, 15),
      expectedWallTime: DateTime(2026, 8, 21, 8, 15),
      expectedOffsetSeconds: 12 * 60 * 60,
    ),
  ];

  group('world timezone matrix', () {
    for (final item in cases) {
      test('${item.city} keeps its local date and wall clock', () async {
        expect(
          WeatherTimeZone.wallTime(item.instantUtc, item.timeZone),
          item.expectedWallTime,
        );
        expect(
          WeatherTimeZone.hourMinute(item.instantUtc, item.timeZone),
          _hourMinute(item.expectedWallTime),
        );
        expect(
          WeatherTimeZone.instantFromLocal(
            item.expectedWallTime,
            item.timeZone,
          ),
          item.instantUtc,
        );

        final forecast = await FixtureForecastDataSource(
          fixtureName: 'dry',
          clock: FixedWeatherClock(item.instantUtc),
          timeZone: item.timeZone,
          locationName: item.city,
        ).load();
        final snapshot = ForecastSnapshotBuilder.build(
          forecast: forecast,
          nowUtc: item.instantUtc,
        );

        expect(forecast.locationName, item.city);
        expect(forecast.timeZone, item.timeZone);
        expect(forecast.utcOffsetSeconds, item.expectedOffsetSeconds);
        expect(snapshot.wallClock, item.expectedWallTime);
        expect(
          snapshot.daily.first.date,
          DateTime(
            item.expectedWallTime.year,
            item.expectedWallTime.month,
            item.expectedWallTime.day,
          ),
        );
        expect(
          WeatherTimeZone.wallTime(snapshot.daily.first.sunrise, item.timeZone),
          DateTime(
            item.expectedWallTime.year,
            item.expectedWallTime.month,
            item.expectedWallTime.day,
            6,
            42,
          ),
        );
        expect(
          WeatherTimeZone.hourMinute(snapshot.hourly.first.time, item.timeZone),
          _hourMinute(item.expectedWallTime),
        );
      });
    }

    test('handles daylight-saving jumps in both hemispheres', () {
      expect(
        WeatherTimeZone.hourMinute(
          DateTime.utc(2026, 3, 8, 6, 30),
          'America/New_York',
        ),
        '01:30',
      );
      expect(
        WeatherTimeZone.hourMinute(
          DateTime.utc(2026, 3, 8, 7, 30),
          'America/New_York',
        ),
        '03:30',
      );
      expect(
        WeatherTimeZone.hourMinute(
          DateTime.utc(2026, 10, 3, 15, 30),
          'Australia/Sydney',
        ),
        '01:30',
      );
      expect(
        WeatherTimeZone.hourMinute(
          DateTime.utc(2026, 10, 3, 16, 30),
          'Australia/Sydney',
        ),
        '03:30',
      );
    });
  });

  group('world timezone widgets', () {
    for (final item in cases) {
      testWidgets('${item.city} is consistent across weather surfaces', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final forecast = _forecastFor(item);
        final snapshot = ForecastSnapshotBuilder.build(
          forecast: forecast,
          nowUtc: item.instantUtc,
        );
        final expectedTime = _hourMinute(item.expectedWallTime);
        final radarState = RadarReady(
          frames: [RadarFrame(time: item.instantUtc, progress: 1)],
          selectedIndex: 0,
          coordinates: Coordinates.paris,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: Column(
                children: [
                  LiveMetrics(forecast: forecast, snapshot: snapshot),
                  Expanded(
                    child: BlocProvider(
                      create: (_) => GraphHorizonCubit(),
                      child: GraphPane(forecast: forecast, snapshot: snapshot),
                    ),
                  ),
                  SizedBox(
                    height: 150,
                    child: RadarTimeline(
                      state: radarState,
                      forecast: forecast,
                      snapshot: snapshot,
                    ),
                  ),
                  SizedBox(
                    height: 220,
                    child: ForecastPane(forecast: forecast, snapshot: snapshot),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.descendant(
            of: find.byKey(const Key('current-local-time')),
            matching: find.text(expectedTime),
          ),
          findsWidgets,
        );
        final graphSemantics = tester.widget<Semantics>(
          find.byKey(const Key('rain-chart-intensity-none')),
        );
        expect(graphSemantics.properties.label, contains(expectedTime));
        expect(graphSemantics.properties.label, contains(item.timeZone));

        final forecastSemantics = tester.widget<Semantics>(
          find.byKey(const Key('forecast-local-time')),
        );
        expect(forecastSemantics.properties.label, contains(expectedTime));
        expect(forecastSemantics.properties.label, contains(item.timeZone));

        final radarSemantics = tester.widget<Semantics>(
          find.byKey(const Key('radar-local-time')),
        );
        expect(radarSemantics.properties.label, contains(expectedTime));
        expect(radarSemantics.properties.label, contains(item.timeZone));

        expect(tester.takeException(), isNull);
      });
    }
  });
}

String _hourMinute(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

Forecast _forecastFor(_WorldTimeCase item) => Forecast(
  locationName: item.city,
  updatedAt: item.instantUtc,
  temperatureCelsius: 20,
  windKph: 10,
  timeZone: item.timeZone,
  utcOffsetSeconds: item.expectedOffsetSeconds,
  brief: const WeatherBrief(
    type: WeatherBriefType.dry,
    intensity: RainIntensity.none,
    headline: 'Temps sec',
    detail: 'Aucune pluie prévue',
  ),
  points: [
    RainPoint(
      time: item.instantUtc,
      rateMmPerHour: 0,
      intensity: RainIntensity.none,
    ),
  ],
  windows: const [],
);
