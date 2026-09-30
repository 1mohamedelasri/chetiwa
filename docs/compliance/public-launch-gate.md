# Gate conformité — lancement public

Statut : **BLOQUÉ tant que les preuves externes ne sont pas archivées**.

Revue locale du 30 septembre 2026 : les brouillons ont été rapprochés du code
et de l'audit du 19 septembre. Aucune publication de pages, acceptation de
contrat, souscription ou soumission Store n'est attestée par ce document.

Ce document transforme la validation fournisseur en condition de release. Les
crédits affichés dans l’application ne constituent pas une autorisation
commerciale. Les contrats, licences et conditions acceptées doivent être
conservés dans un espace contrôlé par l’équipe, avec une copie datée et un
responsable identifié.

## Décisions techniques actuelles

| Composant | Utilisation actuelle | Décision de lancement | Preuve exigée |
| --- | --- | --- | --- |
| Prévisions/géocodage | Open-Meteo direct en dev, proxy en prod | Vérifier le droit d'usage commercial même sans pubs ; le profil production exige une clé commerciale | Conditions acceptées, quota, attribution, DPA applicable |
| Radar | LibreWXR auto-hébergé derrière Cloudflare | Bêta après gate technique ; public après validation du code et de chaque donnée amont | Licences, droit de redistribution, cache/CDN, attribution, capacité et procédure incident |
| Cartographie | Google Maps natif : hybride satellite Radar par défaut, standard sélectionnable, pour tous | Activer les SDK Android/iOS avec deux clés restreintes ; aucun Map ID | Conditions datées, projet facturé, restrictions application/API, logo et attributions vérifiés sur appareil |
| Achats | Fonction présente mais désactivée pour la première release | Sans objet pour la v1 gratuite ; activation ultérieure après validation | Accords de produits, commissions et fiscalité si activés |
| Publicité | Désactivée pour la première release | Sans objet pour la v1 sans publicité ; activation ultérieure après validation | DPA, consentement/CMP, ATT si applicable, déclarations Store si activée |

## Checklist de release

- [ ] Une personne responsable a signé la validation pour chaque fournisseur.
- [ ] LibreWXR et chacune de ses données amont actives sont autorisés pour les
  territoires, le cache et la redistribution de la build publiée.
- [ ] Le droit d’usage commercial, les territoires et la durée sont écrits.
- [ ] Le cache est expressément autorisé : durée, proxy/CDN, stockage disque,
  revalidation et préchargement.
- [ ] L'usage des tuiles est couvert pour la version gratuite publiée ; les
  usages payants/publicitaires ne sont ajoutés qu'après validation distincte.
- [ ] Les crédits exacts de la version publiée ont été vérifiés sur appareil.
- [ ] Les URLs de crédits et les conditions acceptées sont archivées.
- [ ] Les quotas, prix, SLA, limites de concurrence et procédure de révocation
  sont documentés.
- [ ] Les clés, tokens et identifiants sont dans Secret Manager ou la console
  du fournisseur ; aucune clé privée n’est embarquée dans l’app.
- [ ] La configuration de production refuse tout fournisseur non validé.
- [ ] La CMP, la publicité, les achats et les déclarations App Store/Google Play
  correspondent au comportement réel de la build.
- [ ] Le kill switch fournisseur a été testé en staging et le fallback est
  documenté.

## Informations du propriétaire encore nécessaires

Ces champs doivent être confirmés, sans recopier automatiquement un e-mail
de compte développeur dans une page publique.

| Information | État connu | Réponse attendue |
| --- | --- | --- |
| Éditeur responsable | Le domaine `ezplatforms.com` a été donné ; ce n'est pas une identité légale | Nom légal de la personne ou société, adresse professionnelle et pays |
| Contact public | Une adresse de compte développeur a été donnée, sans confirmation de publication | Une adresse support/confidentialité explicitement destinée au public |
| Territoires de lancement | Non confirmés | Pays de première diffusion, pour vérifier couverture et licences |
| Accords fournisseurs existants | Aucun dossier d'acceptation fourni | Référence/emplacement des accords existants, ou confirmation qu'ils restent à obtenir ; aucun secret dans le dépôt |

Après ces réponses : finaliser les textes, confirmer les durées de rétention,
publier les pages HTTPS sur le site retenu, relier les pages dans l'app et
compléter les formulaires avec la build réellement testée. Aucun code de site
privacy/support ni URL publique correspondante n'a été trouvé dans ce dépôt.

## Preuves techniques à obtenir sans les inventer

- Liste des sources radar actives et version de LibreWXR déployée ; licence,
  redistribution, cache et attribution de chacune.
- Configuration et accords Hetzner/Cloudflare/Google, régions par service et
  rétention des journaux ; Firebase ne signifie pas que tous les traitements
  sont nécessairement limités à l'UE.
- Politique des données d'alerte : un `expiresAt` à 180 jours ne suffit pas.
  Seul le TTL des métriques à 30 jours a été confirmé actif lors de l'audit.
- Collecte des SDK natifs : Google Maps est distinct du choix facultatif
  Analytics/Crashlytics. Finaliser les
  [déclarations Store](../release/store-privacy-declarations.md) sur la build signée.

## Dossier de preuve obligatoire

Pour chaque fournisseur, archiver une fiche selon
[`provider-evidence-template.md`](provider-evidence-template.md), puis les
documents dans un coffre versionné hors du dépôt si leur contenu est
confidentiel. Ne jamais committer de clé, contrat confidentiel ou donnée
personnelle.

La release doit référencer un identifiant de dossier, une date de vérification,
un hash ou numéro de version du document et le nom du validateur.

## Contrôle avant publication

Le responsable release doit vérifier le registre
[`provider-register.md`](provider-register.md), le présent gate et la checklist
matériel de release. En cas de fournisseur non validé, l’action correcte est de
le désactiver ou de revenir aux fixtures/cache autorisés, pas de publier avec
une attribution seule.
