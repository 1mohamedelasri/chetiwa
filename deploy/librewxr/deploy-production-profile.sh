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
  "$script_dir/chetiwa-smooth-120-nowcast.patch" \
  "$script_dir/chetiwa-opaque-palette-upgrade.patch" \
  "$script_dir/chetiwa-crisp-presentation.patch" \
  "$script_dir/chetiwa-crisp-palette-upgrade.patch" \
  "$script_dir/radar-watchdog.sh" \
  "$script_dir/chetiwa-radar-watchdog.service" \
  "$script_dir/chetiwa-radar-watchdog.timer" \
  "$server:$staging_dir/"

ssh "$server" "set -eu
available_kb=\$(awk '/MemTotal:/ { print \$2 }' /proc/meminfo)
if [ \"\${available_kb:-0}\" -lt 3500000 ]; then
  echo 'Refusing the 3 GB LibreWXR profile: the host has less than 3.5 GB RAM.' >&2
  exit 2
fi
if ! swapon --noheadings --show=NAME | grep -q .; then
  available_disk_kb=\$(df --output=avail / | tail -n 1 | tr -d ' ')
  if [ \"\${available_disk_kb:-0}\" -lt 3145728 ]; then
    echo 'Refusing to create the 2 GB safety swap: less than 3 GB is free.' >&2
    exit 2
  fi
  fallocate -l 2G /swapfile
  chmod 0600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || printf '%s\n' '/swapfile none swap sw 0 0' >> /etc/fstab
fi
backup_env='$remote_dir/.env.backup-'\$(date -u +%Y%m%dT%H%M%SZ)
cp '$remote_dir/.env' \"\$backup_env\"
smooth_patch_applied=0
palette_patch_applied=0
crisp_patch_applied=0
crisp_palette_patch_applied=0
rollback() {
  echo 'Deployment failed; restoring the previous LibreWXR profile.' >&2
  install -m 0600 \"\$backup_env\" '$remote_dir/.env'
  if [ "\$smooth_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-smooth-120-nowcast.patch' || true
  fi
  if [ "\$palette_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-opaque-palette-upgrade.patch' || true
  fi
  if [ "\$crisp_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-crisp-presentation.patch' || true
  fi
  if [ "\$crisp_palette_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-crisp-palette-upgrade.patch' || true
  fi
  docker compose --env-file '$remote_dir/.env' \
    --project-directory '$remote_dir' up -d --build --force-recreate || true
}
trap rollback EXIT HUP INT TERM
if grep -q 'conservative 45% radar floor' '$remote_dir/src/librewxr/data/nowcast.py'; then
  echo 'Chetiwa smooth 120-minute nowcast patch already installed.'
else
  git -C '$remote_dir' apply --check '$staging_dir/chetiwa-smooth-120-nowcast.patch'
  git -C '$remote_dir' apply '$staging_dir/chetiwa-smooth-120-nowcast.patch'
  smooth_patch_applied=1
fi
if grep -q '(216, 220, 222, 110)' '$remote_dir/src/librewxr/colors/schemes.py'; then
  echo 'Chetiwa opaque radar palette already installed.'
else
  git -C '$remote_dir' apply --check '$staging_dir/chetiwa-opaque-palette-upgrade.patch'
  git -C '$remote_dir' apply '$staging_dir/chetiwa-opaque-palette-upgrade.patch'
  palette_patch_applied=1
fi
if grep -q 'Chetiwa Crisp Grey Red' '$remote_dir/src/librewxr/colors/schemes.py'; then
  echo 'Chetiwa crisp radar presentation patch already installed.'
else
  git -C '$remote_dir' apply --check '$staging_dir/chetiwa-crisp-presentation.patch'
  git -C '$remote_dir' apply '$staging_dir/chetiwa-crisp-presentation.patch'
  crisp_patch_applied=1
fi
if grep -q '_chetiwa_crisp_lut' '$remote_dir/src/librewxr/colors/schemes.py'; then
  echo 'Chetiwa crisp discrete palette already installed.'
else
  git -C '$remote_dir' apply --check '$staging_dir/chetiwa-crisp-palette-upgrade.patch'
  git -C '$remote_dir' apply '$staging_dir/chetiwa-crisp-palette-upgrade.patch'
  crisp_palette_patch_applied=1
fi
install -m 0600 '$staging_dir/hetzner-small.env' '$remote_dir/.env'
install -m 0755 '$staging_dir/radar-watchdog.sh' /usr/local/sbin/chetiwa-radar-watchdog
install -m 0644 '$staging_dir/chetiwa-radar-watchdog.service' /etc/systemd/system/chetiwa-radar-watchdog.service
install -m 0644 '$staging_dir/chetiwa-radar-watchdog.timer' /etc/systemd/system/chetiwa-radar-watchdog.timer
cat > /etc/chetiwa-radar-watchdog.env <<'EOF'
CHETIWA_LIBREWXR_DIR=$remote_dir
CHETIWA_RADAR_LOCAL_HEALTH_URL=http://127.0.0.1:8080/public/weather-maps.json
CHETIWA_RADAR_PUBLIC_PROBE_URL=https://radar.ezplatforms.com/public/weather-maps.json
CHETIWA_CLOUDFLARED_SERVICE=cloudflared.service
CHETIWA_CLOUDFLARED_CONTAINER=cloudflared
CHETIWA_RADAR_FAILURE_THRESHOLD=3
CHETIWA_RADAR_RESTART_COOLDOWN_SECONDS=900
CHETIWA_RADAR_PROBE_TIMEOUT_SECONDS=12
CHETIWA_RADAR_STARTUP_GRACE_SECONDS=600
EOF
chmod 0600 /etc/chetiwa-radar-watchdog.env
docker compose --env-file '$remote_dir/.env' \
  --project-directory '$remote_dir' config --quiet
docker compose --env-file '$remote_dir/.env' \
  --project-directory '$remote_dir' up -d --build --force-recreate
systemctl daemon-reload
systemctl enable --now chetiwa-radar-watchdog.timer
attempt=1
while [ \"\$attempt\" -le 90 ]; do
  if curl --fail --silent --max-time 12 \
    http://127.0.0.1:8080/public/weather-maps.json >/dev/null; then
    curl --fail --silent --max-time 12 \
      https://radar.ezplatforms.com/public/weather-maps.json >/dev/null
    docker compose --env-file '$remote_dir/.env' \
      --project-directory '$remote_dir' ps
    curl --fail --silent --max-time 12 http://127.0.0.1:8080/health
    trap - EXIT HUP INT TERM
    rm -rf '$staging_dir'
    echo \"Previous profile backup retained at \$backup_env\"
    exit 0
  fi
  sleep 5
  attempt=\$((attempt + 1))
done
docker compose --env-file '$remote_dir/.env' \
  --project-directory '$remote_dir' logs --tail=120 >&2
exit 1"
