#!/usr/bin/env bash
# Small, bounded concurrency benchmark for one current LibreWXR frame.
# This is a release gate, not a stress test: defaults to 12 unique tiles and
# four simultaneous requests, and refuses unsafe values.
set -euo pipefail

base_url="${CHETIWA_RADAR_BASE_URL:-https://radar.ezplatforms.com}"
sample_count="${CHETIWA_RADAR_BENCHMARK_SAMPLES:-12}"
concurrency="${CHETIWA_RADAR_BENCHMARK_CONCURRENCY:-4}"
zoom="${CHETIWA_RADAR_PROBE_ZOOM:-10}"
p95_limit_seconds="${CHETIWA_RADAR_COLD_P95_LIMIT_SECONDS:-2.0}"

if (( sample_count < 4 || sample_count > 32 || concurrency < 1 || concurrency > 8 )); then
  echo 'Use 4-32 samples and concurrency 1-8.' >&2
  exit 2
fi
for command in curl jq awk od sort; do
  command -v "$command" >/dev/null || {
    printf 'Missing required command: %s\n' "$command" >&2
    exit 2
  }
done

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
metadata="$work_dir/metadata.json"
curl --fail --silent --show-error --connect-timeout 5 --max-time 20 \
  "$base_url/public/weather-maps.json" -o "$metadata"
frame="$(jq -er '.radar.past[-1].path' "$metadata")"

# Paris at z10 is 518/352. Adjacent unique tiles exercise populated European
# radar paths while remaining a very small bounded load on the origin.
probe_one() {
  local index="$1" x y url headers body metrics status total ttfb bytes
  local content_type cache_status signature valid
  x=$((516 + index % 4))
  y=$((350 + index / 4))
  url="$base_url$frame/256/$zoom/$x/$y/13/1_0.png"
  headers="$work_dir/$index.headers"
  body="$work_dir/$index.png"
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
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s/%s\n' \
    "$index" "$status" "$total" "$ttfb" "$bytes" \
    "${cache_status:-UNKNOWN}" "$valid" "$x" "$y" >"$work_dir/$index.tsv"
}

for ((batch_start = 0; batch_start < sample_count; batch_start += concurrency)); do
  for ((offset = 0; offset < concurrency; offset++)); do
    index=$((batch_start + offset))
    (( index >= sample_count )) && break
    probe_one "$index" &
  done
  wait
done

results="$work_dir/results.tsv"
for ((index = 0; index < sample_count; index++)); do
  cat "$work_dir/$index.tsv"
done >"$results"

if awk -F '\t' '$2 != 200 || $7 != "true" { bad=1 } END { exit !bad }' "$results"; then
  echo 'At least one benchmark tile was invalid.' >&2
  cat "$results" >&2
  exit 1
fi

p95_index="$(awk -v count="$sample_count" 'BEGIN { value=int(count*0.95); if (value < count*0.95) value++; if (value < 1) value=1; print value }')"
p95="$(cut -f3 "$results" | sort -n | sed -n "${p95_index}p")"
p50_index=$(( (sample_count + 1) / 2 ))
p50="$(cut -f3 "$results" | sort -n | sed -n "${p50_index}p")"
misses="$(awk -F '\t' '$6 == "MISS" { count++ } END { print count+0 }' "$results")"
hits="$(awk -F '\t' '$6 == "HIT" { count++ } END { print count+0 }' "$results")"
estimated_rps="$(awk -v parallel="$concurrency" -v latency="$p95" 'BEGIN { if (latency == 0) print 0; else printf "%.2f", parallel/latency }')"

jq -cn \
  --arg measuredAt "$(date -u +%FT%TZ)" \
  --arg frame "$frame" \
  --argjson samples "$sample_count" \
  --argjson concurrency "$concurrency" \
  --argjson hits "$hits" \
  --argjson misses "$misses" \
  --argjson p50Seconds "$p50" \
  --argjson p95Seconds "$p95" \
  --argjson estimatedTileRps "$estimated_rps" \
  '{measuredAt:$measuredAt,frame:$frame,samples:$samples,concurrency:$concurrency,cloudflareHits:$hits,cloudflareMisses:$misses,p50Seconds:$p50Seconds,p95Seconds:$p95Seconds,estimatedTileRpsAtMeasuredConcurrency:$estimatedTileRps}'

if awk -v actual="$p95" -v limit="$p95_limit_seconds" 'BEGIN { exit !(actual > limit) }'; then
  printf 'Radar tile p95 exceeded %ss: %ss.\n' "$p95_limit_seconds" "$p95" >&2
  exit 1
fi
