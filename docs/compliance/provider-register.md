# Chetiwa — registre fournisseurs v1

Dernière vérification : 2026-08-25.

Ce registre n’est pas un avis juridique. Les conditions officielles et contrats
signés prévalent. Une revue finale juridique/confidentialité est obligatoire
avant monétisation.

| Fournisseur | Usage | Stade autorisé | Coût/limite suivie | Attribution/contrat | Repli |
| --- | --- | --- | --- | --- | --- |
| Open-Meteo | Forecast, Graph, geocoding | Gratuit uniquement en prototype non commercial ; plan commercial avant publication commerciale | Free 10 k/jour et 300 k/mois ; Standard 1 M/mois ; Professional 5 M/mois | Attribution CC BY ; contrat commercial à archiver | Dernier cache + message données anciennes |
| LibreWXR auto-hébergé | Radar et point-nowcast actuels | Bêta contrôlée après stabilité origine/CDN ; validation des données amont avant public | Capacité mesurée, VM Hetzner et Cloudflare ; pas de quota utilisateur fournisseur unique | Licence du code et droits/attributions de chaque donnée amont à archiver | Cache mobile, stale CDN et kill switch |
| RainViewer | Ancien radar prototype | Non utilisé dans la configuration de production actuelle | API publique sans SLA commercial public | Attribution obligatoire ; autorisation commerciale écrite manquante | LibreWXR |
| Rainbow | Radar Tiles et nowcast cible | Production après validation contrat | 30 k tiles/mois puis 0,20 $/1 k ; nowcast 5 k puis 0,10 $/1 k selon page officielle actuelle | Conditions, attribution, cache et DPA à archiver | Limiter frames + cache + désactivation |
| OpenFreeMap | Fond vectoriel standard Radar et sélecteur de lieu | Production initiale autorisée selon les conditions publiques, sans SLA | Instance publique annoncée gratuite sans limite | Attribution OpenFreeMap/OpenMapTiles/OpenStreetMap visible | Cache disque, fond minimal ou PMTiles self-hosted |
| Esri | Satellite Chetiwa+ optionnel | Désactivé par défaut ; activer après compte, token, budget et validation des achats | 2 M tuiles gratuites puis 0,15 $/1 k selon tarification actuelle | Token et attribution Esri/data | OpenFreeMap standard ; kill switch `PREMIUM_SATELLITE_ENABLED` |
| Google Cloud/Firebase | API, devices, push, config, observabilité | Staging/prod après DPA et région UE | Free tiers + pay-as-you-go, budgets et max instances | DPA, sous-traitants et rétention à archiver | Cache mobile, runbook panne |
| RevenueCat | Entitlements abonnements | Sandbox puis production | Gratuit jusqu’au seuil MTR officiel, puis pourcentage actuel | DPA, webhooks et politique de données | Validation store directe future |
| Google AdMob/UMP | Ads et consentement | Production après consentement/config stores | Pas de coût fournisseur fixe attendu ; revenu variable | CMP, ATT si requis, Data Safety/App Privacy | Ads désactivées |
| Apple/Google Play | Distribution et paiements | Production | Frais comptes et commissions selon contrats actifs | Contrats développeur, fiscalité, privacy | Aucun pour distribution native |

## Champs à compléter avant Gate 6

- Entité légale contractante et contact support.
- DPA signé/accepté et localisation des traitements.
- Sous-traitants et transferts internationaux.
- Durée de conservation et suppression.
- SLA/support et procédure incident.
- Copie datée des conditions acceptées.
- Clé/token propriétaire, rotation et date d’expiration.

## Liens officiels

- [Open-Meteo terms](https://open-meteo.com/en/terms)
- [Open-Meteo pricing](https://open-meteo.com/en/pricing)
- [RainViewer API](https://www.rainviewer.com/api.html)
- [LibreWXR source](https://github.com/JoshuaKimsey/LibreWXR)
- [Rainbow developer](https://developer.rainbow.ai/)
- [OpenFreeMap](https://openfreemap.org/)
- [OpenFreeMap terms](https://openfreemap.org/tos/)
- [Esri basemap pricing](https://developers.arcgis.com/rest/static-basemap-tiles/)
- [Firebase pricing](https://firebase.google.com/pricing)
- [RevenueCat pricing](https://www.revenuecat.com/pricing)
