#!/usr/bin/env bash
set -euo pipefail

project_id="${1:?usage: provision-api-observability.sh PROJECT_ID API_HOST [NOTIFICATION_CHANNEL_ID,...]}"
api_host="${2:?usage: provision-api-observability.sh PROJECT_ID API_HOST [NOTIFICATION_CHANNEL_ID,...]}"
notification_channels="${3:-}"
display_name="Chetiwa API /healthz"

api_host="${api_host#https://}"
api_host="${api_host%%/*}"
if [ -z "${api_host}" ]; then
  echo 'API_HOST must be a public hostname.' >&2
  exit 2
fi

gcloud services enable monitoring.googleapis.com --project="${project_id}"

check_name="$(gcloud monitoring uptime list-configs \
  --project="${project_id}" \
  --filter="displayName='${display_name}'" \
  --format='value(name)' \
  --limit=1)"

if [ -z "${check_name}" ]; then
  check_name="$(gcloud monitoring uptime create "${display_name}" \
    --project="${project_id}" \
    --resource-type=uptime-url \
    --resource-labels="host=${api_host},project_id=${project_id}" \
    --protocol=https \
    --path=/healthz \
    --request-method=get \
    --status-codes=200 \
    --validate-ssl \
    --period=1 \
    --timeout=10 \
    --regions=europe,usa-iowa,asia-pacific \
    --format='value(name)')"
fi

check_id="${check_name##*/}"
policy_name="Chetiwa API indisponible"
existing_policy="$(gcloud monitoring policies list \
  --project="${project_id}" \
  --filter="displayName='${policy_name}'" \
  --format='value(name)' \
  --limit=1)"

if [ -z "${existing_policy}" ]; then
  policy_args=(
    monitoring policies create
    --project="${project_id}"
    --display-name="${policy_name}"
    --condition-display-name="healthz absent pendant 2 minutes"
    --condition-filter="metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND metric.label.check_id=\"${check_id}\""
    --duration=120s
    --if='< 1'
    --trigger-count=1
    --documentation="La sonde publique /healthz de Chetiwa échoue. Vérifier Cloud Run, les secrets, LibreWXR et le domaine API avant toute nouvelle release."
  )
  if [ -n "${notification_channels}" ]; then
    policy_args+=(--notification-channels="${notification_channels}")
  fi
  gcloud "${policy_args[@]}"
fi

printf 'Uptime check and alert policy ready for https://%s/healthz\n' "${api_host}"
