import 'package:chetiwa/app/app.dart';
import 'package:chetiwa/app/di/chetiwa_dependencies.dart';
import 'package:chetiwa/core/config/api_config.dart';
import 'package:chetiwa/features/radar/application/radar_bloc.dart';
import 'package:chetiwa/features/radar/data/cache/radar_tile_cache.dart';
import 'package:chetiwa/features/radar/domain/services/radar_frame_policy.dart';
import 'package:chetiwa/features/radar/presentation/widgets/radar_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  testWidgets('loads Graph, Radar and Forecast through the Chetiwa backend', (
    tester,
  ) async {
    expect(
      await RadarTileCache.clearDiskCacheForSmokeTest(),
      isTrue,
      reason:
          'Run with --dart-define=CHETIWA_RADAR_SMOKE_TEST=true for a cold-cache proof.',
    );
    // Integration test binaries do not run the production bootstrap that
    // initializes Firebase. Push is outside this Radar test, so keep the real
    // backend/map stack while explicitly disabling only Firebase Messaging.
    await tester.pumpWidget(
      ChetiwaApp(
        dependencies: ChetiwaDependencies.live(firebaseAvailable: false),
      ),
    );
    await _waitFor(tester, find.byKey(const Key('rain-chart')));

    await tester.tap(find.text('Radar'));
    await tester.pump();
    await _waitFor(tester, find.byKey(const Key('radar-local-time')));
    await _waitFor(
      tester,
      find.byKey(const ValueKey('radar-first-tile-ready')),
      timeout: const Duration(seconds: 45),
    );

    final map = find.byType(GoogleMap);
    expect(map, findsOneWidget);
    final tileCache = RadarTileCache.shared;
    final radarBloc = BlocProvider.of<RadarBloc>(
      tester.element(find.byKey(const Key('radar-local-time'))),
    );
    if (ApiConfig.premiumRadarTestMode) {
      final premiumRadar = radarBloc.state as RadarReady;
      final latestObservation = premiumRadar.frames
          .where((frame) => frame.isObservation)
          .last;
      expect(
        premiumRadar.frames.any((frame) => frame.isModelForecast),
        isTrue,
        reason: 'Premium debug mode did not expose any model frame.',
      );
      expect(
        premiumRadar.frames.last.time
            .difference(latestObservation.time)
            .inMinutes,
        greaterThanOrEqualTo(120),
        reason: 'The Premium model timeline does not reach +120 minutes.',
      );
    }
    for (final movement in const <Offset>[
      Offset(-180, 0),
      Offset(0, -180),
      Offset(-180, 0),
      Offset(0, -180),
    ]) {
      await tester.drag(map, movement);
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        find.byKey(const Key('chetiwa-radar-precipitation-tile')),
        findsWidgets,
        reason: 'The decoded Radar layer disappeared after pan $movement',
      );
      expect(
        find.byKey(const ValueKey('radar-first-tile-ready')),
        findsOneWidget,
      );
    }

    // LibreWXR is native through z10. City zooms 11-14 must keep rendering
    // the exact locally cropped ancestor while the Google basemap zooms.
    for (var zoom = 8; zoom <= 14; zoom++) {
      expect(await RadarMapSmokeTestBridge.zoomTo(zoom.toDouble()), isTrue);
      await _waitFor(
        tester,
        find.byKey(ValueKey('radar-zoom-$zoom')),
        timeout: const Duration(seconds: 15),
      );
      await tester.pump(const Duration(milliseconds: 250));
    }

    final tilesBeforeZoomOut = tileCache.successfulTileResponseCount.value;
    expect(await RadarMapSmokeTestBridge.zoomTo(5), isTrue);
    await _waitFor(
      tester,
      find.byKey(const ValueKey('radar-zoom-5')),
      timeout: const Duration(seconds: 5),
    );
    await _waitForCondition(
      tester,
      () => tileCache.successfulTileResponseCount.value > tilesBeforeZoomOut,
      reason: 'Radar tiles did not recover promptly after a large zoom-out',
      timeout: const Duration(seconds: 5),
    );
    await _waitForCondition(
      tester,
      () => (radarBloc.state as RadarReady).isPlaying,
      reason: 'Rapid consecutive zooms left Radar playback suspended',
      timeout: const Duration(seconds: 3),
    );

    radarBloc.add(const RadarPlaybackPaused());
    await tester.pump();
    final beforeSwap = radarBloc.state as RadarReady;
    final swapIndex = (beforeSwap.selectedIndex + 1) % beforeSwap.frames.length;
    RadarMapSmokeTestBridge.resetMaxTileOverlayCount();
    radarBloc.add(RadarFrameSelected(swapIndex));
    await _waitForCondition(
      tester,
      () {
        final state = radarBloc.state as RadarReady;
        return RadarMapSmokeTestBridge.tileOverlayCount == 1 &&
            !RadarMapSmokeTestBridge.tileHandoffPending &&
            RadarMapSmokeTestBridge.presentedTileTemplate ==
                state.selectedFrame.tileUrlTemplate;
      },
      reason:
          'The native Radar handoff did not present the selected tile template',
      timeout: const Duration(seconds: 15),
    );
    expect(
      RadarMapSmokeTestBridge.maxTileOverlayCount,
      lessThanOrEqualTo(2),
      reason: 'Radar animation allocated more than the bounded handoff pair.',
    );

    radarBloc.add(const RadarPlaybackRestarted());
    await _waitForCondition(
      tester,
      () {
        final state = radarBloc.state as RadarReady;
        return state.isPlaying &&
            !RadarMapSmokeTestBridge.tileHandoffPending &&
            RadarMapSmokeTestBridge.presentedTileTemplate ==
                state.selectedFrame.tileUrlTemplate;
      },
      reason: 'Playback started before its first native tile was presented',
      timeout: const Duration(seconds: 15),
    );
    final initialRadar = radarBloc.state as RadarReady;
    final expectedPlaybackIndices = <int>{
      for (
        var index = initialRadar.playbackStartIndex;
        index < initialRadar.frames.length;
        index++
      )
        index,
    };
    final visitedPlaybackIndices = <int>{initialRadar.playbackStartIndex};
    for (var index = 0; index < expectedPlaybackIndices.length; index++) {
      final previousIndex = (radarBloc.state as RadarReady).selectedIndex;
      await _waitForCondition(
        tester,
        () => (radarBloc.state as RadarReady).selectedIndex != previousIndex,
        reason: 'The Radar playback clock did not advance from $previousIndex',
        timeout:
            RadarFramePolicy.playbackFrameDuration + const Duration(seconds: 5),
      );
      await _waitForCondition(
        tester,
        () {
          final state = radarBloc.state as RadarReady;
          return !RadarMapSmokeTestBridge.tileHandoffPending &&
              RadarMapSmokeTestBridge.presentedTileTemplate ==
                  state.selectedFrame.tileUrlTemplate;
        },
        reason:
            'The cursor advanced without presenting the matching native Radar tile',
        timeout: const Duration(seconds: 15),
      );
      final state = radarBloc.state as RadarReady;
      visitedPlaybackIndices.add(state.selectedIndex);
    }
    expect(visitedPlaybackIndices, containsAll(expectedPlaybackIndices));
    expect(
      (radarBloc.state as RadarReady).selectedIndex,
      initialRadar.playbackStartIndex,
    );
    await tester.tap(find.byKey(const Key('radar-playback-button')));
    await tester.pump();

    final probeUrl = initialRadar.selectedFrame.tileUrlTemplate!
        .replaceAll('{z}', '7')
        .replaceAll('{x}', '64')
        .replaceAll('{y}', '44');
    expect(
      tileCache.simulateNext502ForSmokeTest(url: probeUrl),
      isTrue,
      reason:
          'Run with --dart-define=CHETIWA_RADAR_SMOKE_TEST=true to exercise recovery.',
    );
    final failuresBefore = tileCache.simulatedFailureCount.value;
    expect(
      await tileCache.fetchTileForSmokeTest(probeUrl),
      isFalse,
      reason: 'The first probe must receive the injected HTTP 502',
    );
    expect(tileCache.simulatedFailureCount.value, failuresBefore + 1);
    expect(
      await tileCache.fetchTileForSmokeTest(probeUrl),
      isTrue,
      reason: 'The Radar tile request must recover immediately after HTTP 502',
    );
    expect(find.byKey(const Key('radar-local-time')), findsOneWidget);

    await tester.tap(find.text('Prévisions'));
    await tester.pump();
    await _waitFor(tester, find.byKey(const Key('forecast-pane')));
    expect(find.text('PRÉVISIONS HEURE PAR HEURE'), findsOneWidget);
  });
}

Future<void> _waitForCondition(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(condition(), isTrue, reason: reason);
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(finder, findsOneWidget);
}
