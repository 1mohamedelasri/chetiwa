# AdMob / UMP — configuration de production

Le code est intégré, mais aucune publicité réelle n’est activée tant que les
identifiants d’unité publicitaire ne sont pas fournis. La configuration par
défaut utilise uniquement l’identifiant d’application de test Google et des
unités vides : aucune requête publicitaire ne part dans ce mode.

## Séquence obligatoire

1. Créer l’application Android et iOS dans AdMob.
2. Publier la politique de confidentialité et configurer le message UMP dans
   AdMob > Privacy & messaging.
3. Ajouter les identifiants d’application natifs :
   - Android : `-PadmobAppId=ca-app-pub-...~...`
   - iOS : `ADMOB_APP_ID=ca-app-pub-...~...` dans les Build Settings Xcode.
4. Ajouter les unités bannière via les `dart-define` de la build :

```sh
flutter build appbundle \
  --dart-define=CHETIWA_ADMOB_ANDROID_BANNER_ID=ca-app-pub-.../... \
  --dart-define=CHETIWA_ADMOB_IOS_BANNER_ID=ca-app-pub-.../...
```

5. Vérifier sur un appareil test que le formulaire UMP apparaît lorsque la
   géographie l’exige, que « Préférences publicitaires » ouvre les options et
   qu’aucune bannière n’est chargée avant `canRequestAds()`.
6. Vérifier qu’un compte Premium ne crée ni `BannerAd` ni requête réseau.
7. Compléter App Privacy, Data Safety, consentement, DPA et le gate de release
   [`docs/compliance/public-launch-gate.md`](../compliance/public-launch-gate.md).

## Règles techniques appliquées

- `requestConsentInfoUpdate()` est appelé avant les annonces à chaque session.
- `loadAndShowConsentFormIfRequired()` est exécuté avant toute requête.
- `canRequestAds()` est la seule autorisation de chargement.
- Une erreur de consentement ferme le flux publicitaire pour la session.
- Le choix utilisateur est modifiable depuis Settings.
- Premium retourne un slot vide avant même l’initialisation AdMob.

Références : [guide officiel UMP Flutter](https://developers.google.com/admob/flutter/privacy)
et [plugin Google Mobile Ads Flutter](https://pub.dev/packages/google_mobile_ads).
