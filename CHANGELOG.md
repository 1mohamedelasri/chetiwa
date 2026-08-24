# Changelog

## 1.0.0-beta.1 — en préparation

- Météo mondiale, Graph, Radar et Prévisions synchronisés sur le même lieu.
- Recherche, GPS à la demande et sélection directe sur carte.
- Cache local résilient et comportement clair hors connexion.
- Alertes pluie configurables ; l'infrastructure FCM/APNs est prête mais reste
  désactivée tant que les comptes Firebase et Apple ne sont pas provisionnés.
- Préférences locales effaçables depuis Réglages.
- Aucun compte, achat, publicité ni SDK publicitaire actif.
- Radar gratuit sans quota local artificiel de 20 consultations.
- Feature flags distants à activation progressive pour Premium, publicités et
  alertes, tous désactivés par défaut au lancement.
- Firebase Analytics et Crashlytics soumis au consentement explicite ; Analytics
  ne collecte que les quatre événements anonymes documentés.
- Automatisation GitHub Actions pour vérifier et construire les candidats
  Android/iOS, plus déploiement Cloud Run et supervision de l'API.
