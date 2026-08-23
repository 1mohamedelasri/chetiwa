import 'package:flutter/material.dart';

import '../../app/theme/chetiwa_tokens.dart';
import '../l10n/chetiwa_localizations.dart';
import '../weather/weather_data_health.dart';

final class WeatherDataStatusBanner extends StatelessWidget {
  const WeatherDataStatusBanner({
    required this.health,
    required this.domainLabel,
    required this.nowUtc,
    required this.dataUpdatedAt,
    this.onRetry,
    super.key,
  });

  final WeatherDataHealth health;
  final String domainLabel;
  final DateTime nowUtc;
  final DateTime dataUpdatedAt;
  final VoidCallback? onRetry;

  bool get _isVisible =>
      health.issue != null || health.usesCache || health.isRefreshing;

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();
    final issue = health.issue;
    final showAge = health.usesCache || issue != null;
    final age = weatherDataAgeLabel(
      nowUtc: nowUtc,
      dataUpdatedAt: dataUpdatedAt,
      languageCode: context.l10n.locale.languageCode,
    );
    final (icon, message, color) = switch (issue) {
      WeatherDataIssue.offline => (
        Icons.wifi_off_rounded,
        health.usesCache
            ? context.l10n.offlineCached
            : context.l10n.connectionUnavailable,
        ChetiwaColors.warning,
      ),
      WeatherDataIssue.providerUnavailable => (
        Icons.cloud_off_rounded,
        context.l10n.providerUnavailableCached(domainLabel),
        ChetiwaColors.warning,
      ),
      WeatherDataIssue.noRadarCoverage => (
        Icons.radar_rounded,
        context.l10n.noRadarCoverage,
        ChetiwaColors.warning,
      ),
      WeatherDataIssue.invalidResponse => (
        Icons.sync_problem_rounded,
        context.l10n.invalidProviderCached(domainLabel),
        ChetiwaColors.warning,
      ),
      null when health.isStale => (
        Icons.history_rounded,
        context.l10n.savedDataMayBeStale,
        ChetiwaColors.warning,
      ),
      null when health.usesCache && health.isRefreshing => (
        Icons.sync_rounded,
        context.l10n.cacheRefreshing,
        ChetiwaColors.accentPrimary,
      ),
      null when health.usesCache => (
        Icons.inventory_2_outlined,
        context.l10n.savedDataDisplayed,
        ChetiwaColors.textSecondary,
      ),
      null => (
        Icons.sync_rounded,
        context.l10n.refreshing,
        ChetiwaColors.accentPrimary,
      ),
    };
    return Semantics(
      liveRegion: true,
      label: message,
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: ChetiwaColors.backgroundPrimary.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(ChetiwaRadius.small),
          border: Border.all(color: color.withValues(alpha: 0.55)),
          boxShadow: ChetiwaElevation.floating,
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (showAge) ...[
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.dataUpdated(age),
                      key: const Key('weather-data-age'),
                      style: const TextStyle(
                        color: ChetiwaColors.textSecondary,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (health.isRefreshing) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: color,
                ),
              ),
            ],
            if (onRetry != null && !health.isRefreshing) ...[
              const SizedBox(width: 4),
              IconButton(
                key: const Key('weather-data-retry'),
                onPressed: onRetry,
                tooltip: context.l10n.retry,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                icon: Icon(Icons.refresh_rounded, size: 16, color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String weatherDataAgeLabel({
  required DateTime nowUtc,
  required DateTime dataUpdatedAt,
  String languageCode = 'fr',
}) {
  final age = nowUtc.toUtc().difference(dataUpdatedAt.toUtc());
  final french = languageCode == 'fr';
  if (!french) {
    if (age.isNegative || age.inMinutes < 1) return 'just now';
    if (age.inMinutes < 60) return '${age.inMinutes} min ago';
    if (age.inHours < 24) {
      final minutes = age.inMinutes.remainder(60);
      return minutes == 0
          ? '${age.inHours} h ago'
          : '${age.inHours} h ${minutes.toString().padLeft(2, '0')} min ago';
    }
    final days = age.inDays;
    final hours = age.inHours.remainder(24);
    return hours == 0
        ? '$days ${days == 1 ? 'day' : 'days'} ago'
        : '$days ${days == 1 ? 'day' : 'days'} $hours h ago';
  }
  if (age.isNegative || age.inMinutes < 1) return 'à l’instant';
  if (age.inMinutes < 60) return 'il y a ${age.inMinutes} min';
  if (age.inHours < 24) {
    final minutes = age.inMinutes.remainder(60);
    return minutes == 0
        ? 'il y a ${age.inHours} h'
        : 'il y a ${age.inHours} h ${minutes.toString().padLeft(2, '0')} min';
  }
  final days = age.inDays;
  final hours = age.inHours.remainder(24);
  final dayLabel = days == 1 ? 'jour' : 'jours';
  return hours == 0
      ? 'il y a $days $dayLabel'
      : 'il y a $days $dayLabel $hours h';
}

final class WeatherDataUnavailableView extends StatelessWidget {
  const WeatherDataUnavailableView({
    required this.issue,
    required this.domainLabel,
    required this.onRetry,
    super.key,
  });

  final WeatherDataIssue issue;
  final String domainLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (icon, title, detail) = switch (issue) {
      WeatherDataIssue.offline => (
        Icons.wifi_off_rounded,
        context.l10n.offlineTitle,
        context.l10n.offlineDetail(domainLabel),
      ),
      WeatherDataIssue.noRadarCoverage => (
        Icons.radar_rounded,
        context.l10n.noCoverageTitle,
        context.l10n.noCoverageDetail,
      ),
      WeatherDataIssue.invalidResponse => (
        Icons.sync_problem_rounded,
        context.l10n.invalidDataTitle,
        context.l10n.invalidDataDetail(domainLabel),
      ),
      WeatherDataIssue.providerUnavailable => (
        Icons.cloud_off_rounded,
        context.l10n.providerUnavailableTitle(domainLabel),
        context.l10n.providerUnavailableDetail,
      ),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ChetiwaSpacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: ChetiwaColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: ChetiwaColors.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}

final class WeatherDataLoadingView extends StatelessWidget {
  const WeatherDataLoadingView({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(height: 14),
        Text(label, style: const TextStyle(color: ChetiwaColors.textSecondary)),
      ],
    ),
  );
}
