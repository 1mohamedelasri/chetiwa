import 'package:timezone/data/latest.dart' as tzdb;
import 'package:timezone/timezone.dart' as tz;

/// The only source of "now" used by weather and radar features.
abstract interface class WeatherClock {
  DateTime get nowUtc;
}

final class SystemWeatherClock implements WeatherClock {
  const SystemWeatherClock();

  @override
  DateTime get nowUtc => DateTime.now().toUtc();
}

final class FixedWeatherClock implements WeatherClock {
  const FixedWeatherClock(this.value);

  final DateTime value;

  @override
  DateTime get nowUtc => value.toUtc();
}

/// Converts between API wall-clock values and absolute UTC instants.
///
/// Open-Meteo returns the selected IANA zone with local timestamps. Domain
/// entities keep absolute instants; formatting is the only place where those
/// instants become a city's wall clock.
abstract final class WeatherTimeZone {
  static bool _initialized = false;

  static void _ensureInitialized() {
    if (_initialized) return;
    tzdb.initializeTimeZones();
    _initialized = true;
  }

  static tz.Location location(String name) {
    _ensureInitialized();
    try {
      return tz.getLocation(name);
    } on tz.LocationNotFoundException {
      return tz.UTC;
    }
  }

  static DateTime instantFromLocal(DateTime wallTime, String timeZone) {
    final value = tz.TZDateTime(
      location(timeZone),
      wallTime.year,
      wallTime.month,
      wallTime.day,
      wallTime.hour,
      wallTime.minute,
      wallTime.second,
      wallTime.millisecond,
      wallTime.microsecond,
    );
    return DateTime.fromMillisecondsSinceEpoch(
      value.millisecondsSinceEpoch,
      isUtc: true,
    );
  }

  static DateTime parseLocal(String value, String timeZone) =>
      instantFromLocal(DateTime.parse(value), timeZone);

  static tz.TZDateTime atLocation(DateTime instant, String timeZone) =>
      tz.TZDateTime.from(instant.toUtc(), location(timeZone));

  static DateTime wallTime(DateTime instant, String timeZone) {
    final value = atLocation(instant, timeZone);
    return DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }

  /// Formats an absolute instant using the selected place's wall clock.
  /// Every weather surface uses this helper instead of the device timezone.
  static String hourMinute(DateTime instant, String timeZone) =>
      formatWallHourMinute(atLocation(instant, timeZone));

  static String hour(DateTime instant, String timeZone) =>
      atLocation(instant, timeZone).hour.toString().padLeft(2, '0');

  static String formatWallHourMinute(DateTime wallTime) =>
      '${wallTime.hour.toString().padLeft(2, '0')}:'
      '${wallTime.minute.toString().padLeft(2, '0')}';

  static DateTime startOfLocalHour(DateTime instant, String timeZone) {
    final local = atLocation(instant, timeZone);
    final hour = tz.TZDateTime(
      local.location,
      local.year,
      local.month,
      local.day,
      local.hour,
    );
    return DateTime.fromMillisecondsSinceEpoch(
      hour.millisecondsSinceEpoch,
      isUtc: true,
    );
  }
}
