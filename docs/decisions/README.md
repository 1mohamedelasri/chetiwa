# Chetiwa architecture decision records

Les ADR de ce dossier enregistrent les décisions structurantes du produit. Une
décision acceptée reste modifiable, mais seulement au moyen d’un nouvel ADR qui
explique pourquoi elle est remplacée.

| ADR | Décision | Statut |
| --- | --- | --- |
| [0001](0001-weather-provider.md) | Open-Meteo pour les prévisions générales | Accepté |
| [0002](0002-radar-provider.md) | Rainbow pour le radar de production | Accepté |
| [0003](0003-basemap-provider.md) | OpenFreeMap par défaut, Esri satellite Premium | Accepté |
| [0004](0004-backend-platform.md) | Monolithe modulaire sur Cloud Run/Firebase | Accepté |
| [0005](0005-purchases-entitlements.md) | RevenueCat derrière `SubscriptionRepository` | Accepté |
| [0006](0006-ads-consent.md) | AdMob + UMP derrière repositories | Accepté |
| [0007](0007-observability-analytics.md) | Firebase pour observabilité et analytics minimaux | Reporté pour le MVP |
| [0008](0008-lean-mvp-cost-gates.md) | MVP local-first et activation des coûts par paliers | Accepté |

## Format

Chaque ADR contient : contexte, décision, conséquences, garde-fous et conditions
de réévaluation. Les tarifs et licences restent suivis dans le
[registre fournisseurs](../compliance/provider-register.md).
