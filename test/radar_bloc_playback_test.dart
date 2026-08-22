import 'package:chetiwa/features/radar/application/radar_bloc.dart';
import 'package:chetiwa/features/radar/data/repositories/fixture_radar_repository.dart';
import 'package:chetiwa/features/radar/domain/entities/radar_frame.dart';
import 'package:chetiwa/features/radar/domain/repositories/radar_repository.dart';
import 'package:chetiwa/core/location/coordinates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
