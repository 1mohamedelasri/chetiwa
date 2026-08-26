# Politique de confidentialité — Chetiwa

**Brouillon préproduction — à faire relire et à publier avant la bêta externe.**

Dernière mise à jour : 24 août 2026. Champs bloquants à remplacer :
`[ENTITÉ LÉGALE]`, `[ADRESSE]`, `[E-MAIL CONFIDENTIALITÉ]` et
`[URL PUBLIQUE]`.

## Responsable et périmètre

`[ENTITÉ LÉGALE]`, `[ADRESSE]`, édite Chetiwa et traite les données décrites
ci-dessous. Chetiwa fonctionne sans création de compte et n'accède à la
localisation qu'après une action de l'utilisateur. Aucun suivi de localisation
en arrière-plan n'est effectué.

## Données utilisées

| Donnée | Finalité | Conservation |
| --- | --- | --- |
| Ville, point choisi et coordonnées | Fournir météo, graphique, radar, carte et cache | Cache météo/radar local ; cache serveur temporaire et mutualisé |
| Position GPS, si autorisée | Choisir le point météo demandé | Utilisation ponctuelle ; pas d'historique de déplacements |
| Lieux enregistrés et préférences | Personnaliser l'app | Sur l'appareil, jusqu'à suppression |
| Identifiant d'installation aléatoire | Sécuriser l'API, déployer les fonctions progressivement et dédupliquer l'usage | Valeur hachée côté serveur ; compteurs Radar 30 jours |
| Token APNs/FCM, règle d'alerte, coordonnées et fuseau | Envoyer une alerte pluie demandée | Jusqu'à désactivation/suppression ; appareil inactif supprimé par TTL après 180 jours |
| Interactions produit minimales | Mesurer les fonctions utilisées | Firebase Analytics uniquement après consentement |
| Crash et diagnostic technique | Corriger les erreurs | Firebase Crashlytics uniquement après le même consentement ; aucune coordonnée météo ajoutée volontairement |

Les recherches, coordonnées et requêtes techniques transitent par l'API Chetiwa
et ses fournisseurs nécessaires. Les journaux d'infrastructure peuvent contenir
l'adresse IP, l'heure, la version de l'app et des informations de sécurité. Les
tokens push et identifiants bruts ne sont jamais écrits dans les journaux
applicatifs.

## Permissions et choix

- **Localisation** : facultative ; la recherche manuelle et la carte restent
  disponibles sans GPS.
- **Notifications** : demandées uniquement lors de l'activation des alertes.
- **Statistiques et rapports de panne** : désactivés par défaut. Un choix
  facultatif peut être présenté une seule fois lorsque le flag correspondant
  est actif ; un refus est mémorisé sans relance répétée. Le choix reste
  modifiable dans Réglages.
- **Publicité et Chetiwa+** : désactivés au lancement par feature flags. Toute
  activation exige une mise à jour des déclarations, du consentement et de cette
  politique avant exposition aux utilisateurs.

« Effacer les données locales » désactive la collecte, supprime les préférences
locales et demande la suppression de l'enregistrement push et des règles
d'alerte de cette installation. La désinstallation supprime les données locales.

## Destinataires et bases

Les destinataires techniques sont Chetiwa, Google Cloud/Firebase, Apple/Google
pour les push, Open-Meteo pour les prévisions et le géocodage, LibreWXR pour le
radar, et les fournisseurs cartographiques attribués dans l'app. Le registre à
jour est disponible dans
[`provider-register.md`](../compliance/provider-register.md).

La météo demandée et la sécurité du service sont nécessaires à l'exécution du
service. La prévention des abus et la disponibilité relèvent de l'intérêt
légitime de l'éditeur. Analytics, Crashlytics et toute publicité non strictement
nécessaire reposent sur un consentement lorsqu'il est requis.

## Droits et contact

Selon la réglementation applicable, vous pouvez demander accès, rectification,
effacement, limitation ou opposition à `[E-MAIL CONFIDENTIALITÉ]`. Sans compte,
la demande doit fournir l'identifiant technique affichable par le support si une
donnée distante doit être retrouvée. Une réclamation peut être adressée à la
CNIL.

La politique est accessible dans l'app et à `[URL PUBLIQUE]`. Elle sera mise à
jour avant toute modification substantielle. La CNIL recommande une information
accessible avant téléchargement et contextualisée avant chaque permission :
[recommandations applications mobiles](https://www.cnil.fr/fr/permissions-applications-mobiles-recommandations-de-la-cnil-pour-respecter-la-vie-privee).
