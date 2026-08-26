#!/usr/bin/env bash
# Prepares one representative palette-14 tile for every newly published frame.
# LibreWXR performs expensive frame/palette setup on the first tile request;
# warming one Paris tile keeps that work away from the first mobile client
# without rendering a world-wide tile pyramid.
set -euo pipefail

local_base_url="${CHETIWA_RADAR_LOCAL_BASE_URL:-http://127.0.0.1:8080}"
public_base_url="${CHETIWA_RADAR_BASE_URL:-https://radar.ezplatforms.com}"
state_dir="${CHETIWA_RADAR_PREWARM_STATE_DIR:-/var/lib/chetiwa-radar-prewarm}"
zoom="${CHETIWA_RADAR_PREWARM_ZOOM:-7}"
tile_x="${CHETIWA_RADAR_PREWARM_TILE_X:-64}"
tile_y="${CHETIWA_RADAR_PREWARM_TILE_Y:-44}"
scheme="${CHETIWA_RADAR_PREWARM_SCHEME:-14}"

for command in curl python3 flock; do
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
previous="$state_dir/warmed-frames.txt"
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
  local key="$1" frame run path local_url public_url
  frame="${key%%|*}"
  run=""
  if [[ "$key" == *"|"* ]]; then
    run="${key##*|}"
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
  printf '%s\n' "$key" >>"$completed"
}

failures=0
while IFS= read -r key; do
  if grep -Fqx "$key" "$previous"; then
    printf '%s\n' "$key" >>"$completed"
    continue
  fi
  if ! warm_frame "$key"; then
    printf 'Failed to prepare frame key: %s\n' "$key" >&2
    failures=$((failures + 1))
  fi
done <"$work_dir/current-frames.txt"

# Retain only paths still advertised by metadata. Atomic replacement prevents
# an interrupted warm-up from marking a frame ready when it was not.
sort -u "$completed" >"$work_dir/warmed-frames.txt"
install -m 0644 "$work_dir/warmed-frames.txt" "$previous"

printf 'Prepared %s current LibreWXR frames with palette %s.\n' \
  "$(wc -l <"$previous" | tr -d ' ')" "$scheme"

if (( failures > 0 )); then
  printf '%s frame(s) remain cold and will be retried by the next timer.\n' \
    "$failures" >&2
  exit 1
fi
