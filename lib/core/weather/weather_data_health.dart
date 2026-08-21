import 'package:equatable/equatable.dart';

enum WeatherDataFreshness { live, cachedFresh, cachedStale }

enum WeatherDataIssue {
  offline,
  providerUnavailable,
  noRadarCoverage,
  invalidResponse,
}

final class WeatherDataException implements Exception {
  const WeatherDataException(this.issue, this.message);

  final WeatherDataIssue issue;
  final String message;

  @override
  String toString() => 'WeatherDataException(${issue.name}): $message';
}

WeatherDataIssue weatherDataIssueFrom(Object error) {
  if (error is WeatherDataException) return error.issue;
  final description = error.toString().toLowerCase();
  if (description.contains('timeout') ||
      description.contains('socket') ||
      description.contains('network') ||
      description.contains('réseau')) {
    return WeatherDataIssue.offline;
  }
  return WeatherDataIssue.providerUnavailable;
}

final class WeatherDataHealth extends Equatable {
  const WeatherDataHealth({
    this.freshness = WeatherDataFreshness.live,
    this.cachedAt,
    this.issue,
    this.isRefreshing = false,
  });

  final WeatherDataFreshness freshness;
  final DateTime? cachedAt;
  final WeatherDataIssue? issue;
  final bool isRefreshing;

  bool get usesCache => freshness != WeatherDataFreshness.live;
  bool get isStale => freshness == WeatherDataFreshness.cachedStale;

  @override
  List<Object?> get props => [freshness, cachedAt, issue, isRefreshing];
}
