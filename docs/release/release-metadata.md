# Métadonnées de release — Chetiwa

Ce document fixe les informations à vérifier avant de générer une bêta. La
source de vérité de la version reste `pubspec.yaml`; l'écran Réglages lit la
version et le numéro de build réellement intégrés dans l'application.

| Élément | Valeur actuelle |
| --- | --- |
| Nom | Chetiwa |
| Version | `1.0.0` |
| Numéro de build | `1` |
| Android application ID | `com.ezplatforms.chetiwa` |
| iOS bundle ID | `com.ezplatforms.chetiwa` |
| Configuration Firebase | Analytics + Crashlytics opt-in, FCM opt-in |
| Icône Store | `assets/brand/chetiwa_app_icon_master.png` |
| Icône Google Play | `assets/store/google-play-icon-512.png` |
| Feature graphic Play | `assets/store/google-play-feature-graphic.png` |
| Captures iPhone 6,7 pouces | `assets/store/screenshots/ios-6.7/` |
| Captures Android téléphone | `assets/store/screenshots/android-phone/` |

Les captures déterministes utilisent `lib/main_store_screenshots.dart`; la
capture Radar utilise `lib/main_store_live_radar.dart` pour montrer de vraies
tuiles. Ces deux points d'entrée ne sont jamais référencés par les builds
`lib/main.dart` de production et les dossiers Store ne sont pas embarqués dans
le bundle Flutter.

## Avant chaque bêta

1. Augmenter le numéro de build dans `pubspec.yaml` (et la version publique si
   nécessaire).
2. Ajouter les changements destinés aux testeurs dans `CHANGELOG.md`.
3. Vérifier que l'écran **Réglages > Version** affiche le couple attendu.
4. Lancer `flutter analyze`, `flutter test` et un build Android/iOS.
5. Suivre la checklist de [bêta privée](private-beta-checklist.md) avant tout
   envoi TestFlight ou Play Console.

Une build déjà téléversée dans App Store Connect ou Play Console ne doit jamais
être réutilisée : augmenter au minimum son numéro de build.
