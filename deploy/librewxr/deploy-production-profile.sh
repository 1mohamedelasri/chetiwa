#!/usr/bin/env sh
# Applies Chetiwa's versioned memory/cache profile and watchdog to an existing
# LibreWXR host. It never changes firewall, Cloudflare credentials or DNS.
set -eu

server=${1:-root@116.203.124.254}
remote_dir=${CHETIWA_LIBREWXR_DIR:-/opt/chetiwa/librewxr}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
staging_dir=/tmp/chetiwa-librewxr-profile

ssh "$server" "set -eu; test -f '$remote_dir/docker-compose.yml'; mkdir -p '$staging_dir'"
scp \
  "$script_dir/hetzner-small.env" \
  "$script_dir/radar-watchdog.sh" \
  "$script_dir/chetiwa-radar-watchdog.service" \
  "$script_dir/chetiwa-radar-watchdog.timer" \
  "$server:$staging_dir/"

ssh "$server" "set -eu
install -m 0600 '$staging_dir/hetzner-small.env' '$remote_dir/.env'
install -m 0755 '$staging_dir/radar-watchdog.sh' /usr/local/sbin/chetiwa-radar-watchdog
install -m 0644 '$staging_dir/chetiwa-radar-watchdog.service' /etc/systemd/system/chetiwa-radar-watchdog.service
install -m 0644 '$staging_dir/chetiwa-radar-watchdog.timer' /etc/systemd/system/chetiwa-radar-watchdog.timer
cat > /etc/chetiwa-radar-watchdog.env <<'EOF'
CHETIWA_LIBREWXR_DIR=$remote_dir
CHETIWA_RADAR_LOCAL_HEALTH_URL=http://127.0.0.1:8080/public/weather-maps.json
CHETIWA_RADAR_PUBLIC_PROBE_URL=https://radar.ezplatforms.com/public/weather-maps.json
CHETIWA_CLOUDFLARED_SERVICE=cloudflared.service
CHETIWA_RADAR_FAILURE_THRESHOLD=3
CHETIWA_RADAR_RESTART_COOLDOWN_SECONDS=900
CHETIWA_RADAR_PROBE_TIMEOUT_SECONDS=12
EOF
chmod 0600 /etc/chetiwa-radar-watchdog.env
docker compose --env-file '$remote_dir/.env' \
  --project-directory '$remote_dir' up -d --force-recreate
systemctl daemon-reload
systemctl enable --now chetiwa-radar-watchdog.timer
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if curl --fail --silent --max-time 12 \
    http://127.0.0.1:8080/public/weather-maps.json >/dev/null; then
    curl --fail --silent --max-time 12 \
      https://radar.ezplatforms.com/public/weather-maps.json >/dev/null
    docker compose --env-file '$remote_dir/.env' \
      --project-directory '$remote_dir' ps
    curl --fail --silent --max-time 12 http://127.0.0.1:8080/health
    exit 0
  fi
  sleep 5
done
docker compose --env-file '$remote_dir/.env' \
  --project-directory '$remote_dir' logs --tail=120 >&2
exit 1"
