import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:test/test.dart';

void main() {
  test('defaults to a safe local environment', () {
    final config = RuntimeConfig.fromEnvironment(const <String, String>{});

    expect(config.environment, AppEnvironment.local);
    expect(config.port, 8080);
    expect(config.googleCloudProject, isNull);
    expect(config.radarEnabled, isTrue);
    expect(config.radarFreeSessions, 20);
    expect(config.radarPremiumSessions, 200);
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
    });

    expect(config.environment, AppEnvironment.production);
    expect(config.port, 9090);
    expect(config.isProduction, isTrue);
  });

  test('parses radar kill switch and quotas', () {
    final config = RuntimeConfig.fromEnvironment(const <String, String>{
      'CHETIWA_ENV': 'local',
      'RADAR_ENABLED': 'off',
      'RADAR_FREE_SESSIONS': '3',
      'RADAR_PREMIUM_SESSIONS': '30',
    });

    expect(config.radarEnabled, isFalse);
    expect(config.radarFreeSessions, 3);
    expect(config.radarPremiumSessions, 30);
  });
}
