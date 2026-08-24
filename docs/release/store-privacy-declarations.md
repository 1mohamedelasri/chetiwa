# Déclarations App Privacy / Data safety — brouillon de saisie

Ce document reflète la release avec publicité et Chetiwa+ désactivés. Revalider
les réponses dans les formulaires Store et les fiches officielles des SDK avant
soumission. Apple demande d'inclure les pratiques des SDK tiers dans
[App Privacy](https://developer.apple.com/app-store/app-privacy-details/) et
Google impose le formulaire Data safety, même en test fermé :
[Play Console Help](https://support.google.com/googleplay/android-developer/answer/10787469).

## App Store Connect

| Type | Collecté | Lié à l'identité | Tracking | Finalité |
| --- | --- | --- | --- | --- |
| Localisation précise/approximative | Oui, lors d'une demande météo ou d'une alerte | Non, aucun compte | Non | Fonctionnalité de l'app |
| Identifiant de l'appareil/installation | Oui | Non | Non | Sécurité, configuration, push |
| Interaction produit | Seulement après consentement Analytics | Non | Non | Analytics |
| Crash Data | Seulement après consentement Crashlytics | Non | Non | Fonctionnalité/diagnostic |

- Aucun nom, e-mail, téléphone, carnet d'adresses, photo, audio ou donnée santé.
- Aucun identifiant publicitaire et aucun tracking inter-app dans cette release.
- Les lieux conservés uniquement sur l'appareil ne sont pas déclarés comme
  collectés ; les coordonnées d'alertes distantes le sont.

## Google Play Data safety

- **L'app collecte-t-elle des données ?** Oui.
- **Données chiffrées en transit ?** Oui, HTTPS/TLS.
- **Suppression disponible ?** Oui : Réglages → Effacer les données locales
  supprime aussi l'enregistrement push ; documenter l'URL de demande manuelle.
- **Localisation approximative/précise** : facultative, fonctionnalité de l'app.
- **Identifiants appareil/autres identifiants** : fonctionnalité, sécurité et push.
- **Activité dans l'app / interactions** : facultative, Analytics après consentement.
- **Crash logs / diagnostics** : facultatifs, Crashlytics après consentement.
- **Partage** : à déclarer « non » uniquement si les contrats confirment que les
  fournisseurs agissent comme prestataires selon l'exception Google. Sinon,
  déclarer les catégories concernées comme partagées.
- **Publicité** : non pour cette release ; refaire le formulaire avant
  `ADS_ENABLED=true`.

## Permissions à justifier

- Localisation au premier plan uniquement, au moment où l'utilisateur demande
  « Ma position » ; aucune permission de localisation arrière-plan.
- Notifications au moment d'activer Smart Rain Alerts.
- Internet et état réseau pour la météo, le radar, Firebase et les cartes.
