#!/usr/bin/env bash
set -euo pipefail

project_id="${1:?usage: provision-alert-store.sh PROJECT_ID CLOUD_RUN_SERVICE_ACCOUNT [DATABASE_ID]}"
service_account="${2:?usage: provision-alert-store.sh PROJECT_ID CLOUD_RUN_SERVICE_ACCOUNT [DATABASE_ID]}"
database_id="${3:-(default)}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${database_id}" != "(default)" ]]; then
  echo "The launch script supports only the default Firestore database." >&2
  exit 1
fi

gcloud firestore databases describe \
  --project="${project_id}" \
  --database="${database_id}" >/dev/null

gcloud firestore fields ttls update expiresAt \
  --project="${project_id}" \
  --database="${database_id}" \
  --collection-group=devices \
  --enable-ttl \
  --quiet

gcloud firestore fields ttls update expiresAt \
  --project="${project_id}" \
  --database="${database_id}" \
  --collection-group=alertRunMetrics \
  --enable-ttl \
  --quiet

gcloud firestore fields ttls update expiresAt \
  --project="${project_id}" \
  --database="${database_id}" \
  --collection-group=alertDeliveries \
  --enable-ttl \
  --quiet

gcloud firestore fields ttls update expiresAt \
  --project="${project_id}" \
  --database="${database_id}" \
  --collection-group=alerts \
  --enable-ttl \
  --quiet

gcloud firestore fields ttls update expiresAt \
  --project="${project_id}" \
  --database="${database_id}" \
  --collection-group=alertStates \
  --enable-ttl \
  --quiet

gcloud firestore fields ttls update expiresAt \
  --project="${project_id}" \
  --database="${database_id}" \
  --collection-group=alertCellSchedules \
  --enable-ttl \
  --quiet

gcloud projects add-iam-policy-binding "${project_id}" \
  --member="serviceAccount:${service_account}" \
  --role="roles/datastore.user" \
  --quiet >/dev/null

gcloud projects add-iam-policy-binding "${project_id}" \
  --member="serviceAccount:${service_account}" \
  --role="roles/firebasecloudmessaging.admin" \
  --quiet >/dev/null

firebase deploy \
  --only firestore:rules \
  --project="${project_id}" \
  --config="${script_dir}/firebase.json" \
  --non-interactive

gcloud firestore databases describe \
  --project="${project_id}" \
  --database="${database_id}" \
  --format='value(name,locationId,type)'
