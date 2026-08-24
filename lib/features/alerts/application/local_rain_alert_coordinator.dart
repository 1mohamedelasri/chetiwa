import 'dart:async';

import '../../../core/location/location_repository.dart';
import '../../../core/notifications/rain_notification_scheduler.dart';
import '../../../core/time/weather_clock.dart';
import '../../forecast/domain/entities/forecast.dart';
import '../../forecast/domain/repositories/forecast_repository.dart';
import '../data/chetiwa_alert_api.dart';
import 'alert_preferences_controller.dart';
import 'remote_rain_alert_gateway.dart';

enum RainAlertSyncResult { scheduled, disabled, noMainLocation, noRain, failed }

final class LocalRainAlertCoordinator {
  LocalRainAlertCoordinator({
    required ForecastRepository forecastRepository,
    required LocationRepository locationRepository,
    required AlertPreferencesController preferences,
    required RainNotificationScheduler scheduler,
    required WeatherClock clock,
    RemoteRainAlertGateway? remoteGateway,
  }) : _forecastRepository = forecastRepository,
       _locationRepository = locationRepository,
       _preferences = preferences,
       _scheduler = scheduler,
       _clock = clock,
       _remoteGateway = remoteGateway;

  final ForecastRepository _forecastRepository;
  final LocationRepository _locationRepository;
  final AlertPreferencesController _preferences;
  final RainNotificationScheduler _scheduler;
  final WeatherClock _clock;
  final RemoteRainAlertGateway? _remoteGateway;
  StreamSubscription<String>? _tokenSubscription;
  Future<RainAlertSyncResult>? _syncInFlight;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _preferences.ready;
    final remote = _remoteGateway;
    if (remote != null) {
      await remote.initialize();
      _tokenSubscription = remote.tokenRefresh.listen((_) {
        unawaited(sync());
      });
    }
    await sync();
  }

  Future<RainAlertSyncResult> sync() {
    final current = _syncInFlight;
    if (current != null) return current;
    final operation = _performSync();
    _syncInFlight = operation;
    operation.whenComplete(() {
      if (identical(_syncInFlight, operation)) _syncInFlight = null;
    });
    return operation;
  }

  Future<RainAlertSyncResult> _performSync() async {
    try {
      await _preferences.ready;
      if (!_preferences.enabled) {
        final remoteDeleted = await _remoteGateway?.deactivate() ?? true;
        await _scheduler.cancel();
        return remoteDeleted
            ? RainAlertSyncResult.disabled
            : RainAlertSyncResult.failed;
      }
      final location = await _locationRepository.getMainLocation();
      if (location == null) {
        await _remoteGateway?.deactivate();
        await _scheduler.cancel();
        return RainAlertSyncResult.noMainLocation;
      }

      final forecast = await _forecastRepository.getForecast(
        location.coordinates,
      );

      final remote = _remoteGateway;
      if (remote != null) {
        final result = await remote.syncRule(
          location: AlertLocationInput(
            label: location.label,
            latitude: location.coordinates.latitude,
            longitude: location.coordinates.longitude,
            timeZone: forecast.timeZone,
          ),
          leadMinutes: _preferences.leadMinutes,
          minimumIntensity: _preferences.minimumIntensity,
          quietHours: AlertQuietHoursInput(
            enabled: _preferences.quietHoursEnabled,
            start: _preferences.quietHoursStart,
            end: _preferences.quietHoursEnd,
          ),
        );
        if (result == RemoteRainAlertSyncResult.registered ||
            result == RemoteRainAlertSyncResult.retained) {
          // Remote and local delivery are deliberately exclusive so the same
          // rain episode cannot produce two notifications.
          await _scheduler.cancel();
          return RainAlertSyncResult.scheduled;
        }
      }

      final now = _clock.nowUtc;
      final minimum = _minimumIntensity(_preferences.minimumIntensity);
      final candidates = forecast.points.where(
        (point) =>
            !point.time.isBefore(now) && point.intensity.index >= minimum.index,
      );
      final first = candidates.isEmpty ? null : candidates.first;
      if (first == null) {
        await _scheduler.cancel();
        return RainAlertSyncResult.noRain;
      }

      var scheduledAt = first.time.subtract(
        Duration(minutes: _preferences.leadMinutes),
      );
      if (!scheduledAt.isAfter(now)) {
        scheduledAt = now.add(const Duration(seconds: 5));
      }
      if (_isQuietTime(scheduledAt, forecast.timeZone)) {
        await _scheduler.cancel();
        return RainAlertSyncResult.noRain;
      }

      await _scheduler.schedule(
        RainNotification(
          scheduledAt: scheduledAt,
          timeZone: forecast.timeZone,
          locationLabel: location.label,
          body:
              '${_intensityLabel(first.intensity)} prévue vers '
              '${WeatherTimeZone.displayHourMinute(first.time)}.',
        ),
      );
      return RainAlertSyncResult.scheduled;
    } on Object {
      return RainAlertSyncResult.failed;
    }
  }

  Future<bool> deleteRemoteRegistration() async {
    final deleted = await _remoteGateway?.deactivate() ?? true;
    await _scheduler.cancel();
    return deleted;
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _remoteGateway?.dispose();
  }

  RainIntensity _minimumIntensity(RainAlertIntensity value) => switch (value) {
    RainAlertIntensity.light => RainIntensity.light,
    RainAlertIntensity.moderate => RainIntensity.moderate,
    RainAlertIntensity.heavy => RainIntensity.heavy,
  };

  String _intensityLabel(RainIntensity value) => switch (value) {
    RainIntensity.none => 'Aucune pluie',
    RainIntensity.light => 'Pluie faible',
    RainIntensity.moderate => 'Pluie modérée',
    RainIntensity.heavy => 'Forte pluie',
  };

  bool _isQuietTime(DateTime instant, String timeZone) {
    if (!_preferences.quietHoursEnabled) return false;
    final wall = WeatherTimeZone.atLocation(instant, timeZone);
    final minute = wall.hour * 60 + wall.minute;
    final start = _parseMinutes(_preferences.quietHoursStart);
    final end = _parseMinutes(_preferences.quietHoursEnd);
    return start <= end
        ? minute >= start && minute < end
        : minute >= start || minute < end;
  }

  int _parseMinutes(String value) {
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
}
