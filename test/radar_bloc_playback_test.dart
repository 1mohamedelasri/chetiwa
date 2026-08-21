import 'package:chetiwa/features/radar/application/radar_bloc.dart';
import 'package:chetiwa/features/radar/data/repositories/fixture_radar_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('playback loops and reset restarts from the first frame', () async {
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
    expect(playing.selectedIndex, 0);

    final reachedLatestObservationFuture = bloc.stream
        .where((state) => state is RadarReady)
        .cast<RadarReady>()
        .firstWhere((state) => state.isPlaying && state.isAtLatestObservation)
        .timeout(const Duration(seconds: 2));
    for (var index = 1; index <= loaded.currentObservationIndex; index++) {
      bloc.add(const RadarPlaybackAdvanced());
    }
    final reachedLatestObservation = await reachedLatestObservationFuture;
    expect(reachedLatestObservation.isPlaying, isTrue);

    final reachedNowcastFuture = bloc.stream
        .where((state) => state is RadarReady)
        .cast<RadarReady>()
        .firstWhere((state) => state.isPlaying && state.selectedFrame.isNowcast)
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
        .firstWhere((state) => state.isPlaying && state.selectedIndex == 0)
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
        .firstWhere((state) => state.isPlaying && state.selectedIndex == 0)
        .timeout(const Duration(seconds: 2));
    bloc.add(const RadarPlaybackRestarted());
    final restarted = await restartedFuture;
    expect(restarted.isPlaying, isTrue);

    final pausedFuture = bloc.stream
        .where((state) => state is RadarReady)
        .cast<RadarReady>()
        .firstWhere((state) => !state.isPlaying && state.selectedIndex == 0)
        .timeout(const Duration(seconds: 2));
    bloc.add(const RadarPlaybackPaused());
    final paused = await pausedFuture;
    expect(paused.isPlaying, isFalse);

    final nowFuture = bloc.stream
        .where((state) => state is RadarReady)
        .cast<RadarReady>()
        .firstWhere((state) => state.isAtLatestObservation)
        .timeout(const Duration(seconds: 2));
    bloc.add(const RadarNowRequested());
    final now = await nowFuture;
    expect(now.selectedIndex, now.currentObservationIndex);
    expect(now.isPlaying, isFalse);
  });
}
