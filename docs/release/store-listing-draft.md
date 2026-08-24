# Fiches App Store et Google Play — Chetiwa

## Français

- **Nom** : `Chetiwa : pluie et radar`
- **Sous-titre App Store** : `La pluie, avant qu'elle arrive`
- **Description courte Play** : `Graphique de pluie, radar animé et alertes pour le lieu de votre choix.`
- **Texte promotionnel** : `Voyez la pluie arriver, explorez le radar et gardez vos prévisions essentielles au même endroit.`
- **Mots-clés App Store** : `météo,pluie,radar,prévision,alerte,orage,précipitation,carte,nowcast`

### Description complète

Chetiwa vous aide à comprendre la pluie autour du lieu qui compte maintenant.

• Un graphique clair pour voir quand la pluie commence et son intensité.
• Un radar animé qui démarre automatiquement et reste fluide pendant vos déplacements sur la carte.
• Des prévisions horaires et sur plusieurs jours.
• Des alertes pluie facultatives, configurées sans créer de compte.
• Recherche, carte ou position actuelle : vous choisissez toujours le point affiché.

La localisation est facultative et n'est utilisée qu'à votre demande. Chetiwa ne suit pas vos déplacements en arrière-plan. Les statistiques et diagnostics Firebase sont désactivés par défaut et restent sous votre contrôle dans Réglages.

Les données météo et radar sont indicatives et ne remplacent pas les alertes officielles de sécurité.

## English

- **Name**: `Chetiwa: Rain & Radar`
- **App Store subtitle**: `See rain before it arrives`
- **Play short description**: `Rain graph, animated radar and alerts for any place you choose.`
- **Promotional text**: `See rain approaching, explore the radar and keep essential forecasts in one calm place.`
- **App Store keywords**: `weather,rain,radar,forecast,alert,storm,precipitation,map,nowcast`

### Full description

Chetiwa helps you understand the rain around the place that matters right now.

• A clear graph showing when rain starts and how intense it may become.
• An animated radar that starts automatically and stays responsive as you move around the map.
• Hourly and multi-day forecasts.
• Optional rain alerts, with no account required.
• Search, map or current position: you always choose the displayed point.

Location is optional and used only when you request it. Chetiwa does not track your movements in the background. Firebase usage statistics and diagnostics are off by default and remain under your control in Settings.

Weather and radar information is indicative and does not replace official safety alerts.

## Notes de review

- Aucun compte requis.
- Graph s'ouvre au lancement ; Radar démarre automatiquement.
- La localisation peut être refusée : utiliser la recherche ou la carte.
- Alertes : Réglages → Smart Rain Alerts. L'envoi distant n'est testable que si
  Firestore/FCM sont activés pour l'environnement de review.
- Publicité et Chetiwa+ sont masqués dans la première release (`flags=false`).

## Captures requises

1. Graph — début/intensité de pluie.
2. Radar — animation et point sélectionné.
3. Prévisions — horaire et plusieurs jours.
4. Alertes — délai, intensité et heures calmes.
5. Réglages — localisation facultative et confidentialité.

Produire au minimum un jeu iPhone 6,7 pouces et un jeu Android téléphone. Ne pas
utiliser une capture avec bande de debug, notifications personnelles, batterie
faible ou données fournisseur périmées.
