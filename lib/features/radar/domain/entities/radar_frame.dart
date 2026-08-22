import 'package:equatable/equatable.dart';

import '../../../../core/weather/weather_data_provenance.dart';

final class RadarFrame extends Equatable {
  const RadarFrame({
    required this.time,
    required this.progress,
    this.tileUrlTemplate,
    this.kind = WeatherDataKind.radarObservation,
    this.providerName = 'RainViewer',
  });

  final DateTime time;
  final double progress;
  final String? tileUrlTemplate;
  final WeatherDataKind kind;
  final String providerName;

  bool get isObservation => kind == WeatherDataKind.radarObservation;
  bool get isNowcast => kind == WeatherDataKind.radarNowcast;

  WeatherDataProvenance get provenance =>
      WeatherDataProvenance(kind: kind, provider: providerName, validAt: time);

  @override
  List<Object?> get props => [
    time,
    progress,
    tileUrlTemplate,
    kind,
    providerName,
  ];
}
