import 'package:chetiwa/features/forecast/domain/entities/forecast.dart';
import 'package:chetiwa/features/forecast/domain/services/rain_chart_series.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chart series always reaches the exact horizon boundary', () {
    final now = DateTime.utc(2026, 8, 23, 12);
    final series = buildRainChartSeries(
      points: [
        _point(now.add(const Duration(minutes: 105)), 1),
        _point(now.add(const Duration(minutes: 135)), 3),
      ],
      currentRain: _point(now, 0),
      now: now,
      duration: const Duration(hours: 2),
    );

    expect(series.first.time, now);
    expect(series.last.time, now.add(const Duration(hours: 2)));
    expect(series.last.rateMmPerHour, 2);
  });

  test('chart series keeps dry samples between separate rain episodes', () {
    final now = DateTime.utc(2026, 8, 23, 12);
    final dryTime = now.add(const Duration(hours: 1));
    final series = buildRainChartSeries(
      points: [
        _point(now.add(const Duration(minutes: 30)), 2),
        _point(dryTime, 0),
        _point(now.add(const Duration(minutes: 90)), 4),
        _point(now.add(const Duration(hours: 2)), 0),
      ],
      currentRain: _point(now, 0),
      now: now,
      duration: const Duration(hours: 2),
    );

    expect(series.map((point) => point.time), contains(dryTime));
    expect(series.map((point) => point.rateMmPerHour), [0, 2, 0, 4, 0]);
  });
}

RainPoint _point(DateTime time, double rate) => RainPoint(
  time: time,
  rateMmPerHour: rate,
  probability: rate > 0 ? 1 : 0,
  intensity: rate >= 4
      ? RainIntensity.heavy
      : rate > 0
      ? RainIntensity.light
      : RainIntensity.none,
);
