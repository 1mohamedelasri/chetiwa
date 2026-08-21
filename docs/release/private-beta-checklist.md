# Checklist bêta privée — Chetiwa

## Bloquants avant invitation de testeurs externes

- [ ] Créer et publier les URL HTTPS de la politique de confidentialité et des
  conditions, après remplacement de tous les champs `[À COMPLÉTER]`.
- [ ] Nommer l'entité responsable, une adresse e-mail support/confidentialité et
  un canal de feedback.
- [ ] Obtenir par écrit le droit de distribuer la bêta avec Open-Meteo,
  RainViewer et le fond de carte effectivement utilisés, ou désactiver/remplacer
  le composant concerné.
- [ ] Vérifier les attributions visibles dans l'app et les copier dans les
  métadonnées Store si nécessaire.
- [ ] Remplir App Privacy et Data Safety d'après le comportement réel du MVP,
  y compris Firebase Analytics si la bascule « Statistiques d’utilisation » est
  disponible dans la build distribuée.
- [ ] Tester depuis une installation propre sur un Android et un iPhone :
  recherche, carte, GPS refusé/accordé, GPS désactivé, position approximative,
  dernière position connue, mode hors ligne et suppression des lieux.
- [ ] Vérifier qu'aucune clé, URL de staging, identifiant test ou donnée privée
  n'est présente dans l'APK/IPA de test.
- [ ] Faire passer la build par le workflow CI puis exécuter le
  [smoke test sur appareils physiques](physical-device-smoke-test.md) et archiver
  les résultats avant toute invitation externe.

## Déclaration actuelle du MVP (à revalider avant envoi)

- Pas de compte, publicité, achat ni tracking publicitaire.
- Firebase Analytics est désactivé par défaut. Il ne peut être activé qu'après
  un choix explicite et réversible ; seuls les événements anonymes documentés
  dans `ADR-0007` sont alors transmis.
- Lieux et préférences : stockage local sur l'appareil.
- GPS : demandé seulement après action ; pas de suivi en arrière-plan.
- Notifications : autorisation système uniquement ; aucun push distant actif.
- Réseau : coordonnées du lieu consulté envoyées aux fournisseurs météo/radar/
  carte nécessaires à l'affichage.

## Ne pas activer pendant la bêta frugale

- Publicité, personnalisation publicitaire ou identifiant publicitaire.
- Abonnement, achat intégré ou RevenueCat.
- Firestore, push distant, Crashlytics, Performance Monitoring, Remote Config
  ou tout autre produit Firebase/Google Cloud.
- Satellite Esri ou un fournisseur dont le droit de distribution n'est pas
  écrit et archivé.
