import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/time/weather_clock.dart';
import 'package:chetiwa/core/weather/weather_data_provenance.dart';
import 'package:chetiwa/features/forecast/data/datasources/fixture_forecast_data_source.dart';
import 'package:chetiwa/features/forecast/domain/entities/forecast.dart';
import 'package:chetiwa/features/forecast/domain/services/forecast_snapshot_builder.dart';
import 'package:chetiwa/features/radar/application/radar_bloc.dart';
import 'package:chetiwa/features/radar/data/cache/radar_tile_cache.dart';
import 'package:chetiwa/features/radar/domain/entities/radar_frame.dart';
import 'package:chetiwa/features/radar/presentation/widgets/radar_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final change in <String, String>{
    'frame time': 'https://tiles.test/200/{z}/{x}/{y}/14.png?run=1',
    'forecast run': 'https://tiles.test/100/{z}/{x}/{y}/14.png?run=2',
    'palette': 'https://tiles.test/100/{z}/{x}/{y}/15.png?run=1',
  }.entries) {
    test(
      'a ${change.key} timeout cannot reuse or acknowledge older pixels',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'radar-identity-',
        );
        addTearDown(() => _deleteDirectory(directory));
        final png = await _png(const ui.Color(0xFFFF0000));
        var requests = 0;
        final cache = RadarTileCache.forTesting(
          directory: directory,
          client: MockClient((request) async {
            requests++;
            if (request.url.toString() ==
                'https://tiles.test/100/7/64/44/14.png?run=1') {
              return http.Response.bytes(png, 200);
            }
            throw TimeoutException('new identity unavailable');
          }),
        )..beginSession();
        final front = cache.providerFor(
          'https://tiles.test/100/{z}/{x}/{y}/14.png?run=1',
        );
        final incoming = cache.providerFor(change.value);
        expect((await front.getTile(64, 44, 7)).data, png);
        expect((await incoming.getTile(64, 44, 7)).data, isNull);
        expect(incoming.successfulCoordinateCount, 0);
        expect(incoming.hasCompletePresentation, isFalse);
        expect(cache.readyTileCount.value, 1);
        expect(cache.successfulTileResponseCount.value, 1);
        expect(await cache.prepareVisibleFrame(change.value), 0);
        // The exact old identity remains safely reusable in its existing layer.
        expect((await front.getTile(64, 44, 7)).data, png);
        expect(requests, 3);
      },
    );
  }

  test(
    'overzoom never stores fallback pixels under a newer frame identity',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'radar-overzoom-identity-',
      );
      addTearDown(() => _deleteDirectory(directory));
      final red = await _png(const ui.Color(0xFFFF0000));
      final green = await _png(const ui.Color(0xFF00FF00));
      var available = false;
      var incomingRequests = 0;
      final cache = RadarTileCache.forTesting(
        directory: directory,
        client: MockClient((request) async {
          if (request.url.path.startsWith('/old/')) {
            return http.Response.bytes(red, 200);
          }
          incomingRequests++;
          if (!available) throw TimeoutException('next frame unavailable');
          return http.Response.bytes(green, 200);
        }),
      )..beginSession();
      final old = cache.providerFor('https://tiles.test/old/{z}/{x}/{y}.png');
      final incoming = cache.providerFor(
        'https://tiles.test/new/{z}/{x}/{y}.png',
      );
      expect(await _firstPixel((await old.getTile(201, 201, 11)).data!), [
        255,
        0,
        0,
        255,
      ]);
      expect((await incoming.getTile(201, 201, 11)).data, isNull);
      expect(incoming.successfulCoordinateCount, 0);
      available = true;
      final recovered = await incoming.getTile(201, 201, 11);
      expect(await _firstPixel(recovered.data!), [0, 255, 0, 255]);
      expect(incomingRequests, 2);
      expect(incoming.hasCompletePresentation, isTrue);
    },
  );

  testWidgets('timeline describes the retained front frame until promotion', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 9, 30, 18, 55);
    final forecast = await FixtureForecastDataSource(
      clock: FixedWeatherClock(now),
    ).load();
    final old = RadarFrame(
      time: now,
      progress: 0,
      tileUrlTemplate: 'https://tiles.test/old/{z}/{x}/{y}.png?run=1',
    );
    final incoming = RadarFrame(
      time: now.add(const Duration(minutes: 15)),
      progress: 1,
      kind: WeatherDataKind.radarNowcast,
      tileUrlTemplate: 'https://tiles.test/new/{z}/{x}/{y}.png?run=2',
    );
    final state = RadarReady(
      frames: [old, incoming],
      selectedIndex: 1,
      coordinates: Coordinates.paris,
      isPlaying: true,
    );
    Future<void> show(RadarFrame presented) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RadarTimeline(
            state: state,
            presentedFrame: presented,
            forecast: forecast,
            snapshot: ForecastSnapshotBuilder.build(
              forecast: forecast,
              nowUtc: now,
            ),
            playbackProgress: const AlwaysStoppedAnimation(0),
          ),
        ),
      ),
    );
    await show(old);
    final before = tester.widget<Semantics>(
      find.byKey(const Key('radar-local-time')),
    );
    expect(
      before.properties.label,
      contains(WeatherTimeZone.displayHourMinute(old.time)),
    );
    expect(
      before.properties.label,
      isNot(contains(WeatherTimeZone.displayHourMinute(incoming.time))),
    );
    final painterBefore =
        tester
                .widget<CustomPaint>(
                  find.byKey(
                    const ValueKey(
                      'radar-point-profile-unavailable-premium-open',
                    ),
                  ),
                )
                .painter
            as dynamic;
    expect(painterBefore.cursorTime, old.time);
    await show(incoming);
    final after = tester.widget<Semantics>(
      find.byKey(const Key('radar-local-time')),
    );
    expect(
      after.properties.label,
      contains(WeatherTimeZone.displayHourMinute(incoming.time)),
    );
    final painterAfter =
        tester
                .widget<CustomPaint>(
                  find.byKey(
                    const ValueKey(
                      'radar-point-profile-unavailable-premium-open',
                    ),
                  ),
                )
                .painter
            as dynamic;
    expect(painterAfter.cursorTime, incoming.time);
  });

  testWidgets('incoming tile handoff preserves the cursor reached before it', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 9, 30, 20, 10);
    final forecast = Forecast(
      locationName: 'Paris',
      updatedAt: now,
      temperatureCelsius: 20,
      windKph: 5,
      brief: const WeatherBrief(
        type: WeatherBriefType.dry,
        intensity: RainIntensity.none,
        headline: 'Dry',
        detail: 'Dry',
      ),
      points: [
        RainPoint(time: now, rateMmPerHour: 0, intensity: RainIntensity.none),
        RainPoint(
          time: now.add(const Duration(hours: 1)),
          rateMmPerHour: 0,
          intensity: RainIntensity.none,
        ),
      ],
      windows: const [],
    );
    final frames = List.generate(
      3,
      (index) => RadarFrame(
        time: now.add(Duration(minutes: index * 10)),
        progress: index / 2,
        kind: index == 0
            ? WeatherDataKind.radarObservation
            : WeatherDataKind.radarNowcast,
        tileUrlTemplate: 'https://tiles.test/$index/{z}/{x}/{y}.png',
      ),
    );
    Future<DateTime> show({
      required int selected,
      required int presented,
      required double progress,
      bool playing = true,
      bool preservePhase = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RadarTimeline(
              state: RadarReady(
                frames: frames,
                selectedIndex: selected,
                coordinates: Coordinates.paris,
                isPlaying: playing,
              ),
              presentedFrame: frames[presented],
              forecast: forecast,
              snapshot: ForecastSnapshotBuilder.build(
                forecast: forecast,
                nowUtc: now,
              ),
              playbackProgress: AlwaysStoppedAnimation(progress),
              preservePlaybackPhase: preservePhase,
            ),
          ),
        ),
      );
      final paint = tester.widget<CustomPaint>(
        find.byKey(
          const ValueKey('radar-point-profile-unavailable-premium-open'),
        ),
      );
      return (paint.painter as dynamic).cursorTime as DateTime;
    }

    final before = await show(selected: 0, presented: 0, progress: 0.98);
    final held = await show(selected: 1, presented: 0, progress: 0.98);
    expect(held, before);
    final recoveryHold = await show(
      selected: 1,
      presented: 0,
      progress: 0.98,
      playing: false,
      preservePhase: true,
    );
    expect(recoveryHold, before);
    expect(
      tester
          .widget<Semantics>(find.byKey(const Key('radar-local-time')))
          .properties
          .label,
      contains(WeatherTimeZone.displayHourMinute(frames[0].time)),
      reason: 'The retained image still owns its timestamp label.',
    );
    final promoted = await show(selected: 1, presented: 1, progress: 0);
    expect(promoted.isBefore(held), isFalse);
    final heldLast = await show(selected: 2, presented: 1, progress: 1);
    expect(heldLast, frames[2].time);
    final paused = await show(
      selected: 2,
      presented: 1,
      progress: 1,
      playing: false,
    );
    expect(paused, frames[1].time);
  });
}

Future<List<int>> _png(ui.Color color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(
    recorder,
  ).drawRect(const ui.Rect.fromLTWH(0, 0, 256, 256), ui.Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 256);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

Future<List<int>> _firstPixel(List<int> bytes) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final pixel = data!.buffer.asUint8List().take(4).toList();
  frame.image.dispose();
  codec.dispose();
  return pixel;
}

Future<void> _deleteDirectory(Directory directory) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
  if (await directory.exists()) await directory.delete(recursive: true);
}
