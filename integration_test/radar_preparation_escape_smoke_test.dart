import 'package:chetiwa/app/app.dart';
import 'package:chetiwa/app/di/chetiwa_dependencies.dart';
import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/features/radar/application/radar_bloc.dart';
import 'package:chetiwa/features/radar/data/cache/radar_tile_cache.dart';
import 'package:chetiwa/features/radar/presentation/widgets/radar_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  testWidgets('a persistent tile outage never traps the Radar preparation UI', (
    tester,
  ) async {
    final cache = RadarTileCache.shared;
    expect(await RadarTileCache.clearDiskCacheForSmokeTest(), isTrue);
    await tester.pumpWidget(
      ChetiwaApp(
        dependencies: ChetiwaDependencies.live(firebaseAvailable: false),
      ),
    );
    await _waitFor(tester, find.byKey(const Key('rain-chart')));
    await tester.tap(find.text('Radar'));
    await tester.pump();
    await _waitFor(
      tester,
      find.byKey(const ValueKey('radar-first-tile-ready')),
      timeout: const Duration(seconds: 45),
    );
    await _waitFor(
      tester,
      find.byKey(const ValueKey('radar-preparation-hidden')),
      timeout: const Duration(seconds: 10),
    );

    expect(cache.clearVolatileCacheForSmokeTest(), isTrue);
    // Native map retries can be extremely aggressive on iOS. Use a budget
    // large enough to remain a true outage until the test explicitly cancels
    // it below.
    expect(cache.simulateRepeated502ForSmokeTest(count: 100000), isTrue);
    final radarBloc = BlocProvider.of<RadarBloc>(
      tester.element(find.byKey(const Key('radar-local-time'))),
    );

    // A transient outage after a successful first paint must keep the last
    // usable map visible. This is the exact regression where a camera retry
    // re-enabled "Préparation du radar" without arming its escape deadline.
    expect(await RadarMapSmokeTestBridge.zoomTo(11), isTrue);
    await _waitFor(
      tester,
      find.byKey(const ValueKey('radar-zoom-11')),
      timeout: const Duration(seconds: 5),
    );
    await _expectAbsentFor(
      tester,
      find.byKey(const ValueKey('radar-preparation-visible')),
      duration: const Duration(seconds: 6),
      reason: 'A post-first-paint tile retry covered the usable Radar surface.',
    );

    const outageLocation = Coordinates(latitude: 35.6762, longitude: 139.6503);
    radarBloc.add(const RadarLocationChanged(outageLocation));
    await _waitForCondition(
      tester,
      () {
        final state = radarBloc.state;
        return state is RadarReady && state.coordinates == outageLocation;
      },
      reason: 'The outage test location did not load.',
      timeout: const Duration(seconds: 45),
    );
    await _waitFor(
      tester,
      find.byKey(const ValueKey('radar-preparation-visible')),
      timeout: const Duration(seconds: 5),
    );

    // The blocking card has an eight-second hard deadline. The Google basemap
    // must become usable even while every Radar tile still returns HTTP 502.
    await _waitForCondition(
      tester,
      () =>
          find
              .byKey(const ValueKey('radar-preparation-hidden'))
              .evaluate()
              .isNotEmpty &&
          find
              .byKey(const ValueKey('radar-preparation-visible'))
              .evaluate()
              .isEmpty,
      reason: 'The blocking Radar preparation card exceeded its deadline.',
      timeout: const Duration(seconds: 12),
    );
    await _waitForCondition(
      tester,
      () => !(radarBloc.state as RadarReady).isPlaying,
      reason: 'Playback continued while every visible tile was unavailable.',
      diagnostics: () =>
          'state=${radarBloc.state} ready=${cache.readyTileCount.value} '
          '${RadarMapSmokeTestBridge.debugState}',
      timeout: const Duration(seconds: 2),
    );

    // Exercise the cold-start variant deterministically: there is no prior
    // playback intent for Resumed to restore. A native promotion must retry
    // autoplay once it actually becomes the selected front frame.
    radarBloc.add(const RadarPlaybackPaused(isUserInitiated: false));
    await tester.pump();

    // Once the transient outage ends, the existing silent retry loop must
    // restore a real tile and resume playback without clearing app data.
    var resumedBeforeSurfaceReady = false;
    final recoveryStates = radarBloc.stream.listen((state) {
      if (state is RadarReady &&
          state.coordinates == outageLocation &&
          state.isPlaying &&
          !RadarMapSmokeTestBridge.surfaceReady) {
        resumedBeforeSurfaceReady = true;
      }
    });
    addTearDown(recoveryStates.cancel);
    expect(cache.cancelSimulatedFailuresForSmokeTest(), isTrue);
    await _waitForCondition(
      tester,
      () {
        final state = radarBloc.state;
        return state is RadarReady &&
            state.coordinates == outageLocation &&
            state.isPlaying &&
            cache.readyTileCount.value > 0;
      },
      reason: 'Radar did not recover automatically after the tile outage.',
      diagnostics: () =>
          'state=${radarBloc.state} ready=${cache.readyTileCount.value} '
          '${RadarMapSmokeTestBridge.debugState}',
      timeout: const Duration(seconds: 45),
    );
    expect(
      find.byKey(const ValueKey('radar-preparation-hidden')),
      findsOneWidget,
    );
    expect(
      resumedBeforeSurfaceReady,
      isFalse,
      reason: 'Recovery consumed its playback intent before the map settled.',
    );
    final recoveredIndex = (radarBloc.state as RadarReady).selectedIndex;
    await _waitForCondition(
      tester,
      () {
        final state = radarBloc.state;
        return state is RadarReady &&
            state.isPlaying &&
            state.selectedIndex != recoveredIndex;
      },
      reason: 'The recovered radar never advanced to another frame.',
      diagnostics: () => RadarMapSmokeTestBridge.debugState,
      timeout: const Duration(seconds: 15),
    );

    // Recovery completion must not override a subsequent intentional pause,
    // even when a different selected frame completes its native handoff.
    radarBloc.add(const RadarPlaybackPaused());
    await _waitForCondition(
      tester,
      () => !(radarBloc.state as RadarReady).isPlaying,
      reason: 'The explicit pause was not accepted.',
    );
    final paused = radarBloc.state as RadarReady;
    final nextIndex = (paused.selectedIndex + 1) % paused.frames.length;
    radarBloc.add(RadarFrameSelected(nextIndex));
    await _waitForCondition(
      tester,
      () =>
          RadarMapSmokeTestBridge.presentedTileTemplate ==
              paused.frames[nextIndex].tileUrlTemplate &&
          !RadarMapSmokeTestBridge.tileHandoffPending,
      reason: 'The paused frame did not finish its native promotion.',
      diagnostics: () => RadarMapSmokeTestBridge.debugState,
      timeout: const Duration(seconds: 30),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(
      (radarBloc.state as RadarReady).isPlaying,
      isFalse,
      reason: 'A native promotion overrode the explicit user pause.',
    );
  });
}

Future<void> _expectAbsentFor(
  WidgetTester tester,
  Finder finder, {
  required Duration duration,
  required String reason,
}) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    expect(finder, findsNothing, reason: reason);
  }
}

Future<void> _waitForCondition(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  String Function()? diagnostics,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    condition(),
    isTrue,
    reason: diagnostics == null ? reason : '$reason\n${diagnostics()}',
  );
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  await _waitForCondition(
    tester,
    () => finder.evaluate().isNotEmpty,
    reason: 'Expected widget was not found: $finder',
    timeout: timeout,
  );
}
