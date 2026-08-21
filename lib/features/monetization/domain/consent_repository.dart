/// Boundary reserved for the Google UMP consent flow when ads are enabled.
/// It intentionally does not persist or collect anything in the local-first MVP.
abstract interface class ConsentRepository {
  bool get canRequestPersonalizedAds;
}

final class DisabledConsentRepository implements ConsentRepository {
  const DisabledConsentRepository();

  @override
  bool get canRequestPersonalizedAds => false;
}
