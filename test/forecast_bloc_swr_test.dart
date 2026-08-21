import 'dart:async';

import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/time/weather_clock.dart';
import 'package:chetiwa/features/forecast/application/forecast_bloc.dart';
import 'package:chetiwa/features/forecast/domain/entities/forecast.dart';
import 'package:chetiwa/features/forecast/domain/repositories/forecast_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'emits cached data before silently replacing it with fresh data',
    () async {
      final cachedForecast = _forecast('Cache', 17);
      final freshForecast = _forecast('Réseau', 19);
      final repository = _SWRForecastRepository(cachedForecast);
      final bloc = ForecastBloc(
        repository,
        clock: FixedWeatherClock(DateTime.utc(2026, 8, 18, 10)),
      );

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([
          isA<ForecastReady>()
              .having(
                (state) => state.forecast.locationName,
                'location',
                'Cache',
              )
              .having((state) => state.isRefreshing, 'refreshing', isTrue)
              .having((state) => state.isStale, 'stale', isTrue),
          isA<ForecastReady>()
              .having(
                (state) => state.forecast.locationName,
                'location',
                'Réseau',
              )
              .having((state) => state.isRefreshing, 'refreshing', isFalse),
        ]),
      );

      bloc.add(const ForecastRequested());
      await Future<void>.delayed(Duration.zero);
      repository.complete(freshForecast);
      await expectation;
      await bloc.close();
    },
  );
}

final class _SWRForecastRepository implements ForecastRepository {
  _SWRForecastRepository(this.cached);

  final Forecast cached;
  final _fresh = Completer<Forecast>();

  void complete(Forecast forecast) => _fresh.complete(forecast);

  @override
  Future<CachedForecast?> getCachedForecast(Coordinates coordinates) async =>
      CachedForecast(forecast: cached, cachedAt: DateTime.utc(2026, 8, 18, 9));

  @override
  Future<Forecast> getForecast(Coordinates coordinates) => _fresh.future;
}

Forecast _forecast(String location, double temperature) {
  final now = DateTime(2026, 8, 18, 10);
  return Forecast(
    locationName: location,
    updatedAt: now,
    temperatureCelsius: temperature,
    windKph: 10,
    brief: const WeatherBrief(
      type: WeatherBriefType.dry,
      intensity: RainIntensity.none,
      headline: 'Pas de pluie',
      detail: 'Conditions sèches',
    ),
    points: [
      RainPoint(time: now, rateMmPerHour: 0, intensity: RainIntensity.none),
    ],
    windows: const [],
  );
}
