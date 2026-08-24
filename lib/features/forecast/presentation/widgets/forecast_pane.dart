import 'package:flutter/material.dart';

import '../../../../app/theme/chetiwa_tokens.dart';
import '../../../../core/time/weather_clock.dart';
import '../../../../core/l10n/chetiwa_localizations.dart';
import '../../../../core/weather/temperature_formatter.dart';
import '../../domain/entities/forecast.dart';
import '../../domain/services/forecast_snapshot_builder.dart';
import '../forecast_strings.dart';

final class ForecastPane extends StatelessWidget {
  const ForecastPane({
    required this.forecast,
    required this.snapshot,
    super.key,
  });

  final Forecast forecast;
  final ForecastSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final today = snapshot.daily.firstOrNull;
    return Semantics(
      key: const Key('forecast-local-time'),
      label:
          '${context.l10n.isFrench ? 'Heure du téléphone' : 'Phone time'} · '
          '${WeatherTimeZone.displayUtcOffsetLabel(snapshot.nowUtc)} · '
          '${WeatherTimeZone.displayHourMinute(snapshot.nowUtc)}',
      child: CustomScrollView(
        key: const Key('forecast-pane'),
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
            sliver: SliverList.list(
              children: [
                _ForecastProvenance(
                  provider: snapshot.forecastProvenance.provider,
                ),
                const SizedBox(height: 10),
                _CurrentConditions(forecast: forecast, today: today),
                const SizedBox(height: 16),
                _HourlyCard(forecast: forecast, snapshot: snapshot),
                const SizedBox(height: 16),
                _DailyCard(days: snapshot.daily),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Prévisions modèle · ${snapshot.forecastProvenance.provider}',
                    style: const TextStyle(
                      color: ChetiwaColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _ForecastProvenance extends StatelessWidget {
  const _ForecastProvenance({required this.provider});

  final String provider;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      key: const Key('forecast-provenance-label'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ChetiwaColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(ChetiwaRadius.full),
        border: Border.all(color: ChetiwaColors.borderDefault),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_queue_rounded,
            size: 14,
            color: ChetiwaColors.accentPrimary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${context.l10n.modelEstimates} · ${provider.toUpperCase()}',
              style: const TextStyle(
                color: ChetiwaColors.textSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.25,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

final class _CurrentConditions extends StatelessWidget {
  const _CurrentConditions({required this.forecast, required this.today});

  final Forecast forecast;
  final DailyForecast? today;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF173746), Color(0xFF10232D)],
      ),
      borderRadius: BorderRadius.circular(ChetiwaRadius.large),
      border: Border.all(color: ChetiwaColors.borderDefault),
      boxShadow: ChetiwaElevation.floating,
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                forecast.locationName.split(',').first,
                style: const TextStyle(
                  color: ChetiwaColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formatTemperature(context, forecast.temperatureCelsius),
                style: const TextStyle(
                  color: ChetiwaColors.textPrimary,
                  height: 0.95,
                  fontSize: 68,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.weatherCondition(forecast.currentWeatherCode),
                style: const TextStyle(
                  color: ChetiwaColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (today != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Max. ${formatTemperature(context, today!.temperatureMax)}  ·  Min. ${formatTemperature(context, today!.temperatureMin)}',
                  style: const TextStyle(
                    color: ChetiwaColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: weatherColor(
              forecast.currentWeatherCode,
            ).withValues(alpha: 0.13),
            shape: BoxShape.circle,
          ),
          child: Icon(
            weatherIcon(forecast.currentWeatherCode),
            color: weatherColor(forecast.currentWeatherCode),
            size: 54,
          ),
        ),
      ],
    ),
  );
}

final class _HourlyCard extends StatelessWidget {
  const _HourlyCard({required this.forecast, required this.snapshot});

  final Forecast forecast;
  final ForecastSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final hours = snapshot.hourly.take(24).toList(growable: false);
    return _ForecastCard(
      title: context.l10n.hourlyForecast,
      icon: Icons.schedule_rounded,
      child: hours.isEmpty
          ? _EmptyForecast(message: context.l10n.hourlyUnavailable)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text(
                    localizedBriefDetail(
                      context.l10n,
                      snapshot.brief,
                      snapshot.nowUtc,
                    ),
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ),
                const Divider(height: 1),
                SizedBox(
                  height: 142,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    scrollDirection: Axis.horizontal,
                    itemCount: hours.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) => _Hour(item: hours[index]),
                  ),
                ),
              ],
            ),
    );
  }
}

final class _Hour extends StatelessWidget {
  const _Hour({required this.item});

  final HourlyForecast item;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 58,
    child: Column(
      children: [
        Text(
          WeatherTimeZone.displayHour(item.time),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 9),
        Icon(
          weatherIcon(item.weatherCode),
          size: 28,
          color: weatherColor(
            item.weatherCode,
            neutralColor: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        if (item.precipitationProbability > 10)
          Text(
            '${item.precipitationProbability} %',
            style: const TextStyle(
              color: ChetiwaColors.rainLight,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          )
        else
          const SizedBox(height: 12),
        const Spacer(),
        Text(
          formatTemperature(context, item.temperatureCelsius),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

final class _DailyCard extends StatelessWidget {
  const _DailyCard({required this.days});

  final List<DailyForecast> days;

  @override
  Widget build(BuildContext context) => _ForecastCard(
    title: context.l10n.tenDayForecast,
    icon: Icons.calendar_month_outlined,
    child: days.isEmpty
        ? _EmptyForecast(
            message: context.l10n.isFrench
                ? 'Prévisions quotidiennes indisponibles'
                : 'Daily forecast unavailable',
          )
        : Column(
            children: [
              for (var index = 0; index < days.length; index++) ...[
                _Day(item: days[index], isToday: index == 0),
                if (index < days.length - 1)
                  const Divider(height: 1, indent: 16, endIndent: 16),
              ],
            ],
          ),
  );
}

final class _Day extends StatelessWidget {
  const _Day({required this.item, required this.isToday});

  final DailyForecast item;
  final bool isToday;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 66,
            child: Text(
              isToday
                  ? (context.l10n.isFrench ? 'Auj.' : 'Today')
                  : _weekday(item.date, context.l10n.isFrench),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(
            width: 44,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  weatherIcon(item.weatherCode),
                  color: weatherColor(
                    item.weatherCode,
                    neutralColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  size: 25,
                ),
                if (item.precipitationProbability > 10)
                  Text(
                    '${item.precipitationProbability} %',
                    style: const TextStyle(
                      color: ChetiwaColors.rainLight,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            formatTemperature(context, item.temperatureMin),
            style: const TextStyle(
              color: ChetiwaColors.textSecondary,
              fontSize: 18,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ChetiwaRadius.full),
                gradient: LinearGradient(
                  colors: [
                    ChetiwaColors.rainLight,
                    weatherColor(
                      item.weatherCode,
                      neutralColor: Theme.of(context).colorScheme.onSurface,
                    ),
                    ChetiwaColors.warning,
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 34,
            child: Text(
              formatTemperature(context, item.temperatureMax),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );
}

final class _ForecastCard extends StatelessWidget {
  const _ForecastCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(ChetiwaRadius.large),
      border: Border.all(color: Theme.of(context).colorScheme.outline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: ChetiwaColors.textSecondary, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: ChetiwaColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        child,
      ],
    ),
  );
}

final class _EmptyForecast extends StatelessWidget {
  const _EmptyForecast({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
    child: Text(
      message,
      style: const TextStyle(color: ChetiwaColors.textSecondary),
    ),
  );
}

IconData weatherIcon(int code) => switch (code) {
  0 => Icons.wb_sunny_rounded,
  1 || 2 => Icons.wb_cloudy_rounded,
  3 => Icons.cloud_rounded,
  45 || 48 => Icons.blur_on_rounded,
  51 || 53 || 55 || 56 || 57 => Icons.grain_rounded,
  >= 61 && <= 67 => Icons.water_drop_rounded,
  >= 71 && <= 77 => Icons.ac_unit_rounded,
  >= 80 && <= 82 => Icons.shower_rounded,
  >= 85 && <= 86 => Icons.cloudy_snowing,
  >= 95 => Icons.thunderstorm_rounded,
  _ => Icons.cloud_outlined,
};

Color weatherColor(
  int code, {
  Color neutralColor = ChetiwaColors.textPrimary,
}) => switch (code) {
  0 => ChetiwaColors.warning,
  >= 51 && <= 67 => ChetiwaColors.rainLight,
  >= 71 && <= 86 => neutralColor,
  >= 95 => ChetiwaColors.rainHeavy,
  _ => neutralColor,
};

String weatherLabel(int code) => switch (code) {
  0 => 'Ciel dégagé',
  1 => 'Globalement dégagé',
  2 => 'Partiellement nuageux',
  3 => 'Couvert',
  45 || 48 => 'Brouillard',
  >= 51 && <= 57 => 'Bruine',
  >= 61 && <= 67 => 'Pluie',
  >= 71 && <= 77 => 'Neige',
  >= 80 && <= 82 => 'Averses',
  >= 85 && <= 86 => 'Averses de neige',
  >= 95 => 'Orage',
  _ => 'Conditions variables',
};

String _weekday(DateTime date, bool french) {
  const frenchDays = ['Lun.', 'Mar.', 'Mer.', 'Jeu.', 'Ven.', 'Sam.', 'Dim.'];
  const englishDays = ['Mon.', 'Tue.', 'Wed.', 'Thu.', 'Fri.', 'Sat.', 'Sun.'];
  final days = french ? frenchDays : englishDays;
  return days[date.weekday - 1];
}
