import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/location/coordinates.dart';
import '../../../core/time/weather_clock.dart';
import '../../../core/weather/weather_data_health.dart';
import '../../monetization/application/usage_quota_controller.dart';
import '../domain/entities/radar_frame.dart';
import '../domain/repositories/radar_repository.dart';

sealed class RadarEvent extends Equatable {
  const RadarEvent();

  @override
  List<Object?> get props => [];
}

final class RadarRequested extends RadarEvent {
  const RadarRequested();
}

final class RadarLocationChanged extends RadarEvent {
  const RadarLocationChanged(this.coordinates);

  final Coordinates coordinates;

  @override
  List<Object> get props => [coordinates];
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

final class RadarPlaybackPaused extends RadarEvent {
  const RadarPlaybackPaused();
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

  int get playbackStartIndex {
    if (hasNowcast) return currentObservationIndex;
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
    UsageQuotaController? usageQuota,
  }) : _clock = clock,
       _maxFrames = maxFrames,
       _historyHours = historyHours,
       _usageQuota = usageQuota,
       super(const RadarInitial()) {
    on<RadarRequested>(_load);
    on<RadarLocationChanged>(_changeLocation);
    on<RadarFrameSelected>(_selectFrame);
    on<RadarPlaybackToggled>(_togglePlayback);
    on<RadarPlaybackPaused>(_pausePlayback);
    on<RadarPlaybackAdvanced>(_advancePlayback);
    on<RadarNowRequested>(_goToNow);
    on<RadarPlaybackRestarted>(_restartPlayback);
  }

  final RadarRepository _repository;
  final WeatherClock _clock;
  final int _maxFrames;
  final int? _historyHours;
  final UsageQuotaController? _usageQuota;
  Coordinates _coordinates = Coordinates.paris;
  Timer? _playbackTimer;
  var _loadGeneration = 0;

  Future<void> _load(RadarRequested event, Emitter<RadarState> emit) async {
    final generation = ++_loadGeneration;
    final requestedCoordinates = _coordinates;
    _stopPlayback();
    RadarReady? visible;
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
      );
      emit(visible);
    } else {
      emit(const RadarLoading());
    }
    try {
      await _usageQuota?.consumeRadarSession();
      final frames = _limitFrames(
        await _repository.getFrames(requestedCoordinates),
      );
      // A location can change while cache/network work is in flight. Never
      // allow an older response (for example Paris) to overwrite the newer
      // selected place (for example Lyon).
      if (generation != _loadGeneration || emit.isDone) return;
      emit(
        RadarReady(
          frames: frames,
          selectedIndex: _defaultIndex(frames),
          coordinates: requestedCoordinates,
        ),
      );
    } on Object catch (error) {
      if (generation != _loadGeneration || emit.isDone) return;
      final issue = weatherDataIssueFrom(error);
      if (visible != null) {
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
          ),
        );
      } else {
        emit(RadarFailure(issue));
      }
    }
  }

  List<RadarFrame> _limitFrames(List<RadarFrame> frames) {
    var visible = frames;
    final hours = _historyHours;
    if (hours != null && hours > 0 && frames.isNotEmpty) {
      final cutoff = _clock.nowUtc.subtract(Duration(hours: hours));
      final withinHistory = frames
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
      _stopPlayback();
      emit(_copyReady(current, isPlaying: false));
      return;
    }

    emit(
      _copyReady(
        current,
        selectedIndex: current.playbackStartIndex,
        isPlaying: true,
      ),
    );
    _startPlaybackTimer();
  }

  void _pausePlayback(RadarPlaybackPaused event, Emitter<RadarState> emit) {
    final current = state;
    if (current is! RadarReady || !current.isPlaying) return;
    _stopPlayback();
    emit(_copyReady(current, isPlaying: false));
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
    _stopPlayback();
    emit(
      _copyReady(
        current,
        selectedIndex: current.currentObservationIndex,
        isPlaying: false,
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
    _playbackTimer = Timer.periodic(
      // Leave enough time for a physical device to fetch and decode the next
      // radar tiles before advancing again. The tile layer still transitions
      // quickly, but a slow mobile connection no longer skips every image.
      const Duration(milliseconds: 900),
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

  int _defaultIndex(List<RadarFrame> frames) {
    final latestObservation = frames.lastIndexWhere(
      (frame) => frame.isObservation,
    );
    return latestObservation < 0 ? frames.length - 1 : latestObservation;
  }

  @override
  Future<void> close() {
    _stopPlayback();
    return super.close();
  }
}
