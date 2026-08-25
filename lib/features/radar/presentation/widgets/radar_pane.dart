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
import '../../../../core/maps/open_free_map_layer.dart';
import '../../../../core/time/weather_clock.dart';
import '../../../../core/widgets/weather_data_status.dart';
import '../../../forecast/domain/entities/forecast.dart';
import '../../../forecast/domain/services/forecast_snapshot_builder.dart';
import '../../../forecast/domain/services/radar_nowcast_alignment.dart';
import '../../../forecast/domain/services/rain_rate_scale.dart';
import '../../../analytics/application/analytics_tracker.dart';
import '../../application/radar_bloc.dart';
import '../../data/cache/radar_tile_cache.dart';
import '../../domain/entities/radar_frame.dart';
import '../../domain/services/radar_frame_policy.dart';

final class RadarPane extends StatelessWidget {
  const RadarPane({
    required this.forecast,
    required this.snapshot,
    this.isActive = true,
    this.satelliteAvailable = false,
    super.key,
  });

  final Forecast forecast;
  final ForecastSnapshot snapshot;
  final bool isActive;
  final bool satelliteAvailable;

  @override
  Widget build(BuildContext context) => _RadarMap(
    forecast: forecast,
    snapshot: snapshot,
    isActive: isActive,
    satelliteAvailable: satelliteAvailable,
  );
}

enum _RadarBaseMap { standard, satellite }

extension on _RadarBaseMap {
  IconData get icon => switch (this) {
    _RadarBaseMap.standard => Icons.map_outlined,
    _RadarBaseMap.satellite => Icons.satellite_alt_outlined,
  };

  String get satelliteTileUrl => switch (this) {
    _RadarBaseMap.satellite =>
      'https://ibasemaps-api.arcgis.com/arcgis/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}?token=${ApiConfig.arcGisApiKey}',
    _RadarBaseMap.standard => throw StateError(
      'The standard basemap is vector-based and has no raster tile URL.',
    ),
  };

  bool get isSatellite => this == _RadarBaseMap.satellite;
}

final class _RadarMap extends StatefulWidget {
  const _RadarMap({
    required this.forecast,
    required this.snapshot,
    required this.isActive,
    required this.satelliteAvailable,
  });

  final Forecast forecast;
  final ForecastSnapshot snapshot;
  final bool isActive;
  final bool satelliteAvailable;

  @override
  State<_RadarMap> createState() => _RadarMapState();
}

final class _RadarMapState extends State<_RadarMap> {
  // Start close enough to answer "is it raining here?" while staying at the
  // provider's native radar resolution.
  static const _regionalZoom = 7.0;
  static const _cityZoom = 9.0;
  static const _minRadarZoom = 5.0;
  static const _maxNativeRadarZoom = 10;
  // LibreWXR is generated through z10. One extra display zoom keeps the layer
  // visible at the end of a pinch without requesting unsupported z11 tiles.
  static const _maxRadarZoom = 11.0;
  static const _timelineHeight = 150.0;

  final MapController _mapController = MapController();
  final RadarTileCache _tileCache = RadarTileCache.shared;
  final ValueNotifier<int> _zoomLevel = ValueNotifier<int>(
    _regionalZoom.round(),
  );
  late final RadarBloc _radarBloc;
  _RadarBaseMap _baseMap = _RadarBaseMap.standard;
  // Preserve geographic context and avoid making weak echoes look more severe
  // than they are. Users can still raise this from the layer sheet.
  double _radarOpacity = 0.78;
  bool _radarVisible = true;
  bool _mapReady = false;
  LatLng? _lastCenter;
  Timer? _prefetchDebounce;
  Timer? _dataRefreshTimer;
  Timer? _preparationRevealTimer;
  var _refreshFailureStreak = 0;
  var _viewportRequestGeneration = 0;
  var _radarViewportRevision = 0;
  var _reloadCurrentFrameAfterPan = false;
  var _radarTilesLoading = false;
  var _radarTilesUnavailable = false;
  var _userPausedPlayback = false;
  var _autoplayRequested = false;
  var _showTilePreparation = false;
  String? _lastReportedMetadataIssue;
  var _tileIssueReported = false;

  @override
  void initState() {
    super.initState();
    _radarBloc = context.read<RadarBloc>();
    _tileCache.beginSession();
    _tileCache.readyTileCount.addListener(_handleReadyRadarTile);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scheduleDataRefresh(_radarBloc.state);
        _maybeStartAutoplay();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _RadarMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.satelliteAvailable &&
        !widget.satelliteAvailable &&
        _baseMap.isSatellite) {
      _baseMap = _RadarBaseMap.standard;
    }
    if (!oldWidget.isActive && widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeStartAutoplay();
      });
    }
  }

  @override
  void dispose() {
    _prefetchDebounce?.cancel();
    _tileCache.cancelPrefetch();
    _tileCache.readyTileCount.removeListener(_handleReadyRadarTile);
    _dataRefreshTimer?.cancel();
    _preparationRevealTimer?.cancel();
    _radarBloc.add(const RadarPlaybackPaused());
    _mapController.dispose();
    _zoomLevel.dispose();
    super.dispose();
  }

  void _handleReadyRadarTile() {
    if (!mounted || _tileCache.readyTileCount.value == 0) return;
    _preparationRevealTimer?.cancel();
    if (_radarTilesLoading || _radarTilesUnavailable || _showTilePreparation) {
      setState(() {
        _radarTilesLoading = false;
        _radarTilesUnavailable = false;
        _showTilePreparation = false;
      });
    }
    _tileIssueReported = false;
    _maybeStartAutoplay();
  }

  void _reportRadarState(RadarState state) {
    final (issue, cachedDataVisible) = switch (state) {
      RadarReady(:final health) => (health.issue, true),
      RadarFailure(:final issue) => (issue, false),
      _ => (null, false),
    };
    if (issue == null) {
      _lastReportedMetadataIssue = null;
      return;
    }
    final signature = '${issue.name}:$cachedDataVisible';
    if (_lastReportedMetadataIssue == signature) return;
    _lastReportedMetadataIssue = signature;
    final analytics = context.read<AnalyticsTracker?>();
    if (analytics == null) return;
    unawaited(
      analytics.radarAvailabilityIssue(
        issue: issue.name,
        surface: 'metadata',
        cachedDataVisible: cachedDataVisible,
      ),
    );
  }

  void _reportTileIssue() {
    if (_tileIssueReported) return;
    _tileIssueReported = true;
    final analytics = context.read<AnalyticsTracker?>();
    if (analytics == null) return;
    unawaited(
      analytics.radarAvailabilityIssue(
        issue: 'tile_unavailable',
        surface: 'tiles',
        cachedDataVisible: _tileCache.readyTileCount.value > 0,
      ),
    );
  }

  void _revealPreparationIfStillNeeded() {
    _preparationRevealTimer?.cancel();
    if (_tileCache.readyTileCount.value > 0) return;
    // Warm disk-cache hits should appear without flashing a loading card. Only
    // reveal it when first paint is genuinely taking noticeable time.
    _preparationRevealTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || _tileCache.readyTileCount.value > 0) return;
      setState(() => _showTilePreparation = true);
    });
  }

  void _maybeStartAutoplay() {
    if (!mounted ||
        !widget.isActive ||
        _userPausedPlayback ||
        _autoplayRequested) {
      return;
    }
    final state = _radarBloc.state;
    if (state is! RadarReady || state.frames.length < 2 || state.isPlaying) {
      return;
    }
    final needsNetworkTile = state.selectedFrame.tileUrlTemplate != null;
    if (needsNetworkTile && _tileCache.readyTileCount.value == 0) return;
    _autoplayRequested = true;
    _radarBloc.add(const RadarPlaybackStarted());
  }

  void _handleUserPlaybackToggle() {
    final state = _radarBloc.state;
    if (state is! RadarReady) return;
    _userPausedPlayback = state.isPlaying;
    if (!state.isPlaying) _autoplayRequested = true;
  }

  void _handleUserPlaybackRestart() {
    _userPausedPlayback = false;
    _autoplayRequested = true;
  }

  void _scheduleDataRefresh(RadarState state) {
    _dataRefreshTimer?.cancel();
    if (state is RadarReady && state.isRefreshing) return;
    final retrySoon =
        state is RadarReady && (state.health.issue != null || state.isStale);
    final retryDelay = switch (_refreshFailureStreak) {
      0 => const Duration(minutes: 1),
      1 => const Duration(minutes: 2),
      2 => const Duration(minutes: 4),
      3 => const Duration(minutes: 8),
      _ => const Duration(minutes: 15),
    };
    if (retrySoon) {
      _refreshFailureStreak = math.min(_refreshFailureStreak + 1, 4);
    } else {
      _refreshFailureStreak = 0;
    }
    _dataRefreshTimer = Timer(
      retrySoon ? retryDelay : const Duration(minutes: 5),
      () {
        if (!mounted) return;
        _radarBloc.add(const RadarRefreshed());
      },
    );
  }

  @override
  Widget build(BuildContext context) => BlocListener<RadarBloc, RadarState>(
    listener: (_, state) {
      _reportRadarState(state);
      _scheduleDataRefresh(state);
      // Only provider/frame changes need speculative next-frame work. Keeping
      // this in the Bloc listener avoids a local loading setState cancelling
      // the current-frame request that triggered it.
      if (_mapReady &&
          state is RadarReady &&
          !_reloadCurrentFrameAfterPan &&
          !_radarTilesLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _schedulePrefetch(state, _mapController.camera);
          _maybeStartAutoplay();
        });
      } else if (state is RadarReady) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _maybeStartAutoplay();
        });
      }
    },
    child: BlocBuilder<RadarBloc, RadarState>(
      builder: (context, state) {
        if (state is RadarFailure) {
          _mapReady = false;
          return WeatherDataUnavailableView(
            issue: state.issue,
            // Provider names belong in legal attribution, not in a technical
            // error shown to end users.
            domainLabel: context.l10n.radar,
            onRetry: () =>
                context.read<RadarBloc>().add(const RadarRequested()),
          );
        }
        if (state is! RadarReady) {
          _mapReady = false;
          return const _RadarPreparingSurface();
        }

        final frame = state.selectedFrame;
        if (frame.tileUrlTemplate == null) _mapReady = false;
        final center = LatLng(
          state.coordinates.latitude,
          state.coordinates.longitude,
        );
        if (_mapReady && _lastCenter != null && _lastCenter != center) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _mapController.move(center, _regionalZoom);
          });
        }
        _lastCenter = center;
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
                    onMapReady: () {
                      _mapReady = true;
                      _revealPreparationIfStillNeeded();
                      // The current frame is the only first-paint priority.
                      // Retry it immediately while the hidden IndexedStack is
                      // already warming Radar behind the Graph screen.
                      _schedulePrefetch(
                        state,
                        _mapController.camera,
                        refreshCurrentFrame: true,
                        immediate: true,
                      );
                    },
                    onPositionChanged: (camera, hasGesture) {
                      final roundedZoom = camera.zoom.round();
                      if (_zoomLevel.value != roundedZoom) {
                        _zoomLevel.value = roundedZoom;
                      }
                      _schedulePrefetch(
                        state,
                        camera,
                        refreshCurrentFrame: hasGesture,
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
                    if (_baseMap == _RadarBaseMap.standard)
                      const OpenFreeMapLayer()
                    else
                      TileLayer(
                        key: ValueKey(_baseMap),
                        urlTemplate: _baseMap.satelliteTileUrl,
                        userAgentPackageName: 'com.chetiwa.chetiwa',
                        maxNativeZoom: 20,
                        maxZoom: 20,
                      ),
                    if (_radarVisible)
                      Opacity(
                        key: const Key('chetiwa-radar-precipitation-tile'),
                        opacity: _radarOpacity,
                        // One opacity layer for the complete radar is much
                        // cheaper than wrapping every individual map tile.
                        child: TileLayer(
                          key: const ValueKey('radar-tiles'),
                          // Keep one TileLayer alive across frames. flutter_map
                          // detects the URL change and retains previous tiles
                          // until replacements are decoded.
                          urlTemplate: tileUrl,
                          additionalOptions: {
                            'viewportRevision': '$_radarViewportRevision',
                          },
                          userAgentPackageName: 'com.chetiwa.chetiwa',
                          maxNativeZoom: _maxNativeRadarZoom,
                          maxZoom: 22,
                          // One retained ring is enough for short pans; centre
                          // prefetch below handles long moves.
                          panBuffer: 0,
                          keepBuffer: 1,
                          tileProvider: _tileCache.tileProvider,
                          tileDisplay: const TileDisplay.fadeIn(
                            duration: Duration(milliseconds: 120),
                            reloadStartOpacity: 1,
                          ),
                          evictErrorTileStrategy:
                              EvictErrorTileStrategy.notVisible,
                        ),
                      ),
                    if (_baseMap.isSatellite && widget.satelliteAvailable)
                      TileLayer(
                        urlTemplate:
                            'https://static-map-tiles-api.arcgis.com/arcgis/rest/services/static-basemap-tiles-service/v1/arcgis/imagery/labels/static/tile/{z}/{y}/{x}?token=${ApiConfig.arcGisApiKey}',
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
                      widget.forecast.rainPointAt(frame.time)?.rateMmPerHour ??
                      0,
                ),
              ],
              ValueListenableBuilder<int>(
                valueListenable: _tileCache.readyTileCount,
                builder: (_, readyTiles, _) => IgnorePointer(
                  key: ValueKey(
                    readyTiles > 0
                        ? 'radar-first-tile-ready'
                        : 'radar-tiles-loading',
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              if (frame.tileUrlTemplate != null)
                ValueListenableBuilder<int>(
                  valueListenable: _tileCache.readyTileCount,
                  builder: (_, readyTiles, _) => Positioned.fill(
                    bottom: _timelineHeight,
                    child: IgnorePointer(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child:
                            _showTilePreparation &&
                                readyTiles == 0 &&
                                !_radarTilesUnavailable
                            ? const Center(
                                key: ValueKey('radar-preparation-visible'),
                                child: _RadarPreparationCard(),
                              )
                            : const SizedBox.shrink(
                                key: ValueKey('radar-preparation-hidden'),
                              ),
                      ),
                    ),
                  ),
                ),
              ValueListenableBuilder<int>(
                valueListenable: _zoomLevel,
                builder: (_, zoom, _) => IgnorePointer(
                  key: ValueKey('radar-zoom-$zoom'),
                  child: const SizedBox.expand(),
                ),
              ),
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
                        isNowcast: frame.isNowcast,
                        pointRainRateMmPerHour: frame.pointRainRateMmPerHour,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _LayersButton(
                      selectedMap: _baseMap,
                      onPressed: _showLayers,
                    ),
                  ],
                ),
              ),
              if (_radarTilesUnavailable)
                Positioned(
                  left: 60,
                  right: 60,
                  top: 112,
                  child: _RadarTileLoadStatus(
                    unavailable: _radarTilesUnavailable,
                    onRetry: () => _schedulePrefetch(
                      state,
                      _mapController.camera,
                      refreshCurrentFrame: true,
                      immediate: true,
                    ),
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
                  onPlaybackToggled: _handleUserPlaybackToggle,
                  onPlaybackRestarted: _handleUserPlaybackRestart,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  void _schedulePrefetch(
    RadarReady state,
    MapCamera camera, {
    bool refreshCurrentFrame = false,
    bool immediate = false,
  }) {
    if (!_mapReady || state.frames.isEmpty) return;
    if (refreshCurrentFrame) _reloadCurrentFrameAfterPan = true;
    final requestGeneration = ++_viewportRequestGeneration;
    _prefetchDebounce?.cancel();
    // Invalidate work for the previous viewport immediately. At most the
    // small in-flight batch inside RadarTileCache is allowed to finish.
    _tileCache.cancelPrefetch();
    Future<void> run() async {
      if (!mounted) return;
      final latestState = _radarBloc.state;
      if (latestState is! RadarReady) return;
      final reloadCurrent = _reloadCurrentFrameAfterPan;
      _reloadCurrentFrameAfterPan = false;
      if (reloadCurrent) {
        if (mounted) {
          setState(() {
            _radarTilesLoading = true;
            _radarTilesUnavailable = false;
            if (_tileCache.readyTileCount.value == 0) {
              _showTilePreparation = true;
            }
          });
        }
        final currentTemplate = latestState.selectedFrame.tileUrlTemplate;
        if (currentTemplate != null) {
          final readyTiles = await _tileCache.prefetchNextFrames(
            camera: camera,
            frameTemplates: [currentTemplate],
            // The visible TileLayer is already loading the viewport. One
            // centre-tile recovery request is sufficient and avoids doubling
            // cold-origin work during launch.
            maxTiles: 1,
            completeOnFirstReady: true,
          );
          if (!mounted || requestGeneration != _viewportRequestGeneration) {
            return;
          }
          if (readyTiles == 0) {
            _reportTileIssue();
            setState(() {
              _radarTilesLoading = false;
              _radarTilesUnavailable = true;
              _showTilePreparation = false;
            });
            return;
          }
          // The layer may have completed its first lookup before the cache was
          // filled. Trigger a non-destructive image reload as soon as the first
          // central tile is valid; the rest continue warming in background.
          setState(() {
            _radarViewportRevision++;
            _radarTilesLoading = false;
            _radarTilesUnavailable = false;
            _showTilePreparation = false;
          });
          return;
        }
        if (mounted) setState(() => _radarTilesLoading = false);
      }
      unawaited(
        _tileCache.prefetchNextFrames(
          camera: camera,
          frameTemplates: _nextFrameTemplates(latestState),
        ),
      );
    }

    _prefetchDebounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 300),
      run,
    );
  }

  Iterable<String> _nextFrameTemplates(RadarReady state) sync* {
    final frameCount = state.frames.length;
    final maxNextFrames = math.min(1, frameCount - 1);
    var index = state.selectedIndex;
    for (var offset = 0; offset < maxNextFrames; offset++) {
      index++;
      if (index >= frameCount) index = state.playbackStartIndex;
      final template = state.frames[index].tileUrlTemplate;
      if (template != null) yield template;
    }
  }

  Future<void> _showLayers() async {
    final availableMaps = <_RadarBaseMap>[
      _RadarBaseMap.standard,
      if (widget.satelliteAvailable) _RadarBaseMap.satellite,
    ];
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
                  crossAxisCount: availableMaps.length == 1 ? 1 : 2,
                  childAspectRatio: 2.15,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: [
                    for (final map in availableMaps)
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
                  key: const Key('radar-precipitation-explanation'),
                  context.l10n.isFrench
                      ? 'Gris = écho très faible, rose/rouge = pluie plus intense. Ce ne sont pas des nuages. Le Graph suit la valeur LibreWXR exactement au point.'
                      : 'Grey = very weak echo, pink/red = stronger rain. These are not clouds. Graph follows the exact LibreWXR value at the point.',
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

final class _RadarPreparingSurface extends StatelessWidget {
  const _RadarPreparingSurface();

  @override
  Widget build(BuildContext context) => ClipRRect(
    key: const Key('radar-preparing-surface'),
    borderRadius: BorderRadius.circular(ChetiwaRadius.large),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF163640), Color(0xFF0C222B)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (final diameter in [280.0, 190.0, 105.0])
                  Container(
                    width: diameter,
                    height: diameter,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ChetiwaColors.accentPrimary.withValues(
                          alpha: 0.08,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Center(child: _RadarPreparationCard()),
        ],
      ),
    ),
  );
}

final class _RadarPreparationCard extends StatelessWidget {
  const _RadarPreparationCard();

  @override
  Widget build(BuildContext context) => Semantics(
    key: const Key('radar-preparation-card'),
    liveRegion: true,
    label: context.l10n.preparingRadar,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 290),
      child: Material(
        color: ChetiwaColors.backgroundPrimary.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(ChetiwaRadius.medium),
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          ChetiwaColors.accentPrimary,
                          Color(0xFF4BB6C8),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(ChetiwaRadius.small),
                    ),
                    child: const Icon(
                      Icons.radar_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Chetiwa Radar',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.l10n.preparingRadar,
                          style: const TextStyle(
                            color: ChetiwaColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const LinearProgressIndicator(
                key: Key('radar-preparation-progress'),
                minHeight: 3,
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
              const SizedBox(height: 10),
              Text(
                context.l10n.preparingRadarDetail,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: ChetiwaColors.textSecondary,
                  fontSize: 10,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _RadarTileLoadStatus extends StatelessWidget {
  const _RadarTileLoadStatus({
    required this.unavailable,
    required this.onRetry,
  });

  final bool unavailable;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final label = unavailable
        ? context.l10n.radarTilesUnavailable
        : context.l10n.loadingRadarTiles;
    return Semantics(
      key: const Key('radar-tile-load-status'),
      liveRegion: true,
      label: label,
      child: Material(
        color: ChetiwaColors.backgroundPrimary.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(ChetiwaRadius.full),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unavailable)
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 17,
                  color: ChetiwaColors.textSecondary,
                )
              else
                const SizedBox.square(
                  dimension: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              if (unavailable) ...[
                const SizedBox(width: 4),
                TextButton(
                  key: const Key('radar-tile-retry'),
                  onPressed: onRetry,
                  child: Text(context.l10n.retry),
                ),
              ],
            ],
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
              : OpenFreeMapLayer.homepage,
        ),
      ),
      borderRadius: BorderRadius.circular(ChetiwaRadius.small),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(
          baseMap.isSatellite
              ? '© Esri, Maxar, Earthstar · Radar LibreWXR'
              : '${OpenFreeMapLayer.attribution} · Radar LibreWXR',
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
    required this.snapshot,
    required this.selectedInstant,
    required this.isNowcast,
    required this.pointRainRateMmPerHour,
  });

  final Forecast forecast;
  final ForecastSnapshot snapshot;
  final DateTime selectedInstant;
  final bool isNowcast;
  final double? pointRainRateMmPerHour;

  @override
  Widget build(BuildContext context) {
    final location = forecast.locationName.split(',').first;
    final pointRate = snapshot.currentRain.rateMmPerHour;
    final modelAtPoint = pointRate < 0.05
        ? (context.l10n.isFrench
              ? '$location · modèle sec maintenant'
              : '$location · model dry now')
        : (context.l10n.isFrench
              ? '$location · modèle ${pointRate.toStringAsFixed(1)} mm/h'
              : '$location · model ${pointRate.toStringAsFixed(1)} mm/h');
    final frameState = isNowcast
        ? (context.l10n.isFrench ? 'prévision radar' : 'radar forecast')
        : (context.l10n.isFrench
              ? 'précipitations observées'
              : 'observed precipitation');
    final nowcastAtPoint = switch (pointRainRateMmPerHour) {
      null =>
        context.l10n.isFrench
            ? '$location · mesure au point indisponible'
            : '$location · point reading unavailable',
      < 0.05 =>
        context.l10n.isFrench
            ? '$location · sec au point · pluie proche possible'
            : '$location · dry at point · nearby rain possible',
      final rate =>
        context.l10n.isFrench
            ? '$location · ${rate.toStringAsFixed(1)} mm/h au point'
            : '$location · ${rate.toStringAsFixed(1)} mm/h at point',
    };
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: ChetiwaColors.backgroundPrimary.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(ChetiwaRadius.medium),
        border: Border.all(color: ChetiwaColors.borderDefault),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: ChetiwaColors.textPrimary),
        child: Row(
          children: [
            Icon(
              isNowcast ? Icons.auto_graph_rounded : Icons.radar_rounded,
              size: 15,
              color: ChetiwaColors.accentPrimary,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${WeatherTimeZone.displayHourMinute(selectedInstant)} · $frameState',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    isNowcast ? nowcastAtPoint : modelAtPoint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ChetiwaColors.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
  const _RadarLegend({required this.radarVisible, required this.providerName});

  final bool radarVisible;
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
                        ? 'Gris = écho faible ou incertain, rose = pluie modérée, rouge = pluie forte. Ce calque ne montre pas les nuages.'
                        : 'Grey = weak or uncertain echo, pink = moderate rain, red = heavy rain. This layer does not show clouds.',
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
                    colors: const [
                      Color(0xFFB8BEC2),
                      Color(0xFFD8A0A0),
                      Color(0xFFE56A67),
                      Color(0xFFD71920),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.isFrench ? 'Pluie faible' : 'Light rain',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 7),
                    ),
                  ),
                  const SizedBox(width: 4),
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
    this.onPlaybackToggled,
    this.onPlaybackRestarted,
    super.key,
  });

  final RadarReady state;
  final Forecast forecast;
  final ForecastSnapshot snapshot;
  final VoidCallback? onPlaybackToggled;
  final VoidCallback? onPlaybackRestarted;

  @override
  Widget build(BuildContext context) {
    final timelineColors = _RadarTimelineColors.of(context);
    final nowInstant = snapshot.nowUtc;
    final alignedForecast = alignForecastWithRadarNowcast(
      forecast,
      state.frames,
      nowInstant,
    );
    final graphEnd = RadarFramePolicy.timelineWindow(
      state.frames,
      nowInstant,
    ).end;
    final rainPoints = <RainPoint>[
      snapshot.currentRain,
      ...alignedForecast.points.where(
        (point) =>
            point.time.isAfter(nowInstant) && !point.time.isAfter(graphEnd),
      ),
    ];
    final selectedPointRate = state.selectedFrame.pointRainRateMmPerHour;
    final status = state.selectedFrame.isNowcast && selectedPointRate != null
        ? RainRateScale.isRain(selectedPointRate)
              ? '${selectedPointRate.toStringAsFixed(1)} mm/h ${context.l10n.isFrench ? 'au point' : 'at point'}'
              : (context.l10n.isFrench ? 'sec au point' : 'dry at point')
        : state.selectedFrame.isNowcast
        ? (context.l10n.isFrench ? 'prévision' : 'forecast')
        : state.isAtLatestObservation
        ? (context.l10n.isFrench
              ? 'dernière observation'
              : 'latest observation')
        : (context.l10n.isFrench ? 'observation' : 'observation');
    final statusColor =
        state.selectedFrame.isNowcast &&
            selectedPointRate != null &&
            !RainRateScale.isRain(selectedPointRate)
        ? timelineColors.muted
        : state.selectedFrame.isNowcast
        ? ChetiwaColors.warning
        : state.isAtLatestObservation
        ? ChetiwaColors.accentPrimary
        : timelineColors.muted;
    return Semantics(
      key: const Key('radar-local-time'),
      label:
          '${context.l10n.isFrench ? 'Chronologie radar · heure du téléphone' : 'Radar timeline · phone time'} · '
          '${WeatherTimeZone.displayUtcOffsetLabel(state.selectedFrame.time)} · '
          '${WeatherTimeZone.displayHourMinute(state.selectedFrame.time)}',
      child: Container(
        height: 150,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        decoration: BoxDecoration(
          // The map must never bleed through time labels or the scrubber.
          // Full opacity also keeps this panel readable over bright satellite
          // imagery and dense city labels.
          color: timelineColors.surface,
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
                    onTap: () {
                      onPlaybackToggled?.call();
                      context.read<RadarBloc>().add(
                        const RadarPlaybackToggled(),
                      );
                    },
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
                  onPressed: () {
                    onPlaybackRestarted?.call();
                    context.read<RadarBloc>().add(
                      const RadarPlaybackRestarted(),
                    );
                  },
                  icon: const Icon(Icons.replay_rounded, size: 18),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${WeatherTimeZone.displayHourMinute(state.selectedFrame.time)} · $status',
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
                    key: ValueKey(
                      state.frames.any(
                            (frame) =>
                                frame.isNowcast &&
                                frame.pointRainRateMmPerHour != null,
                          )
                          ? 'radar-point-profile-visible'
                          : 'radar-point-profile-unavailable',
                    ),
                    painter: _RadarTimeRulerPainter(
                      frames: state.frames,
                      rainPoints: rainPoints,
                      selectedIndex: state.selectedIndex,
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
    final window = RadarFramePolicy.timelineWindow(
      state.frames,
      snapshot.nowUtc,
    );
    final start = window.start.millisecondsSinceEpoch;
    final end = window.end.millisecondsSinceEpoch;
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
    required this.rainPoints,
    required this.selectedIndex,
    required this.now,
    required this.colors,
  });

  final List<RadarFrame> frames;
  final List<RainPoint> rainPoints;
  final int selectedIndex;
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
    final window = RadarFramePolicy.timelineWindow(frames, now);
    final start = window.start;
    final end = window.end;
    final durationMs = math
        .max(1, end.millisecondsSinceEpoch - start.millisecondsSinceEpoch)
        .toDouble();

    double xForTime(DateTime time) =>
        (size.width *
                (time.millisecondsSinceEpoch - start.millisecondsSinceEpoch) /
                durationMs)
            .toDouble();

    final track = Paint()
      ..color = colors.outline
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset.zero.translate(0, trackY),
      Offset(size.width, trackY),
      track,
    );

    if (hasNowcast) {
      _paintPointRainProfile(
        canvas,
        size,
        start,
        end,
        xForTime,
        chartTop,
        trackY,
      );
    }

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

  void _paintPointRainProfile(
    Canvas canvas,
    Size size,
    DateTime start,
    DateTime end,
    double Function(DateTime) xForTime,
    double chartTop,
    double trackY,
  ) {
    final samples = rainPoints
        .where(
          (point) => !point.time.isBefore(start) && !point.time.isAfter(end),
        )
        .map((point) => (point.time, point.rateMmPerHour))
        .toList(growable: false);
    if (samples.isEmpty) return;
    final graphBottom = trackY - 7;
    final chart = Rect.fromLTRB(0, chartTop, size.width, graphBottom);
    final profilePath = ui.Path();
    for (var index = 0; index < samples.length; index++) {
      final point = Offset(
        xForTime(samples[index].$1).clamp(0, size.width).toDouble(),
        _rainProfileY(samples[index].$2, chartTop, trackY),
      );
      if (index == 0) {
        profilePath.moveTo(point.dx, point.dy);
      } else {
        profilePath.lineTo(point.dx, point.dy);
      }
    }
    final episodes = RainRateScale.episodeRanges(
      samples.map((sample) => sample.$2),
    );
    for (final episode in episodes) {
      final firstRain = episode.first;
      final lastRain = episode.last;
      final areaPath = ui.Path();
      if (firstRain == 0) {
        final firstX = xForTime(
          samples[firstRain].$1,
        ).clamp(0, size.width).toDouble();
        final firstY = _rainProfileY(samples[firstRain].$2, chartTop, trackY);
        areaPath
          ..moveTo(firstX, graphBottom)
          ..lineTo(firstX, firstY);
      } else {
        final startX =
            (xForTime(samples[firstRain - 1].$1) +
                xForTime(samples[firstRain].$1)) /
            2;
        areaPath.moveTo(startX, graphBottom);
      }
      for (var rainIndex = firstRain; rainIndex <= lastRain; rainIndex++) {
        final x = xForTime(
          samples[rainIndex].$1,
        ).clamp(0, size.width).toDouble();
        final y = _rainProfileY(samples[rainIndex].$2, chartTop, trackY);
        areaPath.lineTo(x, y);
      }
      final endX = lastRain == samples.length - 1
          ? xForTime(samples[lastRain].$1).clamp(0, size.width).toDouble()
          : ((xForTime(samples[lastRain].$1) +
                        xForTime(samples[lastRain + 1].$1)) /
                    2)
                .clamp(0, size.width)
                .toDouble();
      areaPath
        ..lineTo(endX, graphBottom)
        ..close();
      canvas.drawPath(
        areaPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF346CC5).withValues(alpha: 0.65),
              const Color(0xFF346CC5).withValues(alpha: 0.08),
            ],
          ).createShader(chart),
      );
    }
    // A zero value is real information. Keep the complete profile visible on
    // the baseline so a dry nowcast never looks like a broken/unfinished line.
    canvas.drawPath(
      profilePath,
      Paint()
        ..color = const Color(0xFF3FA7D6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  double _rainProfileY(double rainRate, double chartTop, double trackY) {
    final graphBottom = trackY - 7;
    final graphHeight = math.max(1.0, graphBottom - chartTop - 8);
    return graphBottom - graphHeight * RainRateScale.normalized(rainRate);
  }

  DateTime _wallTime(DateTime instant) =>
      WeatherTimeZone.displayWallTime(instant);

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
        text: WeatherTimeZone.displayHourMinute(start),
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
      final tickInstant = WeatherTimeZone.displayInstantFromWall(wallTick);
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
        text: WeatherTimeZone.displayHourMinute(end),
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
