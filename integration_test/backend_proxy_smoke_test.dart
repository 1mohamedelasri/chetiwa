import 'package:chetiwa/app/app.dart';
import 'package:chetiwa/features/radar/application/radar_bloc.dart';
import 'package:chetiwa/features/radar/data/cache/radar_tile_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
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
    await tester.pumpWidget(const ChetiwaApp());
    await _waitFor(tester, find.byKey(const Key('rain-chart')));
    expect(find.text('Paris, France'), findsOneWidget);

    await tester.tap(find.text('Radar'));
    await tester.pump();
    await _waitFor(tester, find.byKey(const Key('radar-local-time')));
    await _waitFor(
      tester,
      find.byKey(const ValueKey('radar-first-tile-ready')),
      timeout: const Duration(seconds: 45),
    );

    final map = find.byType(FlutterMap);
    expect(map, findsOneWidget);
    final tileCache = RadarTileCache.shared;
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

    for (var zoom = 8; zoom <= 10; zoom++) {
      final mapCenter = tester.getCenter(map) + const Offset(80, 0);
      await tester.tapAt(mapCenter);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(mapCenter);
      await _waitFor(
        tester,
        find.byKey(ValueKey('radar-zoom-$zoom')),
        timeout: const Duration(seconds: 15),
      );
      // Keep consecutive gestures outside Android's double-tap timeout so a
      // tap from the next loop cannot merge with the previous gesture and skip
      // an intermediate zoom level.
      await tester.pump(const Duration(milliseconds: 400));
    }

    final radarBloc = BlocProvider.of<RadarBloc>(
      tester.element(find.byKey(const Key('radar-local-time'))),
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
    await tester.tap(find.byKey(const Key('radar-playback-button')));
    await tester.pump();
    for (var index = 0; index < expectedPlaybackIndices.length; index++) {
      await tester.pump(const Duration(milliseconds: 1550));
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

    expect(
      tileCache.simulateNext502ForSmokeTest(),
      isTrue,
      reason:
          'Run with --dart-define=CHETIWA_RADAR_SMOKE_TEST=true to exercise recovery.',
    );
    final failuresBefore = tileCache.simulatedFailureCount.value;
    final probeUrl = initialRadar.selectedFrame.tileUrlTemplate!
        .replaceAll('{z}', '7')
        .replaceAll('{x}', '64')
        .replaceAll('{y}', '44');
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
