import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/chetiwa_tokens.dart';
import '../../../../app/theme/chetiwa_theme.dart';
import '../../../../core/time/weather_clock.dart';
import '../../../../core/location/location_repository.dart';
import '../../../../core/location/active_location_controller.dart';
import '../../../../core/l10n/chetiwa_localizations.dart';
import '../../../../core/widgets/weather_data_status.dart';
import '../../../radar/application/radar_bloc.dart';
import '../../../radar/domain/repositories/radar_repository.dart';
import '../../../radar/presentation/widgets/radar_pane.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      context.read<ForecastBloc>().add(const ForecastRefreshed());
      context.read<RadarBloc>().add(const RadarRequested());
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
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: ChetiwaSpacing.x6),
                child: ChetiwaHeader(),
              ),
              const SizedBox(height: ChetiwaSpacing.x2),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ChetiwaSpacing.x6,
                ),
                child: LocationSelector(
                  locationName: forecast.locationName,
                  onLocationSelected: (location) {
                    context.read<ActiveLocationController>().setActive(
                      location,
                    );
                    if (location.usesLastKnownPosition ||
                        location.hasReducedAccuracy) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            location.usesLastKnownPosition
                                ? context.l10n.lastKnownLocationNotice
                                : context.l10n.approximateLocationNotice,
                          ),
                        ),
                      );
                    }
                    context.read<ForecastBloc>().add(
                      ForecastLocationChanged(location),
                    );
                    context.read<RadarBloc>().add(
                      RadarLocationChanged(location.coordinates),
                    );
                  },
                ),
              ),
              const SizedBox(height: ChetiwaSpacing.x3),
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
                      WeatherSection.graph => _DarkDataSurface(
                        key: const ValueKey('graph'),
                        child: GraphPane(
                          forecast: forecast,
                          snapshot: state.snapshot,
                        ),
                      ),
                      WeatherSection.radar => _DarkDataSurface(
                        key: const ValueKey('radar'),
                        child: RadarPane(
                          forecast: forecast,
                          snapshot: state.snapshot,
                        ),
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
                padding: EdgeInsets.fromLTRB(16, 6, 16, 12),
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

final class _DarkDataSurface extends StatelessWidget {
  const _DarkDataSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
    data: ChetiwaTheme.dark,
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: ChetiwaColors.textPrimary),
      child: IconTheme(
        data: const IconThemeData(color: ChetiwaColors.textPrimary),
        child: ColoredBox(color: ChetiwaColors.backgroundPrimary, child: child),
      ),
    ),
  );
}
