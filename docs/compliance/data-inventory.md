# Inventaire des données — Chetiwa préproduction

Dernière mise à jour : 24 août 2026. Cet inventaire doit rester aligné avec la
politique, le code et les formulaires Store.

| Donnée | Finalité | Stockage | Rétention/suppression |
| --- | --- | --- | --- |
| Lieu principal, récents et lieux nommés | Afficher la météo choisie | Appareil | Jusqu'à suppression locale |
| Préférences, quiet hours et caches | Personnaliser/résilient hors ligne | Appareil | Jusqu'à effacement/désinstallation |
| Position GPS | Choisir ponctuellement un point | Mémoire et requête météo | Pas d'historique de déplacements |
| Recherche et coordonnées consultées | Forecast, radar, carte, géocodage | API/fournisseurs ; caches mutualisés et arrondis | Selon cache et contrats fournisseurs |
| Identifiant aléatoire d'installation | Sécurité, télémétrie d'usage, rollout | Brut sur appareil/requête ; SHA-256 côté backend | Compteur 30 jours ; renouvelé après effacement complet |
| Token APNs/FCM et règle d'alerte | Envoyer l'alerte demandée | Firestore | Suppression à la désactivation ; TTL appareil 180 jours |
| Événements allow-listés | Usage produit après consentement | Firebase Analytics | Selon configuration Firebase publiée |
| Crash/stack trace | Fiabilité après consentement | Firebase Crashlytics | Selon configuration Firebase publiée |
| Métriques backend agrégées | Disponibilité, coût, erreurs | Backend/Firestore | Métriques alertes 30 jours ; aucun token/coordonnée dans les logs |

## Interdictions d'implémentation

- ne jamais journaliser token push, identifiant brut, recherche ou coordonnées
  précises ;
- ne jamais envoyer un lieu météo à un profil publicitaire ;
- ne demander une permission qu'au moment de la fonction correspondante ;
- maintenir la recherche manuelle sans permission GPS ;
- documenter tout nouveau champ avant persistance ;
- ne pas activer pubs ou Premium avant mise à jour privacy/consent/stores.
