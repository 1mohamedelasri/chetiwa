# Chetiwa Free / Chetiwa+ — matrice v1

Statut : décision produit initiale à valider pendant la bêta. Aucun SDK
publicitaire, achat ni service Premium n'est une dépendance de la bêta frugale.

| Fonction | Chetiwa Free | Chetiwa+ |
| --- | --- | --- |
| Weather Brief | Oui | Oui |
| Graph pluie 2 h | Oui | Oui |
| Graph 24 h | Oui | Oui |
| Prévisions quotidiennes | Oui | Oui |
| Radar essentiel | Nowcast radar jusqu’à +60 min | Identique |
| Prévision pluie +60–120 min | Non, segment verrouillé | Oui, extrapolation du déplacement radar toutes les 10 min |
| Google Maps standard | Oui | Oui |
| Google Maps satellite hybride | Oui, fond Radar par défaut | Oui |
| Position actuelle | Oui | Oui |
| Recherche/choix sur carte | Oui | Oui |
| Lieux enregistrés | 1 principal | Plusieurs lieux nommés |
| Smart Rain Alerts | Aperçu de valeur | Après validation qualité/coût |
| Alertes par lieu et seuil | Non | Oui |
| Publicité | À décider après bêta | Aucune requête ni slot |
| Compte | Non obligatoire | Non obligatoire en v1 |

## Prix à tester

- Mensuel : 1,49 € comme hypothèse de départ.
- Annuel : 9,99 € comme hypothèse de départ et offre recommandée.
- Les prix finaux sont créés dans chaque store et localisés par marché.
- Aucun prix ne change avant d’avoir assez de données de conversion et de churn.

## Règles produit

- Pas de paywall au premier lancement.
- Le paywall apparaît après une intention Premium compréhensible.
- Le produit Free doit répondre correctement à la question météo principale.
- Ne jamais présenter la tranche +60–120 min comme un radar observé. LibreWXR
  prolonge par advection optique la trajectoire du dernier radar. Cela conserve
  les cellules visuellement, mais l'incertitude de position augmente avec le
  délai et doit rester explicitement nommée « prévision étendue ».
- L'interpolation météorologique est générée côté LibreWXR à dix minutes. Le
  mobile échange atomiquement les trames préchargées : aucun fondu d'opacité
  client ne doit faire disparaître artificiellement une cellule de pluie.
- Le Premium finance d'abord les fonctionnalités récurrentes : alertes, radar
  étendu et multi-lieux. Il n'est pas activé tant que ces coûts et les
  droits fournisseurs ne sont pas validés.
- Le verrouillage dans l'application sert à tester l'offre. La vente ne doit
  être activée qu'après validation serveur des reçus Apple/Google et émission
  d'un entitlement signé ; masquer des trames côté mobile seul n'est pas une
  protection suffisante pour une fonctionnalité payante.
- Choisir Premium ou publicité comme première voie de revenus ; ne pas multiplier
  les SDK et obligations de conformité avant d'avoir validé la rétention.
