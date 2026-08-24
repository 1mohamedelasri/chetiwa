#!/usr/bin/env bash
set -euo pipefail

project_id="${1:?usage: provision-alert-worker.sh PROJECT_ID REGION IMAGE WORKER_SERVICE_ACCOUNT SCHEDULER_SERVICE_ACCOUNT ENV_FILE}"
region="${2:?usage: provision-alert-worker.sh PROJECT_ID REGION IMAGE WORKER_SERVICE_ACCOUNT SCHEDULER_SERVICE_ACCOUNT ENV_FILE}"
image="${3:?usage: provision-alert-worker.sh PROJECT_ID REGION IMAGE WORKER_SERVICE_ACCOUNT SCHEDULER_SERVICE_ACCOUNT ENV_FILE}"
worker_service_account="${4:?usage: provision-alert-worker.sh PROJECT_ID REGION IMAGE WORKER_SERVICE_ACCOUNT SCHEDULER_SERVICE_ACCOUNT ENV_FILE}"
scheduler_service_account="${5:?usage: provision-alert-worker.sh PROJECT_ID REGION IMAGE WORKER_SERVICE_ACCOUNT SCHEDULER_SERVICE_ACCOUNT ENV_FILE}"
env_file="${6:?usage: provision-alert-worker.sh PROJECT_ID REGION IMAGE WORKER_SERVICE_ACCOUNT SCHEDULER_SERVICE_ACCOUNT ENV_FILE}"
job_name="chetiwa-rain-alerts"
scheduler_name="chetiwa-rain-alerts-every-5m"

if [[ ! -f "${env_file}" ]]; then
  echo "Environment file not found: ${env_file}" >&2
  exit 1
fi

gcloud services enable \
  run.googleapis.com \
  cloudscheduler.googleapis.com \
  firestore.googleapis.com \
  fcm.googleapis.com \
  --project="${project_id}"

gcloud projects add-iam-policy-binding "${project_id}" \
  --member="serviceAccount:${worker_service_account}" \
  --role="roles/datastore.user" \
  --quiet >/dev/null

gcloud projects add-iam-policy-binding "${project_id}" \
  --member="serviceAccount:${worker_service_account}" \
  --role="roles/firebasecloudmessaging.admin" \
  --quiet >/dev/null

gcloud run jobs deploy "${job_name}" \
  --project="${project_id}" \
  --region="${region}" \
  --image="${image}" \
  --command=/app/chetiwa-alert-worker \
  --service-account="${worker_service_account}" \
  --env-vars-file="${env_file}" \
  --tasks=1 \
  --max-retries=0 \
  --task-timeout=240s \
  --quiet

gcloud run jobs add-iam-policy-binding "${job_name}" \
  --project="${project_id}" \
  --region="${region}" \
  --member="serviceAccount:${scheduler_service_account}" \
  --role="roles/run.invoker" \
  --quiet >/dev/null

target_uri="https://run.googleapis.com/v2/projects/${project_id}/locations/${region}/jobs/${job_name}:run"
if gcloud scheduler jobs describe "${scheduler_name}" \
  --project="${project_id}" \
  --location="${region}" >/dev/null 2>&1; then
  gcloud scheduler jobs update http "${scheduler_name}" \
    --project="${project_id}" \
    --location="${region}" \
    --schedule="*/5 * * * *" \
    --time-zone="Etc/UTC" \
    --uri="${target_uri}" \
    --http-method=POST \
    --oauth-service-account-email="${scheduler_service_account}" \
    --attempt-deadline=300s \
    --quiet
else
  gcloud scheduler jobs create http "${scheduler_name}" \
    --project="${project_id}" \
    --location="${region}" \
    --schedule="*/5 * * * *" \
    --time-zone="Etc/UTC" \
    --uri="${target_uri}" \
    --http-method=POST \
    --oauth-service-account-email="${scheduler_service_account}" \
    --attempt-deadline=300s \
    --quiet
fi

gcloud run jobs describe "${job_name}" \
  --project="${project_id}" \
  --region="${region}" \
  --format='value(name,terminalCondition.state)'
