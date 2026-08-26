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

  test('stale nowcast keeps a non-zero playback window for the cursor', () {
    final observation = DateTime.utc(2026, 8, 26, 11, 50);
    final lastNowcast = DateTime.utc(2026, 8, 26, 12, 50);
    final phoneNow = DateTime.utc(2026, 8, 26, 16, 36);

    final window = RadarFramePolicy.timelineWindow([
      RadarFrame(
        time: observation.subtract(const Duration(minutes: 10)),
        progress: 0,
        kind: WeatherDataKind.radarObservation,
      ),
      RadarFrame(
        time: observation,
        progress: 0.2,
        kind: WeatherDataKind.radarObservation,
      ),
      RadarFrame(
        time: observation.add(const Duration(minutes: 10)),
        progress: 0.4,
        kind: WeatherDataKind.radarNowcast,
      ),
      RadarFrame(
        time: lastNowcast,
        progress: 1,
        kind: WeatherDataKind.modelForecast,
      ),
    ], phoneNow);

    expect(window.start, observation);
    expect(window.end, lastNowcast);
    expect(window.end.difference(window.start), const Duration(hours: 1));
    expect(
      RadarFramePolicy.interpolateFrameTime(
        observation,
        observation.add(const Duration(minutes: 10)),
        0.5,
      ),
      observation.add(const Duration(minutes: 5)),
    );
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

  test('keeps every interpolated ten-minute extended forecast frame', () {
    final observation = DateTime.utc(2026, 8, 23, 20);
    final frames = <RadarFrame>[
      RadarFrame(
        time: observation,
        progress: 0,
        kind: WeatherDataKind.radarObservation,
      ),
      RadarFrame(
        time: observation.add(const Duration(minutes: 60)),
        progress: 0.4,
        kind: WeatherDataKind.radarNowcast,
      ),
      for (var lead = 70; lead <= 120; lead += 10)
        RadarFrame(
          time: observation.add(Duration(minutes: lead)),
          progress: lead / 120,
          kind: WeatherDataKind.modelForecast,
        ),
    ];

    final selected = RadarFramePolicy.normalizeProgress(frames);

    expect(
      selected
          .where((frame) => frame.isModelForecast)
          .map((frame) => frame.time.difference(observation).inMinutes),
      [70, 80, 90, 100, 110, 120],
    );
    expect(selected.first.progress, 0);
    expect(selected.last.progress, 1);
  });

  test('playhead remains continuous across the +60 minute boundary', () {
    final current = DateTime.utc(2026, 8, 26, 1);
    final next = current.add(const Duration(minutes: 10));

    expect(
      RadarFramePolicy.interpolateFrameTime(current, next, 0.5),
      current.add(const Duration(minutes: 5)),
    );
    expect(RadarFramePolicy.playbackFrameDuration.inMilliseconds, 2000);
  });
}
