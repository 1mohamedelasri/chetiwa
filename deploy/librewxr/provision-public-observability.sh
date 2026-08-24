#!/usr/bin/env bash
# Creates an external metadata uptime check from three Google Cloud regions.
set -euo pipefail

project_id="${1:?usage: provision-public-observability.sh PROJECT_ID [NOTIFICATION_CHANNEL_ID,...]}"
notification_channels="${2:-}"
display_name="Chetiwa LibreWXR metadata"
host="radar.ezplatforms.com"

gcloud services enable monitoring.googleapis.com --project="$project_id"

check_name="$(gcloud monitoring uptime list-configs \
  --project="$project_id" \
  --filter="displayName='$display_name'" \
  --format='value(name)' --limit=1)"

if [[ -z "$check_name" ]]; then
  check_name="$(gcloud monitoring uptime create "$display_name" \
    --project="$project_id" \
    --resource-type=uptime-url \
    --resource-labels="host=$host,project_id=$project_id" \
    --protocol=https \
    --path=/public/weather-maps.json \
    --request-method=get \
    --status-codes=200 \
    --validate-ssl \
    --period=1 \
    --timeout=10 \
    --regions=europe,usa-iowa,asia-pacific \
    --format='value(name)')"
fi

check_id="${check_name##*/}"
policy_name="Chetiwa LibreWXR indisponible"
existing_policy="$(gcloud monitoring policies list \
  --project="$project_id" \
  --filter="displayName='$policy_name'" \
  --format='value(name)' --limit=1)"

if [[ -z "$existing_policy" ]]; then
  policy_args=(
    monitoring policies create
    --project="$project_id"
    --display-name="$policy_name"
    --condition-display-name="metadata 5xx ou inaccessible pendant 2 minutes"
    --condition-filter="metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND metric.label.check_id=\"$check_id\""
    --duration=120s
    --if='< 1'
    --trigger-count=1
    --documentation="La sonde LibreWXR échoue depuis plusieurs régions. Vérifier le conteneur, cloudflared, les erreurs 5xx Cloudflare et le watchdog avant une release."
  )
  if [[ -n "$notification_channels" ]]; then
    policy_args+=(--notification-channels="$notification_channels")
  fi
  gcloud "${policy_args[@]}"
fi

printf 'LibreWXR multi-region uptime and 5xx alert ready for https://%s/public/weather-maps.json\n' "$host"
