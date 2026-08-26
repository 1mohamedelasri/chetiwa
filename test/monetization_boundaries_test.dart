import 'package:chetiwa/features/monetization/domain/ads_repository.dart';
import 'package:chetiwa/features/monetization/domain/consent_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('le MVP local-first ne peut demander ni publicité ni consentement', () {
    expect(const DisabledAdsRepository().canRequestAds, isFalse);
    expect(const DisabledConsentRepository().canRequestAds, isFalse);
  });
}
