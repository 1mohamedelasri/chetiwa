import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../app/preferences/app_preferences_controller.dart';

String formatTemperature(
  BuildContext context,
  double celsius, {
  bool unit = false,
}) {
  final preference =
      Provider.of<AppPreferencesController?>(context)?.temperatureUnit ??
      TemperatureUnit.celsius;
  final value = preference == TemperatureUnit.celsius
      ? celsius
      : (celsius * 9 / 5) + 32;
  final suffix = unit
      ? (preference == TemperatureUnit.celsius ? '°C' : '°F')
      : '°';
  return '${value.round()}$suffix';
}
