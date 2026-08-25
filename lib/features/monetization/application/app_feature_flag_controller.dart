import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/chetiwa_api_client.dart';

final class AppFeatureFlags {
  const AppFeatureFlags({
    required this.premiumAvailable,
    required this.adsEnabled,
    this.premiumSatelliteAvailable = false,
    this.premiumRadarModelAvailable = false,
  });

  const AppFeatureFlags.disabled()
    : premiumAvailable = false,
      adsEnabled = false,
      premiumSatelliteAvailable = false,
      premiumRadarModelAvailable = false;

  final bool premiumAvailable;
  final bool adsEnabled;
  final bool premiumSatelliteAvailable;
  final bool premiumRadarModelAvailable;

  factory AppFeatureFlags.fromApi(Map<String, dynamic> data) {
    final features = data['features'];
    if (features is! Map<String, dynamic>) {
      throw const FormatException('Expected a features object');
    }
    return AppFeatureFlags(
      premiumAvailable: features['premium'] == true,
      adsEnabled: features['ads'] == true,
      premiumSatelliteAvailable: features['premiumSatellite'] == true,
      premiumRadarModelAvailable: features['premiumRadarModel'] == true,
    );
  }
}

abstract interface class AppFeatureFlagGateway {
  Future<AppFeatureFlags> load();
}

final class ChetiwaAppFeatureFlagGateway implements AppFeatureFlagGateway {
  const ChetiwaAppFeatureFlagGateway(this._api);

  final ChetiwaApiClient _api;

  @override
  Future<AppFeatureFlags> load() async =>
      AppFeatureFlags.fromApi(await _api.getData('/v1/app-config'));
}

/// Keeps the last valid public configuration and fails closed on first launch.
/// Premium entitlement still comes from the stores; these flags only control
/// whether a feature is offered to this installation.
final class AppFeatureFlagController extends ChangeNotifier {
  AppFeatureFlagController({
    AppFeatureFlagGateway? gateway,
    AppFeatureFlags initial = const AppFeatureFlags.disabled(),
    bool persist = true,
  }) : _gateway = gateway,
       _flags = initial,
       _persist = persist;

  static const _premiumKey = 'feature-flags:premium:v1';
  static const _adsKey = 'feature-flags:ads:v1';
  static const _premiumSatelliteKey = 'feature-flags:premium-satellite:v1';
  static const _premiumRadarModelKey = 'feature-flags:premium-radar-model:v1';

  final AppFeatureFlagGateway? _gateway;
  final bool _persist;
  AppFeatureFlags _flags;
  bool _initialized = false;

  AppFeatureFlags get flags => _flags;
  bool get premiumAvailable => _flags.premiumAvailable;
  bool get adsEnabled => _flags.adsEnabled;
  bool get premiumSatelliteAvailable => _flags.premiumSatelliteAvailable;
  bool get premiumRadarModelAvailable => _flags.premiumRadarModelAvailable;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (_persist) {
      final preferences = await SharedPreferences.getInstance();
      final premium = preferences.getBool(_premiumKey);
      final ads = preferences.getBool(_adsKey);
      final premiumSatellite = preferences.getBool(_premiumSatelliteKey);
      final premiumRadarModel = preferences.getBool(_premiumRadarModelKey);
      if (premium != null &&
          ads != null &&
          premiumSatellite != null &&
          premiumRadarModel != null) {
        _setFlags(
          AppFeatureFlags(
            premiumAvailable: premium,
            adsEnabled: ads,
            premiumSatelliteAvailable: premiumSatellite,
            premiumRadarModelAvailable: premiumRadarModel,
          ),
        );
      }
    }
    await refresh();
  }

  Future<void> refresh() async {
    final gateway = _gateway;
    if (gateway == null) return;
    try {
      final remote = await gateway.load();
      _setFlags(remote);
      if (_persist) {
        final preferences = await SharedPreferences.getInstance();
        await Future.wait(<Future<bool>>[
          preferences.setBool(_premiumKey, remote.premiumAvailable),
          preferences.setBool(_adsKey, remote.adsEnabled),
          preferences.setBool(
            _premiumSatelliteKey,
            remote.premiumSatelliteAvailable,
          ),
          preferences.setBool(
            _premiumRadarModelKey,
            remote.premiumRadarModelAvailable,
          ),
        ]);
      }
    } on Object {
      // A temporary configuration outage must not alter the last valid state.
    }
  }

  void _setFlags(AppFeatureFlags value) {
    if (_flags.premiumAvailable == value.premiumAvailable &&
        _flags.adsEnabled == value.adsEnabled &&
        _flags.premiumSatelliteAvailable == value.premiumSatelliteAvailable &&
        _flags.premiumRadarModelAvailable == value.premiumRadarModelAvailable) {
      return;
    }
    _flags = value;
    notifyListeners();
  }
}
