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
/// entities keep absolute instants. The selected place's zone is used only to
/// parse provider wall-clock values; UI formatting follows the phone's zone.
abstract final class WeatherTimeZone {
  static bool _initialized = false;
  static String? _displayTimeZoneOverride;

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
  /// This is for provider/domain calculations, not user-facing timestamps.
  static String hourMinute(DateTime instant, String timeZone) =>
      formatWallHourMinute(atLocation(instant, timeZone));

  /// Wall clock used by the UI. Production follows the phone configuration;
  /// tests can pin an IANA zone to remain deterministic on every CI host.
  static DateTime displayWallTime(DateTime instant) {
    final override = _displayTimeZoneOverride;
    return override == null ? instant.toLocal() : wallTime(instant, override);
  }

  static String displayHourMinute(DateTime instant) =>
      formatWallHourMinute(displayWallTime(instant));

  static String displayHour(DateTime instant) =>
      displayWallTime(instant).hour.toString().padLeft(2, '0');

  static DateTime displayInstantFromWall(DateTime wallTime) {
    final override = _displayTimeZoneOverride;
    if (override != null) return instantFromLocal(wallTime, override);
    return DateTime(
      wallTime.year,
      wallTime.month,
      wallTime.day,
      wallTime.hour,
      wallTime.minute,
      wallTime.second,
      wallTime.millisecond,
      wallTime.microsecond,
    ).toUtc();
  }

  static String displayUtcOffsetLabel(DateTime instant) {
    final override = _displayTimeZoneOverride;
    final offset = override == null
        ? instant.toLocal().timeZoneOffset
        : atLocation(instant, override).timeZoneOffset;
    return _offsetLabel(offset);
  }

  /// Test-only display-zone pin. The assignment is removed in release builds.
  static void debugSetDisplayTimeZone(String? timeZone) {
    assert(() {
      _displayTimeZoneOverride = timeZone;
      return true;
    }());
  }

  /// Compact offset shown next to local wall-clock values (for example
  /// `UTC`, `UTC+2` or `UTC+5:45`). The offset is computed for the instant so
  /// daylight-saving changes remain correct.
  static String utcOffsetLabel(DateTime instant, String timeZone) {
    return _offsetLabel(atLocation(instant, timeZone).timeZoneOffset);
  }

  static String _offsetLabel(Duration offset) {
    final totalMinutes = offset.inMinutes;
    if (totalMinutes == 0) return 'UTC';
    final sign = totalMinutes < 0 ? '−' : '+';
    final absolute = totalMinutes.abs();
    final hours = absolute ~/ 60;
    final minutes = absolute % 60;
    return minutes == 0
        ? 'UTC$sign$hours'
        : 'UTC$sign$hours:${minutes.toString().padLeft(2, '0')}';
  }

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
