# Checklist bêta privée — Chetiwa

## Bloquants avant invitation de testeurs externes

- [ ] Créer et publier les URL HTTPS de la politique de confidentialité et des
  conditions, après remplacement de tous les champs entre crochets dans les
  deux brouillons légaux.
- [ ] Nommer l'entité responsable, une adresse e-mail support/confidentialité et
  un canal de feedback.
- [ ] Obtenir par écrit le droit de distribuer la bêta avec Open-Meteo,
  LibreWXR et le fond Esri effectivement utilisés, ou désactiver/remplacer
  le composant concerné.
- [ ] Compléter le [gate conformité du lancement public](../compliance/public-launch-gate.md)
  et archiver une [fiche de preuve par fournisseur](../compliance/provider-evidence-template.md).
- [ ] Vérifier les attributions visibles dans l'app et les copier dans les
  métadonnées Store si nécessaire.
- [ ] Remplir App Privacy et Data Safety d'après le comportement réel du MVP,
  y compris Firebase Analytics, Crashlytics, l'identifiant d'installation et le
  token push lorsque ces fonctions sont présentes dans la build distribuée.
- [ ] Tester depuis une installation propre sur un Android et un iPhone :
  recherche, carte, GPS refusé/accordé, GPS désactivé, position approximative,
  dernière position connue, mode hors ligne et suppression des lieux.
- [ ] Vérifier qu'aucune clé, URL de staging, identifiant test ou donnée privée
  n'est présente dans l'APK/IPA de test.
- [ ] Faire passer la build par le workflow CI puis exécuter le
  [smoke test sur appareils physiques](physical-device-smoke-test.md) et archiver
  les résultats avant toute invitation externe.

## Déclaration actuelle du MVP (à revalider avant envoi)

- Aucun compte, aucune publicité active, aucun achat actif et aucun tracking
  publicitaire.
- Firebase Analytics et Crashlytics sont désactivés par défaut. Ils ne peuvent être activés qu'après
  un choix explicite et réversible ; seuls les événements anonymes documentés
  dans `ADR-0007` sont alors transmis.
- Lieux et préférences : stockage local sur l'appareil.
- GPS : demandé seulement après action ; pas de suivi en arrière-plan.
- Notifications : push distant opt-in ; token et règle supprimables dans l'app.
- Réseau : coordonnées du lieu consulté envoyées au backend et aux fournisseurs
  météo/radar/carte nécessaires à l'affichage.

## Ne pas activer pendant la bêta frugale

- Publicité, personnalisation publicitaire ou identifiant publicitaire.
- Abonnement, achat intégré ou RevenueCat.
- Performance Monitoring, personnalisation publicitaire ou autre SDK cloud non
  inventorié. Firestore/FCM restent désactivés tant que le provisionnement et le
  test de suppression ne sont pas validés.
- Satellite Esri ou un fournisseur dont le droit de distribution n'est pas
  écrit et archivé.
