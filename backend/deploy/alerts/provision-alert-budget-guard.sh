#!/usr/bin/env bash
set -euo pipefail

project_id="${1:?usage: provision-alert-budget-guard.sh PROJECT_ID REGION IMAGE GUARD_SERVICE_ACCOUNT PUBSUB_INVOKER_SERVICE_ACCOUNT BILLING_ACCOUNT ENV_FILE}"
region="${2:?usage: provision-alert-budget-guard.sh PROJECT_ID REGION IMAGE GUARD_SERVICE_ACCOUNT PUBSUB_INVOKER_SERVICE_ACCOUNT BILLING_ACCOUNT ENV_FILE}"
image="${3:?usage: provision-alert-budget-guard.sh PROJECT_ID REGION IMAGE GUARD_SERVICE_ACCOUNT PUBSUB_INVOKER_SERVICE_ACCOUNT BILLING_ACCOUNT ENV_FILE}"
guard_service_account="${4:?usage: provision-alert-budget-guard.sh PROJECT_ID REGION IMAGE GUARD_SERVICE_ACCOUNT PUBSUB_INVOKER_SERVICE_ACCOUNT BILLING_ACCOUNT ENV_FILE}"
invoker_service_account="${5:?usage: provision-alert-budget-guard.sh PROJECT_ID REGION IMAGE GUARD_SERVICE_ACCOUNT PUBSUB_INVOKER_SERVICE_ACCOUNT BILLING_ACCOUNT ENV_FILE}"
billing_account="${6:?usage: provision-alert-budget-guard.sh PROJECT_ID REGION IMAGE GUARD_SERVICE_ACCOUNT PUBSUB_INVOKER_SERVICE_ACCOUNT BILLING_ACCOUNT ENV_FILE}"
env_file="${7:?usage: provision-alert-budget-guard.sh PROJECT_ID REGION IMAGE GUARD_SERVICE_ACCOUNT PUBSUB_INVOKER_SERVICE_ACCOUNT BILLING_ACCOUNT ENV_FILE}"
service_name="chetiwa-alert-budget-guard"
topic_name="chetiwa-alert-budget"
subscription_name="chetiwa-alert-budget-guard"
budget_display_name="Chetiwa alerts 50 EUR hard limit"

if [[ ! -f "${env_file}" ]]; then
  echo "Environment file not found: ${env_file}" >&2
  exit 1
fi

gcloud services enable \
  billingbudgets.googleapis.com \
  pubsub.googleapis.com \
  run.googleapis.com \
  firestore.googleapis.com \
  --project="${project_id}"

gcloud projects add-iam-policy-binding "${project_id}" \
  --member="serviceAccount:${guard_service_account}" \
  --role="roles/datastore.user" \
  --quiet >/dev/null

gcloud run deploy "${service_name}" \
  --project="${project_id}" \
  --region="${region}" \
  --image="${image}" \
  --command=/app/chetiwa-alert-budget-guard \
  --service-account="${guard_service_account}" \
  --env-vars-file="${env_file}" \
  --no-allow-unauthenticated \
  --min=0 \
  --max=1 \
  --concurrency=10 \
  --quiet

service_url="$(gcloud run services describe "${service_name}" \
  --project="${project_id}" \
  --region="${region}" \
  --format='value(status.url)')"

gcloud run services add-iam-policy-binding "${service_name}" \
  --project="${project_id}" \
  --region="${region}" \
  --member="serviceAccount:${invoker_service_account}" \
  --role="roles/run.invoker" \
  --quiet >/dev/null

if ! gcloud pubsub topics describe "${topic_name}" \
  --project="${project_id}" >/dev/null 2>&1; then
  gcloud pubsub topics create "${topic_name}" --project="${project_id}"
fi

project_number="$(gcloud projects describe "${project_id}" \
  --format='value(projectNumber)')"
gcloud projects add-iam-policy-binding "${project_id}" \
  --member="serviceAccount:service-${project_number}@gcp-sa-pubsub.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator" \
  --quiet >/dev/null

if gcloud pubsub subscriptions describe "${subscription_name}" \
  --project="${project_id}" >/dev/null 2>&1; then
  gcloud pubsub subscriptions modify-push-config "${subscription_name}" \
    --project="${project_id}" \
    --push-endpoint="${service_url}/" \
    --push-auth-service-account="${invoker_service_account}"
else
  gcloud pubsub subscriptions create "${subscription_name}" \
    --project="${project_id}" \
    --topic="${topic_name}" \
    --ack-deadline=60 \
    --push-endpoint="${service_url}/" \
    --push-auth-service-account="${invoker_service_account}"
fi

existing_budget="$(gcloud billing budgets list \
  --billing-account="${billing_account}" \
  --filter="displayName='${budget_display_name}'" \
  --format='value(name)' \
  --limit=1)"
if [[ -z "${existing_budget}" ]]; then
  gcloud billing budgets create \
    --billing-account="${billing_account}" \
    --display-name="${budget_display_name}" \
    --budget-amount=50EUR \
    --calendar-period=month \
    --filter-projects="projects/${project_id}" \
    --threshold-rule=percent=0.50 \
    --threshold-rule=percent=1.00 \
    --notifications-rule-pubsub-topic="projects/${project_id}/topics/${topic_name}"
else
  echo "Budget already exists: ${existing_budget}"
fi

echo "Budget guard ready: ${service_url}"
