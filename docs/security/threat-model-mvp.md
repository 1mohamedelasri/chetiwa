# Modèle de menace — MVP local-first

## Périmètre actuel

Chetiwa ne comporte ni compte, ni achat, ni publicité, ni push distant. Firebase
Analytics est le seul SDK cloud embarqué : il est désactivé par défaut et ne
reçoit qu'une liste fermée d'événements anonymes après un choix explicite. Les
données météo et de carte sont demandées à des fournisseurs via l'application ou
le proxy Chetiwa selon la configuration. Les préférences et lieux enregistrés
restent locaux.

## Risques et contrôles

| Risque | Impact | Contrôle MVP | Condition avant publication |
| --- | --- | --- | --- |
| Clé ou URL de test dans la build | Abus fournisseur | Aucune clé payante dans le mobile ; configuration production HTTPS | Inspecter APK/IPA avant bêta |
| Coordonnées précises dans logs/cache | Vie privée | Cache arrondi côté API ; aucun log de coordonnées brutes volontaire | Vérifier logs et politique avant release |
| Réponse fournisseur invalide ou indisponible | Écran vide/décision erronée | Contrats typés, cache SWR, état hors-ligne et fixtures | Smoke test réseau réel |
| Abus du proxy public | Coût/indisponibilité | Limite locale et ETag déjà présents | Quotas distribués après Gate cloud |
| Dépendance compromise | Exécution de code vulnérable | CI et Dependabot hebdomadaire | Revue des mises à jour critiques |
| Faux sentiment de sécurité des alertes | Mauvaise décision utilisateur | Aucune alerte temps réel active pendant la bêta frugale | Mesure silencieuse avant push |
| Mesure d'usage trop intrusive | Atteinte à la vie privée | Opt-in local, retrait dans Réglages, liste fermée sans lieu/texte/valeur météo | Vérifier l'inventaire, la politique et les déclarations stores |

## Hors périmètre MVP, à réviser avant activation

L'ajout d'achats, publicité, compte, crash reporting, push, autre produit
Firebase ou base cloud impose une révision de ce document, de l'inventaire de
données, des déclarations stores et du modèle de consentement. Tout nouvel
événement Analytics suit la même règle. Les secrets et certificats ne doivent
alors exister que dans le CI sécurisé ou le gestionnaire de secrets de
l'hébergeur, jamais dans le dépôt ou l'application.

## Réponse incident minimale

1. Désactiver le fournisseur ou la fonctionnalité affectée via la configuration
   de déploiement ; afficher le cache/état indisponible.
2. Révoquer toute clé exposée et la remplacer côté serveur.
3. Vérifier la portée : version, durée, données touchées et utilisateurs affectés.
4. Corriger, tester en staging puis publier progressivement une build corrective.
