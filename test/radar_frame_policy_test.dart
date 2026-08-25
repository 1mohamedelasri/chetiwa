import 'package:chetiwa/features/radar/domain/services/radar_frame_policy.dart';
import 'package:chetiwa/features/radar/domain/entities/radar_frame.dart';
import 'package:chetiwa/core/weather/weather_data_provenance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps a bounded window centred on recent observations and nowcast', () {
    final observed = List.generate(20, (index) => 'past-$index');
    final nowcast = List.generate(20, (index) => 'next-$index');

    final selected = RadarFramePolicy.select(observed, nowcast);

    expect(selected, hasLength(RadarFramePolicy.maxFrames));
    expect(selected.first, 'past-8');
    expect(selected[11], 'past-19');
    expect(selected[12], 'next-0');
    expect(selected.last, 'next-11');
  });

  test('timeline ends at the final real nowcast frame, not at now plus 2h', () {
    final now = DateTime.utc(2026, 8, 23, 20, 7);
    final lastNowcast = DateTime.utc(2026, 8, 23, 21);
    final window = RadarFramePolicy.timelineWindow([
      RadarFrame(
        time: DateTime.utc(2026, 8, 23, 20),
        progress: 0,
        kind: WeatherDataKind.radarObservation,
      ),
      RadarFrame(
        time: DateTime.utc(2026, 8, 23, 20, 30),
        progress: 0.5,
        kind: WeatherDataKind.radarNowcast,
      ),
      RadarFrame(
        time: lastNowcast,
        progress: 1,
        kind: WeatherDataKind.radarNowcast,
      ),
    ], now);

    expect(window.start, now);
    expect(window.end, lastNowcast);
    expect(window.end, isNot(now.add(const Duration(hours: 2))));
  });

  test('classifies and displays the premium model tail after 60 minutes', () {
    final observation = DateTime.utc(2026, 8, 23, 20);
    final model = observation.add(const Duration(minutes: 70));

    expect(
      RadarFramePolicy.futureKind(
        latestObservation: observation,
        forecastTime: observation.add(const Duration(minutes: 60)),
      ),
      WeatherDataKind.radarNowcast,
    );
    expect(
      RadarFramePolicy.futureKind(
        latestObservation: observation,
        forecastTime: model,
      ),
      WeatherDataKind.modelForecast,
    );

    final window = RadarFramePolicy.timelineWindow([
      RadarFrame(
        time: observation,
        progress: 0,
        kind: WeatherDataKind.radarObservation,
      ),
      RadarFrame(
        time: observation.add(const Duration(minutes: 60)),
        progress: 0.5,
        kind: WeatherDataKind.radarNowcast,
      ),
      RadarFrame(time: model, progress: 1, kind: WeatherDataKind.modelForecast),
    ], observation);

    expect(window.end, model);
  });
}
