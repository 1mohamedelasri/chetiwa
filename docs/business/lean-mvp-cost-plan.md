# Chetiwa — plan de lancement frugal

Ce document traduit l'ADR-0008 en décisions pratiques. Son objectif est de
valider Chetiwa avant d'engager des coûts récurrents.

## Ce qui reste gratuit par défaut

| Élément | Décision MVP | Pourquoi |
| --- | --- | --- |
| Compte utilisateur | Aucun | Aucun serveur d'identité ni données à gérer |
| Lieux, réglages et préférences | Local sur l'appareil | Fonctionne sans base cloud |
| Localisation | GPS sur action, ou recherche manuelle | Pas de suivi permanent |
| Cache météo | Cache disque existant | Réduit les appels et garde une app utile hors ligne |
| Alertes | Réglages et explication seulement | Pas de promesse push tant que la précision n'est pas validée |
| Carte standard | Fond autorisé avec attribution | Éviter satellite et tuiles premium |
| Analyse bêta | Feedback volontaire, tests et métriques locales minimales | Pas de SDK de tracking avant nécessité |

## Ce que nous ne payons pas maintenant

- Firestore, Remote Config, Crashlytics/Analytics, APNs/FCM, RevenueCat et
  AdMob ne sont pas des prérequis du MVP.
- Esri Satellite reste désactivé.
- Le moteur serveur Smart Rain Alerts et le nowcast commercial restent différés.
- Aucun abonnement fournisseur n'est souscrit tant que sa licence, son quota et
  son coût par session réelle ne sont pas vérifiés.

## Parcours avant le premier euro

1. Terminer le choix de lieu sur carte, les permissions GPS et les tests sur
   appareils physiques.
2. Lancer une bêta fermée sans publicité, abonnement ni promesse d'alerte
   distante.
3. Mesurer sur quatre semaines : activation, D7, sessions radar, tuiles/session,
   taux d'erreur et retours sur la précision.
4. Écrire une estimation basse de revenu et haute de coût. Ne pas ouvrir un
   fournisseur payant si la dépense mensuelle maximum dépasse le plafond choisi
   par le propriétaire.
5. Choisir **une seule** première voie de revenus (Premium ou publicité) et
   valider son parcours en sandbox avant de l'activer.

## Règle de décision fournisseur

Avant un lancement public ou monétisé, remplir le registre fournisseurs avec :

- droit de distribution exact (bêta, public, publicité, abonnement) ;
- quota, prix par unité et coût maximal mensuel ;
- nombre maximal de requêtes/tuiles/frames autorisées par session ;
- attribution, durée de cache, DPA et pays de traitement ;
- bouton d'arrêt et comportement de repli.

Si un fournisseur gratuit ne couvre pas explicitement le cas d'usage, il reste
limité au développement ou à la bêta autorisée. Ce n'est pas une dette à payer
maintenant : c'est un gate pour décider si Chetiwa a assez de valeur pour payer.
