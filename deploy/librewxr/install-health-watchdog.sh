#!/usr/bin/env sh
# Run once, as root, after LibreWXR and the named Cloudflare Tunnel work.
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo 'Run this installer as root.' >&2
  exit 1
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
install -m 0755 "$script_dir/radar-watchdog.sh" /usr/local/sbin/chetiwa-radar-watchdog
install -m 0644 "$script_dir/chetiwa-radar-watchdog.service" /etc/systemd/system/chetiwa-radar-watchdog.service
install -m 0644 "$script_dir/chetiwa-radar-watchdog.timer" /etc/systemd/system/chetiwa-radar-watchdog.timer

if [ ! -f /etc/chetiwa-radar-watchdog.env ]; then
  install -m 0600 /dev/null /etc/chetiwa-radar-watchdog.env
  printf '%s\n' \
    'CHETIWA_LIBREWXR_DIR=/opt/chetiwa/librewxr' \
    'CHETIWA_RADAR_LOCAL_HEALTH_URL=http://127.0.0.1:8080/public/weather-maps.json' \
    'CHETIWA_RADAR_PUBLIC_PROBE_URL=https://radar.ezplatforms.com/public/weather-maps.json' \
    'CHETIWA_CLOUDFLARED_SERVICE=cloudflared.service' \
    'CHETIWA_RADAR_FAILURE_THRESHOLD=3' \
    'CHETIWA_RADAR_RESTART_COOLDOWN_SECONDS=900' \
    'CHETIWA_RADAR_PROBE_TIMEOUT_SECONDS=12' \
    > /etc/chetiwa-radar-watchdog.env
else
  sed -i \
    's|^CHETIWA_RADAR_LOCAL_HEALTH_URL=http://127.0.0.1:8080/health$|CHETIWA_RADAR_LOCAL_HEALTH_URL=http://127.0.0.1:8080/public/weather-maps.json|' \
    /etc/chetiwa-radar-watchdog.env
  if ! grep -q '^CHETIWA_RADAR_PROBE_TIMEOUT_SECONDS=' \
    /etc/chetiwa-radar-watchdog.env; then
    printf '%s\n' 'CHETIWA_RADAR_PROBE_TIMEOUT_SECONDS=12' \
      >> /etc/chetiwa-radar-watchdog.env
  fi
fi

systemctl daemon-reload
systemctl enable --now chetiwa-radar-watchdog.timer
systemctl start chetiwa-radar-watchdog.service
systemctl --no-pager status chetiwa-radar-watchdog.timer
