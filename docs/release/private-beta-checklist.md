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
  sans déclarer un SDK qui n'est pas embarqué.
- [ ] Tester depuis une installation propre sur un Android et un iPhone :
  recherche, carte, GPS refusé/accordé, GPS désactivé, position approximative,
  dernière position connue, mode hors ligne et suppression des lieux.
- [ ] Vérifier qu'aucune clé, URL de staging, identifiant test ou donnée privée
  n'est présente dans l'APK/IPA de test.
- [ ] Faire passer la build par le workflow CI puis exécuter le
  [smoke test sur appareils physiques](physical-device-smoke-test.md) et archiver
  les résultats avant toute invitation externe.

## Déclaration actuelle du MVP (à revalider avant envoi)

- Pas de compte, publicité, achat, tracking ou analytics.
- Lieux et préférences : stockage local sur l'appareil.
- GPS : demandé seulement après action ; pas de suivi en arrière-plan.
- Notifications : autorisation système uniquement ; aucun push distant actif.
- Réseau : coordonnées du lieu consulté envoyées aux fournisseurs météo/radar/
  carte nécessaires à l'affichage.

## Ne pas activer pendant la bêta frugale

- Publicité, personnalisation publicitaire ou identifiant publicitaire.
- Abonnement, achat intégré ou RevenueCat.
- Firebase/Firestore, push distant, analytics ou crash reporting.
- Satellite Esri ou un fournisseur dont le droit de distribution n'est pas
  écrit et archivé.
