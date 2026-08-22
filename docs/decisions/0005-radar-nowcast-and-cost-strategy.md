# ADR-0005 — Radar observé, prévision immédiate et coût soutenable

- Statut : Accepté pour bêta ; contrat radar de production requis avant lancement public
- Date : 2026-08-22
- Propriétaire : Produit / Data / Operations Chetiwa

## Décision produit

- Le calque **Radar** représente uniquement des précipitations observées. Il
  ne représente jamais les nuages.
- Avec RainViewer, le bleu est conservé comme palette fournisseur : bleu clair
  à bleu soutenu = signal de précipitation croissant. Aucune couleur grise ne
  doit être présentée comme un nuage ou une absence de pluie.
- Les **2 prochaines heures** sont une prévision de modèle affichée dans
  **Graph**, jamais décrite comme une image radar. En France métropolitaine,
  l'API utilise Météo-France AROME à 15 minutes via Open-Meteo ; ailleurs elle
  utilise le meilleur modèle régional disponible via Open-Meteo.
- Toute vraie animation radar future doit être fournie par un fournisseur sous
  contrat et marquée `prévision radar` dans le contrat API Chetiwa. Le domaine
  `RadarFrame` conserve déjà cette capacité ; RainViewer ne peut pas la fournir.

## Pourquoi

RainViewer a supprimé les frames de nowcast, les palettes autres que Universal
Blue et les zooms supérieurs à 7 le 1er janvier 2026. Son service public reste
adapté à des essais personnels/éducatifs avec deux heures d'observations, mais
pas à une application commerciale à fort trafic.

Météo-France commercialise des produits radar avec extrapolation jusqu'à 3 h
et des produits de prévision immédiate. C'est le premier fournisseur à
consulter pour une France-first publique : demander un contrat qui couvre les
tuiles/API, cache CDN, attribution, publicité, abonnement et volumes mobiles.

## Stratégie de coût

1. **Bêta fermée** — pas de CDN, pas de Redis/Firestore. Un Cloud Run avec
   `max-instances=1`, cache mémoire, cache mobile et limites actuelles suffit.
2. **Réduire l'origine avant d'acheter de l'infrastructure** — les métadonnées
   radar sont partagées pour tous les lieux ; les prévisions backend sont
   mutualisées par cellule de 0,01° pendant 5 minutes ; les tuiles sont déjà
   dédupliquées, bornées et mises en cache sur l'appareil.
3. **10 000 utilisateurs** — ne pas utiliser les offres publiques gratuites
   des fournisseurs en production commerciale. Activer une clé commerciale
   Open-Meteo et signer le fournisseur radar. Mesurer d'abord le taux de cache
   mobile ; ajouter Cloud CDN seulement si le cache mobile + Cloud Run ne
   dépassent pas 90 % de hits ou si le contrat radar le demande.
4. **Au-delà** — Redis/Firestore n'est nécessaire que lorsque plusieurs
   instances Cloud Run sont réellement requises pour des quotas ou budgets
   partagés. Le compteur local reste le choix gratuit et simple avant cela.
5. **Monétisation** — conserver l'observation radar et le Graph 2 h dans la
   valeur Free. Réserver la lecture longue, plus de lieux, alertes distantes et
   la couverture radar/nowcast sous licence au plan Chetiwa+ après validation
   d'un coût unitaire réel. Le kill switch mensuel reste actif pour protéger le
   budget avant toute ouverture large.

## Limite non négociable

Une application commerciale à 10 000 utilisateurs avec radar et nowcast sous
contrat ne peut pas être garantie gratuite : le cache baisse les requêtes et
le coût d'infrastructure, mais ne remplace ni la licence des données ni leurs
conditions d'utilisation.

## Références

- [Transition API RainViewer](https://www.rainviewer.com/api/transition-faq.html)
- [Météo-France — Radar de précipitations](https://services.meteofrance.com/prevision/radar-de-precipitations)
- [Open-Meteo — Météo-France AROME](https://open-meteo.com/en/docs/meteofrance-api)
- [Open-Meteo — conditions et plans](https://open-meteo.com/en/pricing)
