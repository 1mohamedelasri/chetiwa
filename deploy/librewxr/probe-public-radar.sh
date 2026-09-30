#!/usr/bin/env bash
# Bounded public LibreWXR probe. Run it from each launch region to compare the
# Cloudflare edge and bounded cache convergence without flooding origin.
set -euo pipefail

base_url="${CHETIWA_RADAR_BASE_URL:-https://radar.ezplatforms.com}"
probe_region="${CHETIWA_PROBE_REGION:-unknown}"
zoom="${CHETIWA_RADAR_PROBE_ZOOM:-10}"
cold_limit_seconds="${CHETIWA_RADAR_COLD_LIMIT_SECONDS:-2.0}"
warm_limit_seconds="${CHETIWA_RADAR_WARM_LIMIT_SECONDS:-0.5}"

for command in curl jq awk od; do
  command -v "$command" >/dev/null || {
    printf 'Missing required command: %s\n' "$command" >&2
    exit 2
  }
done

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
metadata="$work_dir/metadata.json"
metadata_headers="$work_dir/metadata.headers"

curl --fail --silent --show-error \
  --connect-timeout 5 --max-time 20 \
  --dump-header "$metadata_headers" \
  --output "$metadata" \
  "$base_url/public/weather-maps.json"

frame="$(jq -er '.radar.past[-1].path' "$metadata")"
past_count="$(jq -er '.radar.past | length' "$metadata")"
nowcast_count="$(jq -er '.radar.nowcast | length' "$metadata")"
if [[ "$frame" != /v2/radar/* || "$past_count" -lt 1 ]]; then
  printf 'Invalid LibreWXR metadata contract.\n' >&2
  exit 1
fi

tile_coordinates() {
  local longitude="$1" latitude="$2"
  awk -v lon="$longitude" -v lat="$latitude" -v z="$zoom" '
    BEGIN {
      pi = atan2(0, -1)
      n = 2 ^ z
      x = int((lon + 180) / 360 * n)
      radians = lat * pi / 180
      y = int((1 - log(sin(radians) / cos(radians) + 1 / cos(radians)) / pi) / 2 * n)
      print x "/" y
    }
  '
}

greater_than() {
  awk -v actual="$1" -v limit="$2" 'BEGIN { exit !(actual > limit) }'
}

header_value() {
  local headers="$1" name="$2"
  awk -v name="$name" '
    tolower($0) ~ "^" name ":" {
      sub(/^[^:]*:[[:space:]]*/, "")
      sub(/\r$/, "")
      value = $0
    }
    END { print value }
  ' "$headers"
}

probe_tile() {
  local name="$1" longitude="$2" latitude="$3" attempt="$4"
  local coordinates url pass headers body metrics status total ttfb bytes
  local content_type cache_status age signature limit cf_ray cf_pop cache_control
  coordinates="$(tile_coordinates "$longitude" "$latitude")"
  # Probe the exact palette/presentation requested by the released apps.
  # Keep the probe on the neutral palette served by the API and new app builds.
  url="$base_url$frame/256/$zoom/$coordinates/15/1_0.png?presentation=neutral-v1"

  pass=repeat
  [[ "$attempt" == 1 ]] && pass=first
  headers="$work_dir/$name-$attempt.headers"
  body="$work_dir/$name-$attempt.png"
  metrics="$(curl --silent --show-error \
    --connect-timeout 5 --max-time 30 \
    --dump-header "$headers" --output "$body" \
    --write-out '%{http_code} %{time_total} %{time_starttransfer} %{size_download}' \
    "$url")" || {
    printf 'Radar request failed for %s (sample %s).\n' "$name" "$attempt" >&2
    return 1
  }
  read -r status total ttfb bytes <<<"$metrics"
  content_type="$(header_value "$headers" content-type)"
  cache_status="$(header_value "$headers" cf-cache-status)"
  age="$(header_value "$headers" age)"
  cf_ray="$(header_value "$headers" cf-ray)"
  cf_pop="${cf_ray##*-}"
  [[ "$cf_ray" == *-* ]] || cf_pop=UNKNOWN
  cache_control="$(header_value "$headers" cache-control)"
  signature="$(od -An -tx1 -N8 "$body" | tr -d ' \n')"
  limit="$warm_limit_seconds"
  [[ "$cache_status" == MISS ]] && limit="$cold_limit_seconds"

  jq -cn \
    --arg measuredAt "$(date -u +%FT%TZ)" \
    --arg region "$probe_region" \
    --arg location "$name" \
    --arg phase "$pass" \
    --argjson attempt "$attempt" \
    --arg cfRay "${cf_ray:-UNKNOWN}" \
    --arg cfPop "$cf_pop" \
    --arg cacheControl "$cache_control" \
    --arg frame "$frame" \
    --arg tile "$coordinates" \
    --arg status "$status" \
    --arg cacheStatus "${cache_status:-UNKNOWN}" \
    --arg contentType "${content_type:-UNKNOWN}" \
    --arg age "${age:-0}" \
    --argjson totalSeconds "$total" \
    --argjson ttfbSeconds "$ttfb" \
    --argjson bytes "$bytes" \
    '{measuredAt:$measuredAt,region:$region,location:$location,phase:$phase,attempt:$attempt,cfRay:$cfRay,cfPop:$cfPop,cacheControl:$cacheControl,frame:$frame,tile:$tile,status:($status|tonumber),cacheStatus:$cacheStatus,contentType:$contentType,ageSeconds:($age|tonumber),totalSeconds:$totalSeconds,ttfbSeconds:$ttfbSeconds,bytes:$bytes}' || return 1

  if [[ "$status" != 200 || "$content_type" != image/png* || "$signature" != 89504e470d0a1a0a ]]; then
    printf 'Invalid radar tile for %s (%s).\n' "$name" "$pass" >&2
    return 1
  fi
  case "$cache_status" in
    HIT|MISS|EXPIRED|REVALIDATED|UPDATING) ;;
    *)
      printf '%s tile is not cacheable by Cloudflare (%s, POP %s).\n' \
        "$name" "${cache_status:-UNKNOWN}" "$cf_pop" >&2
      return 1
      ;;
  esac
  if greater_than "$total" "$limit"; then
    printf '%s %s tile exceeded %ss: %ss.\n' "$name" "$pass" "$limit" "$total" >&2
    return 1
  fi
  # A MISS is pending evidence, not success. The caller retries the exact
  # URL in bounded rounds and fails if no later request becomes a HIT.
  [[ "$cache_status" == HIT ]] || return 2
  return 0
}

jq -cn \
  --arg measuredAt "$(date -u +%FT%TZ)" \
  --arg region "$probe_region" \
  --arg frame "$frame" \
  --argjson pastFrames "$past_count" \
  --argjson nowcastFrames "$nowcast_count" \
  '{measuredAt:$measuredAt,region:$region,kind:"metadata",frame:$frame,pastFrames:$pastFrames,nowcastFrames:$nowcastFrames}'

# Always sample each URL at least twice. If an immediate repeat is still a
# MISS, allow 10 and then 45 seconds for cache fill/edge routing to settle.
# Delay between rounds rather than per city: at most 20 tile requests and 55
# seconds of waiting for the whole probe, within the monitor's four-minute job.
# CF-Ray and POP are recorded on every sample so edge changes remain visible.
probe_names=(Paris Freetown New_York Tokyo Sydney)
probe_longitudes=(2.3522 -13.2317 -74.0060 139.6917 151.2093)
probe_latitudes=(48.8566 8.4657 40.7128 35.6895 -33.8688)
retry_delays=(0 0 10 45)
pending_indexes=(0 1 2 3 4)

for round in 0 1 2 3; do
  delay="${retry_delays[$round]}"
  [[ "$delay" == 0 ]] || sleep "$delay"
  next_pending=()
  for index in "${pending_indexes[@]}"; do
    if probe_tile "${probe_names[$index]}" "${probe_longitudes[$index]}" \
        "${probe_latitudes[$index]}" "$((round + 1))"; then
      # A first-request HIT still needs one repeat latency/cache verification.
      [[ "$round" != 0 ]] || next_pending+=("$index")
    else
      result=$?
      [[ "$result" == 2 ]] || exit "$result"
      next_pending+=("$index")
    fi
  done
  # Bash 3.2 treats an empty array expansion as unbound under set -u.
  [[ "${#next_pending[@]}" != 0 ]] || exit 0
  pending_indexes=("${next_pending[@]}")
done

for index in "${pending_indexes[@]}"; do
  printf '%s did not converge to a Cloudflare HIT after 4 samples and 55s of bounded waits; inspect the recorded POPs.\n' \
    "${probe_names[$index]}" >&2
done
exit 1
