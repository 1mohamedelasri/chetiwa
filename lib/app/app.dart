import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../features/forecast/domain/repositories/forecast_repository.dart';
import '../features/forecast/application/weather_section_cubit.dart';
import '../features/radar/domain/repositories/radar_repository.dart';
import '../core/location/location_repository.dart';
import '../core/location/active_location_controller.dart';
import '../core/time/weather_clock.dart';
import '../core/notifications/notification_permission_gateway.dart';
import '../core/notifications/rain_alert_navigation_controller.dart';
import '../features/alerts/application/local_rain_alert_coordinator.dart';
import '../core/l10n/chetiwa_localizations.dart';
import 'di/chetiwa_dependencies.dart';
import 'router/app_router.dart';
import 'preferences/app_preferences_controller.dart';
import '../features/alerts/application/alert_preferences_controller.dart';
import '../features/analytics/application/analytics_consent_controller.dart';
import '../features/analytics/application/analytics_tracker.dart';
import '../features/analytics/presentation/analytics_consent_prompt_gate.dart';
import '../features/monetization/domain/ads_repository.dart';
import '../features/monetization/domain/consent_repository.dart';
import '../features/monetization/application/saved_places_controller.dart';
import '../features/monetization/application/usage_quota_controller.dart';
import '../features/monetization/application/app_feature_flag_controller.dart';
import '../features/monetization/domain/premium_entitlement.dart';
import 'theme/chetiwa_theme.dart';

final class ChetiwaApp extends StatefulWidget {
  const ChetiwaApp({
    this.dependencies,
    this.analyticsConsent = false,
    this.analyticsConsentDecided = false,
    this.initialLocation = '/weather',
    this.initialWeatherSection = WeatherSection.graph,
    super.key,
  });

  final ChetiwaDependencies? dependencies;
  final bool analyticsConsent;
  final bool analyticsConsentDecided;
  final String initialLocation;
  final WeatherSection initialWeatherSection;

  @override
  State<ChetiwaApp> createState() => _ChetiwaAppState();
}

final class _ChetiwaAppState extends State<ChetiwaApp> {
  late final ChetiwaDependencies _dependencies =
      widget.dependencies ?? ChetiwaDependencies.live();
  late final AnalyticsConsentController _analyticsConsentController =
      AnalyticsConsentController(
        initiallyEnabled: widget.analyticsConsent,
        initiallyDecided: widget.analyticsConsentDecided,
      );
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final GoRouter _router = createAppRouter(
    initialLocation: widget.initialLocation,
    initialWeatherSection: widget.initialWeatherSection,
    navigatorKey: _navigatorKey,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_dependencies.localRainAlertCoordinator.initialize());
    unawaited(_dependencies.appFeatureFlagController.initialize());
  }

  @override
  void dispose() {
    _router.dispose();
    _analyticsConsentController.dispose();
    _dependencies.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: _dependencies.preferencesController,
    child: ChangeNotifierProvider<AnalyticsConsentController>.value(
      value: _analyticsConsentController,
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ForecastRepository>.value(
            value: _dependencies.forecastRepository,
          ),
          RepositoryProvider<RadarRepository>.value(
            value: _dependencies.radarRepository,
          ),
          RepositoryProvider<LocationRepository>.value(
            value: _dependencies.locationRepository,
          ),
          RepositoryProvider<WeatherClock>.value(
            value: _dependencies.weatherClock,
          ),
          RepositoryProvider<NotificationPermissionGateway>.value(
            value: _dependencies.notificationPermissionGateway,
          ),
          RepositoryProvider<LocalRainAlertCoordinator>.value(
            value: _dependencies.localRainAlertCoordinator,
          ),
          RepositoryProvider<AdsRepository>.value(
            value: _dependencies.adsRepository,
          ),
          RepositoryProvider<ConsentRepository>.value(
            value: _dependencies.consentRepository,
          ),
          RepositoryProvider<AnalyticsTracker>(
            create: (context) => AnalyticsTracker(
              consent: context.read<AnalyticsConsentController>(),
            ),
          ),
        ],
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<RainAlertNavigationController>.value(
              value: _dependencies.rainAlertNavigationController,
            ),
            ChangeNotifierProvider<AlertPreferencesController>.value(
              value: _dependencies.alertPreferencesController,
            ),
            ChangeNotifierProvider<ActiveLocationController>.value(
              value: _dependencies.activeLocationController,
            ),
            ChangeNotifierProvider<EntitlementController>.value(
              value: _dependencies.entitlementController,
            ),
            ChangeNotifierProvider<SavedPlacesController>.value(
              value: _dependencies.savedPlacesController,
            ),
            ChangeNotifierProvider<UsageQuotaController>.value(
              value: _dependencies.usageQuotaController,
            ),
            ChangeNotifierProvider<AppFeatureFlagController>.value(
              value: _dependencies.appFeatureFlagController,
            ),
          ],
          child: Consumer<AppPreferencesController>(
            builder: (context, preferences, _) => MaterialApp.router(
              onGenerateTitle: (context) => context.l10n.appTitle,
              debugShowCheckedModeBanner: false,
              theme: ChetiwaTheme.light,
              darkTheme: ChetiwaTheme.dark,
              themeMode: preferences.themeMode,
              builder: (context, child) {
                final brightness = Theme.of(context).brightness;
                final lightSurface = brightness == Brightness.light;
                return AnnotatedRegion<SystemUiOverlayStyle>(
                  value: SystemUiOverlayStyle(
                    statusBarColor: Colors.transparent,
                    statusBarIconBrightness: lightSurface
                        ? Brightness.dark
                        : Brightness.light,
                    // On iOS this controls the status-bar foreground.
                    statusBarBrightness: lightSurface
                        ? Brightness.light
                        : Brightness.dark,
                    systemNavigationBarColor: Theme.of(
                      context,
                    ).colorScheme.surface,
                    systemNavigationBarIconBrightness: lightSurface
                        ? Brightness.dark
                        : Brightness.light,
                  ),
                  child: AnalyticsConsentPromptGate(
                    navigatorKey: _navigatorKey,
                    child: child ?? const SizedBox.shrink(),
                  ),
                );
              },
              locale: preferences.locale,
              supportedLocales: ChetiwaLocalizations.supportedLocales,
              localizationsDelegates: const [
                ChetiwaLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              routerConfig: _router,
            ),
          ),
        ),
      ),
    ),
  );
}
