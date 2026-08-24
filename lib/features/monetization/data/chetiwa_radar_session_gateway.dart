import 'dart:math';

import '../../../core/network/chetiwa_api_client.dart';
import '../application/usage_quota_controller.dart';

final class ChetiwaRadarSessionGateway implements RadarSessionGateway {
  ChetiwaRadarSessionGateway(this._api, {Random? random})
    : _random = random ?? Random.secure();

  final ChetiwaApiClient _api;
  final Random _random;

  @override
  Future<RadarSessionDecision> open({required bool premium}) async {
    final data = await _api.postData(
      '/v1/radar/sessions',
      const <String, Object?>{},
      headers: <String, String>{
        'x-chetiwa-plan': premium ? 'premium' : 'free',
        'x-chetiwa-radar-session-id': _newSessionId(),
      },
    );
    final session = data['session'];
    if (session is! Map<String, dynamic>) {
      throw const FormatException('Expected a Radar session decision');
    }
    final allowed = session['allowed'];
    final enforced = session['enforced'];
    final used = session['used'];
    final limit = session['limit'];
    final resetAt = session['resetAt'];
    if (allowed is! bool ||
        enforced is! bool ||
        used is! int ||
        limit is! int ||
        resetAt is! String) {
      throw const FormatException('Invalid Radar session decision');
    }
    return RadarSessionDecision(
      allowed: allowed,
      enforced: enforced,
      used: used,
      limit: limit,
      resetAt: DateTime.parse(resetAt).toLocal(),
    );
  }

  String _newSessionId() => List<int>.generate(
    16,
    (_) => _random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
