import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../app/theme/chetiwa_tokens.dart';
import '../../../../core/l10n/chetiwa_localizations.dart';
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

/// Deterministic native-map controls available only to the opt-in integration
/// smoke test. Real users and production builds cannot activate these hooks.
@visibleForTesting
abstract final class RadarMapSmokeTestBridge {
  static const _enabled = bool.fromEnvironment('CHETIWA_RADAR_SMOKE_TEST');
  static GoogleMapController? _controller;
  static int Function()? _tileOverlayCount;
  static String? Function()? _presentedTileTemplate;
  static bool Function()? _tileHandoffPending;
  static String Function()? _debugState;
  static int _maxTileOverlayCount = 0;
  static int _mapCreationCount = 0;

  static void attach(
    GoogleMapController controller, {
    required int Function() tileOverlayCount,
    required String? Function() presentedTileTemplate,
    required bool Function() tileHandoffPending,
    required String Function() debugState,
  }) {
    if (!_enabled) return;
    _controller = controller;
    _tileOverlayCount = tileOverlayCount;
    _presentedTileTemplate = presentedTileTemplate;
    _tileHandoffPending = tileHandoffPending;
    _debugState = debugState;
    _maxTileOverlayCount = 0;
    _mapCreationCount++;
  }

  static void detach(GoogleMapController? controller) {
    if (!_enabled || !identical(_controller, controller)) return;
    _controller = null;
    _tileOverlayCount = null;
    _presentedTileTemplate = null;
    _tileHandoffPending = null;
    _debugState = null;
  }

  static Future<bool> zoomTo(double zoom) async {
    final controller = _controller;
    if (!_enabled || controller == null) return false;
    await controller.animateCamera(CameraUpdate.zoomTo(zoom));
    return true;
  }

  static int get tileOverlayCount =>
      _enabled ? _tileOverlayCount?.call() ?? 0 : 0;

  static int get maxTileOverlayCount => _enabled ? _maxTileOverlayCount : 0;

  static String? get presentedTileTemplate =>
      _enabled ? _presentedTileTemplate?.call() : null;

  static bool get tileHandoffPending =>
      _enabled && (_tileHandoffPending?.call() ?? false);

  static int get mapCreationCount => _enabled ? _mapCreationCount : 0;

  static String get debugState => _enabled
      ? _debugState?.call() ?? 'Radar map detached'
      : 'Radar smoke bridge disabled';

  static void resetMaxTileOverlayCount() {
    if (!_enabled) return;
    _maxTileOverlayCount = tileOverlayCount;
  }

  static void recordTileOverlayCount(int count) {
    if (_enabled && count > _maxTileOverlayCount) {
      _maxTileOverlayCount = count;
    }
  }
}

final class RadarPane extends StatelessWidget {
  const RadarPane({
    required this.forecast,
    required this.snapshot,
    this.isActive = true,
    this.modelForecastLocked = false,
    super.key,
  });

  final Forecast forecast;
  final ForecastSnapshot snapshot;
  final bool isActive;
  final bool modelForecastLocked;

  @override
  Widget build(BuildContext context) => _RadarMap(
    forecast: forecast,
    snapshot: snapshot,
    isActive: isActive,
    modelForecastLocked: modelForecastLocked,
  );
}

enum _RadarBaseMap { standard, satellite }

extension on _RadarBaseMap {
  IconData get icon => switch (this) {
    _RadarBaseMap.standard => Icons.map_outlined,
    _RadarBaseMap.satellite => Icons.satellite_alt_outlined,
  };

  MapType get googleMapType => switch (this) {
    _RadarBaseMap.standard => MapType.normal,
    // Hybrid keeps place and road labels over the satellite image and is much
    // easier to orient than raw imagery.
    _RadarBaseMap.satellite => MapType.hybrid,
  };
}

final class _RadarMap extends StatefulWidget {
  const _RadarMap({
    required this.forecast,
    required this.snapshot,
    required this.isActive,
    required this.modelForecastLocked,
  });

  final Forecast forecast;
  final ForecastSnapshot snapshot;
  final bool isActive;
  final bool modelForecastLocked;

  @override
  State<_RadarMap> createState() => _RadarMapState();
}

final class _RadarMapState extends State<_RadarMap>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Start close enough to answer "is it raining here?" while staying at the
  // provider's native radar resolution.
  static const _regionalZoom = 7.0;
  static const _cityZoom = 11.0;
  static const _minRadarZoom = 5.0;
  // LibreWXR is generated through z10. The tile provider crops and scales the
  // correct z10 ancestor through z14, so city zoom stays geographically exact
  // instead of disappearing or requesting unsupported server tiles.
  static const _maxRadarZoom = 14.0;
  static const _timelineHeight = 104.0;
  static const _minimumInitialVisibleTileResponses = 4;
  // Animation only needs the eight most-recent (centre-first) viewport tiles
  // warmed ahead. Waiting for the full native off-screen margin cannot finish
  // inside a two-second playback step on a cold mobile connection.
  static const _maxVisibleRadarTiles = 8;

  GoogleMapController? _mapController;
  final RadarTileCache _tileCache = RadarTileCache.shared;
  final ValueNotifier<int> _zoomLevel = ValueNotifier<int>(
    _regionalZoom.round(),
  );
  final ValueNotifier<double?> _timelineScrubFraction = ValueNotifier<double?>(
    null,
  );
  late final RadarBloc _radarBloc;
  _RadarBaseMap _baseMap = _RadarBaseMap.satellite;
  // LibreWXR's palette already encodes the correct per-intensity alpha. Keep
  // the layer itself fully opaque so cells do not appear to fade simply
  // because the app applies a second transparency multiplier.
  double _radarOpacity = 1;
  bool _radarVisible = true;
  bool _mapReady = false;
  LatLng? _lastCenter;
  late final AnimationController _tileTransitionController;
  late final AnimationController _playheadController;
  final List<String?> _tileTemplates = List<String?>.filled(2, null);
  final List<RadarGoogleTileProvider?> _tileProviders =
      List<RadarGoogleTileProvider?>.filled(2, null);
  final List<bool> _tileSlotUsesModelSnapshot = List<bool>.filled(2, false);
  var _frontTileSlot = 0;
  int? _incomingTileSlot;
  var _tileOverlayGeneration = 0;
  var _tileTransitionGeneration = 0;
  var _cameraInteractionGeneration = 0;
  Timer? _prefetchDebounce;
  Timer? _cameraPlaybackResumeTimer;
  Timer? _visibleTileWatchdog;
  Timer? _surfaceReadyTimer;
  Timer? _dataRefreshTimer;
  Timer? _preparationRevealTimer;
  Timer? _preparationEscapeTimer;
  var _refreshFailureStreak = 0;
  var _viewportRequestGeneration = 0;
  var _radarTilesLoading = false;
  var _playbackBufferWarmInProgress = false;
  var _visibleTileRetryCount = 0;
  var _autoplayRequested = false;
  // The BLoC owns the frame index while Google Maps paints tile overlays on a
  // separate native surface. This gate stops only the automatic clock during
  // a handoff so the cursor can never run ahead of the last confirmed image.
  var _tilePlaybackClockHeld = false;
  // Never expose the native map's empty white surface during its cold boot.
  // It is revealed only after the camera has settled and a radar tile is
  // available from memory, disk, or network.
  var _showTilePreparation = true;
  var _preparationDeadlineExpired = false;
  var _surfaceReady = false;
  var _nativeMapSettled = false;
  var _resumeRecoveryInProgress = false;
  var _surfacePreparationGeneration = 0;
  var _minimumSuccessfulTileResponses = _minimumInitialVisibleTileResponses;
  DateTime? _backgroundedAt;
  var _cameraIsMoving = false;
  var _resumePlaybackAfterCameraMove = false;
  var _timelineScrubbing = false;
  var _resumePlaybackAfterTimelineScrub = false;
  var _visibleTileSuccessBaseline = 0;
  LatLng? _activeRadarCenter;
  String? _lastReportedMetadataIssue;
  var _tileIssueReported = false;
  var _lastTileHandoffDiagnostic = 'none';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _radarBloc = context.read<RadarBloc>();
    _tileTransitionController =
        AnimationController(
            vsync: this,
            duration: RadarFramePolicy.tileCrossFadeDuration,
          )
          ..addListener(_rebuildTileCrossFade)
          ..addStatusListener(_handleTileCrossFadeStatus);
    _playheadController = AnimationController(
      vsync: this,
      duration: RadarFramePolicy.playbackFrameDuration,
    );
    _tileCache.beginSession();
    _tileCache.readyTileCount.addListener(_handleReadyRadarTile);
    _tileCache.successfulTileResponseCount.addListener(
      _handleSuccessfulRadarTile,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scheduleDataRefresh(_radarBloc.state);
        _syncPlayhead(_radarBloc.state);
        _maybeStartAutoplay();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _RadarMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      _radarBloc.add(const RadarPlaybackResumed());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeStartAutoplay();
      });
    } else if (oldWidget.isActive && !widget.isActive) {
      _playheadController
        ..stop()
        ..value = 0;
      _radarBloc.add(const RadarPlaybackSuspended());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _backgroundedAt ??= DateTime.timestamp();
      _surfaceReadyTimer?.cancel();
      _surfaceReadyTimer = null;
      _prefetchDebounce?.cancel();
      _cameraPlaybackResumeTimer?.cancel();
      _visibleTileWatchdog?.cancel();
      _playheadController.stop();
      // Stop the BLoC's periodic clock as well as the visual playhead. Keeping
      // that timer alive let the selected radar frame advance while Android or
      // iOS had suspended the native map, producing a frozen tile/cursor pair
      // after resume.
      _radarBloc.add(const RadarPlaybackSuspended());
      return;
    }
    if (state != AppLifecycleState.resumed) return;

    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    final sleptFor = backgroundedAt == null
        ? Duration.zero
        : DateTime.timestamp().difference(backgroundedAt);
    if (sleptFor >= const Duration(seconds: 20)) {
      unawaited(_recoverRadarAfterResume());
      return;
    }
    if (widget.isActive) {
      _radarBloc.add(const RadarPlaybackResumed());
    }
  }

  Future<void> _recoverRadarAfterResume() async {
    if (!mounted || _resumeRecoveryInProgress) return;
    final state = _radarBloc.state;
    if (state is! RadarReady || state.selectedFrame.tileUrlTemplate == null) {
      if (widget.isActive) {
        _radarBloc.add(const RadarPlaybackResumed());
      }
      return;
    }

    final generation = ++_surfacePreparationGeneration;
    final canKeepLastGoodSurface =
        _surfaceReady && _frontViewportPresentationReady;
    _resumeRecoveryInProgress = true;
    _minimumSuccessfulTileResponses =
        _tileCache.successfulTileResponseCount.value +
        _minimumInitialVisibleTileResponses;
    _surfaceReadyTimer?.cancel();
    _surfaceReadyTimer = null;
    _prefetchDebounce?.cancel();
    _visibleTileWatchdog?.cancel();
    _preparationEscapeTimer?.cancel();
    _radarBloc.add(const RadarPlaybackSuspended());
    if (mounted) {
      setState(() {
        // A previously rendered native map is a better recovery surface than
        // a blocking loader. Keep the last good radar visible while its exact
        // current frame is restored from memory/disk. The branded preparation
        // card remains reserved for a genuinely cold first launch.
        if (!canKeepLastGoodSurface) {
          _surfaceReady = false;
          _showTilePreparation = true;
          _preparationDeadlineExpired = false;
          _radarTilesLoading = true;
        }
      });
      if (!canKeepLastGoodSurface) _armPreparationEscape();
    }

    // Preserve the last viewport coordinates so the currently visible frame
    // can be restored from the persistent cache before the native SDK asks for
    // every tile again. Old background work is still invalidated.
    _tileCache.beginViewport(preserveRecentCoordinates: true);
    final template = state.selectedFrame.tileUrlTemplate!;
    await _tileCache
        .prepareVisibleFrame(template, maxTiles: 8)
        .timeout(const Duration(seconds: 9), onTimeout: () => 0);
    if (!mounted || generation != _surfacePreparationGeneration) return;

    _tileProviders[_frontTileSlot]?.resetPresentationTracking();
    await _clearRadarTileCaches();
    if (!mounted || generation != _surfacePreparationGeneration) return;
    _nativeMapSettled = true;
    _scheduleSurfaceReady();
    await _warmPlaybackBuffer(
      state,
    ).timeout(const Duration(seconds: 6), onTimeout: () => false);
    if (!mounted || generation != _surfacePreparationGeneration) return;
    _scheduleSurfaceReady();
    if (canKeepLastGoodSurface) {
      setState(() {
        _resumeRecoveryInProgress = false;
        _radarTilesLoading = false;
      });
      if (widget.isActive) {
        _radarBloc.add(const RadarPlaybackResumed());
      }
      _maybeStartAutoplay();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _prefetchDebounce?.cancel();
    _cameraPlaybackResumeTimer?.cancel();
    _visibleTileWatchdog?.cancel();
    _surfaceReadyTimer?.cancel();
    _tileCache.cancelPrefetch();
    _tileCache.readyTileCount.removeListener(_handleReadyRadarTile);
    _tileCache.successfulTileResponseCount.removeListener(
      _handleSuccessfulRadarTile,
    );
    _dataRefreshTimer?.cancel();
    _preparationRevealTimer?.cancel();
    _preparationEscapeTimer?.cancel();
    _radarBloc.add(const RadarPlaybackPaused());
    RadarMapSmokeTestBridge.detach(_mapController);
    _mapController?.dispose();
    _tileTransitionController.dispose();
    _playheadController.dispose();
    _timelineScrubFraction.dispose();
    _zoomLevel.dispose();
    super.dispose();
  }

  void _handleReadyRadarTile() {
    if (!mounted || _tileCache.readyTileCount.value == 0) return;
    _preparationRevealTimer?.cancel();
    // The cache notifier fires while the native TileProvider is still
    // completing its callback. Reconcile on the next Flutter/native boundary
    // and never cancel recovery merely because one tile succeeded.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reconcileVisibleRadarPresentation();
    });
    _scheduleSurfaceReady();
    _maybeStartAutoplay();
  }

  void _reconcileVisibleRadarPresentation() {
    if (!_frontViewportPresentationReady) return;
    _preparationEscapeTimer?.cancel();
    _visibleTileWatchdog?.cancel();
    _visibleTileRetryCount = 0;
    _tileIssueReported = false;
    if (_surfaceReady && (_radarTilesLoading || _showTilePreparation)) {
      setState(() {
        _radarTilesLoading = false;
        _showTilePreparation = false;
      });
    }
    if (_resumePlaybackAfterCameraMove &&
        !_cameraIsMoving &&
        !_timelineScrubbing &&
        widget.isActive) {
      _resumePlaybackAfterCameraMove = false;
      _radarBloc.add(const RadarPlaybackResumed());
    }
    _scheduleSurfaceReady();
    _maybeStartAutoplay();
  }

  void _handleSuccessfulRadarTile() {
    if (!mounted || _tileCache.successfulTileResponseCount.value == 0) return;
    _scheduleSurfaceReady();
    // A zoom can initially leave the viewport-coordinate set empty because
    // Google Maps reused a native tile. As soon as the forced repaint asks for
    // a real tile again, restart current/next preparation automatically.
    if (_tilePlaybackClockHeld) {
      final state = _radarBloc.state;
      if (state is RadarReady) _schedulePrefetch(state);
    }
  }

  void _resetForRadarLocation(RadarReady state) {
    final center = LatLng(
      state.coordinates.latitude,
      state.coordinates.longitude,
    );
    final previous = _activeRadarCenter;
    _activeRadarCenter = center;
    if (previous == null || previous == center) return;

    _surfacePreparationGeneration++;
    _cameraInteractionGeneration++;
    _viewportRequestGeneration++;
    _tileTransitionGeneration++;
    _tileOverlayGeneration++;
    _surfaceReadyTimer?.cancel();
    _surfaceReadyTimer = null;
    _prefetchDebounce?.cancel();
    _cameraPlaybackResumeTimer?.cancel();
    _visibleTileWatchdog?.cancel();
    _preparationRevealTimer?.cancel();
    _preparationEscapeTimer?.cancel();
    _tileCache.beginViewport();
    for (final provider in _tileProviders.nonNulls) {
      provider.resetPresentationTracking();
    }
    _tileTransitionController
      ..stop()
      ..value = 0;
    _playheadController
      ..stop()
      ..value = 0;
    // Keep the same native Google map alive across city changes. Recreating
    // the iOS platform view occasionally produced a map that never requested
    // its initial TileProvider. A new overlay generation plus the camera move
    // below is sufficient and avoids the blank/recreation race entirely.
    _tileTemplates.fillRange(0, _tileTemplates.length, null);
    _tileProviders.fillRange(0, _tileProviders.length, null);
    _tileSlotUsesModelSnapshot.fillRange(
      0,
      _tileSlotUsesModelSnapshot.length,
      false,
    );
    _frontTileSlot = 0;
    _incomingTileSlot = null;
    _radarTilesLoading = true;
    _visibleTileRetryCount = 0;
    _autoplayRequested = false;
    _tilePlaybackClockHeld = false;
    _showTilePreparation = true;
    _preparationDeadlineExpired = false;
    _surfaceReady = false;
    _nativeMapSettled = false;
    _resumeRecoveryInProgress = false;
    _cameraIsMoving = false;
    _resumePlaybackAfterCameraMove = state.isPlaying;
    _timelineScrubbing = false;
    _resumePlaybackAfterTimelineScrub = false;
    _minimumSuccessfulTileResponses =
        _tileCache.successfulTileResponseCount.value +
        _minimumInitialVisibleTileResponses;
    _visibleTileSuccessBaseline = _tileCache.successfulTileResponseCount.value;
    if (state.isPlaying) _radarBloc.add(const RadarPlaybackSuspended());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _armPreparationEscape();
    });
  }

  void _scheduleSurfaceReady() {
    if (!mounted ||
        _surfaceReady ||
        !_mapReady ||
        !_nativeMapSettled ||
        _tileCache.successfulTileResponseCount.value <
            _minimumSuccessfulTileResponses ||
        _surfaceReadyTimer != null) {
      return;
    }
    final generation = _surfacePreparationGeneration;
    // onCameraIdle is emitted before the native Google surface has necessarily
    // composited its first complete frame on iOS. Keep the branded preparation
    // surface for one short settling window instead of flashing white.
    _surfaceReadyTimer = Timer(const Duration(milliseconds: 450), () {
      _surfaceReadyTimer = null;
      if (!mounted ||
          generation != _surfacePreparationGeneration ||
          !_mapReady ||
          !_nativeMapSettled ||
          _tileCache.successfulTileResponseCount.value <
              _minimumSuccessfulTileResponses ||
          !_frontViewportPresentationReady) {
        return;
      }
      setState(() {
        _surfaceReady = true;
        _resumeRecoveryInProgress = false;
        _radarTilesLoading = false;
        _showTilePreparation = false;
      });
      _preparationEscapeTimer?.cancel();
      _maybeStartAutoplay();
    });
  }

  bool get _frontViewportPresentationReady {
    final provider = _tileProviders[_frontTileSlot];
    if (provider == null) return false;
    // Native Google Maps requests a margin outside the visible viewport.
    // One cold/out-of-coverage coordinate must not keep the whole Radar behind
    // a blocking preparation card forever. Four successful coordinates and a
    // 50% native quorum are sufficient to reveal the map; missing margins are
    // filled by the retry/fallback pipeline in the background.
    return provider.hasPresentationCoverage(
      minimumCoordinates: _minimumInitialVisibleTileResponses,
      minimumRatio: 0.5,
    );
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

  void _rebuildTileCrossFade() {
    if (mounted && _incomingTileSlot != null) setState(() {});
  }

  void _handleTileCrossFadeStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    final incoming = _incomingTileSlot;
    if (incoming == null) return;
    setState(() {
      _frontTileSlot = incoming;
      _incomingTileSlot = null;
    });
    _releasePlaybackClockAfterTileHandoff();
  }

  double get _tileCrossFadeProgress =>
      Curves.easeInOutCubic.transform(_tileTransitionController.value);

  void _setTileSlot(int slot, String template, {required bool modelSnapshot}) {
    _tileTemplates[slot] = template;
    _tileProviders[slot] = _tileCache.providerFor(template);
    _tileSlotUsesModelSnapshot[slot] = modelSnapshot;
  }

  void _initializeFirstTileFrame(
    String template, {
    required bool modelSnapshot,
  }) {
    if (_tileTemplates[_frontTileSlot] != null) return;
    _setTileSlot(_frontTileSlot, template, modelSnapshot: modelSnapshot);
  }

  void _queueTileFrameTransition(
    String template, {
    required bool modelSnapshot,
  }) {
    if (!mounted || !widget.isActive || _cameraIsMoving) return;
    if (_tileTemplates[_frontTileSlot] == template &&
        _incomingTileSlot == null) {
      _releasePlaybackClockAfterTileHandoff();
      return;
    }
    final incoming = _incomingTileSlot;
    if (incoming != null && _tileTemplates[incoming] == template) return;
    final generation = ++_tileTransitionGeneration;
    unawaited(
      _transitionToTileFrame(
        template,
        generation,
        modelSnapshot: modelSnapshot,
      ),
    );
  }

  Future<void> _transitionToTileFrame(
    String template,
    int generation, {
    required bool modelSnapshot,
  }) async {
    // A fast scrub can supersede an incoming timestamp before the native map
    // paints it. Keep the known-good front frame instead of promoting an
    // unconfirmed overlay and exposing a blank flash.
    _cancelTileTransition(invalidatePending: false);
    if (!mounted || generation != _tileTransitionGeneration) return;
    if (_tileTemplates[_frontTileSlot] == template) {
      _releasePlaybackClockAfterTileHandoff();
      return;
    }

    final targetSlot = 1 - _frontTileSlot;
    _setTileSlot(targetSlot, template, modelSnapshot: modelSnapshot);
    await _clearRadarTileSlot(targetSlot);
    // Keep the previous timestamp fully visible until every known tile in the
    // incoming viewport is available. Swapping after only one tile produced
    // the large patch-by-patch jump visible on a cold iPhone launch.
    // Native Google Maps may request a ring of off-screen tiles around a
    // phone viewport. Preparing that entire ring delayed every frame behind
    // coordinates the user could not see. Eight most-recent coordinates cover
    // the visible surface while the provider fills the native margin lazily.
    final expectedTiles = math.min(_tileCache.recentCoordinateCount, 8);
    if (expectedTiles == 0) {
      _lastTileHandoffDiagnostic = 'no-visible-coordinates';
      _pauseForIncompletePlaybackBuffer();
      return;
    }
    final preparedTiles = await _tileCache.prepareVisibleFrame(
      template,
      maxTiles: 8,
    );
    if (!mounted ||
        generation != _tileTransitionGeneration ||
        _cameraIsMoving) {
      return;
    }
    // A wide z5 viewport legitimately contains coordinates outside the
    // regional nowcast footprint. LibreWXR returns no precipitation tile for
    // those coordinates; treating them as failed weather data froze playback
    // forever at 9/16. Require a strong visible quorum while allowing the
    // Google basemap to remain visible outside provider coverage.
    final requiredPreparedTiles = math.min(
      expectedTiles,
      // Two centre-first bytes are enough to attach the incoming native
      // overlay. Promotion below still requires Google Maps to acknowledge at
      // least 50% of its complete request set, so this only removes a Dart
      // prefetch bottleneck; it does not reveal a patchwork frame.
      math.max(2, (expectedTiles * 0.25).ceil()),
    );
    if (preparedTiles < requiredPreparedTiles) {
      _lastTileHandoffDiagnostic =
          'prepared-$preparedTiles-of-$expectedTiles-required-$requiredPreparedTiles';
      _pauseForIncompletePlaybackBuffer();
      return;
    }

    if (!RadarFramePolicy.opacityCrossFadeEnabled) {
      // Dart having the PNG bytes does not mean the native Google surface has
      // painted them. Attach the fully opaque incoming layer above the old
      // one, wait for native tile requests to complete, then remove the old
      // layer. This is a zero-opacity-blend handoff: no white/empty frame and
      // no artificial meteorological dissolve.
      _tileTransitionController.stop();
      final incomingProvider = _tileProviders[targetSlot]!;
      incomingProvider.resetPresentationTracking();
      setState(() => _incomingTileSlot = targetSlot);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || generation != _tileTransitionGeneration) return;
      // iOS keys its native tile cache by overlay id. Clearing this slot before
      // it was attached could be ignored, leaving the new Dart provider with
      // zero requests forever. Clear once more after native insertion so the
      // selected timestamp is guaranteed to be requested.
      await _clearRadarTileSlot(targetSlot);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || generation != _tileTransitionGeneration) return;
      final presented = await _waitForNativeTilePresentation(
        provider: incomingProvider,
        minimumCoordinates: math.min(preparedTiles, 8),
        // The native request set includes off-screen and out-of-coverage
        // coordinates at low zoom. The absolute minimum above still requires
        // eight successfully painted coordinates for this 16-tile viewport.
        minimumCoverage: 0.5,
      );
      if (!mounted || generation != _tileTransitionGeneration) return;
      if (!presented) {
        _lastTileHandoffDiagnostic =
            'native-timeout-requested-${incomingProvider.requestedCoordinateCount}'
            '-successful-${incomingProvider.successfulCoordinateCount}';
        _cancelTileTransition(invalidatePending: false);
        _pauseForIncompletePlaybackBuffer();
        return;
      }
      // One additional Flutter/native composition boundary guarantees that
      // the successful TileProvider responses are visible before the old
      // overlay is detached.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || generation != _tileTransitionGeneration) return;
      setState(() {
        _frontTileSlot = targetSlot;
        _incomingTileSlot = null;
      });
      _lastTileHandoffDiagnostic = 'presented-$preparedTiles';
      _releasePlaybackClockAfterTileHandoff();
      return;
    }

    _tileTransitionController.value = 0;
    setState(() => _incomingTileSlot = targetSlot);
    // Give the native SDK one frame to request the memory-cached tile bytes.
    // The old image remains fully visible during this preparation frame.
    await Future<void>.delayed(const Duration(milliseconds: 34));
    if (!mounted ||
        generation != _tileTransitionGeneration ||
        _incomingTileSlot != targetSlot ||
        _cameraIsMoving) {
      return;
    }
    unawaited(_tileTransitionController.forward(from: 0));
  }

  Future<bool> _waitForNativeTilePresentation({
    required RadarGoogleTileProvider provider,
    required int minimumCoordinates,
    double minimumCoverage = 1,
    bool Function()? isCurrent,
  }) async {
    final completer = Completer<bool>();
    Timer? timeout;
    Timer? settle;
    void evaluate() {
      settle?.cancel();
      if (isCurrent != null && !isCurrent()) {
        if (!completer.isCompleted) completer.complete(false);
        return;
      }
      if (!provider.hasPresentationCoverage(
        minimumCoordinates: minimumCoordinates,
        minimumRatio: minimumCoverage,
      )) {
        return;
      }
      // Native map requests normally arrive as one burst. The short quiet
      // period prevents a first group of four tiles from being mistaken for
      // a complete high-density phone viewport.
      settle = Timer(const Duration(milliseconds: 120), () {
        if (!completer.isCompleted &&
            (isCurrent == null || isCurrent()) &&
            provider.hasPresentationCoverage(
              minimumCoordinates: minimumCoordinates,
              minimumRatio: minimumCoverage,
            )) {
          completer.complete(true);
        }
      });
    }

    provider.presentationRevision.addListener(evaluate);
    timeout = Timer(const Duration(milliseconds: 1500), () {
      if (!completer.isCompleted) completer.complete(false);
    });
    evaluate();
    try {
      return await completer.future;
    } finally {
      timeout.cancel();
      settle?.cancel();
      provider.presentationRevision.removeListener(evaluate);
    }
  }

  void _pauseForIncompletePlaybackBuffer() {
    final state = _radarBloc.state;
    if (state is RadarReady && state.isPlaying) {
      _holdPlaybackClockForTileHandoff();
    }
    if (state is RadarReady) _schedulePrefetch(state);
  }

  bool _isSelectedTilePresented(RadarReady state) {
    final selectedTemplate = state.selectedFrame.tileUrlTemplate;
    if (selectedTemplate == null) return true;
    return _surfaceReady &&
        !_cameraIsMoving &&
        _incomingTileSlot == null &&
        _tileTemplates[_frontTileSlot] == selectedTemplate;
  }

  void _holdPlaybackClockForTileHandoff() {
    if (!mounted) return;
    _tilePlaybackClockHeld = true;
    _playheadController
      ..stop()
      ..value = 0;
    // This event is deliberately idempotent. A lifecycle resume may restart
    // the BLoC timer while a native handoff is still pending, so every playing
    // state with an unpresented tile reasserts the gate.
    _radarBloc.add(const RadarPlaybackClockHeld());
  }

  void _releasePlaybackClockAfterTileHandoff() {
    if (!mounted) return;
    final state = _radarBloc.state;
    if (state is! RadarReady || !_isSelectedTilePresented(state)) return;
    final clockWasHeld = _tilePlaybackClockHeld;
    _tilePlaybackClockHeld = false;
    if (!clockWasHeld || !state.isPlaying) return;
    _radarBloc.add(const RadarPlaybackClockReleased());
    unawaited(_playheadController.forward(from: 0));
  }

  void _cancelTileTransition({required bool invalidatePending}) {
    if (invalidatePending) _tileTransitionGeneration++;
    _tileTransitionController.stop();
    if (_incomingTileSlot == null || !mounted) return;
    setState(() => _incomingTileSlot = null);
  }

  Future<void> _clearRadarTileSlot(int slot) async {
    final controller = _mapController;
    if (controller == null) return;
    try {
      await controller.clearTileCache(_tileOverlayId(slot));
    } on Object {
      // The slot may not exist natively yet. Its first insertion is already a
      // clean cache generation, so this is safe to ignore.
    }
  }

  Future<void> _clearRadarTileCaches() async {
    await Future.wait([_clearRadarTileSlot(0), _clearRadarTileSlot(1)]);
  }

  Set<TileOverlay> _buildRadarTileOverlays() {
    if (!_radarVisible) {
      RadarMapSmokeTestBridge.recordTileOverlayCount(0);
      return const <TileOverlay>{};
    }
    final frontProvider = _tileProviders[_frontTileSlot];
    if (frontProvider == null) {
      RadarMapSmokeTestBridge.recordTileOverlayCount(0);
      return const <TileOverlay>{};
    }
    final incoming = _incomingTileSlot;
    final progress = incoming == null ? 0.0 : _tileCrossFadeProgress;

    TileOverlay overlay(int slot, double contribution, int zIndex) {
      final effectiveOpacity = (_radarOpacity * contribution).clamp(0.0, 1.0);
      return TileOverlay(
        tileOverlayId: _tileOverlayId(slot),
        tileProvider: _tileProviders[slot],
        transparency: 1 - effectiveOpacity,
        // Native fading removes the remaining pop when a pan or zoom exposes
        // a tile that was not part of the previous viewport.
        // Chetiwa preloads every visible frame and controls its own short
        // nowcast transition. Native fading on top caused a second opacity
        // animation and made rain cells appear to dissolve.
        fadeIn: false,
        zIndex: zIndex,
      );
    }

    if (incoming == null || _tileProviders[incoming] == null) {
      final overlays = <TileOverlay>{overlay(_frontTileSlot, 1, 1)};
      RadarMapSmokeTestBridge.recordTileOverlayCount(overlays.length);
      return overlays;
    }
    final overlays = RadarFramePolicy.opacityCrossFadeEnabled
        ? <TileOverlay>{
            overlay(_frontTileSlot, 1 - progress, 1),
            overlay(incoming, progress, 2),
          }
        : <TileOverlay>{
            // Both layers remain fully opaque during the short native handoff.
            // The incoming PNG is above the old one; its transparent pixels
            // temporarily reveal the last valid radar rather than the map.
            overlay(_frontTileSlot, 1, 1),
            overlay(incoming, 1, 2),
          };
    RadarMapSmokeTestBridge.recordTileOverlayCount(overlays.length);
    return overlays;
  }

  TileOverlayId _tileOverlayId(int slot) => TileOverlayId(
    'chetiwa-radar-$_tileOverlayGeneration-${slot == 0 ? 'a' : 'b'}',
  );

  void _revealPreparationIfStillNeeded() {
    _preparationRevealTimer?.cancel();
    if (_showTilePreparation) _armPreparationEscape();
    if (_tileCache.readyTileCount.value > 0 || _preparationDeadlineExpired) {
      return;
    }
    // Warm disk-cache hits should appear without flashing a loading card. Only
    // reveal it when first paint is genuinely taking noticeable time.
    _preparationRevealTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || _tileCache.readyTileCount.value > 0) return;
      setState(() => _showTilePreparation = true);
      _armPreparationEscape();
    });
  }

  void _armPreparationEscape() {
    if ((_preparationEscapeTimer?.isActive ?? false) ||
        !mounted ||
        !_showTilePreparation ||
        _preparationDeadlineExpired) {
      return;
    }
    final generation = _surfacePreparationGeneration;
    _preparationEscapeTimer = Timer(const Duration(seconds: 8), () {
      _preparationEscapeTimer = null;
      if (!mounted ||
          generation != _surfacePreparationGeneration ||
          !_showTilePreparation) {
        return;
      }
      // Never trap the user behind a loader. Keep playback suspended until a
      // real tile quorum is painted, but reveal the interactive Google basemap
      // and let silent retries continue in the background.
      _preparationDeadlineExpired = true;
      _resumePlaybackAfterCameraMove = true;
      _radarBloc.add(const RadarPlaybackSuspended());
      _reportTileIssue();
      setState(() {
        _showTilePreparation = false;
        _radarTilesLoading = false;
      });
      final latest = _radarBloc.state;
      if (latest is RadarReady) _scheduleVisibleRadarRetry();
    });
  }

  void _maybeStartAutoplay() {
    if (!mounted ||
        !widget.isActive ||
        !_surfaceReady ||
        _resumeRecoveryInProgress ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed) ||
        _timelineScrubbing ||
        _cameraIsMoving ||
        _autoplayRequested) {
      return;
    }
    final state = _radarBloc.state;
    if (state is! RadarReady || state.frames.length < 2 || state.isPlaying) {
      return;
    }
    if (!_isSelectedTilePresented(state)) return;
    final needsNetworkTile = state.selectedFrame.tileUrlTemplate != null;
    if (needsNetworkTile && _tileCache.readyTileCount.value == 0) {
      return;
    }
    _autoplayRequested = true;
    _radarBloc.add(const RadarPlaybackStarted());
  }

  void _syncPlayhead(RadarState state) {
    if (state is! RadarReady ||
        !widget.isActive ||
        !_surfaceReady ||
        _resumeRecoveryInProgress ||
        _timelineScrubbing ||
        !state.isPlaying ||
        !_isSelectedTilePresented(state) ||
        state.frames.length < 2 ||
        state.selectedIndex >= state.frames.length - 1) {
      _playheadController
        ..stop()
        ..value = 0;
      return;
    }
    // Every real frame change restarts a linear visual clock. The BLoC uses
    // the exact same duration, so the cursor reaches the next timestamp at the
    // instant the corresponding source frame becomes selected.
    unawaited(_playheadController.forward(from: 0));
  }

  void _handleTimelineScrubStarted() {
    if (_timelineScrubbing) return;
    _timelineScrubbing = true;
    final state = _radarBloc.state;
    _resumePlaybackAfterTimelineScrub = state is RadarReady && state.isPlaying;
    _playheadController
      ..stop()
      ..value = 0;
    if (_resumePlaybackAfterTimelineScrub) {
      _radarBloc.add(const RadarPlaybackSuspended());
    }
  }

  void _handleTimelineScrubEnded() {
    if (!_timelineScrubbing) return;
    _timelineScrubFraction.value = null;
    _timelineScrubbing = false;
    final shouldResume = _resumePlaybackAfterTimelineScrub;
    _resumePlaybackAfterTimelineScrub = false;
    if (!shouldResume) return;
    scheduleMicrotask(() {
      if (!mounted || _timelineScrubbing || !widget.isActive) {
        return;
      }
      _radarBloc.add(const RadarPlaybackResumed());
    });
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
      if (state is RadarReady) _resetForRadarLocation(state);
      if (state is RadarReady && state.isPlaying) {
        if (!_surfaceReady || _resumeRecoveryInProgress) {
          // A parent lifecycle callback can request resume while the native map
          // is still rebuilding. Keep the intent in the BLoC, but never let the
          // timeline outrun a blank or partially restored viewport.
          _radarBloc.add(const RadarPlaybackSuspended());
        } else if (!_isSelectedTilePresented(state)) {
          // The BLoC has selected the next timestamp, but the native map still
          // shows the previous tile. Freeze both clocks until Google Maps has
          // requested and presented the complete incoming viewport.
          _holdPlaybackClockForTileHandoff();
        } else {
          _autoplayRequested = false;
          _releasePlaybackClockAfterTileHandoff();
        }
      }
      _syncPlayhead(state);
      // Only provider/frame changes need speculative next-frame work. Keeping
      // this in the Bloc listener avoids a local loading setState cancelling
      // the current-frame request that triggered it.
      if (_mapReady && state is RadarReady && !_radarTilesLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _schedulePrefetch(state);
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
        if (frame.tileUrlTemplate == null) {
          _mapReady = false;
          _surfaceReady = true;
          _nativeMapSettled = true;
          _resumeRecoveryInProgress = false;
          _showTilePreparation = false;
        }
        final center = LatLng(
          state.coordinates.latitude,
          state.coordinates.longitude,
        );
        if (_mapReady && _lastCenter != null && _lastCenter != center) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              unawaited(
                _mapController?.animateCamera(
                  CameraUpdate.newLatLngZoom(center, _regionalZoom),
                ),
              );
            }
          });
        }
        _lastCenter = center;
        final tileUrl = frame.tileUrlTemplate;
        if (tileUrl != null) {
          _initializeFirstTileFrame(
            tileUrl,
            modelSnapshot: frame.isModelForecast,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _queueTileFrameTransition(
                tileUrl,
                modelSnapshot: frame.isModelForecast,
              );
            }
          });
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(ChetiwaRadius.large),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (tileUrl != null) ...[
                Positioned.fill(
                  bottom: _timelineHeight,
                  child: GoogleMap(
                    key: const ValueKey('chetiwa-google-radar-map'),
                    initialCameraPosition: CameraPosition(
                      target: center,
                      zoom: _regionalZoom,
                    ),
                    mapType: _baseMap.googleMapType,
                    minMaxZoomPreference: const MinMaxZoomPreference(
                      _minRadarZoom,
                      _maxRadarZoom,
                    ),
                    compassEnabled: false,
                    mapToolbarEnabled: false,
                    myLocationButtonEnabled: false,
                    myLocationEnabled: false,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                    zoomControlsEnabled: false,
                    indoorViewEnabled: false,
                    trafficEnabled: false,
                    buildingsEnabled: true,
                    onMapCreated: (controller) {
                      _mapController = controller;
                      _mapReady = true;
                      _nativeMapSettled = false;
                      RadarMapSmokeTestBridge.attach(
                        controller,
                        tileOverlayCount: () =>
                            _incomingTileSlot == null ? 1 : 2,
                        presentedTileTemplate: () =>
                            _tileTemplates[_frontTileSlot],
                        tileHandoffPending: () =>
                            _incomingTileSlot != null ||
                            (_radarBloc.state is RadarReady &&
                                !_isSelectedTilePresented(
                                  _radarBloc.state as RadarReady,
                                )),
                        debugState: () {
                          final provider = _tileProviders[_frontTileSlot];
                          final incoming = _incomingTileSlot;
                          final incomingProvider = incoming == null
                              ? null
                              : _tileProviders[incoming];
                          return 'front=$_frontTileSlot '
                              'incoming=$_incomingTileSlot '
                              'frontTemplate=${_tileTemplates[_frontTileSlot]} '
                              'requested=${provider?.requestedCoordinateCount} '
                              'successful=${provider?.successfulCoordinateCount} '
                              'incomingRequested=${incomingProvider?.requestedCoordinateCount} '
                              'incomingSuccessful=${incomingProvider?.successfulCoordinateCount} '
                              'recent=${_tileCache.recentCoordinateCount} '
                              'surfaceReady=$_surfaceReady '
                              'cameraMoving=$_cameraIsMoving '
                              'resumeAfterCamera=$_resumePlaybackAfterCameraMove '
                              'clockHeld=$_tilePlaybackClockHeld '
                              'lastHandoff=$_lastTileHandoffDiagnostic';
                        },
                      );
                      _visibleTileSuccessBaseline =
                          _tileCache.successfulTileResponseCount.value;
                      _revealPreparationIfStillNeeded();
                      _armVisibleTileWatchdog(state);
                      final selectedTemplate =
                          state.selectedFrame.tileUrlTemplate;
                      if (selectedTemplate != null) {
                        _queueTileFrameTransition(
                          selectedTemplate,
                          modelSnapshot: state.selectedFrame.isModelForecast,
                        );
                      }
                      final overlayGeneration = _tileOverlayGeneration;
                      // iOS may preserve a native NO_TILE decision across map
                      // recreation when the previous city used the same
                      // overlay slot. The location-specific overlay id above
                      // prevents reuse; this post-attach invalidation also
                      // guarantees the new provider receives its first
                      // viewport request without clearing application data.
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        if (!mounted ||
                            overlayGeneration != _tileOverlayGeneration ||
                            !identical(_mapController, controller)) {
                          return;
                        }
                        try {
                          await controller.clearTileCache(
                            _tileOverlayId(_frontTileSlot),
                          );
                        } on Object {
                          // The watchdog retries if the native map is disposed
                          // between this frame and the platform call.
                        }
                      });
                    },
                    onCameraMove: (position) {
                      final roundedZoom = position.zoom.round();
                      if (_zoomLevel.value != roundedZoom) {
                        _zoomLevel.value = roundedZoom;
                      }
                    },
                    onCameraMoveStarted: _handleCameraMoveStarted,
                    onCameraIdle: _handleCameraIdle,
                    markers: {
                      Marker(
                        markerId: const MarkerId('selected-location'),
                        position: center,
                        infoWindow: InfoWindow(
                          title: widget.forecast.locationName.split(',').first,
                        ),
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueCyan,
                        ),
                        onTap: () => unawaited(
                          _mapController?.animateCamera(
                            CameraUpdate.newLatLngZoom(center, _cityZoom),
                          ),
                        ),
                      ),
                    },
                    tileOverlays: _buildRadarTileOverlays(),
                  ),
                ),
                IgnorePointer(
                  key: const Key('chetiwa-radar-precipitation-tile'),
                  child: const SizedBox.expand(),
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
                        child: _showTilePreparation
                            ? const _RadarPreparingSurface(
                                key: ValueKey('radar-preparation-visible'),
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
                        selectedInstant: frame.time,
                        frame: frame,
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
                  // Keep the mandatory Google logo/attribution unobstructed at
                  // the native map's bottom edge.
                  bottom: _timelineHeight + 36,
                  child: _RecenterButton(
                    locationName: widget.forecast.locationName,
                    onPressed: () => unawaited(
                      _mapController?.animateCamera(
                        CameraUpdate.newLatLngZoom(center, _regionalZoom),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 8,
                bottom: _timelineHeight + 36,
                child: _RadarLegend(radarVisible: _radarVisible, frame: frame),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: RadarTimeline(
                  state: state,
                  forecast: widget.forecast,
                  snapshot: widget.snapshot,
                  playbackProgress: _playheadController,
                  scrubFraction: _timelineScrubFraction,
                  modelForecastLocked: widget.modelForecastLocked,
                  onScrubStarted: _handleTimelineScrubStarted,
                  onScrubEnded: _handleTimelineScrubEnded,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  void _schedulePrefetch(RadarReady state) {
    if (!_mapReady || state.frames.isEmpty || _playbackBufferWarmInProgress) {
      return;
    }
    ++_viewportRequestGeneration;
    _prefetchDebounce?.cancel();
    _tileCache.cancelPrefetch();
    _prefetchDebounce = Timer(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      final latestState = _radarBloc.state;
      if (latestState is! RadarReady) return;
      unawaited(_warmPlaybackBuffer(latestState));
    });
  }

  Future<bool> _warmPlaybackBuffer(RadarReady state) async {
    if (_playbackBufferWarmInProgress) return false;
    _playbackBufferWarmInProgress = true;
    try {
      return await _warmPlaybackBufferOnce(state);
    } finally {
      _playbackBufferWarmInProgress = false;
    }
  }

  Future<bool> _warmPlaybackBufferOnce(RadarReady state) async {
    final templates = _currentAndNextFrameTemplates(
      state,
    ).toList(growable: false);
    if (templates.isEmpty) return false;
    final expectedTiles = math.min(
      _tileCache.recentCoordinateCount,
      _maxVisibleRadarTiles,
    );
    if (expectedTiles == 0) return false;

    final selectedTemplate = state.selectedFrame.tileUrlTemplate;
    if (!_isSelectedTilePresented(state) && selectedTemplate != null) {
      // Foreground always wins over speculation. Previously this method
      // downloaded the frame after the selected one first; on a cold iPhone
      // viewport the cursor could therefore wait 15+ seconds while unrelated
      // bytes consumed every download slot.
      final selectedReady = await _tileCache.prepareVisibleFrame(
        selectedTemplate,
        maxTiles: _maxVisibleRadarTiles,
      );
      if (!mounted || _cameraIsMoving) return false;
      final latest = _radarBloc.state;
      if (latest is RadarReady && !_isSelectedTilePresented(latest)) {
        final latestTemplate = latest.selectedFrame.tileUrlTemplate;
        if (latestTemplate != null) {
          _queueTileFrameTransition(
            latestTemplate,
            modelSnapshot: latest.selectedFrame.isModelForecast,
          );
        }
      }
      return selectedReady == expectedTiles;
    }

    // The native front overlay has already presented the selected frame.
    // Re-fetching current+next in interleaved pairs made a cold next frame use
    // only one network slot and could leave iOS paused after a fast zoom. Warm
    // the next timestamp directly. Existing native front-tile downloads have
    // semaphore priority because they were queued first; the remaining bounded
    // slots then fill the next timestamp in about three batches instead of
    // sixteen serial requests. If there is no next template, the visible
    // current frame itself is a complete buffer.
    final nextTemplates = templates.skip(1).toList(growable: false);
    if (nextTemplates.isNotEmpty && state.isPlaying && !_timelineScrubbing) {
      // Freeze both clocks *before* the BLoC reaches the next timestamp. The
      // previous implementation released this gate even when prefetch failed,
      // allowing the red cursor to advance while Google Maps still displayed
      // the old precipitation frame.
      _holdPlaybackClockForTileHandoff();
    }
    final ready = nextTemplates.isEmpty
        ? expectedTiles
        : await _tileCache.prefetchNextFrames(
            frameTemplates: nextTemplates,
            maxFrames: 1,
            maxTiles: _maxVisibleRadarTiles,
            maxConcurrent: 6,
          );
    if (!mounted || _cameraIsMoving) return false;
    final requiredReady = math.min(
      expectedTiles,
      math.max(4, (expectedTiles * 0.5).ceil()),
    );
    final bufferReady = ready >= requiredReady;
    final latestState = _radarBloc.state;
    final sameSelectedFrame =
        latestState is RadarReady &&
        latestState.selectedFrame.tileUrlTemplate ==
            state.selectedFrame.tileUrlTemplate;
    if (bufferReady &&
        latestState is RadarReady &&
        sameSelectedFrame &&
        _isSelectedTilePresented(latestState)) {
      _releasePlaybackClockAfterTileHandoff();
      _maybeStartAutoplay();
    } else if (latestState is RadarReady) {
      // Keep the current image/cursor paired and retry in the background.
      // A transient 5xx may delay the animation, but can never desynchronise
      // it or require the user to clear application data.
      Timer(const Duration(milliseconds: 250), () {
        if (mounted) _schedulePrefetch(latestState);
      });
    }
    return bufferReady;
  }

  void _handleCameraMoveStarted() {
    _cameraPlaybackResumeTimer?.cancel();
    _visibleTileWatchdog?.cancel();
    if (_cameraIsMoving) return;
    _cameraInteractionGeneration++;
    _visibleTileRetryCount = 0;
    _prefetchDebounce?.cancel();
    _tileCache.beginViewport();
    // Wake and cancel presentation waits owned by an older camera generation.
    // Without this, rapid programmatic zooms left several iOS waits sharing
    // and resetting one provider, so the newest viewport could never settle.
    for (final provider in _tileProviders.nonNulls) {
      provider.resetPresentationTracking();
    }
    // Never pan while a native handoff is pending. Retain the last fully
    // presented timestamp; promoting an unconfirmed incoming layer here was a
    // second route to a blank radar surface.
    _cancelTileTransition(invalidatePending: true);
    _cameraIsMoving = true;
    _visibleTileSuccessBaseline = _tileCache.successfulTileResponseCount.value;
    final state = _radarBloc.state;
    final wasPlaying = state is RadarReady && state.isPlaying;
    _resumePlaybackAfterCameraMove =
        _resumePlaybackAfterCameraMove || wasPlaying;
    if (wasPlaying) {
      _radarBloc.add(const RadarPlaybackSuspended());
    }
  }

  void _handleCameraIdle() {
    _cameraIsMoving = false;
    _nativeMapSettled = true;
    _scheduleSurfaceReady();
    final cameraGeneration = _cameraInteractionGeneration;
    final state = _radarBloc.state;
    if (state is RadarReady) {
      // A recovery owns the complete current/next warm-up. Starting the normal
      // debounce at the same time races on the cache generation and can cancel
      // the very operation that should resume playback after a rapid zoom.
      if (!_resumePlaybackAfterCameraMove) _schedulePrefetch(state);
      _armVisibleTileWatchdog(state);
      final selectedTemplate = state.selectedFrame.tileUrlTemplate;
      if (selectedTemplate != null) {
        _queueTileFrameTransition(
          selectedTemplate,
          modelSnapshot: state.selectedFrame.isModelForecast,
        );
      }
    }
    if (!_resumePlaybackAfterCameraMove) {
      _maybeStartAutoplay();
      return;
    }
    unawaited(_resumePlaybackWhenViewportReady(state, cameraGeneration));
  }

  Future<void> _resumePlaybackWhenViewportReady(
    RadarState state,
    int cameraGeneration,
  ) async {
    var viewportReady = true;
    if (state is RadarReady) {
      final template = state.selectedFrame.tileUrlTemplate;
      if (template != null) {
        viewportReady = false;
        final expectedTiles = math.min(_tileCache.recentCoordinateCount, 8);
        final ready = await _tileCache
            .prepareVisibleFrame(template, maxTiles: 8)
            .timeout(const Duration(seconds: 9), onTimeout: () => 0);
        if (!mounted || cameraGeneration != _cameraInteractionGeneration) {
          return;
        }
        final requiredReady = math.min(
          expectedTiles,
          math.max(4, (expectedTiles * 0.5).ceil()),
        );
        if (expectedTiles > 0 && ready >= requiredReady) {
          // Google Maps can retain NO_TILE from a request issued mid-gesture.
          // The bytes are now in Chetiwa's memory cache, so this repaint is
          // immediate instead of exposing an empty overlay for many seconds.
          final provider = _tileProviders[_frontTileSlot];
          provider?.resetPresentationTracking();
          await _clearRadarTileSlot(_frontTileSlot);
          final presented =
              provider != null &&
              await _waitForNativeTilePresentation(
                provider: provider,
                minimumCoordinates: math.min(ready, 4),
                // The bytes for the complete viewport were verified above.
                // iOS may cancel one off-screen native request as a zoom
                // settles; 90% native acknowledgement avoids treating that
                // cancellation as a missing visible weather tile.
                minimumCoverage: 0.9,
                isCurrent: () =>
                    cameraGeneration == _cameraInteractionGeneration &&
                    !_cameraIsMoving,
              );
          if (!mounted ||
              cameraGeneration != _cameraInteractionGeneration ||
              _cameraIsMoving) {
            return;
          }
          viewportReady = presented;
          // The next image is only an optimisation. The per-frame native
          // handoff gate already freezes the cursor if that image is late, so
          // a failed speculative request must never suspend the whole Radar.
          if (presented) unawaited(_warmPlaybackBuffer(state));
        } else {
          if (expectedTiles == 0) {
            // Google Maps may reuse its private tile cache after a zoom and
            // therefore not call our provider. Force one repaint so the new
            // viewport coordinates become observable instead of waiting in a
            // permanent zero-coordinate loop.
            _tileProviders[_frontTileSlot]?.resetPresentationTracking();
            await _clearRadarTileSlot(_frontTileSlot);
          }
          unawaited(_retryVisibleRadar(state));
          return;
        }
      }
    }
    if (!mounted ||
        cameraGeneration != _cameraInteractionGeneration ||
        !viewportReady) {
      if (mounted && !viewportReady && state is RadarReady) {
        unawaited(_retryVisibleRadar(state));
      }
      return;
    }
    _cameraPlaybackResumeTimer = Timer(const Duration(milliseconds: 80), () {
      if (!mounted ||
          cameraGeneration != _cameraInteractionGeneration ||
          !widget.isActive ||
          _timelineScrubbing ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      _resumePlaybackAfterCameraMove = false;
      _radarBloc.add(const RadarPlaybackResumed());
    });
  }

  void _armVisibleTileWatchdog(RadarReady state) {
    _visibleTileWatchdog?.cancel();
    if (!_radarVisible || state.selectedFrame.tileUrlTemplate == null) return;
    final baseline = _visibleTileSuccessBaseline;
    _visibleTileWatchdog = Timer(const Duration(seconds: 3), () {
      if (!mounted ||
          _cameraIsMoving ||
          _tileCache.successfulTileResponseCount.value > baseline) {
        return;
      }
      _reportTileIssue();
      final latest = _radarBloc.state;
      if (latest is RadarReady) unawaited(_retryVisibleRadar(latest));
    });
  }

  Future<void> _retryVisibleRadar(RadarReady state) async {
    if (!_mapReady || state.selectedFrame.tileUrlTemplate == null) return;
    final generation = ++_viewportRequestGeneration;
    setState(() {
      _radarTilesLoading = true;
      if (_tileCache.readyTileCount.value == 0 &&
          !_preparationDeadlineExpired) {
        _showTilePreparation = true;
      }
    });
    final expectedTiles = math.min(_tileCache.recentCoordinateCount, 8);
    final ready = await _tileCache.prefetchNextFrames(
      frameTemplates: [state.selectedFrame.tileUrlTemplate!],
      maxTiles: 8,
    );
    if (!mounted || generation != _viewportRequestGeneration) return;
    final requiredReady = math.min(
      expectedTiles,
      math.max(4, (expectedTiles * 0.5).ceil()),
    );
    if (expectedTiles == 0 || ready < requiredReady) {
      _reportTileIssue();
      setState(() {
        _radarTilesLoading = false;
        _showTilePreparation =
            !_preparationDeadlineExpired && !_frontViewportPresentationReady;
      });
      if (expectedTiles == 0) {
        _tileProviders[_frontTileSlot]?.resetPresentationTracking();
        await _clearRadarTileSlot(_frontTileSlot);
      }
      // A quick pan invalidates old viewport requests by design. Retry
      // silently with capped backoff until the active settled viewport has a
      // real presentation; clearing app data must never be the recovery path.
      _scheduleVisibleRadarRetry();
      return;
    }
    // Only invalidate the visible slot after the complete current viewport is
    // in memory. Clearing first made Google Maps race the network and cache
    // NO_TILE, which is exactly the 10-20 second blank/frozen state observed
    // after a long pan or zoom.
    final provider = _tileProviders[_frontTileSlot];
    provider?.resetPresentationTracking();
    await _clearRadarTileSlot(_frontTileSlot);
    final presented =
        provider != null &&
        await _waitForNativeTilePresentation(
          provider: provider,
          minimumCoordinates: math.min(ready, 4),
        );
    if (!mounted || generation != _viewportRequestGeneration) return;
    if (!presented) {
      _reportTileIssue();
      setState(() => _radarTilesLoading = false);
      _scheduleVisibleRadarRetry();
      return;
    }
    setState(() {
      _radarTilesLoading = false;
      _showTilePreparation = false;
    });
    _preparationEscapeTimer?.cancel();
    _visibleTileRetryCount = 0;
    final latest = _radarBloc.state;
    if (latest is RadarReady) {
      unawaited(_warmPlaybackBuffer(latest));
      if (_resumePlaybackAfterCameraMove &&
          widget.isActive &&
          !_timelineScrubbing) {
        _resumePlaybackAfterCameraMove = false;
        _radarBloc.add(const RadarPlaybackResumed());
      }
    }
  }

  void _scheduleVisibleRadarRetry() {
    if (_cameraIsMoving || !widget.isActive) return;
    _visibleTileRetryCount++;
    final delay = switch (_visibleTileRetryCount) {
      1 => const Duration(seconds: 1),
      2 => const Duration(seconds: 2),
      3 => const Duration(seconds: 4),
      4 => const Duration(seconds: 8),
      _ => const Duration(seconds: 15),
    };
    final retryGeneration = _cameraInteractionGeneration;
    _visibleTileWatchdog?.cancel();
    _visibleTileWatchdog = Timer(delay, () {
      if (!mounted ||
          _cameraIsMoving ||
          retryGeneration != _cameraInteractionGeneration) {
        return;
      }
      final latest = _radarBloc.state;
      if (latest is RadarReady) unawaited(_retryVisibleRadar(latest));
    });
  }

  Iterable<String> _currentAndNextFrameTemplates(RadarReady state) sync* {
    final currentTemplate = state.selectedFrame.tileUrlTemplate;
    if (currentTemplate != null) yield currentTemplate;
    final frameCount = state.frames.length;
    // One completely prepared frame ahead is enough at the two-second cadence
    // and avoids issuing three full viewports of speculative requests.
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
    const availableMaps = <_RadarBaseMap>[
      _RadarBaseMap.satellite,
      _RadarBaseMap.standard,
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
  const _RadarPreparingSurface({super.key});

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
    required this.frame,
    required this.pointRainRateMmPerHour,
  });

  final Forecast forecast;
  final DateTime selectedInstant;
  final RadarFrame frame;
  final double? pointRainRateMmPerHour;

  @override
  Widget build(BuildContext context) {
    final location = forecast.locationName.split(',').first;
    // Extended LibreWXR frames are advected radar echoes. Prefer their exact
    // point sample so the status cannot claim it is dry while the tile shows
    // the same echo crossing the marker. The weather model is only a fallback
    // when point sampling is temporarily unavailable.
    final modelRate =
        frame.pointRainRateMmPerHour ??
        forecast.rainPointAt(selectedInstant)?.rateMmPerHour;
    final usesRadarProjection =
        frame.isModelForecast && frame.pointRainRateMmPerHour != null;
    final modelAtPoint = modelRate == null
        ? (context.l10n.isFrench
              ? '$location · prévision au point indisponible'
              : '$location · point forecast unavailable')
        : modelRate < 0.05
        ? (context.l10n.isFrench
              ? '$location · ${usesRadarProjection ? 'projection radar' : 'modèle'} sèche au point'
              : '$location · ${usesRadarProjection ? 'radar projection' : 'model'} dry at point')
        : (context.l10n.isFrench
              ? '$location · ${usesRadarProjection ? 'projection radar' : 'modèle'} ${modelRate.toStringAsFixed(1)} mm/h au point'
              : '$location · ${usesRadarProjection ? 'radar projection' : 'model'} ${modelRate.toStringAsFixed(1)} mm/h at point');
    final observationDetail = context.l10n.isFrench
        ? '$location · image radar observée'
        : '$location · observed radar image';
    final frameState = frame.isModelForecast
        ? (context.l10n.isFrench
              ? 'prévision étendue · Chetiwa+'
              : 'extended forecast · Chetiwa+')
        : frame.isNowcast
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
        border: Border.all(
          color: frame.isModelForecast
              ? const Color(0xFF7A5AF8).withValues(alpha: 0.7)
              : ChetiwaColors.borderDefault,
        ),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: ChetiwaColors.textPrimary),
        child: Row(
          children: [
            Icon(
              frame.isModelForecast
                  ? Icons.query_stats_rounded
                  : frame.isNowcast
                  ? Icons.auto_graph_rounded
                  : Icons.radar_rounded,
              size: 15,
              color: frame.isModelForecast
                  ? const Color(0xFF7A5AF8)
                  : ChetiwaColors.accentPrimary,
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
                    frame.isModelForecast
                        ? modelAtPoint
                        : frame.isNowcast
                        ? nowcastAtPoint
                        : observationDetail,
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
  const _RadarLegend({required this.radarVisible, required this.frame});

  final bool radarVisible;
  final RadarFrame frame;

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
        border: Border.all(
          color: frame.isModelForecast
              ? const Color(0xFF7A5AF8).withValues(alpha: 0.65)
              : ChetiwaColors.borderDefault,
        ),
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
                          ? frame.isModelForecast
                                ? '${context.l10n.isFrench ? 'PRÉVISION PLUIE' : 'RAIN FORECAST'} · ${frame.providerName.toUpperCase()}'
                                : '${context.l10n.isFrench ? 'ÉCHOS RADAR' : 'RADAR ECHOES'} · ${frame.providerName.toUpperCase()}'
                          : (context.l10n.isFrench
                                ? 'CALQUE MASQUÉ'
                                : 'LAYER HIDDEN'),
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: frame.isModelForecast
                        ? (context.l10n.isFrench
                              ? 'Prévision étendue par extrapolation du déplacement radar. La même cellule est advectée côté serveur ; après 60 min, sa position devient plus incertaine. Ce n’est ni une observation radar ni une carte de nuages.'
                              : 'Extended forecast extrapolated from radar motion. The same cell is advected on the server; after 60 minutes, its position becomes less certain. This is neither a radar observation nor a cloud map.')
                        : (context.l10n.isFrench
                              ? 'Gris = écho faible ou incertain, rose = pluie modérée, rouge = pluie forte. Ce calque ne montre pas les nuages.'
                              : 'Grey = weak or uncertain echo, pink = moderate rain, red = heavy rain. This layer does not show clouds.'),
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
    required this.playbackProgress,
    this.scrubFraction,
    this.modelForecastLocked = false,
    this.onScrubStarted,
    this.onScrubEnded,
    super.key,
  });

  final RadarReady state;
  final Forecast forecast;
  final ForecastSnapshot snapshot;
  final Animation<double> playbackProgress;
  final ValueNotifier<double?>? scrubFraction;
  final bool modelForecastLocked;
  final VoidCallback? onScrubStarted;
  final VoidCallback? onScrubEnded;

  @override
  Widget build(BuildContext context) {
    final timelineColors = _RadarTimelineColors.of(context);
    final nowInstant = snapshot.nowUtc;
    final alignedForecast = alignForecastWithRadarNowcast(
      forecast,
      state.frames,
      nowInstant,
    );
    final timelineWindow = RadarFramePolicy.timelineWindow(
      state.frames,
      nowInstant,
    );
    final graphEnd = timelineWindow.end;
    final premiumEnd = nowInstant.add(const Duration(hours: 2));
    final displayEnd = modelForecastLocked && premiumEnd.isAfter(graphEnd)
        ? premiumEnd
        : graphEnd;
    final rainPoints = <RainPoint>[
      snapshot.currentRain,
      ...alignedForecast.points.where(
        (point) =>
            point.time.isAfter(nowInstant) && !point.time.isAfter(graphEnd),
      ),
    ];
    return Semantics(
      key: const Key('radar-local-time'),
      label:
          '${context.l10n.isFrench ? 'Chronologie radar · heure du téléphone' : 'Radar timeline · phone time'} · '
          '${WeatherTimeZone.displayUtcOffsetLabel(state.selectedFrame.time)} · '
          '${WeatherTimeZone.displayHourMinute(state.selectedFrame.time)}',
      child: Container(
        height: 104,
        padding: const EdgeInsets.fromLTRB(14, 5, 14, 7),
        decoration: BoxDecoration(
          // The map must never bleed through time labels or the scrubber.
          // Full opacity also keeps this panel readable over bright satellite
          // imagery and dense city labels.
          color: timelineColors.surface,
          border: Border(top: BorderSide(color: timelineColors.outline)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            key: const Key('radar-time-ruler'),
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              onScrubStarted?.call();
              _selectFrame(
                context,
                details.localPosition.dx,
                constraints.maxWidth,
                displayEnd,
              );
            },
            onTapUp: (_) => _endScrub(),
            onTapCancel: _endScrub,
            onHorizontalDragStart: (details) {
              onScrubStarted?.call();
              _selectFrame(
                context,
                details.localPosition.dx,
                constraints.maxWidth,
                displayEnd,
              );
            },
            onHorizontalDragUpdate: (details) => _selectFrame(
              context,
              details.localPosition.dx,
              constraints.maxWidth,
              displayEnd,
            ),
            onHorizontalDragEnd: (_) => _endScrub(),
            onHorizontalDragCancel: _endScrub,
            child: Semantics(
              label: modelForecastLocked
                  ? (context.l10n.isFrench
                        ? 'Prévision pluie étendue de 60 à 120 minutes réservée à Chetiwa+'
                        : 'Extended rain forecast from 60 to 120 minutes reserved for Chetiwa+')
                  : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedBuilder(
                    animation: Listenable.merge(<Listenable>[
                      playbackProgress,
                      if (scrubFraction != null) scrubFraction!,
                    ]),
                    builder: (context, _) => CustomPaint(
                      key: ValueKey(
                        '${state.frames.any((frame) => frame.isNowcast && frame.pointRainRateMmPerHour != null) ? 'radar-point-profile-visible' : 'radar-point-profile-unavailable'}-${modelForecastLocked ? 'premium-locked' : 'premium-open'}',
                      ),
                      painter: _RadarTimeRulerPainter(
                        frames: state.frames,
                        rainPoints: rainPoints,
                        cursorTime: _cursorTime(context, displayEnd),
                        now: nowInstant,
                        displayEnd: displayEnd,
                        modelForecastLocked: modelForecastLocked,
                        colors: timelineColors,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  if (modelForecastLocked ||
                      state.frames.any((frame) => frame.isModelForecast))
                    Align(
                      alignment: Alignment.topRight,
                      child: const Padding(
                        padding: EdgeInsets.only(top: 6, right: 7),
                        child: Text(
                          'PRÉVISION ÉTENDUE · 10 MIN',
                          style: TextStyle(
                            color: Color(0xFF7A5AF8),
                            fontSize: 7,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _selectFrame(
    BuildContext context,
    double x,
    double width,
    DateTime displayEnd,
  ) {
    if (state.frames.length < 2 || width <= 0) return;
    final fraction = (x / width).clamp(0.0, 1.0).toDouble();
    scrubFraction?.value = fraction;
    final hasForecast = state.hasForecast;
    final startIndex = hasForecast ? state.currentObservationIndex : 0;
    final endIndex = hasForecast
        ? state.frames.length - 1
        : state.currentObservationIndex;
    final window = RadarFramePolicy.timelineWindow(
      state.frames,
      snapshot.nowUtc,
    );
    final start = window.start.millisecondsSinceEpoch;
    final end = displayEnd.millisecondsSinceEpoch;
    final selectedTime = start + ((end - start) * fraction).toDouble();
    if (modelForecastLocked &&
        selectedTime > window.end.millisecondsSinceEpoch) {
      context.push('/subscription');
      return;
    }
    var index = startIndex;
    var nearestDistance = double.infinity;
    for (var candidate = startIndex; candidate <= endIndex; candidate++) {
      final effectiveTime = hasForecast
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

  void _endScrub() {
    scrubFraction?.value = null;
    onScrubEnded?.call();
  }

  DateTime _cursorTime(BuildContext context, DateTime displayEnd) {
    final activeScrub = scrubFraction?.value;
    if (activeScrub != null) {
      final window = RadarFramePolicy.timelineWindow(
        state.frames,
        snapshot.nowUtc,
      );
      final elapsedMicroseconds = displayEnd
          .difference(window.start)
          .inMicroseconds;
      if (elapsedMicroseconds <= 0) return window.start;
      return window.start.add(
        Duration(microseconds: (elapsedMicroseconds * activeScrub).round()),
      );
    }
    final selected = state.selectedFrame.time;
    if (!state.isPlaying ||
        MediaQuery.maybeOf(context)?.disableAnimations == true ||
        state.selectedIndex >= state.frames.length - 1) {
      return selected;
    }
    final nextFrame = state.frames[state.selectedIndex + 1];
    // LibreWXR supplies optical-flow-interpolated ten-minute frames across the
    // complete product. The playhead therefore remains continuous through the
    // +60-minute boundary without inventing an unsupported image.
    final next = nextFrame.time;
    return RadarFramePolicy.interpolateFrameTime(
      selected,
      next,
      playbackProgress.value,
    );
  }
}

final class _RadarTimeRulerPainter extends CustomPainter {
  const _RadarTimeRulerPainter({
    required this.frames,
    required this.rainPoints,
    required this.cursorTime,
    required this.now,
    required this.displayEnd,
    required this.modelForecastLocked,
    required this.colors,
  });

  final List<RadarFrame> frames;
  final List<RainPoint> rainPoints;
  final DateTime cursorTime;
  final DateTime now;
  final DateTime displayEnd;
  final bool modelForecastLocked;
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
    final hasForecast = frames.any((frame) => frame.isForecast);
    final playbackStartIndex = hasForecast ? observationIndex : 0;
    final playbackEndIndex = hasForecast ? frames.length - 1 : observationIndex;
    final window = RadarFramePolicy.timelineWindow(frames, now);
    final start = window.start;
    final end = displayEnd;
    final durationMs = math
        .max(1, end.millisecondsSinceEpoch - start.millisecondsSinceEpoch)
        .toDouble();

    double xForTime(DateTime time) =>
        (size.width *
                (time.millisecondsSinceEpoch - start.millisecondsSinceEpoch) /
                durationMs)
            .toDouble();

    final lastNowcast = frames.lastWhere(
      (frame) => frame.isNowcast,
      orElse: () => frames[observationIndex],
    );
    final hasModelSegment =
        modelForecastLocked || frames.any((frame) => frame.isModelForecast);
    if (hasModelSegment) {
      final boundary = lastNowcast.isNowcast
          ? lastNowcast.time
          : now.add(RadarFramePolicy.nowcastHorizon);
      final boundaryX = xForTime(boundary).clamp(0, size.width).toDouble();
      canvas.drawRect(
        Rect.fromLTRB(boundaryX, chartTop, size.width, trackY + 5),
        Paint()..color = const Color(0xFF7A5AF8).withValues(alpha: 0.08),
      );
      final divider = Paint()
        ..color = const Color(0xFF7A5AF8).withValues(alpha: 0.65)
        ..strokeWidth = 1;
      for (var y = chartTop; y < trackY + 5; y += 5) {
        canvas.drawLine(
          Offset(boundaryX, y),
          Offset(boundaryX, math.min(y + 2.5, trackY + 5)),
          divider,
        );
      }
    }

    final track = Paint()
      ..color = colors.outline
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset.zero.translate(0, trackY),
      Offset(size.width, trackY),
      track,
    );

    if (hasForecast) {
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
      historical: !hasForecast,
    );

    final nowX = hasForecast ? 0.0 : size.width;
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
        (nowX - (hasForecast ? 0 : nowLabel.width))
            .clamp(0, size.width - nowLabel.width)
            .toDouble(),
        chartTop,
      ),
    );

    final selectedTime = hasForecast && cursorTime.isBefore(start)
        ? start
        : cursorTime;
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
      cursorTime != oldDelegate.cursorTime ||
      rainPoints != oldDelegate.rainPoints ||
      now != oldDelegate.now ||
      displayEnd != oldDelegate.displayEnd ||
      modelForecastLocked != oldDelegate.modelForecastLocked ||
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
