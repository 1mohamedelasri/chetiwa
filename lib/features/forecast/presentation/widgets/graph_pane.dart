import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/chetiwa_tokens.dart';
import '../../../../core/time/weather_clock.dart';
import '../../../../core/l10n/chetiwa_localizations.dart';
import '../../application/graph_horizon_cubit.dart';
import '../../domain/entities/forecast.dart';
import '../../domain/services/forecast_snapshot_builder.dart';
import '../../domain/services/rain_rate_scale.dart';
import 'weather_chrome.dart';
import '../forecast_strings.dart';

final class GraphPane extends StatelessWidget {
  const GraphPane({required this.forecast, required this.snapshot, super.key});

  final Forecast forecast;
  final ForecastSnapshot snapshot;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final chartColors = _ChartColors.of(context);
      final now = snapshot.nowUtc;
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      final compact = constraints.maxHeight < 500 || textScale > 1.45;
      final summary = Padding(
        padding: const EdgeInsets.symmetric(horizontal: ChetiwaSpacing.x6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localizedBriefHeadline(
                      context.l10n,
                      snapshot.brief,
                      snapshot.nowUtc,
                    ),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: ChetiwaSpacing.x1),
                  Text(
                    localizedBriefDetail(
                      context.l10n,
                      snapshot.brief,
                      snapshot.nowUtc,
                      forecast.timeZone,
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: ChetiwaSpacing.x1),
                  Text(
                    '${context.l10n.modelForecast} · ${snapshot.forecastProvenance.provider.toUpperCase()}',
                    key: const Key('graph-provenance-label'),
                    style: TextStyle(
                      color: chartColors.muted,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const _HorizonSelector(),
          ],
        ),
      );
      final metrics = Padding(
        padding: const EdgeInsets.symmetric(horizontal: ChetiwaSpacing.x6),
        child: LiveMetrics(forecast: forecast, snapshot: snapshot),
      );
      final chart = BlocBuilder<GraphHorizonCubit, GraphHorizon>(
        builder: (context, horizon) => _ChetiwaRainChart(
          key: ValueKey(horizon),
          points: forecast.points,
          currentRain: snapshot.currentRain,
          now: now,
          rainStart: snapshot.brief.rainStart,
          timeZone: forecast.timeZone,
          providerName: snapshot.forecastProvenance.provider,
          horizon: horizon,
          languageCode: context.l10n.locale.languageCode,
          colors: chartColors,
        ),
      );
      if (compact) {
        return ListView(
          key: const Key('compact-graph-scroll'),
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            summary,
            const SizedBox(height: ChetiwaSpacing.x3),
            metrics,
            const SizedBox(height: ChetiwaSpacing.x3),
            SizedBox(height: 260, child: chart),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          summary,
          const SizedBox(height: ChetiwaSpacing.x3),
          metrics,
          const SizedBox(height: ChetiwaSpacing.x3),
          Expanded(child: chart),
        ],
      );
    },
  );
}

final class _HorizonSelector extends StatelessWidget {
  const _HorizonSelector();

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<GraphHorizonCubit, GraphHorizon>(
        builder: (context, horizon) => Container(
          width: 100,
          height: 34,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(ChetiwaRadius.full),
          ),
          child: Row(
            children: [
              _Option(
                label: '2H',
                selected: horizon == GraphHorizon.twoHours,
                onTap: () => context.read<GraphHorizonCubit>().select(
                  GraphHorizon.twoHours,
                ),
              ),
              _Option(
                label: '24H',
                selected: horizon == GraphHorizon.twentyFourHours,
                onTap: () => context.read<GraphHorizonCubit>().select(
                  GraphHorizon.twentyFourHours,
                ),
              ),
            ],
          ),
        ),
      );
}

final class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      button: true,
      selected: selected,
      label: selected ? context.l10n.selectedOption(label) : label,
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primary
            : Colors.transparent,
        borderRadius: BorderRadius.circular(ChetiwaRadius.full),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ChetiwaRadius.full),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _ChetiwaRainChart extends StatefulWidget {
  const _ChetiwaRainChart({
    required this.points,
    required this.currentRain,
    required this.now,
    required this.rainStart,
    required this.horizon,
    required this.timeZone,
    required this.providerName,
    required this.languageCode,
    required this.colors,
    super.key,
  });

  final List<RainPoint> points;
  final RainPoint currentRain;
  final DateTime now;
  final DateTime? rainStart;
  final GraphHorizon horizon;
  final String timeZone;
  final String providerName;
  final String languageCode;
  final _ChartColors colors;

  @override
  State<_ChetiwaRainChart> createState() => _ChetiwaRainChartState();
}

final class _ChetiwaRainChartState extends State<_ChetiwaRainChart> {
  double? _cursorX;

  Duration get _duration => widget.horizon == GraphHorizon.twoHours
      ? const Duration(hours: 2)
      : const Duration(hours: 24);

  List<RainPoint> get _visiblePoints {
    final end = widget.now.add(_duration);
    final ordered = [...widget.points]
      ..sort((left, right) => left.time.compareTo(right.time));
    if (ordered.isEmpty) return const [];

    final result = <RainPoint>[widget.currentRain];

    result.addAll(
      ordered.where(
        (point) => point.time.isAfter(widget.now) && !point.time.isAfter(end),
      ),
    );
    return result;
  }

  RainIntensity get _visibleIntensity =>
      _visiblePoints.fold(RainIntensity.none, (strongest, point) {
        final intensity = RainRateScale.intensityFor(point.rateMmPerHour);
        return intensity.index > strongest.index ? intensity : strongest;
      });

  @override
  Widget build(BuildContext context) => Semantics(
    key: ValueKey('rain-chart-intensity-${_visibleIntensity.name}'),
    label: context.l10n.maximumRainIntensity(
      context.l10n.rainIntensityName(_visibleIntensity.name),
      widget.timeZone,
      WeatherTimeZone.hourMinute(widget.now, widget.timeZone),
    ),
    child: GestureDetector(
      key: const Key('rain-chart'),
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) =>
          setState(() => _cursorX = details.localPosition.dx),
      onHorizontalDragStart: (details) =>
          setState(() => _cursorX = details.localPosition.dx),
      onHorizontalDragUpdate: (details) =>
          setState(() => _cursorX = details.localPosition.dx),
      onDoubleTap: () => setState(() => _cursorX = null),
      child: CustomPaint(
        key: ValueKey(
          _cursorX == null
              ? 'rain-chart-cursor-now'
              : 'rain-chart-cursor-selected',
        ),
        painter: _RainChartPainter(
          points: _visiblePoints,
          now: widget.now,
          duration: _duration,
          rainStart: widget.rainStart,
          timeZone: widget.timeZone,
          providerName: widget.providerName,
          languageCode: widget.languageCode,
          cursorX: _cursorX,
          colors: widget.colors,
        ),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

final class _RainChartPainter extends CustomPainter {
  const _RainChartPainter({
    required this.points,
    required this.now,
    required this.duration,
    required this.rainStart,
    required this.cursorX,
    required this.timeZone,
    required this.providerName,
    required this.languageCode,
    required this.colors,
  });

  final List<RainPoint> points;
  final DateTime now;
  final Duration duration;
  final DateTime? rainStart;
  final double? cursorX;
  final String timeZone;
  final String providerName;
  final String languageCode;
  final _ChartColors colors;

  bool get _isFrench => languageCode == 'fr';

  static const _left = 24.0;
  static const _right = 24.0;
  static const _top = 50.0;
  static const _bottom = 44.0;

  @override
  void paint(Canvas canvas, Size size) {
    final chart = Rect.fromLTRB(
      _left,
      _top,
      size.width - _right,
      size.height - _bottom,
    );
    if (chart.width <= 0 || chart.height <= 0) return;

    _text(
      canvas,
      '${_isFrench ? 'PRÉVISION MODÈLE' : 'MODEL FORECAST'} · ${providerName.toUpperCase()}',
      const Offset(_left, 12),
      color: colors.foreground,
      size: 11,
      weight: FontWeight.w700,
    );
    _text(
      canvas,
      _isFrench
          ? '${duration.inHours} PROCHAINES H'
          : 'NEXT ${duration.inHours} HOURS',
      Offset(size.width - _right - 90, 14),
      color: colors.muted,
      size: 11,
      align: TextAlign.right,
      width: 90,
    );

    final levels = _isFrench
        ? [('FORTE', 0.12), ('MODÉRÉE', 0.44), ('FAIBLE', 0.76)]
        : [('HEAVY', 0.12), ('MODERATE', 0.44), ('LIGHT', 0.76)];
    for (final level in levels) {
      final y = chart.top + chart.height * level.$2;
      canvas.drawLine(
        Offset(chart.left, y),
        Offset(chart.right, y),
        Paint()
          ..color = colors.outline.withValues(alpha: 0.55)
          ..strokeWidth = 1,
      );
      _text(
        canvas,
        level.$1,
        Offset(chart.right - 58, y - 14),
        color: colors.muted.withValues(alpha: 0.75),
        size: 9,
        align: TextAlign.right,
        width: 58,
      );
    }

    if (points.isNotEmpty) {
      final line = Path();
      final area = Path()..moveTo(chart.left, chart.bottom);
      for (var index = 0; index < points.length; index++) {
        final point = points[index];
        final elapsed = point.time
            .difference(now)
            .inMinutes
            .clamp(0, duration.inMinutes);
        final x = chart.left + chart.width * elapsed / duration.inMinutes;
        final y =
            chart.bottom -
            chart.height * RainRateScale.normalized(point.rateMmPerHour);
        if (index == 0) {
          line.moveTo(x, y);
          area.lineTo(x, y);
        } else {
          line.lineTo(x, y);
          area.lineTo(x, y);
        }
      }
      area.lineTo(chart.right, chart.bottom);
      area.close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xCC2F6EDB), Color(0x1A2F6EDB)],
          ).createShader(chart),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = ChetiwaColors.rainLight
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
      if (points.every((point) => !RainRateScale.isRain(point.rateMmPerHour))) {
        final labelWidth = math.min(180.0, chart.width);
        _text(
          canvas,
          _isFrench ? 'AUCUNE PLUIE PRÉVUE' : 'NO RAIN EXPECTED',
          Offset(chart.center.dx - labelWidth / 2, chart.center.dy - 8),
          color: ChetiwaColors.accentPrimary,
          size: 11,
          weight: FontWeight.w700,
          align: TextAlign.center,
          width: labelWidth,
        );
      }
    }

    final start = rainStart;
    if (start != null) {
      final minute = start.difference(now).inMinutes;
      if (minute >= 0 && minute <= duration.inMinutes) {
        final x = chart.left + chart.width * minute / duration.inMinutes;
        canvas.drawLine(
          Offset(x, chart.top),
          Offset(x, chart.bottom),
          Paint()
            ..color = ChetiwaColors.warning
            ..strokeWidth = 1.5,
        );
        _text(
          canvas,
          _isFrench
              ? 'PLUIE VERS ${_formatTime(start)}'
              : 'RAIN AROUND ${_formatTime(start)}',
          Offset(math.min(x + 6, chart.right - 116), chart.top + 8),
          color: ChetiwaColors.warning,
          size: 10,
          weight: FontWeight.w700,
        );
      }
    }

    final tickCount = duration.inHours == 2 ? 4 : 6;
    for (var index = 0; index <= tickCount; index++) {
      final ratio = index / tickCount;
      final x = chart.left + chart.width * ratio;
      final time = now.add(
        Duration(minutes: (duration.inMinutes * ratio).round()),
      );
      _text(
        canvas,
        _formatTime(time),
        Offset(x - 24, chart.bottom + 13),
        color: colors.muted,
        size: 9,
        align: TextAlign.center,
        width: 48,
      );
    }

    final rawCursor = cursorX;
    if (rawCursor != null) {
      final x = rawCursor.clamp(chart.left, chart.right);
      canvas.drawLine(
        Offset(x, chart.top),
        Offset(x, chart.bottom),
        Paint()
          ..color = colors.foreground.withValues(alpha: 0.75)
          ..strokeWidth = 1,
      );
      final ratio = (x - chart.left) / chart.width;
      final time = now.add(
        Duration(minutes: (duration.inMinutes * ratio).round()),
      );
      _bubble(canvas, size, x, _formatTime(time));
    }
  }

  String _formatTime(DateTime instant) =>
      WeatherTimeZone.hourMinute(instant, timeZone);

  void _bubble(Canvas canvas, Size size, double x, String label) {
    final left = (x - 30).clamp(8.0, size.width - 68);
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, 20, 60, 26),
      const Radius.circular(13),
    );
    canvas.drawRRect(rect, Paint()..color = colors.bubble);
    _text(
      canvas,
      label,
      Offset(left, 27),
      color: colors.bubbleForeground,
      size: 10,
      align: TextAlign.center,
      width: 60,
    );
  }

  void _text(
    Canvas canvas,
    String value,
    Offset offset, {
    required Color color,
    required double size,
    FontWeight weight = FontWeight.w400,
    TextAlign align = TextAlign.left,
    double? width,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(color: color, fontSize: size, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: width ?? double.infinity);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _RainChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.now != now ||
      oldDelegate.rainStart != rainStart ||
      oldDelegate.duration != duration ||
      oldDelegate.cursorX != cursorX ||
      oldDelegate.languageCode != languageCode ||
      oldDelegate.providerName != providerName ||
      oldDelegate.timeZone != timeZone ||
      oldDelegate.colors != colors;
}

final class _ChartColors {
  const _ChartColors({
    required this.foreground,
    required this.muted,
    required this.outline,
    required this.bubble,
    required this.bubbleForeground,
  });

  factory _ChartColors.of(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _ChartColors(
      foreground: colors.onSurface,
      muted: colors.onSurfaceVariant,
      outline: colors.outline,
      bubble: colors.surfaceContainerHighest,
      bubbleForeground: colors.onSurface,
    );
  }

  final Color foreground;
  final Color muted;
  final Color outline;
  final Color bubble;
  final Color bubbleForeground;
}
