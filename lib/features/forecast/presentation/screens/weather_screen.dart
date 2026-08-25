import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/chetiwa_tokens.dart';
import '../../../../core/location/coordinates.dart';
import '../../../../core/time/weather_clock.dart';
import '../../../../core/location/location_repository.dart';
import '../../../../core/location/active_location_controller.dart';
import '../../../../core/l10n/chetiwa_localizations.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/notifications/rain_alert_navigation_controller.dart';
import '../../../../core/widgets/weather_data_status.dart';
import '../../../radar/application/radar_bloc.dart';
import '../../../radar/domain/repositories/radar_repository.dart';
import '../../../radar/domain/services/radar_basemap_policy.dart';
import '../../../radar/presentation/widgets/radar_pane.dart';
import '../../../analytics/application/analytics_tracker.dart';
import '../../../alerts/application/local_rain_alert_coordinator.dart';
import '../../../monetization/domain/premium_entitlement.dart';
import '../../../monetization/domain/premium_limits.dart';
import '../../../monetization/application/app_feature_flag_controller.dart';
import '../../application/forecast_bloc.dart';
import '../../application/graph_horizon_cubit.dart';
import '../../application/weather_section_cubit.dart';
import '../../domain/repositories/forecast_repository.dart';
import '../widgets/graph_pane.dart';
import '../widgets/forecast_pane.dart';
import '../widgets/weather_chrome.dart';

final class WeatherScreen extends StatelessWidget {
  const WeatherScreen({this.initialSection = WeatherSection.graph, super.key});

  final WeatherSection initialSection;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (context) => ForecastBloc(
          context.read<ForecastRepository>(),
          clock: context.read<WeatherClock>(),
          locationRepository: context.read<LocationRepository>(),
        )..add(const ForecastRequested()),
      ),
      BlocProvider(create: (_) => GraphHorizonCubit()),
      BlocProvider(
        create: (_) => WeatherSectionCubit(initialSection: initialSection),
      ),
      BlocProvider(
        lazy: false,
        create: (context) {
          final entitlement = context.read<EntitlementController>();
          final flags = context.read<AppFeatureFlagController>();
          final limits = PremiumLimits.forEntitlement(entitlement);
          return RadarBloc(
            context.read<RadarRepository>(),
            clock: context.read<WeatherClock>(),
            maxFrames: limits.maxRadarFrames,
            historyHours: limits.radarHistoryHours,
            allowModelForecast:
                entitlement.isPremium && flags.premiumRadarModelAvailable,
          );
        },
      ),
    ],
    child: const _WeatherView(),
  );
}

final class _WeatherView extends StatefulWidget {
  const _WeatherView();

  @override
  State<_WeatherView> createState() => _WeatherViewState();
}

final class _WeatherViewState extends State<_WeatherView>
    with WidgetsBindingObserver {
  late final ActiveLocationController _activeLocationController;
  late final RainAlertNavigationController _alertNavigationController;
  late final EntitlementController _entitlementController;
  late final AppFeatureFlagController _featureFlagController;
  Coordinates? _radarCoordinates;
  Timer? _resumeForecastTimer;
  Timer? _resumeRadarTimer;
  Timer? _resumeAlertTimer;
  Timer? _initialRadarTimer;
  DateTime? _lastResumeRefreshAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeLocationController = context.read<ActiveLocationController>();
    _alertNavigationController = context.read<RainAlertNavigationController>();
    _entitlementController = context.read<EntitlementController>();
    _featureFlagController = context.read<AppFeatureFlagController>();
    _activeLocationController.addListener(_syncRadarLocation);
    _alertNavigationController.addListener(_openRainAlert);
    _entitlementController.addListener(_syncRadarPremiumAccess);
    _featureFlagController.addListener(_syncRadarPremiumAccess);
    // Both the forecast and the active-location controller restore the saved
    // main place asynchronously. Radar used to keep its independent Paris
    // default, so the header could say Lyon while the map pin stayed in Paris.
    // Defer the first sync until every provider above this view is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncRadarLocation();
      _syncRadarPremiumAccess();
      _openRainAlert();
      if (_radarCoordinates == null) {
        // Give the small local saved-place read one short window to complete.
        // Previously Radar fetched Paris immediately and then fetched the
        // restored place again, causing duplicate startup work and jank.
        _initialRadarTimer = Timer(const Duration(milliseconds: 250), () {
          if (!mounted || _radarCoordinates != null) return;
          _syncRadarLocation();
          if (_radarCoordinates == null) {
            context.read<RadarBloc>().add(const RadarRequested());
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _resumeForecastTimer?.cancel();
    _resumeRadarTimer?.cancel();
    _resumeAlertTimer?.cancel();
    _initialRadarTimer?.cancel();
    _activeLocationController.removeListener(_syncRadarLocation);
    _alertNavigationController.removeListener(_openRainAlert);
    _entitlementController.removeListener(_syncRadarPremiumAccess);
    _featureFlagController.removeListener(_syncRadarPremiumAccess);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _syncRadarLocation() {
    if (!mounted) return;
    final coordinates = _activeLocationController.location?.coordinates;
    if (coordinates == null || coordinates == _radarCoordinates) return;
    _radarCoordinates = coordinates;
    context.read<RadarBloc>().add(RadarLocationChanged(coordinates));
  }

  void _syncRadarPremiumAccess() {
    if (!mounted) return;
    final limits = PremiumLimits.forEntitlement(_entitlementController);
    context.read<RadarBloc>().add(
      RadarPremiumAccessChanged(
        allowModelForecast:
            _entitlementController.isPremium &&
            _featureFlagController.premiumRadarModelAvailable,
        maxFrames: limits.maxRadarFrames,
        historyHours: limits.radarHistoryHours,
      ),
    );
  }

  void _openRainAlert() {
    if (!mounted) return;
    final intent = _alertNavigationController.take();
    if (intent == null) return;
    final location = ChetiwaLocation(
      city: intent.locationLabel,
      country: '',
      coordinates: intent.coordinates,
    );
    unawaited(_activeLocationController.setActive(location));
    context.read<ForecastBloc>().add(ForecastLocationChanged(location));
    context.read<WeatherSectionCubit>().select(
      intent.section == 'graph' ? WeatherSection.graph : WeatherSection.radar,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      // Resume the already-buffered animation immediately. Network, decoding
      // and alert work are then staggered after the first responsive frame.
      context.read<RadarBloc>().add(const RadarPlaybackResumed());
      final now = DateTime.timestamp();
      final lastRefresh = _lastResumeRefreshAt;
      if (lastRefresh != null &&
          now.difference(lastRefresh) < const Duration(seconds: 20)) {
        return;
      }
      _lastResumeRefreshAt = now;
      _resumeForecastTimer?.cancel();
      _resumeRadarTimer?.cancel();
      _resumeAlertTimer?.cancel();
      _resumeForecastTimer = Timer(const Duration(milliseconds: 150), () {
        if (mounted) {
          context.read<ForecastBloc>().add(const ForecastRefreshed());
        }
      });
      _resumeRadarTimer = Timer(const Duration(milliseconds: 450), () {
        if (mounted) {
          // A silent refresh preserves the visible frames and avoids a second
          // disk-cache read that RadarRequested performed on every resume.
          context.read<RadarBloc>().add(const RadarRefreshed());
        }
      });
      _resumeAlertTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) {
          unawaited(context.read<LocalRainAlertCoordinator>().sync());
        }
      });
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      context.read<RadarBloc>().add(const RadarPlaybackSuspended());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: BlocBuilder<ForecastBloc, ForecastState>(
        builder: (context, state) {
          if (state is ForecastFailure) {
            return WeatherDataUnavailableView(
              issue: state.issue,
              domainLabel: 'Open-Meteo',
              onRetry: () =>
                  context.read<ForecastBloc>().add(const ForecastRefreshed()),
            );
          }
          if (state is! ForecastReady) {
            return WeatherDataLoadingView(label: context.l10n.loadingWeather);
          }

          final forecast = state.forecast;
          void selectLocation(ChetiwaLocation location) async {
            final analytics = context.read<AnalyticsTracker>();
            final activeLocation = context.read<ActiveLocationController>();
            final forecastBloc = context.read<ForecastBloc>();
            final alertCoordinator = context.read<LocalRainAlertCoordinator>();
            final messenger = ScaffoldMessenger.of(context);
            final lastKnownNotice = context.l10n.lastKnownLocationNotice;
            final approximateNotice = context.l10n.approximateLocationNotice;
            unawaited(analytics.locationSelected(location.acquisition.name));
            await activeLocation.setActive(location);
            if (!mounted) return;
            if (location.usesLastKnownPosition || location.hasReducedAccuracy) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    location.usesLastKnownPosition
                        ? lastKnownNotice
                        : approximateNotice,
                  ),
                ),
              );
            }
            forecastBloc.add(ForecastLocationChanged(location));
            // Header selections must also replace an already scheduled alert
            // immediately; otherwise it can still target the previous city
            // until the next app resume.
            unawaited(alertCoordinator.sync());
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ChetiwaSpacing.x4,
                ),
                child: ChetiwaHeader(
                  locationName: forecast.locationName,
                  onLocationSelected: selectLocation,
                ),
              ),
              const SizedBox(height: ChetiwaSpacing.x2),
              if (state.health.issue != null ||
                  state.health.usesCache ||
                  state.health.isRefreshing) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ChetiwaSpacing.x6,
                  ),
                  child: WeatherDataStatusBanner(
                    key: const Key('forecast-data-status'),
                    health: state.health,
                    domainLabel: 'Open-Meteo',
                    nowUtc: state.snapshot.nowUtc,
                    dataUpdatedAt: state.forecast.updatedAt,
                    onRetry: () => context.read<ForecastBloc>().add(
                      const ForecastRefreshed(),
                    ),
                  ),
                ),
                const SizedBox(height: ChetiwaSpacing.x2),
              ],
              Expanded(
                child: BlocBuilder<WeatherSectionCubit, WeatherSection>(
                  builder: (context, section) => IndexedStack(
                    // Radar is a primary surface. Keep it laid out behind
                    // Graph so flutter_map can load the current viewport while
                    // the user reads the forecast instead of starting every
                    // network request only after the first Radar tap.
                    index: section.index,
                    children: [
                      BlocBuilder<RadarBloc, RadarState>(
                        builder: (context, radarState) => GraphPane(
                          key: const ValueKey('graph'),
                          forecast: forecast,
                          snapshot: state.snapshot,
                          radarFrames: radarState is RadarReady
                              ? radarState.frames
                              : const [],
                        ),
                      ),
                      RadarPane(
                        key: const ValueKey('radar'),
                        forecast: forecast,
                        snapshot: state.snapshot,
                        isActive: section == WeatherSection.radar,
                        satelliteAvailable:
                            RadarBasemapPolicy.canUsePremiumSatellite(
                              isPremium: context
                                  .watch<EntitlementController>()
                                  .isPremium,
                              premiumSatelliteEnabled: context
                                  .watch<AppFeatureFlagController>()
                                  .premiumSatelliteAvailable,
                              arcGisConfigured:
                                  ApiConfig.arcGisApiKey.isNotEmpty,
                            ),
                        modelForecastLocked:
                            context
                                .watch<AppFeatureFlagController>()
                                .premiumAvailable &&
                            context
                                .watch<AppFeatureFlagController>()
                                .premiumRadarModelAvailable &&
                            !context.watch<EntitlementController>().isPremium,
                      ),
                      ForecastPane(
                        key: const ValueKey('forecast'),
                        forecast: forecast,
                        snapshot: state.snapshot,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const AdaptiveAdBannerSlot(),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 5, 16, 8),
                child: WeatherBottomNavigation(),
              ),
              SizedBox(height: MediaQuery.paddingOf(context).bottom),
            ],
          );
        },
      ),
    ),
  );
}
