import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../domain/consent_repository.dart';
import 'admob_config.dart';

final class GoogleConsentRepository implements ConsentRepository {
  bool _canRequestAds = false;
  bool _privacyOptionsRequired = false;
  bool _initialized = false;

  @override
  bool get canRequestPersonalizedAds => _canRequestAds;

  bool get privacyOptionsRequired => _privacyOptionsRequired;

  @override
  Future<void> initialize() async {
    if (_initialized || !AdMobConfig.isConfigured) return;
    _initialized = true;
    final information = ConsentInformation.instance;
    final updated = await _requestUpdate(information);
    if (!updated) return;
    await ConsentForm.loadAndShowConsentFormIfRequired((error) {
      // A form error must fail closed: no ad request is made in this session.
      if (error != null) _canRequestAds = false;
    });
    _canRequestAds = await information.canRequestAds();
    _privacyOptionsRequired =
        await information.getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;
  }

  Future<bool> _requestUpdate(ConsentInformation information) {
    final completer = Completer<bool>();
    information.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => completer.complete(true),
      (_) => completer.complete(false),
    );
    return completer.future;
  }

  @override
  Future<void> showPrivacyOptions() async {
    if (!AdMobConfig.isConfigured) return;
    await ConsentForm.showPrivacyOptionsForm((_) {});
    _canRequestAds = await ConsentInformation.instance.canRequestAds();
  }
}
