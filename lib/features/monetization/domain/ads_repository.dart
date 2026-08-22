/// Boundary for advertising. The MVP deliberately uses [DisabledAdsRepository],
/// so the app has no Google Mobile Ads SDK, no ad request and no AdMob account.
abstract interface class AdsRepository {
  bool get canRequestAds;
  bool get areAdsRemoved;
}

final class DisabledAdsRepository implements AdsRepository {
  const DisabledAdsRepository();

  @override
  bool get canRequestAds => false;

  @override
  bool get areAdsRemoved => false;
}
