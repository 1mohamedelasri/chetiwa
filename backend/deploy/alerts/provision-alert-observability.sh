#!/usr/bin/env bash
set -euo pipefail

project_id="${1:?usage: provision-alert-observability.sh PROJECT_ID}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dashboard_file="${script_dir}/rain-alert-dashboard.json"
base_filter='resource.type="cloud_run_job" AND resource.labels.job_name="chetiwa-rain-alerts" AND jsonPayload.status="completed"'

gcloud services enable logging.googleapis.com monitoring.googleapis.com \
  --project="${project_id}"

upsert_metric() {
  local name="$1"
  local field="$2"
  local kind="$3"
  local unit="$4"
  local verb="create"
  if gcloud logging metrics describe "${name}" \
    --project="${project_id}" >/dev/null 2>&1; then
    verb="update"
  fi
  gcloud logging metrics "${verb}" "${name}" \
    --project="${project_id}" \
    --description="Chetiwa rain-alert aggregate ${field}; contains no token or coordinates." \
    --log-filter="${base_filter}" \
    --value-extractor="EXTRACT(jsonPayload.${field})" \
    --metric-descriptor="metricKind=${kind},valueType=INT64,unit=${unit}"
}

upsert_metric chetiwa_rain_alert_duration_ms durationMilliseconds GAUGE ms
upsert_metric chetiwa_rain_alert_cells cellsEvaluated DELTA 1
upsert_metric chetiwa_rain_alert_proposed deliveriesProposed DELTA 1
upsert_metric chetiwa_rain_alert_push_sent pushSent DELTA 1
upsert_metric chetiwa_rain_alert_push_failed pushFailed DELTA 1

existing_dashboard="$(gcloud monitoring dashboards list \
  --project="${project_id}" \
  --filter='displayName="Chetiwa — Alertes pluie"' \
  --format='value(name)' \
  --limit=1)"
if [[ -z "${existing_dashboard}" ]]; then
  gcloud monitoring dashboards create \
    --project="${project_id}" \
    --config-from-file="${dashboard_file}"
else
  echo "Dashboard already exists: ${existing_dashboard}"
fi
