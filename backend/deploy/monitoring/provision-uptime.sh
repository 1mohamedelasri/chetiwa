#!/usr/bin/env bash
# Public HTTPS checks only. Does not create paid alert policies or send messages.
set -euo pipefail
project_id="${1:-chetiwa}"

ensure_check() {
  local display_name="$1" host="$2" path="$3" existing
  existing="$(gcloud monitoring uptime list-configs --project="$project_id" \
    --filter="displayName=\"$display_name\"" --format='value(name)')"
  if [[ -n "$existing" ]]; then
    printf 'Existing check retained; inspect before changing: %s\n' "$existing"
    return
  fi
  gcloud monitoring uptime create "$display_name" --project="$project_id" \
    --resource-type=uptime-url \
    --resource-labels="host=$host,project_id=$project_id" \
    --protocol=https --validate-ssl=true --path="$path" --status-codes=200 \
    --period=5 --regions=europe,usa-iowa,asia-pacific --timeout=10 \
    --format='value(name)'
}

# 2 checks x 3 regions x 12/hour x 24 hours x 31 days = 53,568 executions.
# Verify current provider pricing/free allowance before deploying elsewhere.
ensure_check 'Chetiwa API health' chetiwa-api.ezplatforms.com /healthz
ensure_check 'Chetiwa radar metadata' radar.ezplatforms.com /public/weather-maps.json
