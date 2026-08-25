#!/usr/bin/env bash
set -euo pipefail

project_id="${1:?usage: deploy-api.sh PROJECT_ID REGION IMAGE RUNTIME_SERVICE_ACCOUNT PUBLIC_BASE_URL}"
region="${2:?usage: deploy-api.sh PROJECT_ID REGION IMAGE RUNTIME_SERVICE_ACCOUNT PUBLIC_BASE_URL}"
image="${3:?usage: deploy-api.sh PROJECT_ID REGION IMAGE RUNTIME_SERVICE_ACCOUNT PUBLIC_BASE_URL}"
runtime_service_account="${4:?usage: deploy-api.sh PROJECT_ID REGION IMAGE RUNTIME_SERVICE_ACCOUNT PUBLIC_BASE_URL}"
public_base_url="${5:?usage: deploy-api.sh PROJECT_ID REGION IMAGE RUNTIME_SERVICE_ACCOUNT PUBLIC_BASE_URL}"
service_name="chetiwa-api"

case "${public_base_url}" in
  https://*) ;;
  *) echo "PUBLIC_BASE_URL must be a public HTTPS URL." >&2; exit 2 ;;
esac

gcloud services enable \
  run.googleapis.com \
  secretmanager.googleapis.com \
  firestore.googleapis.com \
  --project="${project_id}"

# Secret names are stable; their values must be created by the owner in Secret
# Manager. Deployment intentionally fails if either production secret is absent.
gcloud run deploy "${service_name}" \
  --project="${project_id}" \
  --region="${region}" \
  --image="${image}" \
  --service-account="${runtime_service_account}" \
  --allow-unauthenticated \
  --cpu=1 \
  --memory=512Mi \
  --concurrency=40 \
  --timeout=30s \
  --min=0 \
  --max=1 \
  --set-env-vars="CHETIWA_ENV=production,GOOGLE_CLOUD_PROJECT=${project_id},FIRESTORE_DATABASE_ID=(default),RADAR_ENABLED=true,RADAR_QUOTA_ENFORCED=false,GLOBAL_KILL_SWITCH=false,PREMIUM_ENABLED=false,PREMIUM_ROLLOUT_PERCENT=0,PREMIUM_SATELLITE_ENABLED=false,ADS_ENABLED=false,RAIN_ALERTS_ENABLED=false,RAIN_ALERTS_SEND_ENABLED=false,RADAR_PROVIDER=librewxr,RADAR_METADATA_URL=https://radar.ezplatforms.com/public/weather-maps.json,RADAR_TILE_URL_TEMPLATE=https://radar.ezplatforms.com{frame}/256/{z}/{x}/{y}/13/1_0.png,PUBLIC_BASE_URL=${public_base_url}" \
  --set-secrets="OPEN_METEO_API_KEY=open-meteo-api-key:latest,INTERNAL_METRICS_TOKEN=chetiwa-internal-metrics-token:latest"

service_url="$(gcloud run services describe "${service_name}" \
  --project="${project_id}" \
  --region="${region}" \
  --format='value(status.url)')"

curl --fail --silent --show-error \
  --retry 5 --retry-delay 3 --retry-all-errors \
  --max-time 15 "${service_url}/healthz" >/dev/null

printf 'Chetiwa API deployed and healthy: %s\n' "${service_url}"
