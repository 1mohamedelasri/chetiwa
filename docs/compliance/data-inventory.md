# Inventaire des données — Chetiwa préproduction

Dernière mise à jour : 30 septembre 2026. Cet inventaire doit rester aligné avec la
politique, le code et les formulaires Store.

| Donnée | Finalité | Stockage | Rétention/suppression |
| --- | --- | --- | --- |
| Lieu principal, récents et lieux nommés | Afficher la météo choisie | Appareil | Jusqu'à suppression locale |
| Préférences, quiet hours et caches | Personnaliser/résilient hors ligne | Appareil | Jusqu'à effacement/désinstallation |
| Position GPS | Choisir ponctuellement un point | Mémoire et requête météo | Pas d'historique de déplacements |
| Recherche et coordonnées consultées | Forecast, radar, carte, géocodage | API/fournisseurs ; caches mutualisés et arrondis | Selon cache et contrats fournisseurs |
| Identifiant aléatoire d'installation | Sécurité, télémétrie d'usage, rollout | Brut sur appareil/requête ; SHA-256 côté backend | Compteur 30 jours ; renouvelé après effacement complet |
| Token APNs/FCM et règle d'alerte | Envoyer l'alerte demandée | Firestore | Demande de suppression à la désactivation/à l'effacement ; connexion nécessaire. Échéance d'inactivité écrite à 180 jours, mais TTL correspondant non activé lors de l'audit du 19 septembre |
| Événements allow-listés | Usage produit après consentement | Firebase Analytics | Selon configuration Firebase publiée |
| Crash/stack trace | Fiabilité après consentement | Firebase Crashlytics | Selon configuration Firebase publiée |
| Métriques backend agrégées | Disponibilité, coût, erreurs | Backend/Firestore | Métriques alertes 30 jours ; aucun token/coordonnée dans les logs |
| Métadonnées, IP, identifiant SDK Maps, diagnostics et interactions de carte selon utilisation | Cartographie, stabilité et amélioration du SDK | Google Maps | À confirmer avec les conditions et la version de SDK publiées ; ne dépend pas du choix Firebase |
| Journaux de requêtes d'infrastructure | Acheminement et sécurité | Hetzner/Cloudflare/API et fournisseurs nécessaires | Vérifier configuration et durées contractuelles avant de promettre une durée publique |

## Points à résoudre avant la déclaration Store

- Une installation sans compte reste identifiable par son identifiant stable,
  son token et leurs associations aux alertes. Le hachage ne rend pas
  automatiquement ces données anonymes.
- L'audit du 19 septembre confirme le TTL de `alertRunMetrics.expiresAt`
  uniquement ; les politiques des appareils, règles et livraisons restent
  désactivées. Arrêter et tester leur politique de rétention avant publication.
- L'effacement distant est exécuté avant la perte de l'identifiant local et
  reprend après échec. Une désinstallation seule ne déclenche pas cette API.
- Les préférences Firebase ne pilotent pas les diagnostics du SDK Maps.
  Vérifier les SDK natifs et les manifestes de confidentialité de la build
  signée, pas uniquement les événements explicitement émis en Dart.
- Aucun site public de confidentialité/support n'est configuré dans le dépôt.
  Les documents légaux sont des brouillons ; ne pas les citer comme publiés.

Références de comportement : `remote_rain_alert_gateway.dart`,
`settings_screen.dart`, `firestore_device_alert_store.dart`,
`analytics_consent_controller.dart` et
[fiche Google Maps Android](https://developers.google.com/maps/documentation/android-sdk/play-data-disclosure)
(consultée le 30 septembre 2026).

## Interdictions d'implémentation

- ne jamais journaliser token push, identifiant brut, recherche ou coordonnées
  précises ;
- ne jamais envoyer un lieu météo à un profil publicitaire ;
- ne demander une permission qu'au moment de la fonction correspondante ;
- maintenir la recherche manuelle sans permission GPS ;
- documenter tout nouveau champ avant persistance ;
- ne pas activer pubs ou Premium avant mise à jour privacy/consent/stores.
