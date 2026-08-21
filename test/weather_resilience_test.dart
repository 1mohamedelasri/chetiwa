import 'dart:async';

import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/time/weather_clock.dart';
import 'package:chetiwa/core/weather/weather_data_health.dart';
import 'package:chetiwa/core/widgets/weather_data_status.dart';
import 'package:chetiwa/features/forecast/application/forecast_bloc.dart';
import 'package:chetiwa/features/forecast/domain/entities/forecast.dart';
import 'package:chetiwa/features/forecast/domain/repositories/forecast_repository.dart';
import 'package:chetiwa/features/radar/application/radar_bloc.dart';
import 'package:chetiwa/features/radar/domain/entities/radar_frame.dart';
import 'package:chetiwa/features/radar/domain/repositories/radar_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  final clock = FixedWeatherClock(DateTime.utc(2026, 8, 20, 12));

  test('forecast preserves stale cache and exposes an offline issue', () async {
    final repository = _FailingForecastRepository(
      cached: CachedForecast(
        forecast: _forecast,
        cachedAt: DateTime.utc(2026, 8, 20, 10),
      ),
      issue: WeatherDataIssue.offline,
    );
    final bloc = ForecastBloc(repository, clock: clock);
    addTearDown(bloc.close);

    final expectation = expectLater(
      bloc.stream,
      emitsInOrder([
        isA<ForecastReady>()
            .having(
              (state) => state.health.freshness,
              'freshness',
              WeatherDataFreshness.cachedStale,
            )
            .having((state) => state.isRefreshing, 'refreshing', isTrue),
        isA<ForecastReady>()
            .having(
              (state) => state.health.issue,
              'issue',
              WeatherDataIssue.offline,
            )
            .having((state) => state.isStale, 'stale', isTrue)
            .having((state) => state.isRefreshing, 'refreshing', isFalse),
      ]),
    );

    bloc.add(const ForecastRequested());
    await expectation;
  });

  test('forecast exposes provider failure when no cache exists', () async {
    final bloc = ForecastBloc(
      const _FailingForecastRepository(
        issue: WeatherDataIssue.providerUnavailable,
      ),
      clock: clock,
    );
    addTearDown(bloc.close);

    bloc.add(const ForecastRequested());
    final failure = await bloc.stream
        .where((state) => state is ForecastFailure)
        .cast<ForecastFailure>()
        .first;

    expect(failure.issue, WeatherDataIssue.providerUnavailable);
  });

  test(
    'a slow refresh keeps cached forecast visible until completion',
    () async {
      final repository = _ControlledForecastRepository(
        cached: CachedForecast(
          forecast: _forecast,
          cachedAt: DateTime.utc(2026, 8, 20, 11, 58),
        ),
      );
      final bloc = ForecastBloc(repository, clock: clock);
      addTearDown(bloc.close);

      final refreshing = bloc.stream
          .where((state) => state is ForecastReady)
          .cast<ForecastReady>()
          .firstWhere((state) => state.isRefreshing);
      bloc.add(const ForecastRequested());
      final visible = await refreshing;

      expect(visible.forecast, _forecast);
      expect(visible.health.freshness, WeatherDataFreshness.cachedFresh);
      expect(repository.request.isCompleted, isFalse);

      repository.request.complete(_forecast);
      final ready = await bloc.stream
          .where((state) => state is ForecastReady)
          .cast<ForecastReady>()
          .firstWhere((state) => !state.isRefreshing);
      expect(ready.health.issue, isNull);
    },
  );

  test(
    'an intermittent failure recovers on the next explicit refresh',
    () async {
      final repository = _IntermittentForecastRepository();
      final bloc = ForecastBloc(repository, clock: clock);
      addTearDown(bloc.close);

      bloc.add(const ForecastRequested());
      final failure = await bloc.stream
          .where((state) => state is ForecastFailure)
          .cast<ForecastFailure>()
          .first;
      expect(failure.issue, WeatherDataIssue.offline);

      bloc.add(const ForecastRefreshed());
      final recovered = await bloc.stream
          .where((state) => state is ForecastReady)
          .cast<ForecastReady>()
          .first;
      expect(recovered.forecast, _forecast);
      expect(recovered.health.issue, isNull);
    },
  );

  test(
    'clock ticks refresh the displayed age without losing cache state',
    () async {
      final mutableClock = _MutableWeatherClock(DateTime.utc(2026, 8, 20, 12));
      final bloc = ForecastBloc(
        _FailingForecastRepository(
          cached: CachedForecast(
            forecast: _forecast,
            cachedAt: DateTime.utc(2026, 8, 20, 10),
          ),
          issue: WeatherDataIssue.offline,
        ),
        clock: mutableClock,
      );
      addTearDown(bloc.close);

      final offlineFuture = bloc.stream
          .where((state) => state is ForecastReady)
          .cast<ForecastReady>()
          .firstWhere(
            (state) => state.health.issue == WeatherDataIssue.offline,
          );
      bloc.add(const ForecastRequested());
      await offlineFuture;

      mutableClock.value = DateTime.utc(2026, 8, 20, 12, 1);
      final tickFuture = bloc.stream
          .where((state) => state is ForecastReady)
          .cast<ForecastReady>()
          .firstWhere(
            (state) =>
                state.snapshot.nowUtc == DateTime.utc(2026, 8, 20, 12, 1),
          );
      bloc.add(const ForecastClockTicked());
      final ticked = await tickFuture;

      expect(ticked.health.issue, WeatherDataIssue.offline);
      expect(ticked.health.freshness, WeatherDataFreshness.cachedStale);
    },
  );

  test('radar preserves fresh cache when the network is offline', () async {
    final repository = _FailingRadarRepository(
      cached: CachedRadarFrames(
        frames: _frames,
        cachedAt: DateTime.utc(2026, 8, 20, 11, 55),
      ),
      issue: WeatherDataIssue.offline,
    );
    final bloc = RadarBloc(repository, clock: clock);
    addTearDown(bloc.close);

    final expectation = expectLater(
      bloc.stream,
      emitsInOrder([
        isA<RadarReady>()
            .having(
              (state) => state.health.freshness,
              'freshness',
              WeatherDataFreshness.cachedFresh,
            )
            .having((state) => state.isRefreshing, 'refreshing', isTrue),
        isA<RadarReady>()
            .having(
              (state) => state.health.issue,
              'issue',
              WeatherDataIssue.offline,
            )
            .having((state) => state.isRefreshing, 'refreshing', isFalse),
      ]),
    );

    bloc.add(const RadarRequested());
    await expectation;
  });

  test('radar distinguishes missing coverage without cached images', () async {
    final bloc = RadarBloc(
      const _FailingRadarRepository(issue: WeatherDataIssue.noRadarCoverage),
      clock: clock,
    );
    addTearDown(bloc.close);

    bloc.add(const RadarRequested());
    final failure = await bloc.stream
        .where((state) => state is RadarFailure)
        .cast<RadarFailure>()
        .first;

    expect(failure.issue, WeatherDataIssue.noRadarCoverage);
  });

  testWidgets('status banner explains offline cached data', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeatherDataStatusBanner(
            health: const WeatherDataHealth(
              freshness: WeatherDataFreshness.cachedStale,
              issue: WeatherDataIssue.offline,
            ),
            domainLabel: 'Open-Meteo',
            nowUtc: DateTime.utc(2026, 8, 20, 12),
            dataUpdatedAt: DateTime.utc(2026, 8, 20, 10, 42),
          ),
        ),
      ),
    );

    expect(
      find.text('Hors-ligne · dernières données enregistrées affichées'),
      findsOneWidget,
    );
    expect(find.text('Données mises à jour il y a 1 h 18 min'), findsOneWidget);
  });

  test('formats recent, hourly and daily data ages', () {
    final now = DateTime.utc(2026, 8, 20, 12);

    expect(
      weatherDataAgeLabel(
        nowUtc: now,
        dataUpdatedAt: DateTime.utc(2026, 8, 20, 11, 59, 45),
      ),
      'à l’instant',
    );
    expect(
      weatherDataAgeLabel(
        nowUtc: now,
        dataUpdatedAt: DateTime.utc(2026, 8, 20, 10, 52),
      ),
      'il y a 1 h 08 min',
    );
    expect(
      weatherDataAgeLabel(
        nowUtc: now,
        dataUpdatedAt: DateTime.utc(2026, 8, 19, 9),
      ),
      'il y a 1 jour 3 h',
    );
  });

  testWidgets('unavailable view explains missing radar coverage', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeatherDataUnavailableView(
            issue: WeatherDataIssue.noRadarCoverage,
            domainLabel: 'RainViewer',
            onRetry: () {},
          ),
        ),
      ),
    );

    expect(find.text('Radar non couvert'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });
}

final class _FailingForecastRepository implements ForecastRepository {
  const _FailingForecastRepository({this.cached, required this.issue});

  final CachedForecast? cached;
  final WeatherDataIssue issue;

  @override
  Future<CachedForecast?> getCachedForecast(Coordinates coordinates) async =>
      cached;

  @override
  Future<Forecast> getForecast(Coordinates coordinates) =>
      Future.error(WeatherDataException(issue, 'Test failure'));
}

final class _ControlledForecastRepository implements ForecastRepository {
  _ControlledForecastRepository({required this.cached});

  final CachedForecast cached;
  final request = Completer<Forecast>();

  @override
  Future<CachedForecast?> getCachedForecast(Coordinates coordinates) async =>
      cached;

  @override
  Future<Forecast> getForecast(Coordinates coordinates) => request.future;
}

final class _IntermittentForecastRepository implements ForecastRepository {
  var calls = 0;

  @override
  Future<CachedForecast?> getCachedForecast(Coordinates coordinates) async =>
      null;

  @override
  Future<Forecast> getForecast(Coordinates coordinates) async {
    calls++;
    if (calls == 1) {
      throw const WeatherDataException(
        WeatherDataIssue.offline,
        'Intermittent test failure',
      );
    }
    return _forecast;
  }
}

final class _MutableWeatherClock implements WeatherClock {
  _MutableWeatherClock(this.value);

  DateTime value;

  @override
  DateTime get nowUtc => value.toUtc();
}

final class _FailingRadarRepository implements RadarRepository {
  const _FailingRadarRepository({this.cached, required this.issue});

  final CachedRadarFrames? cached;
  final WeatherDataIssue issue;

  @override
  Future<CachedRadarFrames?> getCachedFrames(Coordinates coordinates) async =>
      cached;

  @override
  Future<List<RadarFrame>> getFrames(Coordinates coordinates) =>
      Future.error(WeatherDataException(issue, 'Test failure'));
}

final _forecast = Forecast(
  locationName: 'Paris, France',
  updatedAt: DateTime.utc(2026, 8, 20, 10),
  temperatureCelsius: 20,
  windKph: 8,
  brief: const WeatherBrief(
    type: WeatherBriefType.dry,
    intensity: RainIntensity.none,
    headline: 'Pas de pluie',
    detail: 'Conditions sèches',
  ),
  points: [
    RainPoint(
      time: DateTime.utc(2026, 8, 20, 12),
      rateMmPerHour: 0,
      intensity: RainIntensity.none,
    ),
  ],
  windows: const [],
);

final _frames = [
  RadarFrame(
    time: DateTime.utc(2026, 8, 20, 11, 50),
    progress: 0,
    tileUrlTemplate: 'https://tiles/{z}/{x}/{y}.png',
  ),
];
