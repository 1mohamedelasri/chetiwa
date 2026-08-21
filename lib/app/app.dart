import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../features/forecast/domain/repositories/forecast_repository.dart';
import '../features/radar/domain/repositories/radar_repository.dart';
import '../core/location/location_repository.dart';
import '../core/location/active_location_controller.dart';
import '../core/time/weather_clock.dart';
import '../core/notifications/notification_permission_gateway.dart';
import '../core/l10n/chetiwa_localizations.dart';
import 'di/chetiwa_dependencies.dart';
import 'router/app_router.dart';
import 'preferences/app_preferences_controller.dart';
import '../features/alerts/application/alert_preferences_controller.dart';
import '../features/analytics/application/analytics_consent_controller.dart';
import '../features/analytics/application/analytics_tracker.dart';
import '../features/monetization/domain/ads_repository.dart';
import '../features/monetization/domain/consent_repository.dart';
import 'theme/chetiwa_theme.dart';

final class ChetiwaApp extends StatefulWidget {
  const ChetiwaApp({
    this.dependencies,
    this.analyticsConsent = false,
    super.key,
  });

  final ChetiwaDependencies? dependencies;
  final bool analyticsConsent;

  @override
  State<ChetiwaApp> createState() => _ChetiwaAppState();
}

final class _ChetiwaAppState extends State<ChetiwaApp> {
  late final ChetiwaDependencies _dependencies =
      widget.dependencies ?? ChetiwaDependencies.live();
  late final AnalyticsConsentController _analyticsConsentController =
      AnalyticsConsentController(initiallyEnabled: widget.analyticsConsent);
  late final GoRouter _router = createAppRouter();

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
            ChangeNotifierProvider<AlertPreferencesController>.value(
              value: _dependencies.alertPreferencesController,
            ),
            ChangeNotifierProvider<ActiveLocationController>.value(
              value: _dependencies.activeLocationController,
            ),
          ],
          child: Consumer<AppPreferencesController>(
            builder: (context, preferences, _) => MaterialApp.router(
              onGenerateTitle: (context) => context.l10n.appTitle,
              debugShowCheckedModeBanner: false,
              theme: ChetiwaTheme.light,
              darkTheme: ChetiwaTheme.dark,
              themeMode: preferences.themeMode,
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
