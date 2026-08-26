/// Boundary for the Google UMP consent flow.
abstract interface class ConsentRepository {
  /// UMP's permission to request an ad. This does not imply that the ad is
  /// personalized; UMP may allow limited or non-personalized ads.
  bool get canRequestAds;
  Future<void> initialize();
  Future<void> showPrivacyOptions();
}

final class DisabledConsentRepository implements ConsentRepository {
  const DisabledConsentRepository();

  @override
  bool get canRequestAds => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> showPrivacyOptions() async {}
}
