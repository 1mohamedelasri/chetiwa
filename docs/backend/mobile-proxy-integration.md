# Intégration mobile du proxy Chetiwa

## Sélection de l’environnement

Le mobile lit uniquement des valeurs de compilation non secrètes :

- `CHETIWA_ENV=development|staging|production` ;
- `CHETIWA_API_BASE_URL=https://…` ;
- `CHETIWA_ALLOW_DIRECT_PROVIDER_FALLBACK=true|false`.

Une build `production` refuse de démarrer sans URL backend absolue HTTPS. Le
fallback direct Open-Meteo/RainViewer est réservé au développement et doit être
désactivé pendant les tests d’intégration.

## Chemin des données

```text
Graph / Prévisions ─┐
Radar ──────────────┼─> repositories Chetiwa ─> API v1 ─> adaptateurs fournisseurs
Recherche / GPS ────┘            │
                                 └─> cache disque SWR mobile
```

Le client conserve jusqu’à 32 réponses avec leur `ETag` en mémoire pour traiter
les `304`. Les données météo et radar restent également dans les caches disque
existants. L’identifiant envoyé dans `X-Chetiwa-Device-Id` est un nombre aléatoire
de 128 bits propre à l’installation : il n’est lié ni au compte, ni à la
publicité, ni aux coordonnées.

## Développement local

```sh
cd backend
docker compose up --build
```

iOS Simulator :

```sh
flutter run \
  --dart-define=CHETIWA_API_BASE_URL=http://127.0.0.1:8080 \
  --dart-define=CHETIWA_ALLOW_DIRECT_PROVIDER_FALLBACK=false
```

Android Emulator :

```sh
flutter run \
  --dart-define=CHETIWA_API_BASE_URL=http://10.0.2.2:8080 \
  --dart-define=CHETIWA_ALLOW_DIRECT_PROVIDER_FALLBACK=false
```

Android n’autorise le HTTP local que dans le manifeste `debug`. iOS autorise
uniquement le réseau local via ATS. Aucun assouplissement HTTP général n’existe
dans les configurations de publication.

## Preuves automatisées

- tests unitaires : identifiant stable, `ETag/304`, mapping Forecast, Radar et
  recherche mondiale ;
- `integration_test/backend_proxy_smoke_test.dart` : Graph, Radar et Prévisions
  chargés via le backend réel, fallback coupé ; il vide uniquement le cache de
  tuiles Radar, attend une vraie image décodée, déplace la carte dans quatre
  directions, vérifie le zoom 7→10, parcourt toute l'animation utile et injecte
  un unique HTTP 502 avant de vérifier la récupération ;
- parcours validé sur Android Emulator et iOS Simulator ;
- compilation Android release et iOS avec configuration `production` HTTPS.

Commande sur appareil physique, avec un backend joignable par le téléphone :

```sh
flutter test integration_test/backend_proxy_smoke_test.dart \
  -d <device-id> \
  --dart-define=CHETIWA_ENV=staging \
  --dart-define=CHETIWA_API_BASE_URL=https://api-staging.chetiwa.example \
  --dart-define=CHETIWA_ALLOW_DIRECT_PROVIDER_FALLBACK=false \
  --dart-define=CHETIWA_RADAR_SMOKE_TEST=true
```

Sur un iPhone connecté uniquement en Wi-Fi, construire puis réutiliser la build
Profile évite les délais LLDB de Xcode 26 :

```sh
flutter build ios --profile \
  --target=integration_test/backend_proxy_smoke_test.dart \
  --dart-define=CHETIWA_ENV=staging \
  --dart-define=CHETIWA_API_BASE_URL=https://api-staging.chetiwa.example \
  --dart-define=CHETIWA_ALLOW_DIRECT_PROVIDER_FALLBACK=false \
  --dart-define=CHETIWA_RADAR_SMOKE_TEST=true

flutter drive --profile \
  --use-application-binary=build/ios/iphoneos/Runner.app \
  --driver=test_driver/visual_validation_driver.dart \
  --target=integration_test/backend_proxy_smoke_test.dart \
  -d <device-id>
```

`CHETIWA_RADAR_SMOKE_TEST` n'est activé dans aucune configuration normale. Sans
ce define, la purge ciblée du cache et l'injection 502 sont inopérantes.

## Restant avant production

- déployer staging/production et injecter les secrets depuis Secret Manager ;
- choisir le fournisseur radar commercial et décider proxy/CDN des tuiles ;
- ajouter rate limiting distribué et attestation d’application ;
- créer les endpoints devices/alertes et les droits Premium.
