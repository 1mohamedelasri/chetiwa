# Inventaire minimal des données — MVP bêta locale

Ce document décrit le comportement réellement embarqué dans le MVP. Il devra être
relu avec les textes Privacy Policy/Terms et par un conseil compétent avant toute
distribution externe. Les éléments backend/push/achats sont reportés. Firebase
Analytics est configuré techniquement, mais sa collecte est désactivée par
défaut. Elle ne peut être activée qu'après un choix explicite et réversible dans
Réglages ; la déclaration stores doit refléter le comportement effectivement
publié.

| Donnée | Finalité | Stockage prévu | Rétention cible | Suppression |
| --- | --- | --- | --- | --- |
| Lieu principal et récents | Afficher la météo du lieu choisi | Appareil de l'utilisateur | Jusqu’à remplacement/suppression | Réglages et geste de suppression |
| Préférences d’alerte locales | Délai, seuil, quiet hours, état actif | Appareil de l'utilisateur | Jusqu’à désinstallation ou effacement local | Désactivation/effacement app |
| Position actuelle | Afficher la météo après action explicite | Mémoire pendant le parcours | Non persistée comme position GPS | Fin du parcours / changement de lieu |
| Coordonnées du lieu consulté | Appeler météo, radar et carte | Requête aux fournisseurs concernés | Selon leurs conditions, à vérifier avant bêta externe | Choisir un autre lieu / arrêter d'utiliser le service |
| Événements Analytics autorisés | Usage essentiel et disponibilité Radar après consentement | Firebase Analytics, sans lieu/coordonnées/URL/valeur météo | Selon la configuration Firebase publiée | Désactivation dans Réglages et procédure Firebase applicable |

## Hors MVP — ne pas activer sans mise à jour de cet inventaire

- hash d'identifiant d'installation, token APNs/FCM, alertes distantes ;
- compte, sauvegarde cloud, achats ou droits Premium ;
- crash reporting, publicité ou identifiant publicitaire ;
- analytics Firebase tant que l'utilisateur n'a pas activé le choix dédié.

Règles d’implémentation :

- ne jamais journaliser le token push, l’identifiant brut ou les coordonnées
  précises ;
- ne pas partager le lieu météo avec le profil publicitaire ;
- ne demander localisation et notifications qu’au moment où la fonction les
  nécessite ;
- permettre une météo par recherche manuelle sans permission GPS ;
- documenter chaque nouveau champ avant de le persister ;
- vérifier sous-traitants, DPA, région, transferts et sous-processeurs avant
  d’activer un service en production.
