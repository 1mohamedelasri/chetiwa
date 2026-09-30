# Chetiwa — registre fournisseurs v1

Revue documentaire : 2026-09-30. État des services hébergés : dernier audit
du 2026-09-19, à revalider avant publication. Aucun contrat ou accord propriétaire
n'a été confirmé par cette revue. Les prix/quotas historiques ci-dessous ne
constituent pas un devis actuel ni une autorisation de souscription.

Ce registre n’est pas un avis juridique. Les conditions officielles et contrats
signés prévalent. Une revue finale juridique/confidentialité est obligatoire
avant monétisation.

| Fournisseur | Usage | Stade autorisé | Coût/limite suivie | Attribution/contrat | Repli |
| --- | --- | --- | --- | --- | --- |
| Open-Meteo | Forecast, Graph, geocoding | Free API réservée à l'usage non commercial ; droit commercial et clé exigés par le profil de production actuel | Free 10 k/jour et 300 k/mois ; Standard 1 M/mois ; Professional 5 M/mois, revérifiés le 30 septembre | Attribution CC BY ; abonnement/conditions acceptées à archiver | Dernier cache + message données anciennes |
| LibreWXR auto-hébergé | Radar et point-nowcast actuels | Bêta contrôlée après stabilité origine/CDN ; validation des données amont avant public | Capacité mesurée, VM Hetzner et Cloudflare ; pas de quota utilisateur fournisseur unique | Licence du code et droits/attributions de chaque donnée amont à archiver | Cache mobile, stale CDN et kill switch |
| RainViewer | Ancien radar prototype | Non utilisé dans la configuration de production actuelle | API publique sans SLA commercial public | Attribution obligatoire ; autorisation commerciale écrite manquante | LibreWXR |
| Rainbow | Radar Tiles et nowcast cible | Production après validation contrat | 30 k tiles/mois puis 0,20 $/1 k ; nowcast 5 k puis 0,10 $/1 k selon page officielle actuelle | Conditions, attribution, cache et DPA à archiver | Limiter frames + cache + désactivation |
| Google Maps Platform | Fond satellite hybride Radar et carte standard du sélecteur, pour tous | Production après activation des SDK, facturation et clés restreintes | SKU SDK mobile sans Map ID ; surveiller la tarification et les quotas officiels | Conditions Google Maps, logo/attributions natifs, clés Android/iOS séparées | Graph/Prévisions restent utilisables ; désactivation Radar par configuration si incident |
| Hetzner | VM hébergeant l'API Chetiwa et LibreWXR | Infrastructure observée ; droits/accords et reprise à documenter | Plan VM, RAM/disque, trafic et alertes ; tarif à revérifier avant changement | Conditions, DPA applicable, localisation et procédure de restauration | Cache mobile/CDN ; aucune sauvegarde payante approuvée |
| Cloudflare | Tunnel, routage et cache des domaines API/radar | Infrastructure observée ; paramètres et accords à archiver | Plan actuel, cache, trafic et journaux | Conditions, DPA applicable, traitement réseau et rétention | Cache mobile ; runbook tunnel/origine |
| Google Cloud/Firebase | Firestore, jobs Cloud Run de notifications, FCM, configuration et observabilité ; API HTTP sur Hetzner au dernier audit | Configuration et accords à valider ; jobs de notification en pause au dernier audit | Budgets et coûts pay-as-you-go ; TTL métriques 30 jours uniquement confirmé | DPA, sous-traitants, régions de chaque produit et rétention à archiver | Cache mobile, runbook panne |
| Esri ArcGIS | Géocodage inverse optionnel du backend | Clé absente au dernier audit ; aucune utilisation de production à supposer | Quota et droit d'usage/cache à vérifier avant activation | Conditions et attribution ; traitement des coordonnées | Libellé des coordonnées sans nom de lieu |
| MeteoAlarm/EUMETNET via MeteoGate, Météo-France | Sources des vigilances officielles facultatives | Workers désactivés au dernier audit ; confirmer les sources activées avant publication | Clés, quotas, couverture et fréquence | Licence/droits de redistribution, attribution et conditions de chaque source | Aucune alerte officielle promise si désactivée |
| RevenueCat | Entitlements abonnements | Sandbox puis production | Gratuit jusqu’au seuil MTR officiel, puis pourcentage actuel | DPA, webhooks et politique de données | Validation store directe future |
| Google AdMob/UMP | Ads et consentement | Production après consentement/config stores | Pas de coût fournisseur fixe attendu ; revenu variable | CMP, ATT si requis, Data Safety/App Privacy | Ads désactivées |
| Apple/Google Play | Distribution et paiements | Production | Frais comptes et commissions selon contrats actifs | Contrats développeur, fiscalité, privacy | Aucun pour distribution native |

## Périmètre de la première release

- Les lignes RainViewer/Rainbow décrivent des options historiques ou futures,
  pas des contrats à acheter pour la configuration LibreWXR actuelle.
- RevenueCat, AdMob/UMP et les accords de produits payants restent hors du
  lancement gratuit tant que les fonctionnalités correspondantes sont
  désactivées. Leur présence dans le dépôt ne prouve pas une collecte active.
- L'absence de publicités ne suffit pas à conclure que l'usage Open-Meteo est
  non commercial : ses conditions incluent aussi les produits commerciaux.
  La [licence des données](https://open-meteo.com/en/terms) et le droit d'utiliser
  son service hébergé sont deux éléments à vérifier.
- LibreWXR est un logiciel auto-hébergé, pas l'identité de tous les détenteurs
  de données. Relever chaque source réellement activée et la version déployée,
  puis documenter sa licence et les obligations applicables. Une licence
  publique applicable peut fournir la preuve ; un contrat sur mesure n'est pas
  nécessaire pour chaque source.
- Les fiches officielles ne prouvent ni l'acceptation des conditions par
  l'éditeur ni la configuration d'un compte. Archiver ces preuves séparément.

## Champs à compléter avant Gate 6

- Entité légale contractante et contact support.
- DPA signé/accepté lorsqu'applicable et localisation des traitements.
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
- [Google Maps Platform pricing](https://mapsplatform.google.com/pricing/)
- [Google Maps Platform terms](https://cloud.google.com/maps-platform/terms)
- [Firebase pricing](https://firebase.google.com/pricing)
- [RevenueCat pricing](https://www.revenuecat.com/pricing)
