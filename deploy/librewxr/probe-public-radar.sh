#!/usr/bin/env bash
# Bounded public LibreWXR probe. Run it from each launch region to compare the
# Cloudflare edge, origin MISS and immediate HIT paths without flooding origin.
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

probe_tile() {
  local name="$1" longitude="$2" latitude="$3"
  local coordinates url pass headers body metrics status total ttfb bytes
  local content_type cache_status age signature limit
  coordinates="$(tile_coordinates "$longitude" "$latitude")"
  # Probe the exact palette/presentation requested by the released apps.
  # Probing scheme 13 used to leave scheme 14 cold for the first real user.
  url="$base_url$frame/256/$zoom/$coordinates/14/1_0.png?presentation=crisp-v2"

  for pass in first repeat; do
    headers="$work_dir/$name-$pass.headers"
    body="$work_dir/$name-$pass.png"
    metrics="$(curl --silent --show-error \
      --connect-timeout 5 --max-time 30 \
      --dump-header "$headers" --output "$body" \
      --write-out '%{http_code} %{time_total} %{time_starttransfer} %{size_download}' \
      "$url")"
    read -r status total ttfb bytes <<<"$metrics"
    content_type="$(awk 'BEGIN { IGNORECASE=1 } /^content-type:/ { gsub("\\r", ""); print $2 }' "$headers" | tail -1)"
    cache_status="$(awk 'BEGIN { IGNORECASE=1 } /^cf-cache-status:/ { gsub("\\r", ""); print $2 }' "$headers" | tail -1)"
    age="$(awk 'BEGIN { IGNORECASE=1 } /^age:/ { gsub("\\r", ""); print $2 }' "$headers" | tail -1)"
    signature="$(od -An -tx1 -N8 "$body" | tr -d ' \n')"
    limit="$warm_limit_seconds"
    [[ "$cache_status" == MISS ]] && limit="$cold_limit_seconds"

    jq -cn \
      --arg measuredAt "$(date -u +%FT%TZ)" \
      --arg region "$probe_region" \
      --arg location "$name" \
      --arg phase "$pass" \
      --arg frame "$frame" \
      --arg tile "$coordinates" \
      --arg status "$status" \
      --arg cacheStatus "${cache_status:-UNKNOWN}" \
      --arg contentType "${content_type:-UNKNOWN}" \
      --arg age "${age:-0}" \
      --argjson totalSeconds "$total" \
      --argjson ttfbSeconds "$ttfb" \
      --argjson bytes "$bytes" \
      '{measuredAt:$measuredAt,region:$region,location:$location,phase:$phase,frame:$frame,tile:$tile,status:($status|tonumber),cacheStatus:$cacheStatus,contentType:$contentType,ageSeconds:($age|tonumber),totalSeconds:$totalSeconds,ttfbSeconds:$ttfbSeconds,bytes:$bytes}'

    if [[ "$status" != 200 || "$content_type" != image/png* || "$signature" != 89504e470d0a1a0a ]]; then
      printf 'Invalid radar tile for %s (%s).\n' "$name" "$pass" >&2
      return 1
    fi
    if [[ "$pass" == repeat && "$cache_status" != HIT ]]; then
      printf '%s repeat tile was not a Cloudflare HIT (%s).\n' \
        "$name" "${cache_status:-UNKNOWN}" >&2
      return 1
    fi
    if greater_than "$total" "$limit"; then
      printf '%s %s tile exceeded %ss: %ss.\n' "$name" "$pass" "$limit" "$total" >&2
      return 1
    fi
  done
}

jq -cn \
  --arg measuredAt "$(date -u +%FT%TZ)" \
  --arg region "$probe_region" \
  --arg frame "$frame" \
  --argjson pastFrames "$past_count" \
  --argjson nowcastFrames "$nowcast_count" \
  '{measuredAt:$measuredAt,region:$region,kind:"metadata",frame:$frame,pastFrames:$pastFrames,nowcastFrames:$nowcastFrames}'

# Five bounded points cover the Europe launch area and global fallback. The
# second request to each exact URL verifies that Cloudflare can serve a HIT.
probe_tile Paris 2.3522 48.8566
probe_tile Freetown -13.2317 8.4657
probe_tile New_York -74.0060 40.7128
probe_tile Tokyo 139.6917 35.6895
probe_tile Sydney 151.2093 -33.8688
