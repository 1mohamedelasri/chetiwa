import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../domain/ads_repository.dart';
import 'admob_config.dart';
import 'google_consent_repository.dart';

final class GoogleAdsRepository implements AdsRepository {
  GoogleAdsRepository({required GoogleConsentRepository consent})
    : _consent = consent;

  final GoogleConsentRepository _consent;
  bool _initialized = false;
  bool _initializing = false;

  @override
  bool get canRequestAds => _initialized && _consent.canRequestPersonalizedAds;

  @override
  bool get areAdsRemoved => false;

  Future<void> initialize() async {
    if (_initialized || _initializing) return;
    if (!AdMobConfig.isConfigured) return;
    _initializing = true;
    await _consent.initialize();
    if (_consent.canRequestPersonalizedAds) {
      await MobileAds.instance.initialize();
      _initialized = true;
    }
    _initializing = false;
  }

  BannerAd createBanner({required String adUnitId}) => BannerAd(
    size: AdSize.banner,
    adUnitId: adUnitId,
    request: const AdRequest(),
    listener: BannerAdListener(onAdFailedToLoad: (ad, _) => ad.dispose()),
  );
}
