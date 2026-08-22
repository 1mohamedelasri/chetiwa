import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/chetiwa_tokens.dart';
import '../../../../core/location/coordinates.dart';
import '../../../../core/location/location_repository.dart';
import '../../../../core/l10n/chetiwa_localizations.dart';
import '../../../../core/time/weather_clock.dart';
import '../../../../core/weather/temperature_formatter.dart';
import '../../../analytics/application/analytics_tracker.dart';
import 'map_location_picker_screen.dart';
import '../../application/weather_section_cubit.dart';
import '../../domain/entities/forecast.dart';
import '../../domain/services/forecast_snapshot_builder.dart';

final class ChetiwaHeader extends StatelessWidget {
  const ChetiwaHeader({
    required this.locationName,
    required this.onLocationSelected,
    super.key,
  });

  final String locationName;
  final ValueChanged<ChetiwaLocation> onLocationSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 88,
    child: Column(
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              const SizedBox.square(dimension: 44),
              const Expanded(
                child: Text(
                  'Chetiwa',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  tooltip: context.l10n.settings,
                  onPressed: () => context.push('/settings'),
                  icon: const Icon(Icons.tune_rounded, size: 21),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        LocationSelector(
          locationName: locationName,
          onLocationSelected: onLocationSelected,
        ),
      ],
    ),
  );
}

final class LocationSelector extends StatelessWidget {
  const LocationSelector({
    required this.locationName,
    required this.onLocationSelected,
    super.key,
  });

  final String locationName;
  final ValueChanged<ChetiwaLocation> onLocationSelected;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.l10n.selectedLocationLabel(locationName),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(ChetiwaRadius.medium),
      child: InkWell(
        onTap: () async {
          final repository = context.read<LocationRepository>();
          final selected = await showModalBottomSheet<ChetiwaLocation>(
            context: context,
            useSafeArea: true,
            isScrollControlled: true,
            backgroundColor: Theme.of(context).colorScheme.surface,
            builder: (_) => _LocationPicker(repository: repository),
          );
          if (selected != null) onLocationSelected(selected);
        },
        borderRadius: BorderRadius.circular(ChetiwaRadius.medium),
        child: SizedBox(
          height: 42,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: ChetiwaSpacing.x2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_on_outlined, size: 18),
                const SizedBox(width: ChetiwaSpacing.x2),
                Flexible(
                  child: Text(
                    locationName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: ChetiwaSpacing.x1),
                const Icon(Icons.expand_more_rounded, size: 22),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

final class LiveMetrics extends StatelessWidget {
  const LiveMetrics({
    required this.forecast,
    required this.snapshot,
    super.key,
  });

  final Forecast forecast;
  final ForecastSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final currentRain = snapshot.currentRain.rateMmPerHour;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return Container(
      height: 68 * textScale.clamp(1, 1.65),
      padding: const EdgeInsets.symmetric(
        horizontal: ChetiwaSpacing.x3,
        vertical: ChetiwaSpacing.x3,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(ChetiwaRadius.medium),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        children: [
          _Metric(
            key: const Key('current-local-time'),
            label: context.l10n.currentEstimate,
            value: WeatherTimeZone.hourMinute(
              snapshot.nowUtc,
              forecast.timeZone,
            ),
          ),
          _Metric(
            label: context.l10n.rain,
            value:
                '${currentRain.toStringAsFixed(currentRain == 0 ? 0 : 1)} mm/h',
          ),
          _Metric(
            label: 'TEMP.',
            value: formatTemperature(
              context,
              forecast.temperatureCelsius,
              unit: true,
            ),
          ),
          _Metric(
            label: context.l10n.wind,
            value: '${forecast.windKph.round()} km/h',
          ),
        ],
      ),
    );
  }
}

final class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 8,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

final class WeatherBottomNavigation extends StatelessWidget {
  const WeatherBottomNavigation({super.key});

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<WeatherSectionCubit, WeatherSection>(
    builder: (context, section) => Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(ChetiwaRadius.large),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        boxShadow: ChetiwaElevation.floating,
      ),
      child: Row(
        children: [
          _NavigationItem(
            label: context.l10n.graph,
            icon: Icons.show_chart_rounded,
            selected: section == WeatherSection.graph,
            onTap: () {
              context.read<WeatherSectionCubit>().select(WeatherSection.graph);
              unawaited(context.read<AnalyticsTracker>().tabSelected('graph'));
            },
          ),
          _NavigationItem(
            label: context.l10n.radar,
            icon: Icons.radar_rounded,
            selected: section == WeatherSection.radar,
            onTap: () {
              context.read<WeatherSectionCubit>().select(WeatherSection.radar);
              unawaited(context.read<AnalyticsTracker>().tabSelected('radar'));
            },
          ),
          _NavigationItem(
            label: context.l10n.forecasts,
            icon: Icons.cloud_outlined,
            selected: section == WeatherSection.forecast,
            onTap: () {
              context.read<WeatherSectionCubit>().select(
                WeatherSection.forecast,
              );
              unawaited(
                context.read<AnalyticsTracker>().tabSelected('forecast'),
              );
            },
          ),
        ],
      ),
    ),
  );
}

final class AdaptiveAdBannerSlot extends StatelessWidget {
  const AdaptiveAdBannerSlot({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final height = media.size.height < 600 ? 36.0 : 50.0;
    return Semantics(
      label: context.l10n.advertisement,
      container: true,
      child: Container(
        key: const Key('adaptive-ad-banner-slot'),
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: ChetiwaSpacing.x4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(ChetiwaRadius.small),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        alignment: Alignment.center,
        child: Text(
          context.l10n.advertisement,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 8,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }
}

final class _LocationPicker extends StatefulWidget {
  const _LocationPicker({required this.repository});

  final LocationRepository repository;

  @override
  State<_LocationPicker> createState() => _LocationPickerState();
}

final class _LocationPickerState extends State<_LocationPicker> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<ChetiwaLocation> _results = const [];
  List<ChetiwaLocation> _recent = const [];
  bool _isSearching = false;
  bool _isLocating = false;
  String? _searchError;
  String? _locationError;
  LocationRecoveryAction? _locationRecoveryAction;
  int _searchGeneration = 0;

  bool get _isQuerying => _searchController.text.trim().length >= 2;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final recent = await widget.repository.getRecentLocations();
    if (mounted) setState(() => _recent = recent);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    setState(() {
      _searchError = null;
      if (query.length < 2) {
        _results = const [];
        _isSearching = false;
      }
    });
    if (query.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (mounted) {
      unawaited(context.read<AnalyticsTracker>().locationSearchRequested());
    }
    final generation = ++_searchGeneration;
    setState(() {
      _isSearching = true;
      _searchError = null;
    });
    try {
      final results = await widget.repository.search(query);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = results;
        _isSearching = false;
      });
    } on LocationException catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = const [];
        _isSearching = false;
        _searchError = context.l10n.locationIssue(error);
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _isLocating = true;
      _locationError = null;
      _locationRecoveryAction = null;
    });
    try {
      final location = await widget.repository.getCurrentLocation();
      if (!mounted) return;
      Navigator.pop(context, location);
    } on LocationException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLocating = false;
        _locationError = context.l10n.locationIssue(error);
        _locationRecoveryAction = error.recoveryAction;
      });
    }
  }

  Future<void> _openLocationRecovery() async {
    final action = _locationRecoveryAction;
    if (action == null) return;
    await widget.repository.openLocationRecovery(action);
    if (!mounted) return;
    setState(() {
      _locationError = action == LocationRecoveryAction.appSettings
          ? context.l10n.allowThenRetry
          : context.l10n.enableGpsThenRetry;
    });
  }

  Future<void> _select(ChetiwaLocation location) async {
    await Future.wait<void>([
      widget.repository.setMainLocation(location),
      widget.repository.remember(location),
    ]);
    if (mounted) Navigator.pop(context, location);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.74,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, controller) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.outline,
              borderRadius: BorderRadius.circular(ChetiwaRadius.full),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Row(
              children: [
                const Icon(Icons.location_city_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.l10n.chooseCity,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.close,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: TextField(
              key: const Key('location-search-field'),
              controller: _searchController,
              onChanged: _onSearchChanged,
              onSubmitted: (value) {
                _debounce?.cancel();
                if (value.trim().length >= 2) _search(value.trim());
              },
              textInputAction: TextInputAction.search,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: context.l10n.searchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.l10n.clear,
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                        icon: const Icon(Icons.clear_rounded),
                      ),
                filled: true,
                fillColor: colors.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ChetiwaRadius.medium),
                  borderSide: BorderSide(color: colors.outline),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                ListTile(
                  key: const Key('current-location-tile'),
                  enabled: !_isLocating,
                  minVerticalPadding: 12,
                  leading: CircleAvatar(
                    backgroundColor: colors.primary,
                    child: Icon(
                      Icons.my_location_rounded,
                      color: colors.onPrimary,
                    ),
                  ),
                  title: Text(
                    context.l10n.useCurrentLocation,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    _locationError ?? context.l10n.onDemandLocation,
                    style: TextStyle(
                      color: _locationError == null
                          ? colors.onSurfaceVariant
                          : ChetiwaColors.error,
                    ),
                  ),
                  trailing: _isLocating
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _locationRecoveryAction == null
                      ? const Icon(Icons.chevron_right_rounded)
                      : TextButton(
                          key: const Key('open-location-settings-button'),
                          onPressed: _openLocationRecovery,
                          child: Text(context.l10n.settings),
                        ),
                  onTap: _isLocating ? null : _useCurrentLocation,
                ),
                if (_locationRecoveryAction != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(72, 0, 12, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        context.l10n.retryCurrentLocationHelp,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('choose-on-map-tile'),
                  minVerticalPadding: 12,
                  leading: CircleAvatar(
                    backgroundColor: colors.surfaceContainer,
                    child: Icon(Icons.map_outlined, color: colors.primary),
                  ),
                  title: Text(
                    context.l10n.chooseOnMap,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(context.l10n.moveMapToChoose),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final selected = await Navigator.of(context)
                        .push<ChetiwaLocation>(
                          MaterialPageRoute<ChetiwaLocation>(
                            builder: (_) => MapLocationPickerScreen(
                              repository: widget.repository,
                            ),
                          ),
                        );
                    if (selected != null && mounted) await _select(selected);
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildLocationList(context, controller)),
        ],
      ),
    );
  }

  Widget _buildLocationList(BuildContext context, ScrollController controller) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchError case final error?) {
      return _PickerMessage(
        icon: Icons.wifi_off_rounded,
        message: error,
        actionLabel: context.l10n.retry,
        onAction: () => _search(_searchController.text.trim()),
      );
    }
    if (_isQuerying && _results.isEmpty) {
      return _PickerMessage(
        icon: Icons.location_off_outlined,
        message: context.l10n.noCity,
      );
    }

    final locations = _isQuerying
        ? _results
        : LocationCatalog.locations.take(10).toList(growable: false);
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        if (!_isQuerying && _recent.isNotEmpty) ...[
          _PickerSectionTitle(context.l10n.recent),
          for (final location in _recent)
            Dismissible(
              key: ValueKey(
                'remove-recent-${location.coordinates.latitude}-${location.coordinates.longitude}',
              ),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                color: ChetiwaColors.error,
                child: const Icon(Icons.delete_outline_rounded),
              ),
              onDismissed: (_) async {
                await widget.repository.removeRecentLocation(location);
                if (mounted) {
                  setState(
                    () => _recent = _recent
                        .where(
                          (item) => item.coordinates != location.coordinates,
                        )
                        .toList(growable: false),
                  );
                }
              },
              child: _locationTile(context, location),
            ),
          const Divider(height: 20),
        ],
        _PickerSectionTitle(
          _isQuerying ? context.l10n.results : context.l10n.popularCities,
        ),
        for (final location in locations) _locationTile(context, location),
        if (!_isQuerying)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
            child: Text(
              context.l10n.searchWorldwideHelp,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _locationTile(BuildContext context, ChetiwaLocation location) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      minVerticalPadding: 12,
      leading: CircleAvatar(
        backgroundColor: colors.surfaceContainer,
        child: Icon(Icons.location_on_outlined, color: colors.primary),
      ),
      title: Text(
        location.city,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: location.details.isEmpty ? null : Text(location.details),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => _select(location),
    );
  }
}

final class _PickerSectionTitle extends StatelessWidget {
  const _PickerSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
    child: Text(
      label,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    ),
  );
}

final class _PickerMessage extends StatelessWidget {
  const _PickerMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 36,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel case final label?) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onAction, child: Text(label)),
          ],
        ],
      ),
    ),
  );
}

final class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: selected
            ? context.l10n.selectedNavigation(label)
            : context.l10n.selectNavigation(label),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(ChetiwaRadius.medium),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(ChetiwaRadius.medium),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 17,
                      color: selected
                          ? ChetiwaColors.accentPrimary
                          : colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          style: TextStyle(
                            color: selected
                                ? colors.onSurface
                                : colors.onSurfaceVariant,
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                AnimatedContainer(
                  key: selected
                      ? const Key('selected-navigation-indicator')
                      : null,
                  duration: ChetiwaMotion.accessible(
                    context,
                    ChetiwaMotion.fast,
                  ),
                  width: selected ? 28 : 0,
                  height: 3,
                  decoration: BoxDecoration(
                    color: ChetiwaColors.accentPrimary,
                    borderRadius: BorderRadius.circular(ChetiwaRadius.full),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
