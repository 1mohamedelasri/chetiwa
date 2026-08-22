/// Boundary for the Google UMP consent flow.
abstract interface class ConsentRepository {
  bool get canRequestPersonalizedAds;
  Future<void> initialize();
  Future<void> showPrivacyOptions();
}

final class DisabledConsentRepository implements ConsentRepository {
  const DisabledConsentRepository();

  @override
  bool get canRequestPersonalizedAds => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> showPrivacyOptions() async {}
}
