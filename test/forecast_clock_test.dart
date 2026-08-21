import 'package:chetiwa/core/time/weather_clock.dart';
import 'package:chetiwa/core/weather/weather_data_provenance.dart';
import 'package:chetiwa/features/forecast/domain/entities/forecast.dart';
import 'package:chetiwa/features/forecast/domain/services/forecast_snapshot_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WeatherClock', () {
    test('keeps an injected absolute UTC instant', () {
      final clock = FixedWeatherClock(DateTime.parse('2026-08-19T17:58:30Z'));

      expect(clock.nowUtc, DateTime.utc(2026, 8, 19, 17, 58, 30));
    });

    test('uses the selected city timezone and crosses midnight', () {
      final paris = WeatherTimeZone.wallTime(
        DateTime.utc(2026, 8, 19, 22, 30),
        'Europe/Paris',
      );
      final tokyo = WeatherTimeZone.wallTime(
        DateTime.utc(2026, 8, 19, 22, 30),
        'Asia/Tokyo',
      );

      expect(paris, DateTime(2026, 8, 20, 0, 30));
      expect(tokyo, DateTime(2026, 8, 20, 7, 30));
    });

    test('applies the IANA daylight-saving transition', () {
      final before = WeatherTimeZone.wallTime(
        DateTime.utc(2026, 3, 29, 0, 30),
        'Europe/Paris',
      );
      final after = WeatherTimeZone.wallTime(
        DateTime.utc(2026, 3, 29, 1, 30),
        'Europe/Paris',
      );

      expect(before, DateTime(2026, 3, 29, 1, 30));
      expect(after, DateTime(2026, 3, 29, 3, 30));
    });
  });

  group('ForecastSnapshot', () {
    final now = DateTime.utc(2026, 8, 19, 17, 58);
    final forecast = Forecast(
      locationName: 'Paris, France',
      updatedAt: DateTime.utc(2026, 8, 19, 17, 45),
      temperatureCelsius: 22,
      windKph: 16,
      timeZone: 'Europe/Paris',
      utcOffsetSeconds: 2 * 60 * 60,
      brief: const WeatherBrief(
        type: WeatherBriefType.dry,
        intensity: RainIntensity.none,
        headline: 'Ancien résumé',
        detail: 'Ne doit pas être affiché',
      ),
      points: [
        RainPoint(
          time: DateTime.utc(2026, 8, 19, 17, 45),
          rateMmPerHour: 0.8,
          intensity: RainIntensity.moderate,
        ),
        RainPoint(
          time: DateTime.utc(2026, 8, 19, 18),
          rateMmPerHour: 0,
          intensity: RainIntensity.none,
        ),
      ],
      windows: const [],
    );

    test('interpolates rain at the same UTC instant used by every surface', () {
      final snapshot = ForecastSnapshotBuilder.build(
        forecast: forecast,
        nowUtc: now,
      );

      expect(snapshot.wallClock, DateTime(2026, 8, 19, 19, 58));
      expect(snapshot.currentRain.time, now);
      expect(snapshot.currentRain.rateMmPerHour, closeTo(0.1067, 0.001));
      expect(snapshot.currentRain.intensity, RainIntensity.light);
      expect(snapshot.brief.type, WeatherBriefType.raining);
      expect(snapshot.brief.headline, 'Pluie en cours');
      expect(snapshot.brief.detail, contains('20:00'));
      expect(snapshot.currentProvenance.kind, WeatherDataKind.modelEstimate);
      expect(snapshot.forecastProvenance.kind, WeatherDataKind.modelForecast);
      expect(snapshot.forecastProvenance.provider, 'Open-Meteo');
    });

    test('does not extrapolate expired rain beyond provider coverage', () {
      final snapshot = ForecastSnapshotBuilder.build(
        forecast: forecast,
        nowUtc: DateTime.utc(2026, 8, 19, 19),
      );

      expect(snapshot.currentRain.rateMmPerHour, 0);
      expect(snapshot.brief.type, WeatherBriefType.dry);
    });
  });
}
