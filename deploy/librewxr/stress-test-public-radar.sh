#!/usr/bin/env bash
# Controlled stepped load test for the public LibreWXR path. Each stage uses
# unique current-frame tiles so Cloudflare/origin caches do not make later
# concurrency levels artificially faster. This is deliberately bounded.
set -euo pipefail

base_url="${CHETIWA_RADAR_BASE_URL:-https://radar.ezplatforms.com}"
samples_per_stage="${CHETIWA_RADAR_STRESS_SAMPLES_PER_STAGE:-48}"
stages="${CHETIWA_RADAR_STRESS_STAGES:-1 2 4 8 12 16}"
zoom="${CHETIWA_RADAR_PROBE_ZOOM:-10}"
p95_stop_seconds="${CHETIWA_RADAR_STRESS_P95_STOP_SECONDS:-3.0}"

if (( samples_per_stage < 16 || samples_per_stage > 64 )); then
  echo 'Use 16-64 samples per stage.' >&2
  exit 2
fi
for command in curl jq awk od sort; do
  command -v "$command" >/dev/null || {
    printf 'Missing required command: %s\n' "$command" >&2
    exit 2
  }
done
for concurrency in $stages; do
  if (( concurrency < 1 || concurrency > 16 )); then
    echo 'Concurrency stages must remain between 1 and 16.' >&2
    exit 2
  fi
done

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
metadata="$work_dir/metadata.json"
curl --fail --silent --show-error --connect-timeout 5 --max-time 20 \
  "$base_url/public/weather-maps.json" -o "$metadata"
frame="$(jq -er '.radar.past[-1].path' "$metadata")"

probe_one() {
  local stage_number="$1" index="$2" x="$3" y="$4"
  local url headers body metrics status total ttfb bytes
  local content_type cache_status signature valid
  url="$base_url$frame/256/$zoom/$x/$y/13/1_0.png"
  headers="$work_dir/$stage_number-$index.headers"
  body="$work_dir/$stage_number-$index.png"
  metrics="$(curl --silent --show-error --connect-timeout 5 --max-time 30 \
    --dump-header "$headers" --output "$body" \
    --write-out '%{http_code} %{time_total} %{time_starttransfer} %{size_download}' \
    "$url" || printf '000 30 30 0')"
  read -r status total ttfb bytes <<<"$metrics"
  content_type="$(awk 'BEGIN { IGNORECASE=1 } /^content-type:/ { gsub("\\r", ""); print $2 }' "$headers" | tail -1)"
  cache_status="$(awk 'BEGIN { IGNORECASE=1 } /^cf-cache-status:/ { gsub("\\r", ""); print $2 }' "$headers" | tail -1)"
  signature="$(od -An -tx1 -N8 "$body" 2>/dev/null | tr -d ' \n')"
  valid=false
  if [[ "$status" == 200 && "$content_type" == image/png* && "$signature" == 89504e470d0a1a0a ]]; then
    valid=true
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$status" "$total" "$ttfb" "$bytes" "${cache_status:-UNKNOWN}" \
    "$valid" "$x/$y" >"$work_dir/$stage_number-$index.tsv"
}

stage_number=0
global_index=0
for concurrency in $stages; do
  stage_number=$((stage_number + 1))
  stage_started="$(date +%s)"
  for ((batch_start = 0; batch_start < samples_per_stage; batch_start += concurrency)); do
    for ((offset = 0; offset < concurrency; offset++)); do
      index=$((batch_start + offset))
      (( index >= samples_per_stage )) && break
      # Eight columns around Europe, advancing six fresh rows per stage.
      tile_index=$((global_index + index))
      x=$((512 + tile_index % 8))
      y=$((344 + tile_index / 8))
      probe_one "$stage_number" "$index" "$x" "$y" &
    done
    wait
  done
  stage_finished="$(date +%s)"
  elapsed=$((stage_finished - stage_started))
  (( elapsed < 1 )) && elapsed=1

  results="$work_dir/$stage_number-results.tsv"
  for ((index = 0; index < samples_per_stage; index++)); do
    cat "$work_dir/$stage_number-$index.tsv"
  done >"$results"

  errors="$(awk -F '\t' '$1 != 200 || $6 != "true" { count++ } END { print count+0 }' "$results")"
  p95_index="$(awk -v count="$samples_per_stage" 'BEGIN { value=int(count*0.95); if (value < count*0.95) value++; print value }')"
  p95="$(cut -f2 "$results" | sort -n | sed -n "${p95_index}p")"
  p50_index=$(( (samples_per_stage + 1) / 2 ))
  p50="$(cut -f2 "$results" | sort -n | sed -n "${p50_index}p")"
  maximum="$(cut -f2 "$results" | sort -n | tail -1)"
  hits="$(awk -F '\t' '$5 == "HIT" { count++ } END { print count+0 }' "$results")"
  misses="$(awk -F '\t' '$5 == "MISS" { count++ } END { print count+0 }' "$results")"
  throughput="$(awk -v samples="$samples_per_stage" -v seconds="$elapsed" 'BEGIN { printf "%.2f", samples/seconds }')"

  jq -cn \
    --arg measuredAt "$(date -u +%FT%TZ)" \
    --arg frame "$frame" \
    --argjson stage "$stage_number" \
    --argjson samples "$samples_per_stage" \
    --argjson concurrency "$concurrency" \
    --argjson errors "$errors" \
    --argjson hits "$hits" \
    --argjson misses "$misses" \
    --argjson elapsedSeconds "$elapsed" \
    --argjson p50Seconds "$p50" \
    --argjson p95Seconds "$p95" \
    --argjson maxSeconds "$maximum" \
    --argjson throughputTileRps "$throughput" \
    '{measuredAt:$measuredAt,frame:$frame,stage:$stage,samples:$samples,concurrency:$concurrency,errors:$errors,cloudflareHits:$hits,cloudflareMisses:$misses,elapsedSeconds:$elapsedSeconds,p50Seconds:$p50Seconds,p95Seconds:$p95Seconds,maxSeconds:$maxSeconds,throughputTileRps:$throughputTileRps}'

  if (( errors > 0 )); then
    echo 'Stopping: at least one invalid tile or HTTP error.' >&2
    exit 1
  fi
  if awk -v actual="$p95" -v limit="$p95_stop_seconds" 'BEGIN { exit !(actual > limit) }'; then
    printf 'Stopping: p95 exceeded %ss at concurrency %s.\n' \
      "$p95_stop_seconds" "$concurrency" >&2
    exit 1
  fi
  global_index=$((global_index + samples_per_stage))
done
