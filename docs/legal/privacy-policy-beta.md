# Politique de confidentialité — Chetiwa

**Brouillon préproduction — à faire relire et à publier avant la bêta externe.**

Dernière mise à jour du brouillon : 30 septembre 2026. Champs bloquants à remplacer :
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
| Token APNs/FCM, règle d'alerte, coordonnées et fuseau | Envoyer une alerte pluie demandée | Suppression sur demande depuis l'app lorsque la connexion le permet ; durée maximale d'inactivité à finaliser avant publication |
| Interactions produit minimales | Mesurer les fonctions utilisées | Firebase Analytics uniquement après consentement |
| Crash et diagnostic technique | Corriger les erreurs | Firebase Crashlytics uniquement après le même consentement ; aucune coordonnée météo ajoutée volontairement |
| Données techniques du SDK cartographique | Afficher la carte et maintenir le service Google Maps | Selon la version du SDK et les conditions Google Maps ; distinctes du consentement Firebase |

**Note de préparation à retirer après résolution :** l'audit du 19 septembre
2026 confirme uniquement la suppression automatique des métriques d'exécution
`alertRunMetrics` après leur échéance de 30 jours. Les champs `expiresAt` à
180 jours des appareils/règles ne déclenchent pas leur suppression tant que
les politiques correspondantes restent désactivées. Ne pas publier une
promesse de suppression automatique à 180 jours avant validation et test de
la politique de rétention choisie.

Les recherches, coordonnées et requêtes techniques transitent par l'API Chetiwa
et ses fournisseurs nécessaires. Les journaux d'infrastructure peuvent contenir
l'adresse IP, l'heure, la version de l'app et des informations de sécurité. Les
tokens push et identifiants bruts ne sont jamais écrits dans les journaux
applicatifs.

Le SDK Google Maps traite également des informations techniques. La fiche
Android du fournisseur décrit notamment un identifiant pseudonyme propre au
SDK, l'adresse IP, des diagnostics et, selon l'utilisation, des interactions
avec la carte. Le choix Analytics/Crashlytics de Chetiwa ne contrôle pas cette
collecte cartographique. Vérifier les versions Android et iOS de la build
publiée et leurs déclarations avant publication.

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

« Effacer les données locales » désactive Analytics/Crashlytics et demande la
suppression de l'enregistrement push et des règles d'alerte de cette
installation avant d'effacer ses préférences. Si la suppression distante
échoue, l'app demande de se reconnecter et de réessayer ; elle conserve
l'identifiant nécessaire à la demande. La désinstallation seule n'envoie pas
de demande de suppression au serveur.

## Destinataires et bases

Les destinataires techniques comprennent l'éditeur de Chetiwa, Hetzner pour
l'hébergement, Cloudflare pour l'acheminement et le cache, Google
Cloud/Firebase, Apple/Google pour les push, Open-Meteo pour les prévisions et
la recherche de lieux, et Google Maps pour les cartes. Le radar est traité par
le logiciel LibreWXR auto-hébergé ; ses sources météo amont doivent être
énumérées dans les crédits de la version publiée. ArcGIS pour les noms de
lieux à partir de coordonnées et les sources de vigilance officielle ne
doivent figurer dans la politique publiée que s'ils sont effectivement actifs.

**Note de préparation :** compléter les pays de traitement, garanties de
transfert, durées des journaux et liens publics à partir des accords retenus.
Le [registre interne](../compliance/provider-register.md) ne constitue pas
une page publique de confidentialité.

La météo demandée et la sécurité du service sont nécessaires à l'exécution du
service. La prévention des abus et la disponibilité relèvent de l'intérêt
légitime de l'éditeur. Analytics, Crashlytics et toute publicité non strictement
nécessaire reposent sur un consentement lorsqu'il est requis.

## Droits et contact

Selon la réglementation applicable, vous pouvez demander accès, rectification,
effacement, limitation ou opposition à `[E-MAIL CONFIDENTIALITÉ]`. La suppression
depuis l'app est le parcours disponible pour les données d'alerte associées à
l'installation. La procédure de demande au support doit être finalisée avant
publication sans demander aux utilisateurs de partager un token push ou un
identifiant secret. Une réclamation peut être adressée à l'autorité de contrôle
compétente.

La politique est accessible dans l'app et à `[URL PUBLIQUE]`. Elle sera mise à
jour avant toute modification substantielle. La CNIL recommande une information
accessible avant téléchargement et contextualisée avant chaque permission :
[recommandations applications mobiles](https://www.cnil.fr/fr/permissions-applications-mobiles-recommandations-de-la-cnil-pour-respecter-la-vie-privee).

## Référence technique pour la préparation

- [Collecte du SDK Google Maps Android](https://developers.google.com/maps/documentation/android-sdk/play-data-disclosure), consultée le 30 septembre 2026.
