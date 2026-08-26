# Chetiwa — KPI et garde-fous financiers v1

Les seuils protègent le produit avant qu’il génère des revenus. Ils seront
réévalués après chaque phase de bêta, jamais augmentés silencieusement.

## Budgets par étape

| Étape | Trafic | Plafond mensuel initial | Action au plafond |
| --- | --- | ---: | --- |
| Développement interne | Équipe | 0 € par défaut | Ne lancer aucun service cloud ; utiliser fixtures/cache local |
| Bêta fermée | Testeurs invités | 0 € par défaut, ou plafond explicitement approuvé | Geler invitations et analyser au premier coût inattendu |
| Lancement progressif | Public limité | plafond approuvé avant activation | Limiter radar/satellite avant dépassement |

Les frais développeur stores et obligations administratives sont suivis
séparément. Un abonnement fournisseur commercial requis peut dépasser le budget
interne uniquement après approbation explicite.

## Règles économiques

- Alertes fournisseur/cloud à 50 %, 75 %, 90 % et 100 % du budget/quota.
- Coûts variables backend + météo + radar + carte : cible inférieure à 20 % du
  revenu net mensuel ; alerte à 15 %, gel d’expansion à 20 %.
- Aucun fond satellite gratuit et illimité.
- Si Cloud Run est requis : `min-instances=0` et `max-instances=1` au départ.
- Les quotas Free/Premium, caches et kill switches sont testés avant production.
- Les dépenses ne sont jamais augmentées sur la seule base du nombre d’inscrits :
  elles sont comparées au revenu et à la rétention des cohortes.
- Aucun fournisseur payant n'est engagé avant une vérification écrite de la
  licence et du coût maximal ; voir le [plan MVP frugal](lean-mvp-cost-plan.md).

## KPI produit et qualité

| Domaine | KPI initial |
| --- | --- |
| Activation | Première prévision réussie / installation |
| Utilité | Weekly Weather Decisions |
| Rétention | D1, D7, D30 |
| Fiabilité mobile | Utilisateurs sans crash ≥ 99,5 % en release candidate |
| Chargement | Brief depuis cache p95 ≤ 1,5 s ; réseau frais p95 ≤ 4 s |
| Données | Succès forecast ≥ 99 % hors panne fournisseur déclarée |
| Radar | Sessions, tuiles/session, cache hit rate, coût/session |
| Alertes | Duplicats = 0 ; faux positifs/négatifs mesurés par zone |
| Ads | Revenu net / utilisateur Free actif et impact rétention |
| Premium | Paywall → achat, renouvellement, churn et revenu net |

## Kill switches obligatoires

- Radar animé et nombre de frames.
- Rainbow Nowcast/Alerts.
- Quotas/erreurs Google Maps Platform.
- Publicités.
- Nouveau pays/zone de Smart Alerts.
- Fournisseur forecast primaire.

## Revue

- Quotidienne pendant la première semaine de bêta/lancement.
- Hebdomadaire jusqu’à stabilité.
- Mensuelle ensuite avec décision écrite sur budgets et limites.
