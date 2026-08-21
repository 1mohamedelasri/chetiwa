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
| Configuration Firebase | Analytics uniquement, désactivé par défaut |

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
