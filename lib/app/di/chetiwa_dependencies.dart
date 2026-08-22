import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';
import '../../core/location/chetiwa_location_repository.dart';
import '../../core/location/active_location_controller.dart';
import '../../core/location/device_location_provider.dart';
import '../../core/location/fixture_location_repository.dart';
import '../../core/location/location_repository.dart';
import '../../core/location/open_meteo_location_repository.dart';
import '../../core/network/chetiwa_api_client.dart';
import '../../core/notifications/notification_permission_gateway.dart';
import '../../core/notifications/rain_notification_scheduler.dart';
import '../../core/time/weather_clock.dart';
import '../../features/forecast/data/cache/forecast_cache_data_source.dart';
import '../../features/forecast/data/datasources/fixture_forecast_data_source.dart';
import '../../features/forecast/data/repositories/fixture_forecast_repository.dart';
import '../../features/forecast/data/repositories/chetiwa_forecast_repository.dart';
import '../../features/forecast/data/repositories/open_meteo_forecast_repository.dart';
import '../../features/forecast/data/providers/open_meteo_forecast_provider.dart';
import '../../features/forecast/domain/repositories/forecast_repository.dart';
import '../../features/radar/data/cache/radar_cache_data_source.dart';
import '../../features/radar/data/repositories/fixture_radar_repository.dart';
import '../../features/radar/data/repositories/chetiwa_radar_repository.dart';
import '../../features/radar/data/repositories/rain_viewer_radar_repository.dart';
import '../../features/radar/data/providers/rain_viewer_radar_provider.dart';
import '../../features/radar/domain/repositories/radar_repository.dart';
import '../../features/alerts/application/alert_preferences_controller.dart';
import '../../features/alerts/application/local_rain_alert_coordinator.dart';
import '../../features/monetization/domain/ads_repository.dart';
import '../../features/monetization/domain/consent_repository.dart';
import '../preferences/app_preferences_controller.dart';
import 'development_fallback_repositories.dart';

final class ChetiwaDependencies {
  ChetiwaDependencies._({
    required this.forecastRepository,
    required this.radarRepository,
    required this.locationRepository,
    required this.activeLocationController,
    required this.weatherClock,
    required this.preferencesController,
    required this.alertPreferencesController,
    required this.notificationPermissionGateway,
    required this.rainNotificationScheduler,
    required this.adsRepository,
    required this.consentRepository,
    http.Client? client,
  }) : _client = client;

  factory ChetiwaDependencies.live() {
    final client = http.Client();
    const weatherClock = SystemWeatherClock();
    const forecastCache = ForecastCacheDataSource(clock: weatherClock);
    const radarCache = RadarCacheDataSource(clock: weatherClock);
    const deviceLocationProvider = GeolocatorDeviceLocationProvider();
    final directForecast = OpenMeteoForecastRepository(
      provider: OpenMeteoForecastProvider(client),
      cache: forecastCache,
    );
    final notificationTestForecast = FixtureForecastRepository(
      const FixtureForecastDataSource(
        fixtureName: 'notification_test',
        locationName: 'Paris, France',
      ),
    );
    final directRadar = RainViewerRadarRepository(
      provider: RainViewerRadarProvider(client),
      cache: radarCache,
    );
    final directLocation = OpenMeteoLocationRepository(
      client: client,
      deviceLocationProvider: deviceLocationProvider,
    );

    if (!ApiConfig.usesChetiwaBackend) {
      if (ApiConfig.isProduction) {
        throw StateError(
          'CHETIWA_API_BASE_URL is required in production. Direct provider '
          'access is forbidden.',
        );
      }
      return ChetiwaDependencies._(
        client: client,
        weatherClock: weatherClock,
        preferencesController: AppPreferencesController(),
        alertPreferencesController: AlertPreferencesController(),
        notificationPermissionGateway:
            const SystemNotificationPermissionGateway(),
        rainNotificationScheduler: SystemRainNotificationScheduler(),
        adsRepository: const DisabledAdsRepository(),
        consentRepository: const DisabledConsentRepository(),
        forecastRepository: ApiConfig.usesNotificationTestForecast
            ? notificationTestForecast
            : directForecast,
        radarRepository: directRadar,
        locationRepository: directLocation,
        activeLocationController: ActiveLocationController(directLocation),
      );
    }

    final api = ChetiwaApiClient(
      baseUri: ApiConfig.requireChetiwaApiBaseUri(),
      client: client,
    );
    final backendForecast = ChetiwaForecastRepository(
      api: api,
      cache: forecastCache,
    );
    final backendRadar = ChetiwaRadarRepository(api: api, cache: radarCache);
    final backendLocation = ChetiwaLocationRepository(
      api: api,
      deviceLocationProvider: deviceLocationProvider,
    );
    final fallback = ApiConfig.allowsDirectProviderFallback;
    final locationRepository = fallback
        ? DevelopmentFallbackLocationRepository(backendLocation, directLocation)
        : backendLocation;
    return ChetiwaDependencies._(
      client: client,
      weatherClock: weatherClock,
      preferencesController: AppPreferencesController(),
      alertPreferencesController: AlertPreferencesController(),
      notificationPermissionGateway:
          const SystemNotificationPermissionGateway(),
      rainNotificationScheduler: SystemRainNotificationScheduler(),
      adsRepository: const DisabledAdsRepository(),
      consentRepository: const DisabledConsentRepository(),
      forecastRepository: ApiConfig.usesNotificationTestForecast
          ? notificationTestForecast
          : fallback
          ? DevelopmentFallbackForecastRepository(
              backendForecast,
              directForecast,
            )
          : backendForecast,
      radarRepository: fallback
          ? DevelopmentFallbackRadarRepository(backendRadar, directRadar)
          : backendRadar,
      locationRepository: locationRepository,
      activeLocationController: ActiveLocationController(locationRepository),
    );
  }

  factory ChetiwaDependencies.fixture() => ChetiwaDependencies._(
    weatherClock: const SystemWeatherClock(),
    preferencesController: AppPreferencesController(persist: false),
    alertPreferencesController: AlertPreferencesController(persist: false),
    notificationPermissionGateway: FixtureNotificationPermissionGateway(),
    rainNotificationScheduler: FixtureRainNotificationScheduler(),
    adsRepository: const DisabledAdsRepository(),
    consentRepository: const DisabledConsentRepository(),
    forecastRepository: const FixtureForecastRepository(
      FixtureForecastDataSource(),
    ),
    radarRepository: const FixtureRadarRepository(),
    locationRepository: const FixtureLocationRepository(),
    activeLocationController: ActiveLocationController(
      const FixtureLocationRepository(),
    ),
  );

  factory ChetiwaDependencies.testing({
    required ForecastRepository forecastRepository,
    required RadarRepository radarRepository,
    required LocationRepository locationRepository,
    ActiveLocationController? activeLocationController,
    WeatherClock weatherClock = const SystemWeatherClock(),
    AppPreferencesController? preferencesController,
    AlertPreferencesController? alertPreferencesController,
    NotificationPermissionGateway? notificationPermissionGateway,
    RainNotificationScheduler? rainNotificationScheduler,
    AdsRepository? adsRepository,
    ConsentRepository? consentRepository,
  }) => ChetiwaDependencies._(
    forecastRepository: forecastRepository,
    radarRepository: radarRepository,
    locationRepository: locationRepository,
    activeLocationController:
        activeLocationController ??
        ActiveLocationController(locationRepository),
    weatherClock: weatherClock,
    preferencesController:
        preferencesController ?? AppPreferencesController(persist: false),
    alertPreferencesController:
        alertPreferencesController ??
        AlertPreferencesController(persist: false),
    notificationPermissionGateway:
        notificationPermissionGateway ?? FixtureNotificationPermissionGateway(),
    rainNotificationScheduler:
        rainNotificationScheduler ?? FixtureRainNotificationScheduler(),
    adsRepository: adsRepository ?? const DisabledAdsRepository(),
    consentRepository: consentRepository ?? const DisabledConsentRepository(),
  );

  final ForecastRepository forecastRepository;
  final RadarRepository radarRepository;
  final LocationRepository locationRepository;
  final ActiveLocationController activeLocationController;
  final WeatherClock weatherClock;
  final AppPreferencesController preferencesController;
  final AlertPreferencesController alertPreferencesController;
  final NotificationPermissionGateway notificationPermissionGateway;
  final RainNotificationScheduler rainNotificationScheduler;
  final AdsRepository adsRepository;
  final ConsentRepository consentRepository;
  final http.Client? _client;

  LocalRainAlertCoordinator get localRainAlertCoordinator =>
      LocalRainAlertCoordinator(
        forecastRepository: forecastRepository,
        locationRepository: locationRepository,
        preferences: alertPreferencesController,
        scheduler: rainNotificationScheduler,
        clock: weatherClock,
      );

  void dispose() {
    _client?.close();
    preferencesController.dispose();
    alertPreferencesController.dispose();
    activeLocationController.dispose();
  }
}
