import '../../../core/l10n/chetiwa_localizations.dart';
import '../../../core/time/weather_clock.dart';
import '../domain/entities/forecast.dart';

String localizedBriefHeadline(
  ChetiwaLocalizations strings,
  WeatherBrief brief,
  DateTime nowUtc,
) {
  if (strings.isFrench) return brief.headline;
  final minutes = brief.rainStart?.difference(nowUtc).inMinutes.clamp(1, 120);
  return switch (brief.type) {
    WeatherBriefType.dry => 'No rain in the next 2 hours',
    WeatherBriefType.raining => 'Rain now',
    WeatherBriefType.imminent => 'Rain in ${minutes ?? 1} min',
    WeatherBriefType.multipleEpisodes => 'First shower in ${minutes ?? 1} min',
  };
}

String localizedBriefDetail(
  ChetiwaLocalizations strings,
  WeatherBrief brief,
  DateTime nowUtc,
) {
  if (strings.isFrench) return brief.detail;
  final intensity = switch (brief.intensity) {
    RainIntensity.none => 'Very light',
    RainIntensity.light => 'Light',
    RainIntensity.moderate => 'Moderate',
    RainIntensity.heavy => 'Heavy',
  };
  return switch (brief.type) {
    WeatherBriefType.dry => 'Dry conditions for going out',
    WeatherBriefType.multipleEpisodes =>
      'Two possible rain episodes in the next 2 hours',
    WeatherBriefType.raining =>
      brief.rainEnd == null
          ? '$intensity · uncertain duration'
          : '$intensity · ending near ${WeatherTimeZone.displayHourMinute(brief.rainEnd!)}',
    WeatherBriefType.imminent => intensity,
  };
}
