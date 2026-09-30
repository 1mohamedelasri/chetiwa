# Déclarations App Privacy / Data safety — brouillon de saisie

Statut au 30 septembre 2026 : **brouillon non soumis, validation encore requise**.
Ce document vise la release avec publicité et Chetiwa+ désactivés. Aucun
formulaire Store rempli n'a été vérifié. Revalider les réponses sur la build
signée et les fiches des SDK réellement embarqués avant soumission. Apple
demande d'inclure les pratiques des SDK tiers dans
[App Privacy](https://developer.apple.com/app-store/app-privacy-details/) et
Google impose le formulaire Data safety, même en test fermé :
[Play Console Help](https://support.google.com/googleplay/android-developer/answer/10787469).

## App Store Connect — base de travail

| Type | Collecté | Lié à l'identité | Tracking | Finalité |
| --- | --- | --- | --- | --- |
| Localisation précise/approximative | Oui pour les alertes distantes ; vérifier aussi les caches/journaux des demandes météo et SDK | Oui pour les coordonnées d'alertes rattachées à l'installation | Pas de tracking publicitaire implémenté ; vérifier les SDK/configurations | Fonctionnalité de l'app |
| Identifiant de l'appareil/installation et push | Oui | Oui pour l'identifiant stable et les données associées | Même contrôle | Sécurité, configuration, push |
| Interaction produit | Analytics après consentement ; vérifier séparément Maps et les dépendances natives | À déterminer d'après les identifiants réellement transmis | Même contrôle | Analytics / fonctionnement selon le flux |
| Crash Data / diagnostics | Crashlytics après consentement ; autres SDK à inventorier séparément | À déterminer pour chaque SDK | Même contrôle | Fonctionnalité/diagnostic |

L'absence de compte ou d'e-mail ne suffit pas à répondre « non lié à
l'utilisateur ». Apple inclut le lien à l'appareil. Le backend conserve un
hash stable d'installation avec les règles, coordonnées et token push : cette
pseudonymisation ne supprime pas le lien. Une réponse différente doit être
étayée par la façon dont chaque flux est dé-identifié avant collecte et par
les pratiques des partenaires. [Définition Apple](https://developer.apple.com/app-store/app-privacy-details/#data-linked-to-the-user).

- Aucun nom, e-mail, téléphone, carnet d'adresses, photo, audio ou donnée santé.
- Publicité et tracking publicitaire désactivés dans la configuration prévue ;
  confirmer sur la build native finale, y compris les SDK présents mais inactifs.
- Les lieux conservés uniquement sur l'appareil ne sont pas déclarés comme
  collectés ; les coordonnées d'alertes distantes le sont.

## Google Play Data safety

- **L'app collecte-t-elle des données ?** Oui.
- **Données chiffrées en transit ?** Oui, HTTPS/TLS.
- **Suppression disponible ?** Parcours implémenté : Réglages → Effacer les
  données locales demande aussi l'effacement distant. Une connexion est
  nécessaire ; en cas d'échec l'app conserve l'identifiant et demande de
  réessayer. Valider ce parcours sur la build et les workers publiés avant de
  confirmer la réponse ; finaliser le contact/la page de demande manuelle.
- **Localisation approximative/précise** : facultative, fonctionnalité de l'app.
- **Identifiants appareil/autres identifiants** : fonctionnalité, sécurité et push.
- **Activité dans l'app / interactions** : Analytics facultatif après
  consentement ; évaluer séparément les interactions émises par Google Maps.
- **Crash logs / diagnostics** : Crashlytics facultatif après consentement ;
  ne pas déclarer tous les diagnostics facultatifs, car Maps possède sa propre
  collecte technique indépendante de ce choix.
- **Partage** : à déclarer « non » uniquement si les contrats confirment que les
  fournisseurs agissent comme prestataires selon l'exception Google. Sinon,
  déclarer les catégories concernées comme partagées.
- **Publicité** : non pour cette release ; refaire le formulaire avant
  `ADS_ENABLED=true`.

Les coordonnées d'alertes sont persistées. Ne pas déclarer l'ensemble des
localisations comme éphémères : il faut vérifier chaque cache, journal et
fournisseur. Les données pseudonymes restent dans le périmètre du formulaire.

## Preuves à joindre avant saisie finale

- [ ] Version/build et liste des SDK natifs résolus, avec leurs manifestes.
- [ ] Configuration de production : publicité/achats désactivés, état des
  alertes, consentement Firebase et absence de collecte avant ce consentement.
- [ ] Vérification des SDK cartographiques indépendamment de Firebase ; la
  [fiche Android Maps](https://developers.google.com/maps/documentation/android-sdk/play-data-disclosure)
  doit être rapprochée de la version embarquée.
- [ ] Vérification des dépendances Firebase directes et transitives avec les
  fiches [Android](https://firebase.google.com/docs/android/play-data-disclosure)
  et [Apple](https://firebase.google.com/docs/ios/app-store-data-collection).
- [ ] Résultat du test de suppression, politique de rétention effective et
  contact public. Le TTL appareils à 180 jours n'était pas activé au dernier
  audit ; seule la purge des métriques à 30 jours était confirmée.
- [ ] Droits et rôles des fournisseurs, pays de traitement et garanties de
  transfert ; justification de toute exception au « partage ».
- [ ] URL HTTPS publique sans authentification, texte identique à celui
  accessible depuis l'app, identité de l'éditeur et contact confirmés.
- [ ] Export/captures des formulaires effectivement soumis avec la date et
  la version correspondante.

Fiches officielles consultées le 30 septembre 2026. Une fiche pour le SDK le
plus récent ne remplace pas la vérification de la version résolue du projet.

## Permissions à justifier

- Localisation au premier plan uniquement, au moment où l'utilisateur demande
  « Ma position » ; aucune permission de localisation arrière-plan.
- Notifications au moment d'activer Smart Rain Alerts.
- Internet et état réseau pour la météo, le radar, Firebase et les cartes.
