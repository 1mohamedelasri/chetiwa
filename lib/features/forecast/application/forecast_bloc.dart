import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/location/coordinates.dart';
import '../../../core/location/location_repository.dart';
import '../../../core/time/weather_clock.dart';
import '../../../core/weather/weather_data_health.dart';
import '../domain/entities/forecast.dart';
import '../domain/repositories/forecast_repository.dart';
import '../domain/services/forecast_snapshot_builder.dart';

sealed class ForecastEvent extends Equatable {
  const ForecastEvent();

  @override
  List<Object?> get props => [];
}

final class ForecastRequested extends ForecastEvent {
  const ForecastRequested();
}

final class ForecastRefreshed extends ForecastEvent {
  const ForecastRefreshed();
}

final class ForecastClockTicked extends ForecastEvent {
  const ForecastClockTicked();
}

final class ForecastLocationChanged extends ForecastEvent {
  const ForecastLocationChanged(this.location);

  final ChetiwaLocation location;

  @override
  List<Object> get props => [location];
}

sealed class ForecastState extends Equatable {
  const ForecastState();

  @override
  List<Object?> get props => [];
}

final class ForecastInitial extends ForecastState {
  const ForecastInitial();
}

final class ForecastLoading extends ForecastState {
  const ForecastLoading();
}

final class ForecastReady extends ForecastState {
  const ForecastReady(
    this.forecast, {
    required this.snapshot,
    this.health = const WeatherDataHealth(),
  });

  final Forecast forecast;
  final ForecastSnapshot snapshot;
  final WeatherDataHealth health;

  bool get isRefreshing => health.isRefreshing;
  bool get isStale => health.isStale;

  @override
  List<Object> get props => [forecast, snapshot, health];
}

final class ForecastFailure extends ForecastState {
  const ForecastFailure(this.issue);

  final WeatherDataIssue issue;

  @override
  List<Object> get props => [issue];
}

final class ForecastBloc extends Bloc<ForecastEvent, ForecastState> {
  ForecastBloc(
    this._repository, {
    WeatherClock clock = const SystemWeatherClock(),
    LocationRepository? locationRepository,
  }) : _clock = clock,
       _locationRepository = locationRepository,
       super(const ForecastInitial()) {
    on<ForecastRequested>(_load);
    on<ForecastRefreshed>(_load);
    on<ForecastLocationChanged>(_changeLocation);
    on<ForecastClockTicked>(_tick);
    _scheduleClockTick();
  }

  final ForecastRepository _repository;
  final WeatherClock _clock;
  final LocationRepository? _locationRepository;
  Coordinates _coordinates = Coordinates.paris;
  String? _selectedLocationName;
  Timer? _clockTimer;
  var _didRestoreMainLocation = false;

  Forecast _withSelectedLocation(Forecast forecast) =>
      _selectedLocationName == null
      ? forecast
      : forecast.copyWith(locationName: _selectedLocationName);

  ForecastReady _ready(
    Forecast forecast, {
    WeatherDataHealth health = const WeatherDataHealth(),
  }) => ForecastReady(
    forecast,
    snapshot: ForecastSnapshotBuilder.build(
      forecast: forecast,
      nowUtc: _clock.nowUtc,
    ),
    health: health,
  );

  Future<void> _load(ForecastEvent event, Emitter<ForecastState> emit) async {
    if (event is ForecastRequested && !_didRestoreMainLocation) {
      _didRestoreMainLocation = true;
      final savedLocation = await _locationRepository?.getMainLocation();
      if (savedLocation != null) {
        _coordinates = savedLocation.coordinates;
        _selectedLocationName = savedLocation.label;
      }
    }
    ForecastReady? visible =
        event is! ForecastLocationChanged && state is ForecastReady
        ? state as ForecastReady
        : null;
    if (event is! ForecastRefreshed) {
      final cached = await _repository.getCachedForecast(_coordinates);
      if (cached != null) {
        visible = _ready(
          _withSelectedLocation(cached.forecast),
          health: WeatherDataHealth(
            freshness: cached.isStaleAt(_clock.nowUtc)
                ? WeatherDataFreshness.cachedStale
                : WeatherDataFreshness.cachedFresh,
            cachedAt: cached.cachedAt,
            isRefreshing: true,
          ),
        );
        emit(visible);
      }
    }
    if (visible == null) {
      emit(const ForecastLoading());
    } else if (!visible.isRefreshing) {
      visible = _ready(
        visible.forecast,
        health: WeatherDataHealth(
          freshness: visible.health.freshness,
          cachedAt: visible.health.cachedAt,
          issue: visible.health.issue,
          isRefreshing: true,
        ),
      );
      emit(visible);
    }
    try {
      emit(
        _ready(
          _withSelectedLocation(await _repository.getForecast(_coordinates)),
        ),
      );
    } on Object catch (error) {
      final issue = weatherDataIssueFrom(error);
      if (visible != null) {
        emit(
          _ready(
            visible.forecast,
            health: WeatherDataHealth(
              freshness: visible.health.freshness,
              cachedAt: visible.health.cachedAt,
              issue: issue,
            ),
          ),
        );
      } else {
        emit(ForecastFailure(issue));
      }
    }
  }

  Future<void> _changeLocation(
    ForecastLocationChanged event,
    Emitter<ForecastState> emit,
  ) async {
    _selectedLocationName = event.location.label;
    _coordinates = event.location.coordinates;
    await _load(event, emit);
  }

  void _tick(ForecastClockTicked event, Emitter<ForecastState> emit) {
    final current = state;
    if (current is! ForecastReady) return;
    emit(_ready(current.forecast, health: current.health));
  }

  void _scheduleClockTick() {
    final now = _clock.nowUtc;
    final nextMinute = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _clockTimer = Timer(
      nextMinute.difference(now) + const Duration(milliseconds: 50),
      () {
        if (!isClosed) add(const ForecastClockTicked());
        if (!isClosed) _scheduleClockTick();
      },
    );
  }

  @override
  Future<void> close() {
    _clockTimer?.cancel();
    return super.close();
  }
}
