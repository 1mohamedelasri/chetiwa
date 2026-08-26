import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/location/coordinates.dart';
import '../../../core/time/weather_clock.dart';
import '../../../core/weather/weather_data_health.dart';
import '../domain/entities/radar_frame.dart';
import '../domain/repositories/radar_repository.dart';
import '../domain/services/radar_frame_policy.dart';

sealed class RadarEvent extends Equatable {
  const RadarEvent();

  @override
  List<Object?> get props => [];
}

final class RadarRequested extends RadarEvent {
  const RadarRequested();
}

/// Silent refresh while the radar screen stays open. It does not count as a
/// new user radar session and keeps the currently visible frames/playback.
final class RadarRefreshed extends RadarEvent {
  const RadarRefreshed();
}

final class RadarLocationChanged extends RadarEvent {
  const RadarLocationChanged(this.coordinates);

  final Coordinates coordinates;

  @override
  List<Object> get props => [coordinates];
}

final class RadarPremiumAccessChanged extends RadarEvent {
  const RadarPremiumAccessChanged({
    required this.allowModelForecast,
    required this.maxFrames,
    required this.historyHours,
  });

  final bool allowModelForecast;
  final int maxFrames;
  final int historyHours;

  @override
  List<Object> get props => [allowModelForecast, maxFrames, historyHours];
}

final class RadarFrameSelected extends RadarEvent {
  const RadarFrameSelected(this.index);

  final int index;

  @override
  List<Object> get props => [index];
}

final class RadarPlaybackToggled extends RadarEvent {
  const RadarPlaybackToggled();
}

/// Idempotent UI autoplay request sent only after the first visible tile is
/// ready. Unlike a toggle, duplicate readiness callbacks cannot pause Radar.
final class RadarPlaybackStarted extends RadarEvent {
  const RadarPlaybackStarted();
}

final class RadarPlaybackPaused extends RadarEvent {
  const RadarPlaybackPaused();
}

/// Temporarily stops playback while the application is not visible. Unlike
/// [RadarPlaybackPaused], this remembers that playback must resume after the
/// next successful refresh.
final class RadarPlaybackSuspended extends RadarEvent {
  const RadarPlaybackSuspended();
}

/// Resumes only playback that was running before an application suspension.
/// A user-paused animation remains paused.
final class RadarPlaybackResumed extends RadarEvent {
  const RadarPlaybackResumed();
}

final class RadarPlaybackAdvanced extends RadarEvent {
  const RadarPlaybackAdvanced();
}

final class RadarNowRequested extends RadarEvent {
  const RadarNowRequested();
}

final class RadarPlaybackRestarted extends RadarEvent {
  const RadarPlaybackRestarted();
}

sealed class RadarState extends Equatable {
  const RadarState();

  @override
  List<Object?> get props => [];
}

final class RadarInitial extends RadarState {
  const RadarInitial();
}

final class RadarLoading extends RadarState {
  const RadarLoading();
}

final class RadarReady extends RadarState {
  const RadarReady({
    required this.frames,
    required this.selectedIndex,
    required this.coordinates,
    this.health = const WeatherDataHealth(),
    this.isPlaying = false,
  });

  final List<RadarFrame> frames;
  final int selectedIndex;
  final Coordinates coordinates;
  final WeatherDataHealth health;
  final bool isPlaying;

  bool get isRefreshing => health.isRefreshing;
  bool get isStale => health.isStale;

  RadarFrame get selectedFrame => frames[selectedIndex];

  int get currentObservationIndex {
    final index = frames.lastIndexWhere((frame) => frame.isObservation);
    return index < 0 ? frames.length - 1 : index;
  }

  bool get hasNowcast => frames.any((frame) => frame.isNowcast);
  bool get hasForecast => frames.any((frame) => frame.isForecast);

  int get playbackStartIndex {
    if (hasForecast) return currentObservationIndex;
    final index = frames.indexWhere((frame) => frame.isObservation);
    return index < 0 ? 0 : index;
  }

  bool get isAtLatestObservation => selectedIndex == currentObservationIndex;

  @override
  List<Object> get props => [
    frames,
    selectedIndex,
    coordinates,
    health,
    isPlaying,
  ];
}

final class RadarFailure extends RadarState {
  const RadarFailure(this.issue);

  final WeatherDataIssue issue;

  @override
  List<Object> get props => [issue];
}

final class RadarBloc extends Bloc<RadarEvent, RadarState> {
  RadarBloc(
    this._repository, {
    WeatherClock clock = const SystemWeatherClock(),
    int maxFrames = 24,
    int? historyHours,
    bool allowModelForecast = false,
  }) : _clock = clock,
       _maxFrames = maxFrames,
       _historyHours = historyHours,
       _allowModelForecast = allowModelForecast,
       super(const RadarInitial()) {
    on<RadarRequested>(_load);
    on<RadarRefreshed>(_load);
    on<RadarLocationChanged>(_changeLocation);
    on<RadarPremiumAccessChanged>(_changePremiumAccess);
    on<RadarFrameSelected>(_selectFrame);
    on<RadarPlaybackToggled>(_togglePlayback);
    on<RadarPlaybackStarted>(_startPlayback);
    on<RadarPlaybackPaused>(_pausePlayback);
    on<RadarPlaybackSuspended>(_suspendPlayback);
    on<RadarPlaybackResumed>(_resumePlayback);
    on<RadarPlaybackAdvanced>(_advancePlayback);
    on<RadarNowRequested>(_goToNow);
    on<RadarPlaybackRestarted>(_restartPlayback);
  }

  final RadarRepository _repository;
  final WeatherClock _clock;
  int _maxFrames;
  int? _historyHours;
  bool _allowModelForecast;
  Coordinates _coordinates = Coordinates.paris;
  Timer? _playbackTimer;
  var _loadGeneration = 0;
  var _resumeAfterSuspension = false;

  Future<void> _load(RadarEvent event, Emitter<RadarState> emit) async {
    final generation = ++_loadGeneration;
    final requestedCoordinates = _coordinates;
    final backgroundRefresh = event is RadarRefreshed && state is RadarReady;
    final wasPlaying =
        _resumeAfterSuspension ||
        switch (state) {
          RadarReady(:final isPlaying) => isPlaying,
          _ => false,
        };
    _stopPlayback();
    RadarReady? visible;
    final activeBeforeRefresh = state;
    if (backgroundRefresh && activeBeforeRefresh is RadarReady) {
      visible = RadarReady(
        frames: activeBeforeRefresh.frames,
        selectedIndex: activeBeforeRefresh.selectedIndex,
        coordinates: activeBeforeRefresh.coordinates,
        health: WeatherDataHealth(
          freshness: activeBeforeRefresh.health.freshness,
          cachedAt: activeBeforeRefresh.health.cachedAt,
          issue: activeBeforeRefresh.health.issue,
          isRefreshing: true,
        ),
        isPlaying: wasPlaying,
      );
      emit(visible);
      if (wasPlaying && visible.frames.length > 1) {
        _startPlaybackTimer();
      }
    } else {
      final cached = await _repository.getCachedFrames(requestedCoordinates);
      if (generation != _loadGeneration || emit.isDone) return;
      if (cached != null) {
        visible = RadarReady(
          frames: _limitFrames(cached.frames),
          selectedIndex: _defaultIndex(_limitFrames(cached.frames)),
          coordinates: requestedCoordinates,
          health: WeatherDataHealth(
            freshness: cached.isStaleAt(_clock.nowUtc)
                ? WeatherDataFreshness.cachedStale
                : WeatherDataFreshness.cachedFresh,
            cachedAt: cached.cachedAt,
            isRefreshing: true,
          ),
          isPlaying: wasPlaying,
        );
        emit(visible);
        if (wasPlaying && visible.frames.length > 1) {
          _resumeAfterSuspension = false;
          _startPlaybackTimer();
        }
      } else {
        emit(const RadarLoading());
      }
    }
    try {
      final frames = _limitFrames(
        await _repository.getFrames(requestedCoordinates),
      );
      // A location can change while cache/network work is in flight. Never
      // allow an older response (for example Paris) to overwrite the newer
      // selected place (for example Lyon).
      if (generation != _loadGeneration || emit.isDone) return;
      final active = state;
      final continuePlaying =
          frames.length > 1 &&
          (wasPlaying ||
              active is RadarReady &&
                  active.coordinates == requestedCoordinates &&
                  active.isPlaying);
      final selectedIndex =
          active is RadarReady && active.coordinates == requestedCoordinates
          ? _nearestFrameIndex(frames, active.selectedFrame.time)
          : _defaultIndex(frames);
      emit(
        RadarReady(
          frames: frames,
          selectedIndex: selectedIndex,
          coordinates: requestedCoordinates,
          isPlaying: continuePlaying,
        ),
      );
      if (continuePlaying) {
        _resumeAfterSuspension = false;
        _startPlaybackTimer();
      }
    } on Object catch (error) {
      if (generation != _loadGeneration || emit.isDone) return;
      final issue = weatherDataIssueFrom(error);
      if (visible != null) {
        final active = state;
        final continuePlaying =
            visible.frames.length > 1 &&
            (wasPlaying ||
                active is RadarReady &&
                    active.coordinates == requestedCoordinates &&
                    active.isPlaying);
        emit(
          RadarReady(
            frames: visible.frames,
            selectedIndex: visible.selectedIndex,
            coordinates: visible.coordinates,
            health: WeatherDataHealth(
              freshness: visible.health.freshness,
              cachedAt: visible.health.cachedAt,
              issue: issue,
            ),
            isPlaying: continuePlaying,
          ),
        );
        if (continuePlaying) {
          _resumeAfterSuspension = false;
          _startPlaybackTimer();
        } else {
          _stopPlayback();
        }
      } else {
        emit(RadarFailure(issue));
      }
    }
  }

  List<RadarFrame> _limitFrames(List<RadarFrame> frames) {
    var visible = _allowModelForecast
        ? frames
        : frames
              .where((frame) => !frame.isModelForecast)
              .toList(growable: false);
    final hours = _historyHours;
    if (hours != null && hours > 0 && visible.isNotEmpty) {
      final cutoff = _clock.nowUtc.subtract(Duration(hours: hours));
      final withinHistory = visible
          .where((frame) => !frame.time.isBefore(cutoff))
          .toList(growable: false);
      // Keep at least one frame when provider and device clocks differ.
      if (withinHistory.isNotEmpty) visible = withinHistory;
    }
    if (visible.length <= _maxFrames) return visible;
    // Keep the newest observation and the nearest nowcast frames. Providers
    // return frames chronologically, so a tail slice is the least surprising
    // history reduction for both playback and cache memory.
    return visible.sublist(visible.length - _maxFrames);
  }

  void _selectFrame(RadarFrameSelected event, Emitter<RadarState> emit) {
    final current = state;
    if (current is! RadarReady) return;
    final index = event.index.clamp(0, current.frames.length - 1);
    emit(
      RadarReady(
        frames: current.frames,
        selectedIndex: index,
        coordinates: current.coordinates,
        health: current.health,
        isPlaying: current.isPlaying,
      ),
    );
  }

  void _togglePlayback(RadarPlaybackToggled event, Emitter<RadarState> emit) {
    final current = state;
    if (current is! RadarReady || current.frames.length < 2) return;

    if (current.isPlaying) {
      _resumeAfterSuspension = false;
      _stopPlayback();
      emit(_copyReady(current, isPlaying: false));
      return;
    }

    final resumeIndex = current.selectedIndex >= current.frames.length - 1
        ? current.playbackStartIndex
        : current.selectedIndex;
    emit(_copyReady(current, selectedIndex: resumeIndex, isPlaying: true));
    _resumeAfterSuspension = false;
    _startPlaybackTimer();
  }

  void _startPlayback(RadarPlaybackStarted event, Emitter<RadarState> emit) {
    final current = state;
    if (current is! RadarReady ||
        current.frames.length < 2 ||
        current.isPlaying) {
      return;
    }
    final startIndex = current.selectedIndex >= current.frames.length - 1
        ? current.playbackStartIndex
        : current.selectedIndex;
    emit(_copyReady(current, selectedIndex: startIndex, isPlaying: true));
    _resumeAfterSuspension = false;
    _startPlaybackTimer();
  }

  void _pausePlayback(RadarPlaybackPaused event, Emitter<RadarState> emit) {
    final current = state;
    _resumeAfterSuspension = false;
    if (current is! RadarReady || !current.isPlaying) return;
    _stopPlayback();
    emit(_copyReady(current, isPlaying: false));
  }

  void _suspendPlayback(
    RadarPlaybackSuspended event,
    Emitter<RadarState> emit,
  ) {
    final current = state;
    if (current is! RadarReady) return;
    // Mobile platforms commonly send inactive and then paused for one sleep.
    // Preserve the first event's playback intent instead of clearing it when
    // the second event observes the already-suspended state.
    _resumeAfterSuspension = _resumeAfterSuspension || current.isPlaying;
    _stopPlayback();
    if (current.isPlaying) emit(_copyReady(current, isPlaying: false));
  }

  void _resumePlayback(RadarPlaybackResumed event, Emitter<RadarState> emit) {
    final current = state;
    if (!_resumeAfterSuspension ||
        current is! RadarReady ||
        current.frames.length < 2 ||
        current.isPlaying) {
      return;
    }
    _resumeAfterSuspension = false;
    emit(_copyReady(current, isPlaying: true));
    _startPlaybackTimer();
  }

  void _advancePlayback(RadarPlaybackAdvanced event, Emitter<RadarState> emit) {
    final current = state;
    if (current is! RadarReady || !current.isPlaying) return;
    if (current.selectedIndex >= current.frames.length - 1) {
      emit(
        _copyReady(
          current,
          selectedIndex: current.playbackStartIndex,
          isPlaying: true,
        ),
      );
      return;
    }
    emit(
      _copyReady(
        current,
        selectedIndex: current.selectedIndex + 1,
        isPlaying: true,
      ),
    );
  }

  void _goToNow(RadarNowRequested event, Emitter<RadarState> emit) {
    final current = state;
    if (current is! RadarReady) return;
    emit(
      _copyReady(
        current,
        selectedIndex: current.currentObservationIndex,
        isPlaying: current.isPlaying,
      ),
    );
  }

  void _restartPlayback(
    RadarPlaybackRestarted event,
    Emitter<RadarState> emit,
  ) {
    final current = state;
    if (current is! RadarReady || current.frames.length < 2) return;
    _stopPlayback();
    emit(
      _copyReady(
        current,
        selectedIndex: current.playbackStartIndex,
        isPlaying: true,
      ),
    );
    _startPlaybackTimer();
  }

  RadarReady _copyReady(
    RadarReady state, {
    int? selectedIndex,
    required bool isPlaying,
  }) => RadarReady(
    frames: state.frames,
    selectedIndex: selectedIndex ?? state.selectedIndex,
    coordinates: state.coordinates,
    health: state.health,
    isPlaying: isPlaying,
  );

  void _stopPlayback() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
  }

  void _startPlaybackTimer() {
    _stopPlayback();
    _playbackTimer = Timer.periodic(
      RadarFramePolicy.playbackFrameDuration,
      (_) => add(const RadarPlaybackAdvanced()),
    );
  }

  Future<void> _changeLocation(
    RadarLocationChanged event,
    Emitter<RadarState> emit,
  ) async {
    _coordinates = event.coordinates;
    await _load(const RadarRequested(), emit);
  }

  Future<void> _changePremiumAccess(
    RadarPremiumAccessChanged event,
    Emitter<RadarState> emit,
  ) async {
    if (_allowModelForecast == event.allowModelForecast &&
        _maxFrames == event.maxFrames &&
        _historyHours == event.historyHours) {
      return;
    }
    _allowModelForecast = event.allowModelForecast;
    _maxFrames = event.maxFrames;
    _historyHours = event.historyHours;

    final current = state;
    if (current is RadarReady) {
      final visible = _limitFrames(current.frames);
      if (visible.isNotEmpty) {
        emit(
          RadarReady(
            frames: visible,
            selectedIndex: _nearestFrameIndex(
              visible,
              current.selectedFrame.time,
            ),
            coordinates: current.coordinates,
            health: current.health,
            isPlaying: current.isPlaying && visible.length > 1,
          ),
        );
      }
      await _load(const RadarRefreshed(), emit);
    }
  }

  int _defaultIndex(List<RadarFrame> frames) {
    final latestObservation = frames.lastIndexWhere(
      (frame) => frame.isObservation,
    );
    return latestObservation < 0 ? frames.length - 1 : latestObservation;
  }

  int _nearestFrameIndex(List<RadarFrame> frames, DateTime instant) {
    var nearestIndex = 0;
    var nearestDistance = frames.first.time.difference(instant).abs();
    for (var index = 1; index < frames.length; index++) {
      final distance = frames[index].time.difference(instant).abs();
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
    }
    return nearestIndex;
  }

  @override
  Future<void> close() {
    _stopPlayback();
    return super.close();
  }
}
