# Matrice de préparation de l’application

Dernière mise à jour : 20 août 2026

Cette matrice couvre les contrôles automatisables de la Gate 1. Elle complète les
scénarios météo de référence et la matrice mondiale des fuseaux horaires. Les
contrôles visuels sur appareils réels restent une validation de release séparée.

La Gate 1 est également couverte par 30 captures d’intégration reproductibles :
cinq scénarios × trois écrans × Android Emulator et iOS Simulator. Les captures
et le protocole sont documentés dans les
[scénarios météo de référence](weather-reference-scenarios.md).

## Réseau et cycle de vie

| Situation | Comportement attendu | Couverture |
|---|---|---|
| Réseau lent | Les dernières données en cache restent visibles pendant l’actualisation | `weather_resilience_test.dart` |
| Réseau coupé | Le cache reste visible avec une explication hors-ligne non bloquante | `weather_resilience_test.dart` |
| Réseau intermittent | Une erreur transitoire peut être récupérée par la prochaine actualisation | `weather_resilience_test.dart` |
| Fournisseur lent ou instable | Timeout de 12 secondes et trois tentatives avec backoff | tests des repositories Open-Meteo et RainViewer |
| Retour au premier plan | Météo et radar sont resynchronisés, sans vider l’écran | `app_readiness_test.dart` |
| Passage en arrière-plan | L’animation radar est arrêtée pour ne pas consommer inutilement | `radar_bloc_playback_test.dart` |

Le flux reste stale-while-revalidate : le cache est rendu immédiatement, puis la
source distante est sollicitée en arrière-plan. Une erreur réseau ne remplace pas
des données déjà utilisables par un écran vide.

## Apparence et accessibilité visuelle

| Profil | Taille logique | Facteur de texte | Résultat automatisé |
|---|---:|---:|---|
| Petit téléphone | 320 × 568 | 200 % | Aucun overflow, contenu principal défilable |
| Téléphone standard | 390 × 844 | 100 % | Aucun overflow |
| Paysage compact | 844 × 390 | 100 % | Aucun overflow, graphe compact défilable |
| Tablette | 800 × 1280 | 130 % | Aucun overflow |

Les thèmes Système, Clair et Sombre et les langues Français/Anglais sont
persistés. Le changement est appliqué sans redémarrer l’application. Le Graph et
le Radar conservent une surface sombre spécialisée en thème clair afin de garder
le contraste des données et des tuiles cartographiques.

## Audit FR/EN

Sont localisés : navigation, partage et réglages, recherche mondiale et position
actuelle, onboarding, états réseau/cache, prévisions horaires et quotidiennes,
résumé météo, Graph (y compris les libellés dessinés), Radar, légende, couches,
timeline, thème, langue et pages temporaires Confidentialité/Chetiwa+.

Les noms de villes et pays proviennent du géocodeur et restent dans la langue
retournée par la source. Les noms de fournisseurs, unités, heures et valeurs ne
sont pas traduits. Les documents juridiques définitifs seront ajoutés pendant la
phase Conformité et Stores.

## Commandes de validation

```sh
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --simulator --no-codesign

# Validation visuelle (remplacer les identifiants de device)
flutter drive --driver=test_driver/visual_validation_driver.dart \
  --target=integration_test/reference_weather_visual_test.dart \
  -d <device>
```

Avant une release publique, exécuter aussi les cinq scénarios météo de référence
sur au moins un iPhone et un appareil Android réels, en clair et en sombre, puis
archiver les captures dans le dossier de release.
