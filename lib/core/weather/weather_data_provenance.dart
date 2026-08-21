import 'package:equatable/equatable.dart';

enum WeatherDataKind {
  radarObservation,
  radarNowcast,
  modelEstimate,
  modelForecast,
}

final class WeatherDataProvenance extends Equatable {
  const WeatherDataProvenance({
    required this.kind,
    required this.provider,
    required this.validAt,
  });

  final WeatherDataKind kind;
  final String provider;
  final DateTime validAt;

  @override
  List<Object> get props => [kind, provider, validAt];
}
