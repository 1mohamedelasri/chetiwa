# Smoke test sur appareils physiques — Chetiwa

Ce test est requis avant toute bêta externe. Il complète les tests automatisés :
un émulateur ne valide ni les permissions réelles, ni les performances de carte,
ni l'installation depuis un store.

## Appareils minimum

- Deux Android : un appareil milieu/bas de gamme et un appareil récent.
- Deux iPhone compatibles avec la version iOS cible.
- Au moins un appareil par plateforme avec réseau mobile, pas seulement Wi-Fi.

## Installation et parcours principal

- Installer une build propre ; vérifier lancement, thème système clair/sombre et
  texte système à 100 % puis 200 %.
- Rechercher une ville dans un autre fuseau, confirmer sur la carte, puis revenir
  à la position actuelle.
- Vérifier que Graph, Radar et Prévisions montrent le même lieu et les mêmes
  heures locales.
- Tester le curseur Radar, lecture/pause/reprise/reset et le changement de fond
  de carte disponible.
- Vérifier l'emplacement de publicité réservé : il doit rester vide dans le MVP
  et ne jamais recouvrir le contenu ou la navigation.

## Localisation et résilience

- Tester GPS autorisé, refusé, refus permanent, services de localisation coupés,
  précision réduite et dernière position connue.
- Couper le réseau après une première synchronisation ; vérifier l'état cache et
  la compréhension de l'erreur par l'utilisateur.
- Tester réseau lent et reprise de réseau pendant Graph et Radar.

## Accessibilité et sortie

- Parcourir les trois écrans météo avec TalkBack ou VoiceOver et vérifier les
  libellés des boutons principaux.
- Vérifier les zones tactiles, contraste et absence de débordement à 200 %.
- Consigner appareil, OS, build, réseau et résultat dans le canal de feedback.
- Tout crash, écran météo vide, localisation erronée ou incohérence horaire est
  bloquant pour la bêta externe.
