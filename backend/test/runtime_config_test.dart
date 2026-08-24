import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:test/test.dart';

void main() {
  test('defaults to a safe local environment', () {
    final config = RuntimeConfig.fromEnvironment(const <String, String>{});

    expect(config.environment, AppEnvironment.local);
    expect(config.port, 8080);
    expect(config.googleCloudProject, isNull);
    expect(config.radarProvider, RadarProvider.librewxr);
    expect(config.radarEnabled, isTrue);
    expect(config.radarQuotaEnforced, isFalse);
    expect(config.radarFreeSessions, 20);
    expect(config.radarPremiumSessions, 200);
    expect(config.premiumEnabled, isFalse);
    expect(config.premiumRolloutPercent, 0);
    expect(config.adsEnabled, isFalse);
    expect(config.rainAlertsEnabled, isFalse);
    expect(config.rainAlertsSendEnabled, isFalse);
    expect(config.rainAlertSoftBudgetCents, 2500);
    expect(config.rainAlertHardBudgetCents, 5000);
  });

  test('requires a Google Cloud project for staging', () {
    expect(
      () => RuntimeConfig.fromEnvironment(const <String, String>{
        'CHETIWA_ENV': 'staging',
      }),
      throwsStateError,
    );
  });

  test('accepts a complete production profile', () {
    final config = RuntimeConfig.fromEnvironment(const <String, String>{
      'CHETIWA_ENV': 'production',
      'PORT': '9090',
      'GOOGLE_CLOUD_PROJECT': 'chetiwa-production',
      'PUBLIC_BASE_URL': 'https://api.chetiwa.example',
    });

    expect(config.environment, AppEnvironment.production);
    expect(config.port, 9090);
    expect(config.isProduction, isTrue);
  });

  test('production radar requires a public HTTPS API URL', () {
    expect(
      () => RuntimeConfig.fromEnvironment(const <String, String>{
        'CHETIWA_ENV': 'production',
        'GOOGLE_CLOUD_PROJECT': 'chetiwa-production',
      }),
      throwsStateError,
    );
    expect(
      () => RuntimeConfig.fromEnvironment(const <String, String>{
        'CHETIWA_ENV': 'production',
        'GOOGLE_CLOUD_PROJECT': 'chetiwa-production',
        'PUBLIC_BASE_URL': 'https://127.0.0.1:8080',
      }),
      throwsStateError,
    );
  });

  test('parses the explicit radar provider', () {
    final config = RuntimeConfig.fromEnvironment(const <String, String>{
      'RADAR_PROVIDER': 'configured',
    });

    expect(config.radarProvider, RadarProvider.configured);
  });

  test('parses radar kill switch and quotas', () {
    final config = RuntimeConfig.fromEnvironment(const <String, String>{
      'CHETIWA_ENV': 'local',
      'RADAR_ENABLED': 'off',
      'RADAR_QUOTA_ENFORCED': 'on',
      'RADAR_FREE_SESSIONS': '3',
      'RADAR_PREMIUM_SESSIONS': '30',
    });

    expect(config.radarEnabled, isFalse);
    expect(config.radarQuotaEnforced, isTrue);
    expect(config.radarFreeSessions, 3);
    expect(config.radarPremiumSessions, 30);
  });

  test('parses the opt-in rain alert worker limits', () {
    final config = RuntimeConfig.fromEnvironment(const <String, String>{
      'RAIN_ALERTS_ENABLED': 'true',
      'RAIN_ALERTS_SEND_ENABLED': 'true',
      'RAIN_ALERT_CELL_SIZE_DEGREES': '0.04',
      'RAIN_ALERT_MAX_CONCURRENT_CELLS': '6',
      'RAIN_ALERT_SOFT_BUDGET_CENTS': '3000',
      'RAIN_ALERT_HARD_BUDGET_CENTS': '6000',
    });

    expect(config.rainAlertsEnabled, isTrue);
    expect(config.rainAlertsSendEnabled, isTrue);
    expect(config.rainAlertCellSizeDegrees, 0.04);
    expect(config.rainAlertMaxConcurrentCells, 6);
    expect(config.rainAlertSoftBudgetCents, 3000);
    expect(config.rainAlertHardBudgetCents, 6000);
  });

  test('parses monetization feature flags and validates rollout', () {
    final config = RuntimeConfig.fromEnvironment(const <String, String>{
      'PREMIUM_ENABLED': 'true',
      'PREMIUM_ROLLOUT_PERCENT': '25',
      'ADS_ENABLED': 'true',
    });

    expect(config.premiumEnabled, isTrue);
    expect(config.premiumRolloutPercent, 25);
    expect(config.adsEnabled, isTrue);
    expect(
      () => RuntimeConfig.fromEnvironment(const <String, String>{
        'PREMIUM_ROLLOUT_PERCENT': '101',
      }),
      throwsFormatException,
    );
  });

  test('rejects an alert hard budget below its warning threshold', () {
    expect(
      () => RuntimeConfig.fromEnvironment(const <String, String>{
        'RAIN_ALERT_SOFT_BUDGET_CENTS': '5000',
        'RAIN_ALERT_HARD_BUDGET_CENTS': '5000',
      }),
      throwsFormatException,
    );
  });
}
