#!/usr/bin/env bash
# Prepares representative European and CONUS tiles at the zoom levels used by
# the mobile Radar. LibreWXR performs expensive region/frame setup on the first
# request; warming Paris alone left the United States and zoom transitions cold.
set -euo pipefail

local_base_url="${CHETIWA_RADAR_LOCAL_BASE_URL:-http://127.0.0.1:8080}"
public_base_url="${CHETIWA_RADAR_BASE_URL:-https://radar.ezplatforms.com}"
api_local_base_url="${CHETIWA_API_LOCAL_BASE_URL:-http://127.0.0.1:8081}"
api_public_base_url="${CHETIWA_API_BASE_URL:-https://chetiwa-api.ezplatforms.com}"
state_dir="${CHETIWA_RADAR_PREWARM_STATE_DIR:-/var/lib/chetiwa-radar-prewarm}"
scheme="${CHETIWA_RADAR_PREWARM_SCHEME:-14}"
# name:zoom:x:y. One tile initializes the regional frame/palette path without
# attempting an expensive world-wide pyramid. Override as a space-separated
# list when the launch geography changes.
warm_target_spec="${CHETIWA_RADAR_PREWARM_TARGETS:-paris-z5:5:16:11 paris-z7:7:64:44 paris-z9:9:259:176 nashville-z5:5:8:12 nashville-z7:7:33:50 nashville-z9:9:132:200}"
read -r -a warm_targets <<<"$warm_target_spec"

for command in base64 curl python3 flock; do
  command -v "$command" >/dev/null || {
    printf 'Missing required command: %s\n' "$command" >&2
    exit 2
  }
done

install -d -m 0755 "$state_dir"
exec 9>"$state_dir/prewarm.lock"
flock -n 9 || exit 0

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
metadata="$work_dir/metadata.json"
previous="$state_dir/warmed-api-frames-v3.txt"
completed="$work_dir/completed.txt"
touch "$previous" "$completed"

curl --fail --silent --show-error \
  --connect-timeout 3 --max-time 12 \
  --output "$metadata" \
  "$local_base_url/public/weather-maps.json"

python3 - "$metadata" >"$work_dir/current-frames.txt" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    metadata = json.load(source)
radar = metadata.get("radar") or {}
past = [frame for frame in radar.get("past") or [] if isinstance(frame, dict)]
nowcast = [
    frame for frame in radar.get("nowcast") or [] if isinstance(frame, dict)
]
latest_observation = max(
    (frame.get("time", 0) for frame in past if isinstance(frame.get("time"), int)),
    default=0,
)
keys = {
    frame["path"]
    for frame in past
    if isinstance(frame.get("path"), str)
}
# Forecast PNGs are versioned by the latest observation in both the backend
# proxy and the mobile direct-fallback URL. Seed that exact Cloudflare cache
# key; warming the unversioned URL left real clients paying the cold render.
keys.update(
    f'{frame["path"]}|{latest_observation}'
    for frame in nowcast
    if isinstance(frame.get("path"), str) and latest_observation > 0
)
for key in sorted(keys):
    print(key)
PY

warm_frame() {
  local key="$1" target="$2" frame run target_name zoom tile_x tile_y
  local path local_url public_url frame_id api_path
  frame="${key%%|*}"
  run=""
  if [[ "$key" == *"|"* ]]; then
    run="${key##*|}"
  fi
  IFS=: read -r target_name zoom tile_x tile_y <<<"$target"
  if [[ -z "$target_name" || -z "$zoom" || -z "$tile_x" || -z "$tile_y" ]]; then
    printf 'Invalid prewarm target: %s\n' "$target" >&2
    return 1
  fi
  path="$frame/256/$zoom/$tile_x/$tile_y/$scheme/1_0.png?presentation=crisp-v2"
  if [[ -n "$run" ]]; then
    path="$path&run=$run"
  fi
  local_url="$local_base_url$path"
  public_url="$public_base_url$path"

  # The local call performs LibreWXR's cold preparation. The following public
  # call verifies the tunnel and seeds Cloudflare after the origin is warm.
  curl --fail --silent --show-error --retry 1 --retry-delay 1 \
    --connect-timeout 3 --max-time 45 --output /dev/null "$local_url" || return 1
  curl --fail --silent --show-error --retry 1 --retry-delay 1 \
    --connect-timeout 3 --max-time 15 --output /dev/null "$public_url" || return 1

  # Production phones use the Chetiwa API proxy, not the LibreWXR hostname.
  # Warming only radar.ezplatforms.com left the API binary cache and its
  # Cloudflare cache cold, so the first phone still paid the complete render
  # cost. Seed the exact base64 frame URL emitted by /v1/radar/frames.
  frame_id="$(printf '%s' "$frame" | base64 | tr '+/' '-_' | tr -d '=\n')"
  # The .png suffix makes Cloudflare cache the API response as a static asset.
  api_path="/v1/radar/tiles/$frame_id/$zoom/$tile_x/$tile_y.png"
  if [[ -n "$run" ]]; then
    api_path="$api_path?run=$run"
  fi
  curl --fail --silent --show-error --retry 1 --retry-delay 1 \
    --connect-timeout 3 --max-time 45 --output /dev/null \
    "$api_local_base_url$api_path" || return 1
  curl --fail --silent --show-error --retry 1 --retry-delay 1 \
    --connect-timeout 3 --max-time 15 --output /dev/null \
    "$api_public_base_url$api_path" || return 1
  printf '%s|%s\n' "$key" "$target_name" >>"$completed"
}

failures=0
while IFS= read -r key; do
  for target in "${warm_targets[@]}"; do
    target_name="${target%%:*}"
    warm_key="$key|$target_name"
    if grep -Fqx "$warm_key" "$previous"; then
      printf '%s\n' "$warm_key" >>"$completed"
      continue
    fi
    if ! warm_frame "$key" "$target"; then
      printf 'Failed to prepare frame/target: %s / %s\n' "$key" "$target_name" >&2
      failures=$((failures + 1))
    fi
  done
done <"$work_dir/current-frames.txt"

# Retain only paths still advertised by metadata. Atomic replacement prevents
# an interrupted warm-up from marking a frame ready when it was not.
sort -u "$completed" >"$work_dir/warmed-frames.txt"
install -m 0644 "$work_dir/warmed-frames.txt" "$previous"

printf 'Prepared %s current LibreWXR frame/target pairs with palette %s.\n' \
  "$(wc -l <"$previous" | tr -d ' ')" "$scheme"

if (( failures > 0 )); then
  printf '%s frame(s) remain cold and will be retried by the next timer.\n' \
    "$failures" >&2
  exit 1
fi
