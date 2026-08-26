import 'package:chetiwa/app/app.dart';
import 'package:chetiwa/app/di/chetiwa_dependencies.dart';
import 'package:chetiwa/core/config/api_config.dart';
import 'package:chetiwa/core/location/coordinates.dart';
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
    await _waitFor(
      tester,
      find.byKey(const ValueKey('radar-preparation-hidden')),
      timeout: const Duration(seconds: 10),
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
      diagnostics: () => RadarMapSmokeTestBridge.debugState,
      // iOS may need one native tile-cache invalidation and composition pass
      // after crossing z14 -> z5. It must recover automatically, but a cold
      // server/network path is not required to finish inside three seconds.
      timeout: const Duration(seconds: 15),
    );
    await _waitFor(
      tester,
      find.byKey(const ValueKey('radar-preparation-hidden')),
      timeout: const Duration(seconds: 10),
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
        diagnostics: () =>
            'ready=${tileCache.readyTileCount.value} '
            '${RadarMapSmokeTestBridge.debugState}',
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
        diagnostics: () {
          final state = radarBloc.state as RadarReady;
          return 'selected=${state.selectedIndex} '
              'selectedTemplate=${state.selectedFrame.tileUrlTemplate} '
              '${RadarMapSmokeTestBridge.debugState}';
        },
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
    radarBloc.add(const RadarPlaybackPaused());
    await tester.pump();

    // Reproduce the real cache-persistence regression: zoom out in one
    // viewport, cross the Atlantic, then return to Paris without clearing app
    // data. Every location must create a fresh native map presentation and
    // restart automatic playback on its own.
    for (final coordinates in const <Coordinates>[
      Coordinates(latitude: 36.1627, longitude: -86.7816),
      Coordinates.paris,
    ]) {
      final mapCreationsBefore = RadarMapSmokeTestBridge.mapCreationCount;
      radarBloc.add(RadarLocationChanged(coordinates));
      await _waitForCondition(
        tester,
        () {
          final state = radarBloc.state;
          return state is RadarReady && state.coordinates == coordinates;
        },
        reason: 'Changing continent did not update the Radar viewport',
        timeout: const Duration(seconds: 45),
      );
      expect(
        RadarMapSmokeTestBridge.mapCreationCount,
        mapCreationsBefore,
        reason:
            'Changing city should preserve the stable native Google map surface',
      );
      await _waitForCondition(
        tester,
        () {
          final state = radarBloc.state;
          return state is RadarReady &&
              state.coordinates == coordinates &&
              state.isPlaying &&
              !RadarMapSmokeTestBridge.tileHandoffPending &&
              RadarMapSmokeTestBridge.presentedTileTemplate ==
                  state.selectedFrame.tileUrlTemplate;
        },
        reason:
            'Radar did not recover tiles and playback after changing continent',
        diagnostics: () {
          final state = radarBloc.state;
          return 'target=$coordinates state=$state '
              '${RadarMapSmokeTestBridge.debugState}';
        },
        timeout: const Duration(seconds: 45),
      );
      await _waitFor(
        tester,
        find.byKey(const ValueKey('radar-preparation-hidden')),
        timeout: const Duration(seconds: 10),
      );
    }

    radarBloc.add(const RadarPlaybackPaused());
    await tester.pump();

    // HTTP 502 recovery is exercised with an entire persistent outage in
    // radar_preparation_escape_smoke_test.dart. Keeping that fault injection
    // separate avoids conflating it with this live pan/zoom/playback proof.
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
  String Function()? diagnostics,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 16));
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
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(finder, findsOneWidget);
}
