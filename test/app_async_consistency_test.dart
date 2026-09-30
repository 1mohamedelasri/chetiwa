import 'dart:async';

import 'package:chetiwa/core/location/active_location_controller.dart';
import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/location/location_repository.dart';
import 'package:chetiwa/core/network/chetiwa_api_client.dart';
import 'package:chetiwa/features/forecast/application/forecast_bloc.dart';
import 'package:chetiwa/features/forecast/domain/entities/forecast.dart';
import 'package:chetiwa/features/forecast/domain/repositories/forecast_repository.dart';
import 'package:chetiwa/features/radar/application/radar_bloc.dart';
import 'package:chetiwa/features/radar/domain/entities/radar_frame.dart';
import 'package:chetiwa/features/radar/domain/repositories/radar_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _lyon = ChetiwaLocation(
  city: 'Lyon',
  country: 'France',
  coordinates: Coordinates(latitude: 45.764, longitude: 4.8357),
);
const _paris = ChetiwaLocation(
  city: 'Paris',
  country: 'France',
  coordinates: Coordinates.paris,
);

void main() {
  for (final failOldRequest in [false, true]) {
    test('old forecast ${failOldRequest ? 'failure' : 'response'} cannot '
        'replace the selected city', () async {
      final repository = _ForecastRequests();
      final bloc = ForecastBloc(repository);
      addTearDown(bloc.close);
      bloc.add(const ForecastRequested());
      await _flushEvents();
      bloc.add(const ForecastLocationChanged(_lyon));
      await _flushEvents();
      repository.requests[_lyon.coordinates]!.complete(_forecast(27));
      await _flushEvents();
      expect((bloc.state as ForecastReady).forecast.temperatureCelsius, 27);

      if (failOldRequest) {
        repository.requests[Coordinates.paris]!.completeError(
          StateError('old connection failed'),
        );
      } else {
        repository.requests[Coordinates.paris]!.complete(_forecast(12));
      }
      await _flushEvents();
      final ready = bloc.state as ForecastReady;
      expect(ready.forecast.locationName, _lyon.label);
      expect(ready.forecast.temperatureCelsius, 27);
      expect(ready.health.issue, isNull);
    });
  }

  test('late cached forecast cannot replace a newly selected city', () async {
    final oldCache = Completer<CachedForecast?>();
    final repository = _ForecastRequests(oldCache: oldCache.future);
    final bloc = ForecastBloc(repository);
    addTearDown(bloc.close);
    bloc.add(const ForecastRequested());
    await _flushEvents();
    bloc.add(const ForecastLocationChanged(_lyon));
    await _flushEvents();
    repository.requests[_lyon.coordinates]!.complete(_forecast(27));
    await _flushEvents();
    oldCache.complete(
      CachedForecast(forecast: _forecast(12), cachedAt: DateTime.now()),
    );
    await _flushEvents();
    expect(repository.requests.containsKey(Coordinates.paris), isFalse);
    expect((bloc.state as ForecastReady).forecast.temperatureCelsius, 27);
  });

  test(
    'saved forecast location restore yields to explicit selection',
    () async {
      final locations = _DelayedLocationRepository();
      final repository = _ForecastRequests();
      final bloc = ForecastBloc(repository, locationRepository: locations);
      addTearDown(bloc.close);
      bloc.add(const ForecastRequested());
      await _flushEvents();
      bloc.add(const ForecastLocationChanged(_lyon));
      await _flushEvents();
      repository.requests[_lyon.coordinates]!.complete(_forecast(27));
      await _flushEvents();
      locations.saved.complete(_paris);
      await _flushEvents();
      expect(repository.requests.containsKey(Coordinates.paris), isFalse);
      expect((bloc.state as ForecastReady).forecast.locationName, _lyon.label);
    },
  );

  test(
    'refresh during startup still waits for the saved forecast place',
    () async {
      final locations = _DelayedLocationRepository();
      final repository = _ForecastRequests();
      final bloc = ForecastBloc(repository, locationRepository: locations);
      addTearDown(bloc.close);
      bloc.add(const ForecastRequested());
      await _flushEvents();
      bloc.add(const ForecastRefreshed());
      await _flushEvents();
      expect(repository.requests, isEmpty);
      locations.saved.complete(_lyon);
      await _flushEvents();
      expect(repository.requests.keys, [_lyon.coordinates]);
      repository.requests[_lyon.coordinates]!.complete(_forecast(27));
      await _flushEvents();
      expect((bloc.state as ForecastReady).forecast.locationName, _lyon.label);
    },
  );

  test('failed saved-place read does not block forecast loading', () async {
    final locations = _DelayedLocationRepository();
    final repository = _ForecastRequests();
    final bloc = ForecastBloc(repository, locationRepository: locations);
    addTearDown(bloc.close);
    bloc.add(const ForecastRequested());
    await _flushEvents();
    locations.saved.completeError(StateError('storage unavailable'));
    await _flushEvents();
    repository.requests[Coordinates.paris]!.complete(_forecast(12));
    await _flushEvents();
    expect(bloc.state, isA<ForecastReady>());
  });

  test('active location restore cannot undo selection or clear', () async {
    for (final clearSelection in [false, true]) {
      final repository = _DelayedLocationRepository();
      final controller = ActiveLocationController(repository);
      addTearDown(controller.dispose);
      await controller.setActive(_lyon);
      if (clearSelection) controller.clear();
      repository.saved.complete(_paris);
      await _flushEvents();
      expect(controller.location, clearSelection ? null : _lyon);
    }
  });

  test(
    'active location restore tolerates disposal and storage failure',
    () async {
      final disposedRepository = _DelayedLocationRepository();
      final disposed = ActiveLocationController(disposedRepository);
      disposed.dispose();
      disposedRepository.saved.complete(_paris);
      await _flushEvents();

      final failedRepository = _DelayedLocationRepository();
      final controller = ActiveLocationController(failedRepository);
      addTearDown(controller.dispose);
      failedRepository.saved.completeError(StateError('storage unavailable'));
      await _flushEvents();
      await controller.setActive(_lyon);
      expect(controller.location, _lyon);
    },
  );

  for (final suspend in [false, true]) {
    for (final failRefresh in [false, true]) {
      test('radar refresh ${failRefresh ? 'failure' : 'completion'} respects '
          '${suspend ? 'background suspension' : 'manual pause'}', () async {
        final repository = _RadarRefresh();
        final bloc = RadarBloc(repository);
        addTearDown(bloc.close);
        bloc.add(const RadarRequested());
        await _flushEvents();
        bloc.add(const RadarPlaybackStarted());
        await _flushEvents();
        expect((bloc.state as RadarReady).isPlaying, isTrue);
        bloc.add(const RadarRefreshed());
        await _flushEvents();
        bloc.add(
          suspend
              ? const RadarPlaybackSuspended()
              : const RadarPlaybackPaused(),
        );
        await _flushEvents();
        if (failRefresh) {
          repository.refresh.completeError(StateError('network unavailable'));
        } else {
          repository.refresh.complete(_frames);
        }
        await _flushEvents();
        expect((bloc.state as RadarReady).isPlaying, isFalse);
        if (suspend) {
          // A late tile-preparation callback must also respect backgrounding.
          bloc.add(const RadarPlaybackStarted());
          bloc.add(const RadarPlaybackRestarted());
          await _flushEvents();
          expect((bloc.state as RadarReady).isPlaying, isFalse);
        }
        bloc.add(const RadarPlaybackResumed());
        await _flushEvents();
        expect((bloc.state as RadarReady).isPlaying, suspend);
      });
    }
  }

  test(
    'API write deadline includes a response body that never closes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final body = StreamController<List<int>>();
      addTearDown(body.close);
      final api = ChetiwaApiClient(
        baseUri: Uri.parse('https://api.chetiwa.test'),
        client: _StalledBodyClient(body.stream),
        requestTimeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        api
            .postData('/v1/alerts', const {})
            .timeout(const Duration(seconds: 1)),
        throwsA(
          isA<ChetiwaApiException>().having(
            (error) => error.code,
            'code',
            'network_timeout',
          ),
        ),
      );
    },
  );
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

final class _ForecastRequests implements ForecastRepository {
  _ForecastRequests({this.oldCache});
  final Future<CachedForecast?>? oldCache;
  final requests = <Coordinates, Completer<Forecast>>{};

  @override
  Future<CachedForecast?> getCachedForecast(Coordinates coordinates) =>
      coordinates == Coordinates.paris && oldCache != null
      ? oldCache!
      : Future.value(null);

  @override
  Future<Forecast> getForecast(Coordinates coordinates) =>
      (requests[coordinates] = Completer<Forecast>()).future;
}

final class _DelayedLocationRepository implements LocationRepository {
  final saved = Completer<ChetiwaLocation?>();
  @override
  Future<ChetiwaLocation?> getMainLocation() => saved.future;
  @override
  Future<void> setMainLocation(ChetiwaLocation location) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RadarRefresh implements RadarRepository {
  final refresh = Completer<List<RadarFrame>>();
  var requests = 0;
  @override
  Future<CachedRadarFrames?> getCachedFrames(Coordinates coordinates) async =>
      null;
  @override
  Future<List<RadarFrame>> getFrames(Coordinates coordinates) =>
      requests++ == 0 ? Future.value(_frames) : refresh.future;
}

final class _StalledBodyClient extends http.BaseClient {
  _StalledBodyClient(this.body);
  final Stream<List<int>> body;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(body, 200);
}

Forecast _forecast(double temperature) => Forecast(
  locationName: 'Repository label',
  updatedAt: DateTime.utc(2026, 9, 19, 12),
  temperatureCelsius: temperature,
  windKph: 8,
  brief: const WeatherBrief(
    type: WeatherBriefType.dry,
    intensity: RainIntensity.none,
    headline: 'Dry',
    detail: 'Dry weather',
  ),
  points: const [],
  windows: const [],
);

final _frames = List.generate(
  3,
  (index) => RadarFrame(
    time: DateTime.utc(2026, 9, 19, 12, index * 10),
    progress: index / 2,
  ),
);
