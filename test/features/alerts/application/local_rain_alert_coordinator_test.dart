import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/location/location_repository.dart';
import 'package:chetiwa/core/notifications/rain_notification_scheduler.dart';
import 'package:chetiwa/core/time/weather_clock.dart';
import 'package:chetiwa/features/alerts/application/alert_preferences_controller.dart';
import 'package:chetiwa/features/alerts/application/local_rain_alert_coordinator.dart';
import 'package:chetiwa/features/alerts/application/remote_rain_alert_gateway.dart';
import 'package:chetiwa/features/forecast/domain/entities/forecast.dart';
import 'package:chetiwa/features/forecast/domain/repositories/forecast_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 22, 10);
  const paris = ChetiwaLocation(
    city: 'Paris',
    country: 'France',
    coordinates: Coordinates.paris,
  );

  test('programme localement la prochaine pluie du lieu principal', () async {
    final preferences = AlertPreferencesController(persist: false);
    await preferences.setEnabled(true);
    await preferences.setLeadMinutes(15);
    final scheduler = FixtureRainNotificationScheduler();
    final coordinator = LocalRainAlertCoordinator(
      forecastRepository: _ForecastRepository(now),
      locationRepository: _LocationRepository(paris),
      preferences: preferences,
      scheduler: scheduler,
      clock: FixedWeatherClock(now),
    );

    expect(await coordinator.sync(), RainAlertSyncResult.scheduled);
    expect(scheduler.scheduled?.locationLabel, 'Paris, France');
    expect(
      scheduler.scheduled?.scheduledAt,
      now.add(const Duration(minutes: 15)),
    );
  });

  test('refuse une alerte sans lieu principal', () async {
    final preferences = AlertPreferencesController(persist: false);
    await preferences.setEnabled(true);
    final scheduler = FixtureRainNotificationScheduler();
    final coordinator = LocalRainAlertCoordinator(
      forecastRepository: _ForecastRepository(now),
      locationRepository: _LocationRepository(null),
      preferences: preferences,
      scheduler: scheduler,
      clock: FixedWeatherClock(now),
    );

    expect(await coordinator.sync(), RainAlertSyncResult.noMainLocation);
    expect(scheduler.scheduled, isNull);
  });

  test('utilise le push distant sans programmer de doublon local', () async {
    final preferences = AlertPreferencesController(persist: false);
    await preferences.setEnabled(true);
    final scheduler = FixtureRainNotificationScheduler();
    final remote = FixtureRemoteRainAlertGateway();
    final coordinator = LocalRainAlertCoordinator(
      forecastRepository: _ForecastRepository(now),
      locationRepository: _LocationRepository(paris),
      preferences: preferences,
      scheduler: scheduler,
      clock: FixedWeatherClock(now),
      remoteGateway: remote,
    );

    expect(await coordinator.sync(), RainAlertSyncResult.scheduled);
    expect(remote.syncCount, 1);
    expect(scheduler.scheduled, isNull);
  });

  test(
    'conserve le distant exclusif pendant une panne de resynchronisation',
    () async {
      final preferences = AlertPreferencesController(persist: false);
      await preferences.setEnabled(true);
      final scheduler = FixtureRainNotificationScheduler();
      await scheduler.schedule(
        RainNotification(
          scheduledAt: now.add(const Duration(minutes: 15)),
          timeZone: 'Europe/Paris',
          locationLabel: 'Paris, France',
          body: 'ancienne alerte locale',
        ),
      );
      final remote = FixtureRemoteRainAlertGateway(
        result: RemoteRainAlertSyncResult.retained,
      );
      final coordinator = LocalRainAlertCoordinator(
        forecastRepository: _ForecastRepository(now),
        locationRepository: _LocationRepository(paris),
        preferences: preferences,
        scheduler: scheduler,
        clock: FixedWeatherClock(now),
        remoteGateway: remote,
      );

      expect(await coordinator.sync(), RainAlertSyncResult.scheduled);
      expect(scheduler.scheduled, isNull);
    },
  );

  test(
    'conserve le repli local avant la première inscription distante',
    () async {
      final preferences = AlertPreferencesController(persist: false);
      await preferences.setEnabled(true);
      final scheduler = FixtureRainNotificationScheduler();
      final coordinator = LocalRainAlertCoordinator(
        forecastRepository: _ForecastRepository(now),
        locationRepository: _LocationRepository(paris),
        preferences: preferences,
        scheduler: scheduler,
        clock: FixedWeatherClock(now),
        remoteGateway: FixtureRemoteRainAlertGateway(
          result: RemoteRainAlertSyncResult.failed,
        ),
      );

      expect(await coordinator.sync(), RainAlertSyncResult.scheduled);
      expect(scheduler.scheduled, isNotNull);
    },
  );

  test('resynchronise la règle quand Firebase renouvelle le token', () async {
    final preferences = AlertPreferencesController(persist: false);
    await preferences.setEnabled(true);
    final remote = FixtureRemoteRainAlertGateway();
    final coordinator = LocalRainAlertCoordinator(
      forecastRepository: _ForecastRepository(now),
      locationRepository: _LocationRepository(paris),
      preferences: preferences,
      scheduler: FixtureRainNotificationScheduler(),
      clock: FixedWeatherClock(now),
      remoteGateway: remote,
    );

    await coordinator.initialize();
    expect(remote.syncCount, 1);

    remote.emitToken('renewed-fcm-token');
    await Future<void>.delayed(Duration.zero);
    expect(remote.syncCount, 2);

    await coordinator.dispose();
  });
}

final class _ForecastRepository implements ForecastRepository {
  const _ForecastRepository(this.now);

  final DateTime now;

  @override
  Future<CachedForecast?> getCachedForecast(Coordinates coordinates) async =>
      null;

  @override
  Future<Forecast> getForecast(Coordinates coordinates) async => Forecast(
    locationName: 'Paris, France',
    updatedAt: now,
    temperatureCelsius: 20,
    windKph: 10,
    timeZone: 'Europe/Paris',
    brief: WeatherBrief(
      type: WeatherBriefType.imminent,
      intensity: RainIntensity.moderate,
      headline: 'Pluie bientôt',
      detail: 'Modérée',
      rainStart: now.add(const Duration(minutes: 30)),
    ),
    points: [
      RainPoint(
        time: now.add(const Duration(minutes: 30)),
        rateMmPerHour: 2,
        intensity: RainIntensity.moderate,
      ),
    ],
    windows: [
      RainWindow(
        start: now.add(const Duration(minutes: 30)),
        intensity: RainIntensity.moderate,
      ),
    ],
  );
}

final class _LocationRepository implements LocationRepository {
  const _LocationRepository(this.mainLocation);

  final ChetiwaLocation? mainLocation;

  @override
  Future<ChetiwaLocation?> getMainLocation() async => mainLocation;

  @override
  Future<void> clearMainLocation() async {}

  @override
  Future<ChetiwaLocation> getCurrentLocation() => throw UnimplementedError();

  @override
  Future<List<ChetiwaLocation>> getRecentLocations() async => const [];

  @override
  Future<bool> openLocationRecovery(LocationRecoveryAction action) async =>
      false;

  @override
  Future<void> remember(ChetiwaLocation location) async {}

  @override
  Future<void> removeRecentLocation(ChetiwaLocation location) async {}

  @override
  Future<ChetiwaLocation> resolveCoordinates(Coordinates coordinates) =>
      throw UnimplementedError();

  @override
  Future<List<ChetiwaLocation>> search(String query) async => const [];

  @override
  Future<void> setMainLocation(ChetiwaLocation location) async {}
}
