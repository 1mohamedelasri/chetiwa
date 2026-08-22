import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/chetiwa_tokens.dart';
import '../../../../core/location/coordinates.dart';
import '../../../../core/time/weather_clock.dart';
import '../../../../core/location/location_repository.dart';
import '../../../../core/location/active_location_controller.dart';
import '../../../../core/l10n/chetiwa_localizations.dart';
import '../../../../core/widgets/weather_data_status.dart';
import '../../../radar/application/radar_bloc.dart';
import '../../../radar/domain/repositories/radar_repository.dart';
import '../../../radar/presentation/widgets/radar_pane.dart';
import '../../../analytics/application/analytics_tracker.dart';
import '../../../alerts/application/local_rain_alert_coordinator.dart';
import '../../../monetization/application/usage_quota_controller.dart';
import '../../../monetization/domain/premium_entitlement.dart';
import '../../../monetization/domain/premium_limits.dart';
import '../../application/forecast_bloc.dart';
import '../../application/graph_horizon_cubit.dart';
import '../../application/weather_section_cubit.dart';
import '../../domain/repositories/forecast_repository.dart';
import '../widgets/graph_pane.dart';
import '../widgets/forecast_pane.dart';
import '../widgets/weather_chrome.dart';

final class WeatherScreen extends StatelessWidget {
  const WeatherScreen({super.key});

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
      BlocProvider(create: (_) => WeatherSectionCubit()),
      BlocProvider(
        lazy: false,
        create: (context) => RadarBloc(
          context.read<RadarRepository>(),
          clock: context.read<WeatherClock>(),
          maxFrames: PremiumLimits.forEntitlement(
            context.read<EntitlementController>(),
          ).maxRadarFrames,
          historyHours: PremiumLimits.forEntitlement(
            context.read<EntitlementController>(),
          ).radarHistoryHours,
          usageQuota: context.read<UsageQuotaController>(),
        )..add(const RadarRequested()),
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
  Coordinates? _radarCoordinates;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeLocationController = context.read<ActiveLocationController>();
    _activeLocationController.addListener(_syncRadarLocation);
    // Both the forecast and the active-location controller restore the saved
    // main place asynchronously. Radar used to keep its independent Paris
    // default, so the header could say Lyon while the map pin stayed in Paris.
    // Defer the first sync until every provider above this view is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncRadarLocation());
  }

  @override
  void dispose() {
    _activeLocationController.removeListener(_syncRadarLocation);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      context.read<ForecastBloc>().add(const ForecastRefreshed());
      context.read<RadarBloc>().add(const RadarRequested());
      unawaited(context.read<LocalRainAlertCoordinator>().sync());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      context.read<RadarBloc>().add(const RadarPlaybackPaused());
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
                  ),
                ),
                const SizedBox(height: ChetiwaSpacing.x2),
              ],
              Expanded(
                child: BlocBuilder<WeatherSectionCubit, WeatherSection>(
                  builder: (context, section) => AnimatedSwitcher(
                    duration: ChetiwaMotion.accessible(
                      context,
                      ChetiwaMotion.standard,
                    ),
                    switchInCurve: Curves.easeOutCubic,
                    child: switch (section) {
                      WeatherSection.graph => GraphPane(
                        key: const ValueKey('graph'),
                        forecast: forecast,
                        snapshot: state.snapshot,
                      ),
                      WeatherSection.radar => RadarPane(
                        key: const ValueKey('radar'),
                        forecast: forecast,
                        snapshot: state.snapshot,
                      ),
                      WeatherSection.forecast => ForecastPane(
                        key: const ValueKey('forecast'),
                        forecast: forecast,
                        snapshot: state.snapshot,
                      ),
                    },
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
