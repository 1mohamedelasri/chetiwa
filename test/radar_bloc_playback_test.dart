import 'dart:async';

import 'package:chetiwa/features/radar/application/radar_bloc.dart';
import 'package:chetiwa/features/radar/data/repositories/fixture_radar_repository.dart';
import 'package:chetiwa/features/radar/domain/entities/radar_frame.dart';
import 'package:chetiwa/features/radar/domain/repositories/radar_repository.dart';
import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/time/weather_clock.dart';
import 'package:chetiwa/core/weather/weather_data_provenance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('autoplay start is idempotent and never toggles playback off', () async {
    final bloc = RadarBloc(const FixtureRadarRepository());
    addTearDown(bloc.close);

    bloc.add(const RadarRequested());
    await bloc.stream
        .where((state) => state is RadarReady)
        .cast<RadarReady>()
        .first
        .timeout(const Duration(seconds: 2));

    bloc.add(const RadarPlaybackStarted());
    await bloc.stream
        .where((state) => state is RadarReady)
        .cast<RadarReady>()
        .firstWhere((state) => state.isPlaying)
        .timeout(const Duration(seconds: 2));
    bloc.add(const RadarPlaybackStarted());
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect((bloc.state as RadarReady).isPlaying, isTrue);
  });

  test(
    'native tile handoff gate prevents the cursor outrunning Radar',
    () async {
      final bloc = RadarBloc(const FixtureRadarRepository());
      addTearDown(bloc.close);

      bloc.add(const RadarRequested());
      await bloc.stream
          .where((state) => state is RadarReady)
          .cast<RadarReady>()
          .first
          .timeout(const Duration(seconds: 2));
      bloc.add(const RadarPlaybackStarted());
      final playing = await bloc.stream
          .where((state) => state is RadarReady)
          .cast<RadarReady>()
          .firstWhere((state) => state.isPlaying)
          .timeout(const Duration(seconds: 2));

      bloc.add(const RadarPlaybackClockHeld());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      bloc.add(const RadarPlaybackAdvanced());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((bloc.state as RadarReady).selectedIndex, playing.selectedIndex);
      expect((bloc.state as RadarReady).isPlaying, isTrue);

      bloc.add(const RadarPlaybackClockReleased());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final advanced = bloc.stream
          .where((state) => state is RadarReady)
          .cast<RadarReady>()
          .firstWhere((state) => state.selectedIndex != playing.selectedIndex);
      bloc.add(const RadarPlaybackAdvanced());
      await advanced.timeout(const Duration(seconds: 2));
    },
  );

  test(
    'playback loops and reset restart from the current observation',
    () async {
      final bloc = RadarBloc(const FixtureRadarRepository());
      addTearDown(bloc.close);

      bloc.add(const RadarRequested());
      final loaded = await bloc.stream
          .where((state) => state is RadarReady)
          .cast<RadarReady>()
          .first
          .timeout(const Duration(seconds: 2));
      expect(loaded.selectedIndex, loaded.currentObservationIndex);

      bloc.add(const RadarPlaybackToggled());
      final playing = await bloc.stream
          .where((state) => state is RadarReady)
          .cast<RadarReady>()
          .firstWhere((state) => state.isPlaying)
          .timeout(const Duration(seconds: 2));
      expect(playing.isPlaying, isTrue);
      expect(playing.selectedIndex, loaded.currentObservationIndex);

      final reachedNowcastFuture = bloc.stream
          .where((state) => state is RadarReady)
          .cast<RadarReady>()
          .firstWhere(
            (state) => state.isPlaying && state.selectedFrame.isNowcast,
          )
          .timeout(const Duration(seconds: 2));
      bloc.add(const RadarPlaybackAdvanced());
      final reachedNowcast = await reachedNowcastFuture;
      expect(reachedNowcast.selectedFrame.isNowcast, isTrue);

      for (
        var index = reachedNowcast.selectedIndex + 1;
        index < loaded.frames.length;
        index++
      ) {
        bloc.add(const RadarPlaybackAdvanced());
      }

      final loopedFuture = bloc.stream
          .where((state) => state is RadarReady)
          .cast<RadarReady>()
          .firstWhere(
            (state) =>
                state.isPlaying &&
                state.selectedIndex == state.currentObservationIndex,
          )
          .timeout(const Duration(seconds: 2));
      bloc.add(const RadarPlaybackAdvanced());
      final looped = await loopedFuture;
      expect(looped.isPlaying, isTrue);

      final historicalFuture = bloc.stream
          .where((state) => state is RadarReady)
          .cast<RadarReady>()
          .firstWhere((state) => state.selectedIndex == 1)
          .timeout(const Duration(seconds: 2));
      bloc.add(const RadarFrameSelected(1));
      final historical = await historicalFuture;
      expect(historical.isAtLatestObservation, isFalse);

      final restartedFuture = bloc.stream
          .where((state) => state is RadarReady)
          .cast<RadarReady>()
          .firstWhere(
            (state) =>
                state.isPlaying &&
                state.selectedIndex == state.currentObservationIndex,
          )
          .timeout(const Duration(seconds: 2));
      bloc.add(const RadarPlaybackRestarted());
      final restarted = await restartedFuture;
      expect(restarted.isPlaying, isTrue);

      final pausedFuture = bloc.stream
          .where((state) => state is RadarReady)
          .cast<RadarReady>()
          .firstWhere(
            (state) =>
                !state.isPlaying &&
                state.selectedIndex == state.currentObservationIndex,
          )
          .timeout(const Duration(seconds: 2));
      bloc.add(const RadarPlaybackPaused());
      final paused = await pausedFuture;
      expect(paused.isPlaying, isFalse);

      final movedBackFuture = bloc.stream
          .where((state) => state is RadarReady)
          .cast<RadarReady>()
          .firstWhere((state) => state.selectedIndex == 1)
          .timeout(const Duration(seconds: 2));
      bloc.add(const RadarFrameSelected(1));
      await movedBackFuture;

      final nowFuture = bloc.stream
          .where((state) => state is RadarReady)
          .cast<RadarReady>()
          .firstWhere((state) => state.isAtLatestObservation)
          .timeout(const Duration(seconds: 2));
      bloc.add(const RadarNowRequested());
      final now = await nowFuture;
      expect(now.selectedIndex, now.currentObservationIndex);
      expect(now.isPlaying, isFalse);
    },
  );

  test(
    'observation-only playback animates the real historical frames',
    () async {
      final bloc = RadarBloc(const _ObservedOnlyRadarRepository());
      addTearDown(bloc.close);

      bloc.add(const RadarRequested());
      final loaded = await bloc.stream
          .where((state) => state is RadarReady)
          .cast<RadarReady>()
          .first
          .timeout(const Duration(seconds: 2));
      expect(loaded.hasNowcast, isFalse);
      expect(loaded.playbackStartIndex, 0);

      bloc.add(const RadarPlaybackToggled());
      final playing = await bloc.stream
          .where((state) => state is RadarReady)
          .cast<RadarReady>()
          .firstWhere((state) => state.isPlaying)
          .timeout(const Duration(seconds: 2));
      expect(playing.selectedIndex, 0);

      final advancedFuture = bloc.stream
          .where((state) => state is RadarReady)
          .cast<RadarReady>()
          .firstWhere((state) => state.isPlaying && state.selectedIndex == 1)
          .timeout(const Duration(seconds: 2));
      bloc.add(const RadarPlaybackAdvanced());
      await advancedFuture;

      bloc.add(const RadarFrameSelected(2));
      await bloc.stream
          .where((state) => state is RadarReady)
          .cast<RadarReady>()
          .firstWhere((state) => state.selectedIndex == 2)
          .timeout(const Duration(seconds: 2));
      final loopedFuture = bloc.stream
          .where((state) => state is RadarReady)
          .cast<RadarReady>()
          .firstWhere((state) => state.isPlaying && state.selectedIndex == 0)
          .timeout(const Duration(seconds: 2));
      bloc.add(const RadarPlaybackAdvanced());
      await loopedFuture;
    },
  );

  test('a stale response cannot replace the newly selected location', () async {
    const lyon = Coordinates(latitude: 45.7640, longitude: 4.8357);
    final bloc = RadarBloc(const _RacingRadarRepository());
    addTearDown(bloc.close);

    bloc.add(const RadarRequested());
    await Future<void>.delayed(const Duration(milliseconds: 5));
    bloc.add(const RadarLocationChanged(lyon));

    await bloc.stream
        .where((state) => state is RadarReady)
        .cast<RadarReady>()
        .firstWhere((state) => state.coordinates == lyon)
        .timeout(const Duration(seconds: 2));
    // The deliberately slower Paris request completes after Lyon. Its result
    // must be discarded rather than moving the map back to Paris.
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect((bloc.state as RadarReady).coordinates, lyon);
  });

  test('a network refresh does not stop playback started from cache', () async {
    final repository = _RefreshingRadarRepository();
    final bloc = RadarBloc(repository);
    addTearDown(bloc.close);

    bloc.add(const RadarRequested());
    final cached = await bloc.stream
        .where((state) => state is RadarReady)
        .cast<RadarReady>()
        .firstWhere((state) => state.isRefreshing)
        .timeout(const Duration(seconds: 2));
    expect(cached.isPlaying, isFalse);

    bloc.add(const RadarPlaybackRestarted());
    await bloc.stream
        .where((state) => state is RadarReady)
        .cast<RadarReady>()
        .firstWhere((state) => state.isPlaying)
        .timeout(const Duration(seconds: 2));

    repository.completeRefresh();
    final fresh = await bloc.stream
        .where((state) => state is RadarReady)
        .cast<RadarReady>()
        .firstWhere((state) => !state.isRefreshing)
        .timeout(const Duration(seconds: 2));
    expect(fresh.isPlaying, isTrue);
  });

  test('background suspension resumes unless the user paused', () async {
    final bloc = RadarBloc(const FixtureRadarRepository());
    addTearDown(bloc.close);

    bloc.add(const RadarRequested());
    await bloc.stream
        .where((state) => state is RadarReady)
        .cast<RadarReady>()
        .first
        .timeout(const Duration(seconds: 2));
    bloc.add(const RadarPlaybackRestarted());
    await bloc.stream
        .where((state) => state is RadarReady)
        .cast<RadarReady>()
        .firstWhere((state) => state.isPlaying)
        .timeout(const Duration(seconds: 2));

    bloc.add(const RadarPlaybackSuspended());
    await bloc.stream
        .where((state) => state is RadarReady)
        .cast<RadarReady>()
        .firstWhere((state) => !state.isPlaying)
        .timeout(const Duration(seconds: 2));

    // Real devices normally emit inactive followed by paused for one sleep.
    bloc.add(const RadarPlaybackSuspended());
    bloc.add(const RadarPlaybackResumed());
    final resumed = await bloc.stream
        .where((state) => state is RadarReady)
        .cast<RadarReady>()
        .firstWhere((state) => state.isPlaying)
        .timeout(const Duration(seconds: 2));
    expect(resumed.isPlaying, isTrue);

    bloc.add(const RadarPlaybackPaused());
    await bloc.stream
        .where((state) => state is RadarReady)
        .cast<RadarReady>()
        .firstWhere((state) => !state.isPlaying)
        .timeout(const Duration(seconds: 2));
    bloc.add(const RadarPlaybackSuspended());
    bloc.add(const RadarPlaybackResumed());
    await Future<void>.delayed(Duration.zero);
    expect((bloc.state as RadarReady).isPlaying, isFalse);
  });

  test(
    'model frames are exposed only after premium access is enabled',
    () async {
      final bloc = RadarBloc(
        const _PremiumRadarRepository(),
        clock: FixedWeatherClock(DateTime.utc(2026, 8, 22, 12)),
      );
      addTearDown(bloc.close);

      bloc.add(const RadarRequested());
      final free = await bloc.stream
          .where((state) => state is RadarReady)
          .cast<RadarReady>()
          .first
          .timeout(const Duration(seconds: 2));
      expect(free.frames.any((frame) => frame.isModelForecast), isFalse);
      expect(free.hasForecast, isTrue);

      bloc.add(
        const RadarPremiumAccessChanged(
          allowModelForecast: true,
          maxFrames: 24,
          historyHours: 6,
        ),
      );
      final premium = await bloc.stream
          .where((state) => state is RadarReady)
          .cast<RadarReady>()
          .firstWhere(
            (state) => state.frames.any((frame) => frame.isModelForecast),
          )
          .timeout(const Duration(seconds: 2));
      expect(premium.frames.last.isModelForecast, isTrue);

      bloc.add(
        const RadarPremiumAccessChanged(
          allowModelForecast: false,
          maxFrames: 12,
          historyHours: 2,
        ),
      );
      final downgraded = await bloc.stream
          .where((state) => state is RadarReady)
          .cast<RadarReady>()
          .firstWhere(
            (state) => !state.frames.any((frame) => frame.isModelForecast),
          )
          .timeout(const Duration(seconds: 2));
      expect(downgraded.frames.any((frame) => frame.isModelForecast), isFalse);
    },
  );
}

final class _PremiumRadarRepository implements RadarRepository {
  const _PremiumRadarRepository();

  @override
  Future<CachedRadarFrames?> getCachedFrames(Coordinates coordinates) async =>
      null;

  @override
  Future<List<RadarFrame>> getFrames(Coordinates coordinates) async {
    final observation = DateTime.utc(2026, 8, 22, 12);
    return <RadarFrame>[
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
      RadarFrame(
        time: observation.add(const Duration(minutes: 70)),
        progress: 1,
        kind: WeatherDataKind.modelForecast,
      ),
    ];
  }
}

final class _RefreshingRadarRepository implements RadarRepository {
  final Completer<void> _refresh = Completer<void>();

  List<RadarFrame> get _frames {
    final now = DateTime.utc(2026, 8, 22, 12);
    return List.generate(
      3,
      (index) => RadarFrame(
        time: now.add(Duration(minutes: index * 10)),
        progress: index / 2,
        tileUrlTemplate: 'https://example.test/$index/{z}/{x}/{y}.png',
        kind: index == 0
            ? WeatherDataKind.radarObservation
            : WeatherDataKind.radarNowcast,
      ),
      growable: false,
    );
  }

  void completeRefresh() => _refresh.complete();

  @override
  Future<CachedRadarFrames?> getCachedFrames(Coordinates coordinates) async =>
      CachedRadarFrames(
        frames: _frames,
        cachedAt: DateTime.utc(2026, 8, 22, 12),
      );

  @override
  Future<List<RadarFrame>> getFrames(Coordinates coordinates) async {
    await _refresh.future;
    return _frames;
  }
}

final class _ObservedOnlyRadarRepository implements RadarRepository {
  const _ObservedOnlyRadarRepository();

  @override
  Future<CachedRadarFrames?> getCachedFrames(Coordinates coordinates) async =>
      null;

  @override
  Future<List<RadarFrame>> getFrames(Coordinates coordinates) async {
    final now = DateTime.utc(2026, 8, 22, 12);
    return List.generate(
      3,
      (index) => RadarFrame(
        time: now.subtract(Duration(minutes: (2 - index) * 10)),
        progress: index / 2,
        tileUrlTemplate: 'https://example.test/$index/{z}/{x}/{y}.png',
      ),
      growable: false,
    );
  }
}

final class _RacingRadarRepository implements RadarRepository {
  const _RacingRadarRepository();

  @override
  Future<CachedRadarFrames?> getCachedFrames(Coordinates coordinates) async =>
      null;

  @override
  Future<List<RadarFrame>> getFrames(Coordinates coordinates) async {
    await Future<void>.delayed(
      coordinates == Coordinates.paris
          ? const Duration(milliseconds: 80)
          : const Duration(milliseconds: 5),
    );
    return [
      RadarFrame(
        time: DateTime.utc(2026, 8, 22, 12),
        progress: 1,
        tileUrlTemplate: 'https://example.test/{z}/{x}/{y}.png',
      ),
    ];
  }
}
