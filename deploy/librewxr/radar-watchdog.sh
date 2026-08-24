#!/usr/bin/env sh
# Restarts only the failed LibreWXR layer after repeated health failures.
# Intended to run from chetiwa-radar-watchdog.timer as root on the origin VM.
set -eu

librewxr_dir=${CHETIWA_LIBREWXR_DIR:-/opt/chetiwa/librewxr}
# `/health` serializes several large cache statistics and can take seconds on a
# busy single worker. The small metadata document is the real readiness signal
# required by clients and avoids restarting a healthy origin during tile work.
local_health_url=${CHETIWA_RADAR_LOCAL_HEALTH_URL:-http://127.0.0.1:8080/public/weather-maps.json}
public_probe_url=${CHETIWA_RADAR_PUBLIC_PROBE_URL:-https://radar.ezplatforms.com/public/weather-maps.json}
cloudflared_service=${CHETIWA_CLOUDFLARED_SERVICE:-cloudflared.service}
cloudflared_container=${CHETIWA_CLOUDFLARED_CONTAINER:-cloudflared}
state_dir=${CHETIWA_RADAR_WATCHDOG_STATE_DIR:-/var/lib/chetiwa-radar-watchdog}
failure_threshold=${CHETIWA_RADAR_FAILURE_THRESHOLD:-3}
cooldown_seconds=${CHETIWA_RADAR_RESTART_COOLDOWN_SECONDS:-900}
probe_timeout_seconds=${CHETIWA_RADAR_PROBE_TIMEOUT_SECONDS:-12}
startup_grace_seconds=${CHETIWA_RADAR_STARTUP_GRACE_SECONDS:-600}

mkdir -p "$state_dir"

probe() {
  curl --silent --show-error --fail \
    --connect-timeout 4 \
    --max-time "$probe_timeout_seconds" \
    --output /dev/null \
    "$1"
}

reset_failures() {
  printf '%s\n' 0 > "$state_dir/$1.failures"
}

record_failure() {
  component=$1
  counter_file="$state_dir/$component.failures"
  failures=0
  if [ -f "$counter_file" ]; then
    failures=$(cat "$counter_file" 2>/dev/null || printf '%s' 0)
  fi
  case $failures in
    ''|*[!0-9]*) failures=0 ;;
  esac
  failures=$((failures + 1))
  printf '%s\n' "$failures" > "$counter_file"
  printf '%s\n' "$failures"
}

restart_allowed() {
  component=$1
  last_restart_file="$state_dir/$component.last-restart"
  last_restart=0
  if [ -f "$last_restart_file" ]; then
    last_restart=$(cat "$last_restart_file" 2>/dev/null || printf '%s' 0)
  fi
  case $last_restart in
    ''|*[!0-9]*) last_restart=0 ;;
  esac
  now=$(date +%s)
  [ $((now - last_restart)) -ge "$cooldown_seconds" ]
}

mark_restarted() {
  date +%s > "$state_dir/$1.last-restart"
}

origin_in_startup_grace() {
  container_id=$(docker compose --project-directory "$librewxr_dir" ps -q librewxr 2>/dev/null | head -n 1)
  [ -n "$container_id" ] || return 1
  started_at=$(docker inspect --format '{{.State.StartedAt}}' "$container_id" 2>/dev/null) || return 1
  started_epoch=$(date -d "$started_at" +%s 2>/dev/null) || return 1
  now=$(date +%s)
  [ $((now - started_epoch)) -lt "$startup_grace_seconds" ]
}

restart_tunnel() {
  if systemctl cat "$cloudflared_service" >/dev/null 2>&1; then
    systemctl restart "$cloudflared_service"
    return
  fi
  if docker inspect "$cloudflared_container" >/dev/null 2>&1; then
    docker restart "$cloudflared_container" >/dev/null
    return
  fi
  echo "No Cloudflare service or container found." >&2
  return 1
}

if ! probe "$local_health_url"; then
  if origin_in_startup_grace; then
    reset_failures origin
    echo "LibreWXR is starting; watchdog grace period is active."
    exit 0
  fi
  failures=$(record_failure origin)
  echo "LibreWXR local health failed ($failures/$failure_threshold)." >&2
  if [ "$failures" -lt "$failure_threshold" ] || ! restart_allowed origin; then
    exit 1
  fi
  mark_restarted origin
  docker compose --project-directory "$librewxr_dir" restart librewxr
  reset_failures origin
  echo 'LibreWXR restart initiated; startup grace period is active.'
  exit 0
fi
reset_failures origin

if ! probe "$public_probe_url"; then
  failures=$(record_failure tunnel)
  echo "Cloudflare public radar probe failed ($failures/$failure_threshold)." >&2
  if [ "$failures" -lt "$failure_threshold" ] || ! restart_allowed tunnel; then
    exit 1
  fi
  mark_restarted tunnel
  restart_tunnel
  sleep 5
  if probe "$public_probe_url"; then
    reset_failures tunnel
    echo 'Cloudflare Tunnel recovered after restart.'
    exit 0
  fi
  echo 'Cloudflare Tunnel is still unhealthy after restart.' >&2
  exit 1
fi

reset_failures tunnel
echo 'LibreWXR origin and public tunnel are healthy.'
