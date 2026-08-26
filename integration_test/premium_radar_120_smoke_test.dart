import 'package:chetiwa/app/app.dart';
import 'package:chetiwa/core/config/api_config.dart';
import 'package:chetiwa/features/radar/application/radar_bloc.dart';
import 'package:chetiwa/features/radar/presentation/widgets/radar_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  testWidgets('Premium debug exposes and renders the real +120 model frame', (
    tester,
  ) async {
    expect(
      ApiConfig.premiumRadarTestMode,
      isTrue,
      reason: 'Run with --dart-define=CHETIWA_PREMIUM_RADAR_TEST_MODE=true.',
    );

    await tester.pumpWidget(const ChetiwaApp());
    await _waitFor(tester, find.byKey(const Key('rain-chart')));
    await tester.tap(find.text('Radar'));
    await tester.pump();
    await _waitFor(tester, find.byKey(const Key('radar-local-time')));

    final radarBloc = BlocProvider.of<RadarBloc>(
      tester.element(find.byKey(const Key('radar-local-time'))),
    );
    await _waitForCondition(
      tester,
      () =>
          radarBloc.state is RadarReady &&
          (radarBloc.state as RadarReady).frames.any(
            (frame) => frame.isModelForecast,
          ),
      reason: 'LibreWXR did not expose Premium model frames.',
      timeout: const Duration(seconds: 45),
    );

    final ready = radarBloc.state as RadarReady;
    final latestObservation = ready.frames
        .where((frame) => frame.isObservation)
        .last;
    final lastModelIndex = ready.frames.lastIndexWhere(
      (frame) => frame.isModelForecast,
    );
    final lastModel = ready.frames[lastModelIndex];
    final modelLeads = ready.frames
        .where((frame) => frame.isModelForecast)
        .map((frame) => frame.time.difference(latestObservation.time).inMinutes)
        .toList(growable: false);
    expect(modelLeads, <int>[70, 80, 90, 100, 110, 120]);
    expect(
      lastModel.time.difference(latestObservation.time).inMinutes,
      greaterThanOrEqualTo(120),
    );

    await _waitFor(
      tester,
      find.byKey(const ValueKey('radar-first-tile-ready')),
      timeout: const Duration(seconds: 45),
    );
    if (const bool.fromEnvironment('CHETIWA_RADAR_SMOKE_TEST')) {
      await _waitForCondition(
        tester,
        () => RadarMapSmokeTestBridge.tileOverlayCount == 1,
        reason: 'The initial Radar tile overlay was not attached.',
      );
      RadarMapSmokeTestBridge.resetMaxTileOverlayCount();
    }

    radarBloc
      ..add(const RadarPlaybackPaused())
      ..add(RadarFrameSelected(lastModelIndex));
    await tester.pump();
    await _waitFor(tester, find.textContaining('prévision étendue Chetiwa+'));
    await _waitFor(tester, find.textContaining('PRÉVISION PLUIE'));
    expect(find.textContaining('ÉCHOS RADAR'), findsNothing);
    await _waitFor(
      tester,
      find.byKey(const ValueKey('radar-first-tile-ready')),
      timeout: const Duration(seconds: 45),
    );
    if (const bool.fromEnvironment('CHETIWA_RADAR_SMOKE_TEST')) {
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        RadarMapSmokeTestBridge.maxTileOverlayCount,
        lessThanOrEqualTo(2),
        reason:
            'The extended forecast allocated more than the bounded handoff pair.',
      );
    }
  });
}

Future<void> _waitForCondition(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(condition(), isTrue, reason: reason);
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
