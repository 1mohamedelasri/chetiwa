import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/chetiwa_tokens.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/l10n/chetiwa_localizations.dart';
import '../../../../core/time/weather_clock.dart';
import '../../../../core/widgets/weather_data_status.dart';
import '../../../forecast/domain/entities/forecast.dart';
import '../../../forecast/domain/services/forecast_snapshot_builder.dart';
import '../../../forecast/domain/services/rain_rate_scale.dart';
import '../../../monetization/application/usage_quota_controller.dart';
import '../../application/radar_bloc.dart';
import '../../data/cache/radar_tile_cache.dart';
import '../../domain/entities/radar_frame.dart';

final class RadarPane extends StatelessWidget {
  const RadarPane({required this.forecast, required this.snapshot, super.key});

  final Forecast forecast;
  final ForecastSnapshot snapshot;

  @override
  Widget build(BuildContext context) =>
      _RadarMap(forecast: forecast, snapshot: snapshot);
}

enum _RadarBaseMap { satellite, dark, light, voyager }

extension on _RadarBaseMap {
  IconData get icon => switch (this) {
    _RadarBaseMap.satellite => Icons.satellite_alt_outlined,
    _RadarBaseMap.dark => Icons.dark_mode_outlined,
    _RadarBaseMap.light => Icons.light_mode_outlined,
    _RadarBaseMap.voyager => Icons.map_outlined,
  };

  String get tileUrl => switch (this) {
    _RadarBaseMap.satellite when ApiConfig.arcGisApiKey.isNotEmpty =>
      'https://ibasemaps-api.arcgis.com/arcgis/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}?token=${ApiConfig.arcGisApiKey}',
    _RadarBaseMap.satellite =>
      'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    _RadarBaseMap.dark =>
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png',
    _RadarBaseMap.light =>
      'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png',
    _RadarBaseMap.voyager =>
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
  };

  bool get isSatellite => this == _RadarBaseMap.satellite;
}

final class _RadarMap extends StatefulWidget {
  const _RadarMap({required this.forecast, required this.snapshot});

  final Forecast forecast;
  final ForecastSnapshot snapshot;

  @override
  State<_RadarMap> createState() => _RadarMapState();
}

final class _RadarMapState extends State<_RadarMap> {
  static const _regionalZoom = 6.35;
  static const _cityZoom = 9.25;
  static const _minRadarZoom = 5.0;
  static const _maxRadarZoom = 10.0;
  static const _timelineHeight = 150.0;

  final MapController _mapController = MapController();
  final RadarTileCache _tileCache = RadarTileCache.shared;
  _RadarBaseMap _baseMap = _RadarBaseMap.satellite;
  double _radarOpacity = 0.96;
  bool _radarVisible = true;
  bool _readableRadarPalette = true;
  bool _showWeakRadarEchoes = false;
  LatLng? _lastCenter;

  @override
  void initState() {
    super.initState();
    _tileCache.beginSession();
  }

  static const _neutralRadarFilter = ColorFilter.mode(
    Color(0xFF5E6663),
    BlendMode.srcIn,
  );
  static const _contextRadarFilter = ColorFilter.mode(
    Color(0xFFD6DBD7),
    BlendMode.srcIn,
  );

  // RainViewer Universal Blue already reserves yellow/orange/red for stronger
  // reflectivity. Boost those genuine cells while suppressing blue/cyan noise.
  static const _warmRadarFilter = ColorFilter.matrix(<double>[
    1.25,
    0,
    0,
    0,
    10,
    0,
    1.15,
    0,
    0,
    0,
    0,
    0,
    0.85,
    0,
    0,
    2.3,
    -0.75,
    -0.5,
    0.5,
    -330,
  ]);

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<RadarBloc, RadarState>(
    builder: (context, state) {
      if (state is RadarFailure) {
        return WeatherDataUnavailableView(
          issue: state.issue,
          domainLabel: 'RainViewer',
          onRetry: () => context.read<RadarBloc>().add(const RadarRequested()),
        );
      }
      if (state is! RadarReady) {
        return WeatherDataLoadingView(label: context.l10n.loadingRadar);
      }

      final frame = state.selectedFrame;
      final center = LatLng(
        state.coordinates.latitude,
        state.coordinates.longitude,
      );
      if (_lastCenter != null && _lastCenter != center) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _mapController.move(center, _regionalZoom);
        });
      }
      _lastCenter = center;
      final quota = context.watch<UsageQuotaController?>();
      return ClipRRect(
        borderRadius: BorderRadius.circular(ChetiwaRadius.large),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (frame.tileUrlTemplate case final tileUrl?) ...[
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: _regionalZoom,
                  minZoom: _minRadarZoom,
                  maxZoom: _maxRadarZoom,
                  onPositionChanged: (camera, _) {
                    unawaited(
                      _tileCache.prefetchNextFrames(
                        camera: camera,
                        frameTemplates: state.frames
                            .skip(state.selectedIndex + 1)
                            .map((item) => item.tileUrlTemplate)
                            .whereType<String>(),
                      ),
                    );
                  },
                  backgroundColor: Colors.transparent,
                  interactionOptions: const InteractionOptions(
                    // Keep the useful navigation gestures explicit and avoid
                    // accidental map rotation on a compact radar surface.
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  TileLayer(
                    key: ValueKey(_baseMap),
                    urlTemplate: _baseMap.tileUrl,
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'com.chetiwa.chetiwa',
                    maxNativeZoom: 20,
                    maxZoom: 20,
                  ),
                  if (_radarVisible)
                    TileLayer(
                      // Keep one TileLayer alive across frames. flutter_map
                      // detects the URL change and reloads its images while
                      // retaining the previous tiles until the next ones are
                      // ready; recreating the layer here made playback look
                      // frozen on physical devices with normal network lag.
                      urlTemplate: tileUrl,
                      userAgentPackageName: 'com.chetiwa.chetiwa',
                      maxNativeZoom: 7,
                      maxZoom: _maxRadarZoom,
                      panBuffer: 1,
                      keepBuffer: 1,
                      tileProvider: _tileCache.tileProvider,
                      tileDisplay: const TileDisplay.fadeIn(
                        duration: Duration(milliseconds: 140),
                        reloadStartOpacity: 0.25,
                      ),
                      tileBuilder: (context, tileWidget, tile) =>
                          _buildRadarTile(tileWidget),
                    ),
                  if (_baseMap.isSatellite)
                    TileLayer(
                      urlTemplate:
                          'https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
                      userAgentPackageName: 'com.chetiwa.chetiwa',
                      maxNativeZoom: 20,
                      maxZoom: 20,
                    ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: center,
                        width: 52,
                        height: 52,
                        child: _UserLocationMarker(
                          locationName: widget.forecast.locationName,
                          onDoubleTap: () =>
                              _mapController.move(center, _cityZoom),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ] else ...[
              const ColoredBox(color: Color(0xFF162B32)),
              SvgPicture.asset(
                'assets/images/paris_radar_roads.svg',
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  ChetiwaColors.surfaceSecondary.withValues(alpha: 0.72),
                  BlendMode.srcIn,
                ),
              ),
              RadarIntensityOverlay(
                progress: frame.progress,
                rainRate:
                    widget.forecast.rainPointAt(frame.time)?.rateMmPerHour ?? 0,
              ),
            ],
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: Row(
                children: [
                  Expanded(
                    child: _CompactRadarStatus(
                      forecast: widget.forecast,
                      snapshot: widget.snapshot,
                      selectedInstant: frame.time,
                      isLatestObservation: state.isAtLatestObservation,
                      isNowcast: frame.isNowcast,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _LayersButton(selectedMap: _baseMap, onPressed: _showLayers),
                ],
              ),
            ),
            if (quota != null)
              Positioned(
                right: 16,
                top: 68,
                child: _RadarQuotaBadge(snapshot: quota.radarSessions),
              ),
            if (state.health.issue != null ||
                state.health.usesCache ||
                state.health.isRefreshing)
              Positioned(
                left: 16,
                right: 16,
                top: 68,
                child: WeatherDataStatusBanner(
                  key: const Key('radar-data-status'),
                  health: state.health,
                  domainLabel: 'RainViewer',
                  nowUtc: widget.snapshot.nowUtc,
                  dataUpdatedAt:
                      state.frames[state.currentObservationIndex].time,
                ),
              ),
            if (frame.tileUrlTemplate == null)
              Center(
                child: _UserLocationMarker(
                  locationName: widget.forecast.locationName,
                  onDoubleTap: () {},
                ),
              ),
            if (frame.tileUrlTemplate != null)
              Positioned(
                right: 10,
                bottom: _timelineHeight + 12,
                child: _RecenterButton(
                  locationName: widget.forecast.locationName,
                  onPressed: () => _mapController.move(center, _regionalZoom),
                ),
              ),
            Positioned(
              left: 8,
              bottom: _timelineHeight + 12,
              child: _RadarLegend(
                radarVisible: _radarVisible,
                readablePalette: _readableRadarPalette,
                showWeakEchoes: _showWeakRadarEchoes,
                providerName: frame.providerName,
              ),
            ),
            Positioned(
              left: 8,
              bottom: _timelineHeight,
              child: _MapAttribution(baseMap: _baseMap),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: RadarTimeline(
                state: state,
                forecast: widget.forecast,
                snapshot: widget.snapshot,
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _buildRadarTile(Widget tileWidget) => _readableRadarPalette
      ? Stack(
          key: const Key('readable-radar-tile'),
          fit: StackFit.expand,
          children: [
            // Keep the original tile alpha for the radar footprint. This gives
            // every cell a soft, light-grey perimeter instead of painting all
            // weak echoes as blue rain.
            Opacity(
              opacity: _radarOpacity * (_showWeakRadarEchoes ? 0.52 : 0.36),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2),
                child: ColorFiltered(
                  colorFilter: _contextRadarFilter,
                  child: tileWidget,
                ),
              ),
            ),
            // A darker inner footprint preserves the shape and movement of a
            // cell. The source alpha naturally keeps uncertain echoes faint.
            Opacity(
              opacity: _radarOpacity * (_showWeakRadarEchoes ? 0.62 : 0.48),
              child: ColorFiltered(
                colorFilter: _neutralRadarFilter,
                child: tileWidget,
              ),
            ),
            // Only stronger reflectivity reaches this warm core. It sits above
            // the two grey context layers: orange, red, then dark red.
            Opacity(
              opacity: _radarOpacity,
              child: ColorFiltered(
                colorFilter: _warmRadarFilter,
                child: tileWidget,
              ),
            ),
          ],
        )
      : Opacity(opacity: _radarOpacity, child: tileWidget);

  Future<void> _showLayers() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outline,
                      borderRadius: BorderRadius.circular(ChetiwaRadius.full),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  context.l10n.mapLayers,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  childAspectRatio: 2.15,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: [
                    for (final map in _RadarBaseMap.values)
                      _MapStyleOption(
                        map: map,
                        selected: _baseMap == map,
                        onTap: () {
                          setState(() => _baseMap = map);
                          setSheetState(() {});
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.precipitationRadar),
                  subtitle: Text(context.l10n.showRadarEchoes),
                  value: _radarVisible,
                  onChanged: (value) {
                    setState(() => _radarVisible = value);
                    setSheetState(() {});
                  },
                ),
                SwitchListTile.adaptive(
                  key: const Key('readable-radar-palette-toggle'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.noiseReduction),
                  subtitle: Text(
                    context.l10n.isFrench
                        ? 'Halo gris clair, cœur gris foncé, puis orange et rouge pour les signaux forts'
                        : 'Light-grey halo, dark-grey core, then orange and red for strong signals',
                  ),
                  value: _readableRadarPalette,
                  onChanged: _radarVisible
                      ? (value) {
                          setState(() => _readableRadarPalette = value);
                          setSheetState(() {});
                        }
                      : null,
                ),
                SwitchListTile.adaptive(
                  key: const Key('weak-radar-echoes-toggle'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.weakEchoes),
                  subtitle: Text(
                    context.l10n.isFrench
                        ? 'Peuvent contenir du bruit radar ou de la pluie qui n’atteint pas le sol'
                        : 'May contain radar noise or rain that does not reach the ground',
                  ),
                  value: _showWeakRadarEchoes,
                  onChanged: _radarVisible && _readableRadarPalette
                      ? (value) {
                          setState(() => _showWeakRadarEchoes = value);
                          setSheetState(() {});
                        }
                      : null,
                ),
                Row(
                  children: [
                    Text(context.l10n.opacity),
                    Expanded(
                      child: Slider(
                        value: _radarOpacity,
                        min: 0.25,
                        max: 1,
                        divisions: 3,
                        label: '${(_radarOpacity * 100).round()} %',
                        onChanged: _radarVisible
                            ? (value) {
                                setState(() => _radarOpacity = value);
                                setSheetState(() {});
                              }
                            : null,
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text('${(_radarOpacity * 100).round()} %'),
                    ),
                  ],
                ),
                Text(
                  context.l10n.isFrench
                      ? 'Gris : écho faible ou incertain, pas une pluie confirmée. Orange/rouge : signal radar plus intense. Le radar ne représente pas les nuages.'
                      : 'Grey: weak or uncertain echo, not confirmed rain. Orange/red: stronger radar signal. Radar does not show clouds.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
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

final class _MapAttribution extends StatelessWidget {
  const _MapAttribution({required this.baseMap});

  final _RadarBaseMap baseMap;

  @override
  Widget build(BuildContext context) => Material(
    color: ChetiwaColors.backgroundPrimary.withValues(alpha: 0.78),
    borderRadius: BorderRadius.circular(ChetiwaRadius.small),
    child: InkWell(
      onTap: () => launchUrl(
        Uri.parse(
          baseMap.isSatellite
              ? 'https://www.esri.com/en-us/legal/terms/full-master-agreement'
              : 'https://carto.com/legal/terms/',
        ),
      ),
      borderRadius: BorderRadius.circular(ChetiwaRadius.small),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(
          baseMap.isSatellite
              ? '© Esri, Maxar, Earthstar · Radar RainViewer'
              : '© OpenStreetMap © CARTO · Radar RainViewer',
          style: const TextStyle(
            color: ChetiwaColors.textSecondary,
            fontSize: 8,
          ),
        ),
      ),
    ),
  );
}

final class _LayersButton extends StatelessWidget {
  const _LayersButton({required this.selectedMap, required this.onPressed});

  final _RadarBaseMap selectedMap;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Couches radar',
    child: Material(
      key: const Key('radar-layers-button'),
      color: ChetiwaColors.backgroundPrimary.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(ChetiwaRadius.medium),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(ChetiwaRadius.medium),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ChetiwaRadius.medium),
            border: Border.all(color: ChetiwaColors.borderDefault),
          ),
          alignment: Alignment.center,
          child: Badge(
            backgroundColor: ChetiwaColors.accentPrimary,
            smallSize: 7,
            child: Icon(
              selectedMap.icon,
              size: 19,
              color: ChetiwaColors.textPrimary,
            ),
          ),
        ),
      ),
    ),
  );
}

final class _CompactRadarStatus extends StatelessWidget {
  const _CompactRadarStatus({
    required this.forecast,
    required this.selectedInstant,
    required this.isLatestObservation,
    required this.isNowcast,
    required this.snapshot,
  });

  final Forecast forecast;
  final DateTime selectedInstant;
  final bool isLatestObservation;
  final bool isNowcast;
  final ForecastSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final rain = isLatestObservation
        ? snapshot.currentRain.rateMmPerHour
        : forecast.rainPointAt(selectedInstant)?.rateMmPerHour ?? 0;
    final frameState = isNowcast
        ? (context.l10n.isFrench ? 'prévision' : 'forecast')
        : (context.l10n.isFrench ? 'observation' : 'observation');
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: ChetiwaColors.backgroundPrimary.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(ChetiwaRadius.medium),
        border: Border.all(color: ChetiwaColors.borderDefault),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: ChetiwaColors.textPrimary),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.water_drop_outlined,
                size: 15,
                color: ChetiwaColors.accentPrimary,
              ),
              const SizedBox(width: 5),
              Text(
                '${rain.toStringAsFixed(rain < 0.05 ? 0 : 1)} mm/h',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const _StatusDivider(),
              Text(
                '${WeatherTimeZone.hourMinute(selectedInstant, forecast.timeZone)} · $frameState',
                style: const TextStyle(
                  color: ChetiwaColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _StatusDivider extends StatelessWidget {
  const _StatusDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 14,
    margin: const EdgeInsets.symmetric(horizontal: 9),
    color: ChetiwaColors.borderDefault,
  );
}

final class _MapStyleOption extends StatelessWidget {
  const _MapStyleOption({
    required this.map,
    required this.selected,
    required this.onTap,
  });

  final _RadarBaseMap map;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colors.primary.withValues(alpha: 0.14)
          : colors.surfaceContainer,
      borderRadius: BorderRadius.circular(ChetiwaRadius.medium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ChetiwaRadius.medium),
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ChetiwaRadius.medium),
            border: Border.all(
              color: selected ? colors.primary : colors.outline,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                map.icon,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.mapStyle(map.name),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _RadarLegend extends StatelessWidget {
  const _RadarLegend({
    required this.radarVisible,
    required this.readablePalette,
    required this.showWeakEchoes,
    required this.providerName,
  });

  final bool radarVisible;
  final bool readablePalette;
  final bool showWeakEchoes;
  final String providerName;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    duration: ChetiwaMotion.accessible(context, ChetiwaMotion.fast),
    opacity: radarVisible ? 1 : 0.5,
    child: Container(
      width: 138,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: ChetiwaColors.backgroundPrimary.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(ChetiwaRadius.small),
        border: Border.all(color: ChetiwaColors.borderDefault),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: ChetiwaColors.textPrimary),
        child: IconTheme(
          data: const IconThemeData(color: ChetiwaColors.textPrimary),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      radarVisible
                          ? '${context.l10n.isFrench ? 'ÉCHOS RADAR' : 'RADAR ECHOES'} · ${providerName.toUpperCase()}'
                          : (context.l10n.isFrench
                                ? 'RADAR MASQUÉ'
                                : 'RADAR HIDDEN'),
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: context.l10n.isFrench
                        ? 'Le radar ne montre pas les nuages. Gris clair et gris foncé indiquent des échos faibles ou incertains; orange et rouge indiquent un signal plus intense.'
                        : 'Radar does not show clouds. Light and dark grey indicate weak or uncertain echoes; orange and red indicate a stronger signal.',
                    child: const Icon(Icons.info_outline_rounded, size: 11),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                height: 7,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(ChetiwaRadius.full),
                  gradient: LinearGradient(
                    colors: readablePalette
                        ? const [
                            Color(0xFFD6DBD7),
                            Color(0xFF5E6663),
                            Color(0xFFFF7300),
                            Color(0xFFFF3B30),
                            Color(0xFF8E1010),
                          ]
                        : const [
                            Color(0xFF9DEBFF),
                            Color(0xFF009FE3),
                            Color(0xFFFFE000),
                            Color(0xFFFF8A00),
                            Color(0xFFFF3B30),
                          ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    readablePalette
                        ? (context.l10n.isFrench ? 'Écho faible' : 'Weak echo')
                        : (context.l10n.isFrench ? 'Faible' : 'Light'),
                    style: const TextStyle(fontSize: 7),
                  ),
                  Text(
                    context.l10n.isFrench ? 'Forte' : 'Heavy',
                    style: const TextStyle(fontSize: 7),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _RecenterButton extends StatelessWidget {
  const _RecenterButton({required this.locationName, required this.onPressed});

  final String locationName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.recenterOnSelectedLocation(locationName);
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: ChetiwaColors.backgroundPrimary.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(ChetiwaRadius.small),
          child: InkWell(
            key: const Key('radar-recenter-selected-location'),
            onTap: onPressed,
            borderRadius: BorderRadius.circular(ChetiwaRadius.small),
            child: const SizedBox(
              width: 42,
              height: 42,
              child: Icon(
                // This is intentionally not `my_location`: the action follows
                // the place selected in Chetiwa, never the phone's live GPS.
                Icons.center_focus_strong_rounded,
                size: 19,
                color: ChetiwaColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _UserLocationMarker extends StatelessWidget {
  const _UserLocationMarker({
    required this.locationName,
    required this.onDoubleTap,
  });

  final String locationName;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 52,
    height: 52,
    child: Semantics(
      label: context.l10n.isFrench
          ? '${locationName.split(',').first}, touchez deux fois pour zoomer'
          : '${locationName.split(',').first}, double-tap to zoom',
      button: true,
      child: GestureDetector(
        key: const Key('radar-city-pin'),
        behavior: HitTestBehavior.opaque,
        onDoubleTap: onDoubleTap,
        child: Center(
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: ChetiwaColors.accentPrimary,
              shape: BoxShape.circle,
              border: Border.all(color: ChetiwaColors.textPrimary, width: 2),
              boxShadow: ChetiwaElevation.floating,
            ),
            child: const Icon(
              Icons.navigation_rounded,
              size: 14,
              color: ChetiwaColors.backgroundPrimary,
            ),
          ),
        ),
      ),
    ),
  );
}

final class RadarTimeline extends StatelessWidget {
  const RadarTimeline({
    required this.state,
    required this.forecast,
    required this.snapshot,
    super.key,
  });

  final RadarReady state;
  final Forecast forecast;
  final ForecastSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final timelineColors = _RadarTimelineColors.of(context);
    final nowInstant = snapshot.nowUtc;
    final status = state.selectedFrame.isNowcast
        ? (context.l10n.isFrench ? 'prévision' : 'forecast')
        : state.isAtLatestObservation
        ? (context.l10n.isFrench
              ? 'dernière observation'
              : 'latest observation')
        : (context.l10n.isFrench ? 'observation' : 'observation');
    final statusColor = state.selectedFrame.isNowcast
        ? ChetiwaColors.warning
        : state.isAtLatestObservation
        ? ChetiwaColors.accentPrimary
        : timelineColors.muted;
    return Semantics(
      key: const Key('radar-local-time'),
      label:
          '${context.l10n.isFrench ? 'Chronologie radar' : 'Radar timeline'} · ${forecast.timeZone} · '
          '${WeatherTimeZone.hourMinute(state.selectedFrame.time, forecast.timeZone)}',
      child: Container(
        height: 150,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              timelineColors.surface.withValues(alpha: 0.94),
              timelineColors.surface,
            ],
          ),
          border: Border(top: BorderSide(color: timelineColors.outline)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Material(
                  color: state.isPlaying
                      ? ChetiwaColors.accentPrimary.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(ChetiwaRadius.full),
                  child: InkWell(
                    key: const Key('radar-playback-button'),
                    onTap: () => context.read<RadarBloc>().add(
                      const RadarPlaybackToggled(),
                    ),
                    borderRadius: BorderRadius.circular(ChetiwaRadius.full),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: ChetiwaMotion.accessible(
                              context,
                              ChetiwaMotion.fast,
                            ),
                            child: Icon(
                              state.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              key: ValueKey(state.isPlaying),
                              size: 20,
                              color: state.isPlaying
                                  ? ChetiwaColors.accentPrimary
                                  : timelineColors.foreground,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            state.isPlaying
                                ? context.l10n.pause
                                : context.l10n.play,
                            style: TextStyle(
                              color: timelineColors.foreground,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!state.isAtLatestObservation) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    key: const Key('radar-now-button'),
                    tooltip: context.l10n.returnLatestRadar,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => context.read<RadarBloc>().add(
                      const RadarNowRequested(),
                    ),
                    icon: const Icon(Icons.update_rounded, size: 18),
                  ),
                ],
                IconButton(
                  key: const Key('radar-reset-button'),
                  tooltip: context.l10n.restartPlayback,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () => context.read<RadarBloc>().add(
                    const RadarPlaybackRestarted(),
                  ),
                  icon: const Icon(Icons.replay_rounded, size: 18),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${WeatherTimeZone.hourMinute(state.selectedFrame.time, forecast.timeZone)} · $status',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => GestureDetector(
                  key: const Key('radar-time-ruler'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => _selectFrame(
                    context,
                    details.localPosition.dx,
                    constraints.maxWidth,
                  ),
                  onHorizontalDragStart: (details) => _selectFrame(
                    context,
                    details.localPosition.dx,
                    constraints.maxWidth,
                  ),
                  onHorizontalDragUpdate: (details) => _selectFrame(
                    context,
                    details.localPosition.dx,
                    constraints.maxWidth,
                  ),
                  child: CustomPaint(
                    painter: _RadarTimeRulerPainter(
                      frames: state.frames,
                      selectedIndex: state.selectedIndex,
                      rainPoints: forecast.points,
                      timeZone: forecast.timeZone,
                      now: nowInstant,
                      colors: timelineColors,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectFrame(BuildContext context, double x, double width) {
    if (state.frames.length < 2 || width <= 0) return;
    final hasNowcast = state.hasNowcast;
    final startIndex = hasNowcast ? state.currentObservationIndex : 0;
    final endIndex = hasNowcast
        ? state.frames.length - 1
        : state.currentObservationIndex;
    final start = hasNowcast
        ? snapshot.nowUtc.millisecondsSinceEpoch
        : state.frames[startIndex].time.millisecondsSinceEpoch;
    final end = hasNowcast
        ? math.max(
            start + const Duration(minutes: 30).inMilliseconds,
            state.frames[endIndex].time.millisecondsSinceEpoch,
          )
        : state.frames[endIndex].time.millisecondsSinceEpoch;
    final selectedTime =
        start + ((end - start) * (x / width).clamp(0, 1)).toDouble();
    var index = startIndex;
    var nearestDistance = double.infinity;
    for (var candidate = startIndex; candidate <= endIndex; candidate++) {
      final effectiveTime = hasNowcast
          ? math.max(start, state.frames[candidate].time.millisecondsSinceEpoch)
          : state.frames[candidate].time.millisecondsSinceEpoch;
      final distance = (effectiveTime - selectedTime).abs().toDouble();
      if (distance < nearestDistance) {
        nearestDistance = distance;
        index = candidate;
      }
    }
    context.read<RadarBloc>().add(RadarFrameSelected(index));
  }
}

final class _RadarTimeRulerPainter extends CustomPainter {
  const _RadarTimeRulerPainter({
    required this.frames,
    required this.selectedIndex,
    required this.rainPoints,
    required this.timeZone,
    required this.now,
    required this.colors,
  });

  final List<RadarFrame> frames;
  final int selectedIndex;
  final List<RainPoint> rainPoints;
  final String timeZone;
  final DateTime now;
  final _RadarTimelineColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (frames.isEmpty) return;
    const chartTop = 5.0;
    final trackY = size.height - 18;
    final currentObservationIndex = frames.lastIndexWhere(
      (frame) => frame.isObservation,
    );
    final observationIndex = currentObservationIndex < 0
        ? frames.length - 1
        : currentObservationIndex;
    final hasNowcast = frames.any((frame) => frame.isNowcast);
    final playbackStartIndex = hasNowcast ? observationIndex : 0;
    final playbackEndIndex = hasNowcast ? frames.length - 1 : observationIndex;
    final start = hasNowcast ? now : frames[playbackStartIndex].time;
    final lastFrameTime = frames[playbackEndIndex].time;
    final end = hasNowcast && !lastFrameTime.isAfter(start)
        ? start.add(const Duration(minutes: 30))
        : lastFrameTime;
    final durationMs = math
        .max(1, end.millisecondsSinceEpoch - start.millisecondsSinceEpoch)
        .toDouble();

    double xForTime(DateTime time) =>
        (size.width *
                (time.millisecondsSinceEpoch - start.millisecondsSinceEpoch) /
                durationMs)
            .toDouble();

    _paintRainProfile(canvas, size, start, end, xForTime, chartTop, trackY);

    final profileLabel = TextPainter(
      text: TextSpan(
        text: 'ESTIMATION AU POINT',
        style: TextStyle(
          color: colors.muted,
          fontSize: 7,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    profileLabel.paint(canvas, Offset(0, chartTop));

    final track = Paint()
      ..color = colors.outline
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset.zero.translate(0, trackY),
      Offset(size.width, trackY),
      track,
    );

    final minorTick = Paint()
      ..color = colors.muted.withValues(alpha: 0.65)
      ..strokeWidth = 1;
    for (var index = playbackStartIndex; index <= playbackEndIndex; index++) {
      final frame = frames[index];
      final effectiveTime = frame.time.isBefore(start) ? start : frame.time;
      final x = xForTime(effectiveTime).clamp(0, size.width).toDouble();
      canvas.drawLine(Offset(x, trackY - 3), Offset(x, trackY + 3), minorTick);
    }

    _paintTimeLabels(
      canvas,
      size,
      start,
      end,
      xForTime,
      trackY,
      historical: !hasNowcast,
    );

    final nowX = hasNowcast ? 0.0 : size.width;
    final nowPaint = Paint()
      ..color = ChetiwaColors.accentPrimary.withValues(alpha: 0.85)
      ..strokeWidth = 1;
    for (var y = chartTop; y < trackY + 5; y += 5) {
      canvas.drawLine(
        Offset(nowX, y),
        Offset(nowX, math.min(y + 2.5, trackY + 5)),
        nowPaint,
      );
    }
    final nowLabel = TextPainter(
      text: TextSpan(
        text: 'MAINT.',
        style: TextStyle(
          color: ChetiwaColors.accentPrimary,
          fontSize: 7,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    nowLabel.paint(
      canvas,
      Offset(
        (nowX - (hasNowcast ? 0 : nowLabel.width))
            .clamp(0, size.width - nowLabel.width)
            .toDouble(),
        chartTop,
      ),
    );

    final selectedTime =
        hasNowcast && frames[selectedIndex].time.isBefore(start)
        ? start
        : frames[selectedIndex].time;
    final cursorX = xForTime(selectedTime).clamp(0, size.width).toDouble();
    final cursor = Paint()
      ..color = ChetiwaColors.error
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cursorX, chartTop),
      Offset(cursorX, trackY + 5),
      cursor,
    );
    canvas.drawCircle(Offset(cursorX, chartTop), 3.5, cursor);
  }

  DateTime _wallTime(DateTime instant) =>
      WeatherTimeZone.wallTime(instant, timeZone);

  void _paintRainProfile(
    Canvas canvas,
    Size size,
    DateTime start,
    DateTime end,
    double Function(DateTime) xForTime,
    double chartTop,
    double trackY,
  ) {
    final points = rainPoints
        .where(
          (point) => !point.time.isBefore(start) && !point.time.isAfter(end),
        )
        .toList(growable: false);
    if (points.length < 2 ||
        !points.any((point) => RainRateScale.isRain(point.rateMmPerHour))) {
      return;
    }

    final chartHeight = math.max(12.0, trackY - chartTop - 12);
    final area = ui.Path()..moveTo(xForTime(points.first.time), trackY);
    for (final point in points) {
      area.lineTo(
        xForTime(point.time).clamp(0, size.width).toDouble(),
        trackY - RainRateScale.normalized(point.rateMmPerHour) * chartHeight,
      );
    }
    area
      ..lineTo(xForTime(points.last.time), trackY)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, chartTop), Offset(0, trackY), [
          ChetiwaColors.rainModerate.withValues(alpha: 0.9),
          ChetiwaColors.rainLight.withValues(alpha: 0.3),
        ]),
    );
  }

  void _paintTimeLabels(
    Canvas canvas,
    Size size,
    DateTime start,
    DateTime end,
    double Function(DateTime) xForTime,
    double trackY, {
    required bool historical,
  }) {
    if (historical) {
      final durationMinutes = math.max(1, end.difference(start).inMinutes);
      final durationLabel = durationMinutes >= 60
          ? '−${(durationMinutes / 60).ceil()} H'
          : '−$durationMinutes MIN';
      final startLabel = TextPainter(
        text: TextSpan(
          text: durationLabel,
          style: TextStyle(color: colors.muted, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      startLabel.paint(canvas, Offset(0, trackY + 6));

      final endLabel = TextPainter(
        text: TextSpan(
          text: 'DERNIÈRE',
          style: TextStyle(color: colors.muted, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      endLabel.paint(canvas, Offset(size.width - endLabel.width, trackY + 6));
      return;
    }

    final startLabel = TextPainter(
      text: TextSpan(
        text: WeatherTimeZone.hourMinute(start, timeZone),
        style: TextStyle(color: colors.muted, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    startLabel.paint(canvas, Offset(0, trackY + 6));

    final wallStart = _wallTime(start);
    var wallTick = DateTime.utc(
      wallStart.year,
      wallStart.month,
      wallStart.day,
      wallStart.hour + (wallStart.minute == 0 ? 0 : 1),
    );
    final labelStyle = TextStyle(color: colors.muted, fontSize: 9);
    while (true) {
      final tickInstant = WeatherTimeZone.instantFromLocal(wallTick, timeZone);
      if (tickInstant.isAfter(end)) break;
      final tooCloseToStart =
          tickInstant.difference(start).inMinutes.abs() < 12;
      final tooCloseToEnd = end.difference(tickInstant).inMinutes.abs() < 12;
      if (!tickInstant.isBefore(start) && !tooCloseToStart && !tooCloseToEnd) {
        final x = xForTime(tickInstant).clamp(0, size.width).toDouble();
        canvas.drawLine(
          Offset(x, trackY - 5),
          Offset(x, trackY + 5),
          Paint()
            ..color = colors.muted
            ..strokeWidth = 1.2,
        );
        final label = TextPainter(
          text: TextSpan(
            text: WeatherTimeZone.formatWallHourMinute(wallTick),
            style: labelStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(
          canvas,
          Offset(
            (x - label.width / 2).clamp(0, size.width - label.width).toDouble(),
            trackY + 6,
          ),
        );
      }
      wallTick = wallTick.add(const Duration(hours: 1));
    }

    final endLabel = TextPainter(
      text: TextSpan(
        text: WeatherTimeZone.hourMinute(end, timeZone),
        style: TextStyle(color: colors.muted, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    endLabel.paint(canvas, Offset(size.width - endLabel.width, trackY + 6));
  }

  @override
  bool shouldRepaint(covariant _RadarTimeRulerPainter oldDelegate) =>
      frames != oldDelegate.frames ||
      selectedIndex != oldDelegate.selectedIndex ||
      rainPoints != oldDelegate.rainPoints ||
      timeZone != oldDelegate.timeZone ||
      now != oldDelegate.now ||
      colors != oldDelegate.colors;
}

final class _RadarTimelineColors {
  const _RadarTimelineColors({
    required this.surface,
    required this.foreground,
    required this.muted,
    required this.outline,
  });

  factory _RadarTimelineColors.of(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _RadarTimelineColors(
      surface: colors.surface,
      foreground: colors.onSurface,
      muted: colors.onSurfaceVariant,
      outline: colors.outline,
    );
  }

  final Color surface;
  final Color foreground;
  final Color muted;
  final Color outline;
}

final class _RadarQuotaBadge extends StatelessWidget {
  const _RadarQuotaBadge({required this.snapshot});

  final UsageQuotaSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          'Radar ${snapshot.used}/${snapshot.limit}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

/// Provider-independent fallback used when live radar tiles are unavailable.
///
/// Keeping this layer independent from the map and the radar BLoC makes the
/// five reference rain scenarios deterministic and directly testable.
final class RadarIntensityOverlay extends StatelessWidget {
  const RadarIntensityOverlay({
    required this.progress,
    required this.rainRate,
    super.key,
  });

  final double progress;
  final double rainRate;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      key: ValueKey(
        'fallback-radar-${RainRateScale.intensityFor(rainRate).name}',
      ),
      painter: _RadarOverlayPainter(progress: progress, rainRate: rainRate),
    ),
  );
}

final class _RadarOverlayPainter extends CustomPainter {
  const _RadarOverlayPainter({required this.progress, required this.rainRate});

  final double progress;
  final double rainRate;

  @override
  void paint(Canvas canvas, Size size) {
    final intensity = RainRateScale.intensityFor(rainRate);
    if (intensity == RainIntensity.none) return;
    final strength = RainRateScale.normalized(rainRate);
    final frontX = size.width * (-0.18 + progress * 0.72);
    canvas.save();
    canvas.translate(frontX, size.height * 0.12);
    canvas.rotate(-0.22);

    final soft = Paint()
      ..color = const Color(
        0xFFD6DBD7,
      ).withValues(alpha: 0.14 + strength * 0.26)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    final neutral = Paint()
      ..color = const Color(0xFF5E6663).withValues(alpha: 0.34 + strength * 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    final moderate = Paint()
      ..color = const Color(0xFFFF7300).withValues(alpha: 0.72)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    final heavy = Paint()
      ..color = const Color(0xFFFF3B30).withValues(alpha: 0.76)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    final heavyCore = Paint()
      ..color = const Color(0xFF8E1010).withValues(alpha: 0.84)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    for (var index = 0; index < 6; index++) {
      final y = index * size.height * 0.11;
      final wobble = math.sin(index * 1.7) * 22;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(wobble, y),
          width: size.width * 0.52,
          height: size.height * 0.16,
        ),
        soft,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(wobble - 5, y + 5),
          width: size.width * 0.38,
          height: size.height * 0.12,
        ),
        neutral,
      );
      if (intensity.index >= RainIntensity.moderate.index) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(wobble - 12, y + 8),
            width: size.width * 0.28,
            height: size.height * 0.09,
          ),
          moderate,
        );
      }
      if (intensity == RainIntensity.heavy && index.isEven) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(wobble - 28, y + 10),
            width: size.width * 0.1,
            height: size.height * 0.05,
          ),
          heavy,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(wobble - 31, y + 11),
            width: size.width * 0.055,
            height: size.height * 0.028,
          ),
          heavyCore,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RadarOverlayPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.rainRate != rainRate;
}
