import 'dart:async';

import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';
import '../../core/location/chetiwa_location_repository.dart';
import '../../core/location/coordinates.dart';
import '../../core/location/active_location_controller.dart';
import '../../core/location/device_location_provider.dart';
import '../../core/location/fixture_location_repository.dart';
import '../../core/location/location_repository.dart';
import '../../core/location/open_meteo_location_repository.dart';
import '../../core/network/chetiwa_api_client.dart';
import '../../core/notifications/notification_permission_gateway.dart';
import '../../core/notifications/rain_notification_scheduler.dart';
import '../../core/notifications/firebase_push_messaging.dart';
import '../../core/notifications/rain_alert_navigation_controller.dart';
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
import '../../features/alerts/application/remote_rain_alert_gateway.dart';
import '../../features/alerts/data/chetiwa_alert_api.dart';
import '../../features/monetization/domain/ads_repository.dart';
import '../../features/monetization/domain/consent_repository.dart';
import '../../features/monetization/application/saved_places_controller.dart';
import '../../features/monetization/application/usage_quota_controller.dart';
import '../../features/monetization/application/app_feature_flag_controller.dart';
import '../../features/monetization/data/store_purchase_gateway.dart';
import '../../features/monetization/data/chetiwa_radar_session_gateway.dart';
import '../../features/monetization/data/google_ads_repository.dart';
import '../../features/monetization/data/google_consent_repository.dart';
import '../../features/monetization/domain/premium_entitlement.dart';
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
    RainAlertNavigationController? rainAlertNavigationController,
    this.remoteRainAlertGateway,
    required this.adsRepository,
    required this.consentRepository,
    required this.entitlementController,
    required this.savedPlacesController,
    required this.usageQuotaController,
    required this.appFeatureFlagController,
    http.Client? client,
  }) : rainAlertNavigationController =
           rainAlertNavigationController ?? RainAlertNavigationController(),
       _client = client;

  factory ChetiwaDependencies.live() {
    final client = http.Client();
    final consentRepository = GoogleConsentRepository();
    final adsRepository = GoogleAdsRepository(consent: consentRepository);
    final entitlementController = EntitlementController(
      gateway: StorePurchaseGateway(),
    );
    final savedPlacesController = SavedPlacesController(
      entitlement: entitlementController,
    );
    final api = ApiConfig.usesChetiwaBackend
        ? ChetiwaApiClient(
            baseUri: ApiConfig.requireChetiwaApiBaseUri(),
            client: client,
          )
        : null;
    final usageQuotaController = UsageQuotaController(
      entitlement: entitlementController,
      radarSessionGateway: api == null ? null : ChetiwaRadarSessionGateway(api),
    );
    final appFeatureFlagController = AppFeatureFlagController(
      gateway: api == null ? null : ChetiwaAppFeatureFlagGateway(api),
    );
    final rainAlertNavigationController = RainAlertNavigationController();
    final remoteRainAlertGateway = api == null
        ? null
        : ChetiwaRemoteRainAlertGateway(
            api: ChetiwaAlertApi(api),
            messaging: FirebasePushMessagingGateway(
              navigation: rainAlertNavigationController,
            ),
          );
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
        rainAlertNavigationController: rainAlertNavigationController,
        remoteRainAlertGateway: remoteRainAlertGateway,
        adsRepository: adsRepository,
        consentRepository: consentRepository,
        entitlementController: entitlementController,
        savedPlacesController: savedPlacesController,
        usageQuotaController: usageQuotaController,
        appFeatureFlagController: appFeatureFlagController,
        forecastRepository: ApiConfig.usesNotificationTestForecast
            ? notificationTestForecast
            : directForecast,
        radarRepository: directRadar,
        locationRepository: directLocation,
        activeLocationController: ActiveLocationController(directLocation),
      );
    }

    final backendForecast = ChetiwaForecastRepository(
      api: api!,
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
      rainAlertNavigationController: rainAlertNavigationController,
      remoteRainAlertGateway: remoteRainAlertGateway,
      adsRepository: adsRepository,
      consentRepository: consentRepository,
      entitlementController: entitlementController,
      savedPlacesController: savedPlacesController,
      usageQuotaController: usageQuotaController,
      appFeatureFlagController: appFeatureFlagController,
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

  factory ChetiwaDependencies.fixture({
    AppFeatureFlags featureFlags = const AppFeatureFlags(
      premiumAvailable: true,
      adsEnabled: true,
    ),
    bool storeScreenshot = false,
  }) {
    final entitlementController = EntitlementController(
      gateway: FixturePremiumPurchaseGateway(),
      persist: false,
      autoSync: false,
    );
    final fixtureLocation = FixtureLocationRepository(
      mainLocation: storeScreenshot ? LocationCatalog.locations.first : null,
    );
    return ChetiwaDependencies._(
      weatherClock: const SystemWeatherClock(),
      preferencesController: AppPreferencesController(persist: false),
      alertPreferencesController: AlertPreferencesController(persist: false),
      notificationPermissionGateway: FixtureNotificationPermissionGateway(),
      rainNotificationScheduler: FixtureRainNotificationScheduler(),
      adsRepository: const DisabledAdsRepository(),
      consentRepository: const DisabledConsentRepository(),
      entitlementController: entitlementController,
      savedPlacesController: SavedPlacesController(
        entitlement: entitlementController,
        persist: false,
      ),
      usageQuotaController: UsageQuotaController(
        entitlement: entitlementController,
        persist: false,
      ),
      appFeatureFlagController: AppFeatureFlagController(
        initial: featureFlags,
        persist: false,
      ),
      forecastRepository: FixtureForecastRepository(
        FixtureForecastDataSource(
          providerName: storeScreenshot
              ? 'Météo-France AROME via Open-Meteo'
              : 'Fixture Open-Meteo',
        ),
      ),
      radarRepository: FixtureRadarRepository(
        providerName: storeScreenshot ? 'LibreWXR' : 'Fixture Radar',
      ),
      locationRepository: fixtureLocation,
      activeLocationController: ActiveLocationController(fixtureLocation),
    );
  }

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
    RemoteRainAlertGateway? remoteRainAlertGateway,
    AdsRepository? adsRepository,
    ConsentRepository? consentRepository,
    EntitlementController? entitlementController,
    SavedPlacesController? savedPlacesController,
    UsageQuotaController? usageQuotaController,
    AppFeatureFlagController? appFeatureFlagController,
  }) {
    final entitlement =
        entitlementController ??
        EntitlementController(
          gateway: FixturePremiumPurchaseGateway(),
          persist: false,
          autoSync: false,
        );
    return ChetiwaDependencies._(
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
          notificationPermissionGateway ??
          FixtureNotificationPermissionGateway(),
      rainNotificationScheduler:
          rainNotificationScheduler ?? FixtureRainNotificationScheduler(),
      remoteRainAlertGateway: remoteRainAlertGateway,
      adsRepository: adsRepository ?? const DisabledAdsRepository(),
      consentRepository: consentRepository ?? const DisabledConsentRepository(),
      entitlementController: entitlement,
      savedPlacesController:
          savedPlacesController ??
          SavedPlacesController(entitlement: entitlement, persist: false),
      usageQuotaController:
          usageQuotaController ??
          UsageQuotaController(entitlement: entitlement, persist: false),
      appFeatureFlagController:
          appFeatureFlagController ??
          AppFeatureFlagController(
            initial: const AppFeatureFlags(
              premiumAvailable: true,
              adsEnabled: true,
            ),
            persist: false,
          ),
    );
  }

  final ForecastRepository forecastRepository;
  final RadarRepository radarRepository;
  final LocationRepository locationRepository;
  final ActiveLocationController activeLocationController;
  final WeatherClock weatherClock;
  final AppPreferencesController preferencesController;
  final AlertPreferencesController alertPreferencesController;
  final NotificationPermissionGateway notificationPermissionGateway;
  final RainNotificationScheduler rainNotificationScheduler;
  final RainAlertNavigationController rainAlertNavigationController;
  final RemoteRainAlertGateway? remoteRainAlertGateway;
  final AdsRepository adsRepository;
  final ConsentRepository consentRepository;
  final EntitlementController entitlementController;
  final SavedPlacesController savedPlacesController;
  final UsageQuotaController usageQuotaController;
  final AppFeatureFlagController appFeatureFlagController;
  final http.Client? _client;

  late final LocalRainAlertCoordinator localRainAlertCoordinator =
      LocalRainAlertCoordinator(
        forecastRepository: forecastRepository,
        locationRepository: locationRepository,
        preferences: alertPreferencesController,
        scheduler: rainNotificationScheduler,
        clock: weatherClock,
        remoteGateway: remoteRainAlertGateway,
      );

  void dispose() {
    _client?.close();
    preferencesController.dispose();
    alertPreferencesController.dispose();
    entitlementController.dispose();
    savedPlacesController.dispose();
    usageQuotaController.dispose();
    appFeatureFlagController.dispose();
    activeLocationController.dispose();
    rainAlertNavigationController.dispose();
    unawaited(localRainAlertCoordinator.dispose());
  }
}
