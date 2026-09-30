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
  "$script_dir/chetiwa-native-nowcast-memory.patch" \
  "$script_dir/chetiwa-distinct-flow-baseline.patch" \
  "$script_dir/chetiwa-small-host-cpu-isolation.patch" \
  "$script_dir/chetiwa-opaque-palette-upgrade.patch" \
  "$script_dir/chetiwa-crisp-presentation.patch" \
  "$script_dir/chetiwa-crisp-palette-upgrade.patch" \
  "$script_dir/chetiwa-visible-light-rain-palette.patch" \
  "$script_dir/chetiwa-neutral-rain-palette.patch" \
  "$script_dir/chetiwa-restored-startup.patch" \
  "$script_dir/chetiwa-nonblocking-frame-reads.patch" \
  "$script_dir/chetiwa-interactive-tile-executor.patch" \
  "$script_dir/chetiwa-rrqpe-startup-cleanup.patch" \
  "$script_dir/chetiwa-fetch-stage-memory-release.patch" \
  "$script_dir/chetiwa-rrqpe-chunked-decode.patch" \
  "$script_dir/chetiwa-float32-coordinate-grids.patch" \
  "$script_dir/chetiwa-sparse-coordinate-grids.patch" \
  "$script_dir/chetiwa-chunked-nowcast-remap.patch" \
  "$script_dir/chetiwa-row-clamp-nowcast.patch" \
  "$script_dir/radar-watchdog.sh" \
  "$script_dir/storage-guard.sh" \
  "$script_dir/origin-firewall.sh" \
  "$script_dir/prewarm-public-radar.sh" \
  "$script_dir/chetiwa-radar-watchdog.service" \
  "$script_dir/chetiwa-radar-watchdog.timer" \
  "$script_dir/chetiwa-radar-prewarm.service" \
  "$script_dir/chetiwa-radar-prewarm.timer" \
  "$script_dir/chetiwa-storage-guard.service" \
  "$script_dir/chetiwa-storage-guard.timer" \
  "$script_dir/chetiwa-origin-firewall.service" \
  "$server:$staging_dir/"

ssh "$server" "set -eu
available_kb=\$(awk '/MemTotal:/ { print \$2 }' /proc/meminfo)
if [ \"\${available_kb:-0}\" -lt 3500000 ]; then
  echo 'Refusing the 3 GB LibreWXR profile: the host has less than 3.5 GB RAM.' >&2
  exit 2
fi
# This is a dedicated origin host. Old build layers are disposable and can
# otherwise consume most of its small system disk after repeated deploys.
docker builder prune --all --force --filter until=24h >/dev/null 2>&1 || true
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
native_nowcast_memory_patch_applied=0
distinct_flow_patch_applied=0
small_host_cpu_patch_applied=0
palette_patch_applied=0
crisp_patch_applied=0
crisp_palette_patch_applied=0
visible_light_rain_palette_patch_applied=0
neutral_rain_palette_patch_applied=0
restored_startup_patch_applied=0
nonblocking_frame_reads_patch_applied=0
interactive_tile_executor_patch_applied=0
rrqpe_startup_cleanup_patch_applied=0
fetch_stage_memory_release_patch_applied=0
rrqpe_chunked_decode_patch_applied=0
float32_coordinate_grids_patch_applied=0
sparse_coordinate_grids_patch_applied=0
chunked_nowcast_remap_patch_applied=0
row_clamp_nowcast_patch_applied=0
rollback() {
  echo 'Deployment failed; restoring the previous LibreWXR profile.' >&2
  install -m 0600 \"\$backup_env\" '$remote_dir/.env'
  # Palette 15 depends on the crisp renderer; remove it before prior palettes.
  if [ "\$neutral_rain_palette_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-neutral-rain-palette.patch' || true
  fi
  # Undo coordinate/remap patches in reverse dependency order.
  if [ "\$row_clamp_nowcast_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-row-clamp-nowcast.patch' || true
  fi
  if [ "\$chunked_nowcast_remap_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-chunked-nowcast-remap.patch' || true
  fi
  if [ "\$sparse_coordinate_grids_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-sparse-coordinate-grids.patch' || true
  fi
  if [ "\$float32_coordinate_grids_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-float32-coordinate-grids.patch' || true
  fi
  if [ "\$smooth_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-smooth-120-nowcast.patch' || true
  fi
  if [ "\$native_nowcast_memory_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-native-nowcast-memory.patch' || true
  fi
  if [ "\$distinct_flow_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-distinct-flow-baseline.patch' || true
  fi
  if [ "\$small_host_cpu_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-small-host-cpu-isolation.patch' || true
  fi
  if [ "\$palette_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-opaque-palette-upgrade.patch' || true
  fi
  if [ "\$crisp_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-crisp-presentation.patch' || true
  fi
  if [ "\$visible_light_rain_palette_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-visible-light-rain-palette.patch' || true
  fi
  if [ "\$crisp_palette_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-crisp-palette-upgrade.patch' || true
  fi
  if [ "\$restored_startup_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-restored-startup.patch' || true
  fi
  if [ "\$nonblocking_frame_reads_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-nonblocking-frame-reads.patch' || true
  fi
  if [ "\$interactive_tile_executor_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-interactive-tile-executor.patch' || true
  fi
  if [ "\$rrqpe_startup_cleanup_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-rrqpe-startup-cleanup.patch' || true
  fi
  if [ "\$fetch_stage_memory_release_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-fetch-stage-memory-release.patch' || true
  fi
  if [ "\$rrqpe_chunked_decode_patch_applied" -eq 1 ]; then
    git -C '$remote_dir' apply -R '$staging_dir/chetiwa-rrqpe-chunked-decode.patch' || true
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
if grep -q 'forecast_regions.discard' '$remote_dir/src/librewxr/data/nowcast.py'; then
  echo 'Chetiwa native-region nowcast memory patch already installed.'
else
  git -C '$remote_dir' apply --check '$staging_dir/chetiwa-native-nowcast-memory.patch'
  git -C '$remote_dir' apply '$staging_dir/chetiwa-native-nowcast-memory.patch'
  native_nowcast_memory_patch_applied=1
fi
if grep -q 'region_step_spans' '$remote_dir/src/librewxr/data/nowcast.py'; then
  echo 'Chetiwa content-distinct flow baseline patch already installed.'
else
  git -C '$remote_dir' apply --check '$staging_dir/chetiwa-distinct-flow-baseline.patch'
  git -C '$remote_dir' apply '$staging_dir/chetiwa-distinct-flow-baseline.patch'
  distinct_flow_patch_applied=1
fi
if grep -q 'settings.nowcast_workers' '$remote_dir/src/librewxr/data/nowcast.py'; then
  echo 'Chetiwa small-host CPU isolation patch already installed.'
else
  git -C '$remote_dir' apply --check '$staging_dir/chetiwa-small-host-cpu-isolation.patch'
  git -C '$remote_dir' apply '$staging_dir/chetiwa-small-host-cpu-isolation.patch'
  small_host_cpu_patch_applied=1
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
if grep -q 'visible warm tint for light rain' '$remote_dir/src/librewxr/colors/schemes.py'; then
  echo 'Chetiwa visible light-rain palette already installed.'
else
  git -C '$remote_dir' apply --check '$staging_dir/chetiwa-visible-light-rain-palette.patch'
  git -C '$remote_dir' apply '$staging_dir/chetiwa-visible-light-rain-palette.patch'
  visible_light_rain_palette_patch_applied=1
fi
if git -C '$remote_dir' apply -R --check '$staging_dir/chetiwa-neutral-rain-palette.patch' >/dev/null 2>&1; then
  echo 'Chetiwa immutable neutral palette 15 already installed.'
else
  git -C '$remote_dir' apply --check '$staging_dir/chetiwa-neutral-rain-palette.patch'
  git -C '$remote_dir' apply '$staging_dir/chetiwa-neutral-rain-palette.patch'
  neutral_rain_palette_patch_applied=1
fi
if grep -q 'Serving %d restored radar frame' '$remote_dir/src/librewxr/data/fetcher.py'; then
  echo 'Chetiwa restored-frame fast startup patch already installed.'
else
  git -C '$remote_dir' apply --check '$staging_dir/chetiwa-restored-startup.patch'
  git -C '$remote_dir' apply '$staging_dir/chetiwa-restored-startup.patch'
  restored_startup_patch_applied=1
fi
if grep -q 'Keep serving the immutable previous snapshot' '$remote_dir/src/librewxr/data/store.py'; then
  echo 'Chetiwa non-blocking frame-read patch already installed.'
else
  git -C '$remote_dir' apply --check '$staging_dir/chetiwa-nonblocking-frame-reads.patch'
  git -C '$remote_dir' apply '$staging_dir/chetiwa-nonblocking-frame-reads.patch'
  nonblocking_frame_reads_patch_applied=1
fi
if grep -q 'interactive-tile-geometry' '$remote_dir/src/librewxr/main.py'; then
  echo 'Chetiwa interactive tile executor patch already installed.'
else
  git -C '$remote_dir' apply --check '$staging_dir/chetiwa-interactive-tile-executor.patch'
  git -C '$remote_dir' apply '$staging_dir/chetiwa-interactive-tile-executor.patch'
  interactive_tile_executor_patch_applied=1
fi
if grep -q 'Removed %d stale RRQPE memmap' '$remote_dir/src/librewxr/sources/world/rrqpe/grid.py'; then
  echo 'Chetiwa RRQPE startup cleanup patch already installed.'
else
  git -C '$remote_dir' apply --check '$staging_dir/chetiwa-rrqpe-startup-cleanup.patch'
  git -C '$remote_dir' apply '$staging_dir/chetiwa-rrqpe-startup-cleanup.patch'
  rrqpe_startup_cleanup_patch_applied=1
fi
if grep -q 'dead ingestion workspaces' '$remote_dir/src/librewxr/data/fetcher.py'; then
  echo 'Chetiwa fetch-stage memory release patch already installed.'
else
  git -C '$remote_dir' apply --check '$staging_dir/chetiwa-fetch-stage-memory-release.patch'
  git -C '$remote_dir' apply '$staging_dir/chetiwa-fetch-stage-memory-release.patch'
  fetch_stage_memory_release_patch_applied=1
fi
if grep -q '_DECODE_OUTPUT_CHUNK_ROWS' '$remote_dir/src/librewxr/sources/world/rrqpe/grid.py'; then
  echo 'Chetiwa RRQPE bounded decode patch already installed.'
else
  git -C '$remote_dir' apply --check '$staging_dir/chetiwa-rrqpe-chunked-decode.patch'
  git -C '$remote_dir' apply '$staging_dir/chetiwa-rrqpe-chunked-decode.patch'
  rrqpe_chunked_decode_patch_applied=1
fi
if git -C '$remote_dir' apply -R --check '$staging_dir/chetiwa-float32-coordinate-grids.patch' >/dev/null 2>&1 ||
   git -C '$remote_dir' apply -R --check '$staging_dir/chetiwa-sparse-coordinate-grids.patch' >/dev/null 2>&1 ||
   git -C '$remote_dir' apply -R --check '$staging_dir/chetiwa-chunked-nowcast-remap.patch' >/dev/null 2>&1 ||
   git -C '$remote_dir' apply -R --check '$staging_dir/chetiwa-row-clamp-nowcast.patch' >/dev/null 2>&1; then
  echo 'Chetiwa float32 coordinate grids already installed.'
else
  git -C '$remote_dir' apply --check '$staging_dir/chetiwa-float32-coordinate-grids.patch'
  git -C '$remote_dir' apply '$staging_dir/chetiwa-float32-coordinate-grids.patch'
  float32_coordinate_grids_patch_applied=1
fi
if git -C '$remote_dir' apply -R --check '$staging_dir/chetiwa-sparse-coordinate-grids.patch' >/dev/null 2>&1 ||
   git -C '$remote_dir' apply -R --check '$staging_dir/chetiwa-chunked-nowcast-remap.patch' >/dev/null 2>&1 ||
   git -C '$remote_dir' apply -R --check '$staging_dir/chetiwa-row-clamp-nowcast.patch' >/dev/null 2>&1; then
  echo 'Chetiwa sparse coordinate axes already installed.'
else
  git -C '$remote_dir' apply --check '$staging_dir/chetiwa-sparse-coordinate-grids.patch'
  git -C '$remote_dir' apply '$staging_dir/chetiwa-sparse-coordinate-grids.patch'
  sparse_coordinate_grids_patch_applied=1
fi
if git -C '$remote_dir' apply -R --check '$staging_dir/chetiwa-chunked-nowcast-remap.patch' >/dev/null 2>&1 ||
   git -C '$remote_dir' apply -R --check '$staging_dir/chetiwa-row-clamp-nowcast.patch' >/dev/null 2>&1; then
  echo 'Chetiwa bounded nowcast remap already installed.'
else
  git -C '$remote_dir' apply --check '$staging_dir/chetiwa-chunked-nowcast-remap.patch'
  git -C '$remote_dir' apply '$staging_dir/chetiwa-chunked-nowcast-remap.patch'
  chunked_nowcast_remap_patch_applied=1
fi
if git -C '$remote_dir' apply -R --check '$staging_dir/chetiwa-row-clamp-nowcast.patch' >/dev/null 2>&1; then
  echo 'Chetiwa bounded row-clamp nowcast already installed.'
else
  git -C '$remote_dir' apply --check '$staging_dir/chetiwa-row-clamp-nowcast.patch'
  git -C '$remote_dir' apply '$staging_dir/chetiwa-row-clamp-nowcast.patch'
  row_clamp_nowcast_patch_applied=1
fi
install -m 0600 '$staging_dir/hetzner-small.env' '$remote_dir/.env'
install -m 0755 '$staging_dir/radar-watchdog.sh' /usr/local/sbin/chetiwa-radar-watchdog
install -m 0755 '$staging_dir/storage-guard.sh' /usr/local/sbin/chetiwa-storage-guard
install -m 0755 '$staging_dir/origin-firewall.sh' /usr/local/sbin/chetiwa-origin-firewall
install -m 0755 '$staging_dir/prewarm-public-radar.sh' /usr/local/sbin/chetiwa-radar-prewarm
install -m 0644 '$staging_dir/chetiwa-radar-watchdog.service' /etc/systemd/system/chetiwa-radar-watchdog.service
install -m 0644 '$staging_dir/chetiwa-radar-watchdog.timer' /etc/systemd/system/chetiwa-radar-watchdog.timer
install -m 0644 '$staging_dir/chetiwa-radar-prewarm.service' /etc/systemd/system/chetiwa-radar-prewarm.service
install -m 0644 '$staging_dir/chetiwa-radar-prewarm.timer' /etc/systemd/system/chetiwa-radar-prewarm.timer
install -m 0644 '$staging_dir/chetiwa-storage-guard.service' /etc/systemd/system/chetiwa-storage-guard.service
install -m 0644 '$staging_dir/chetiwa-storage-guard.timer' /etc/systemd/system/chetiwa-storage-guard.timer
install -m 0644 '$staging_dir/chetiwa-origin-firewall.service' /etc/systemd/system/chetiwa-origin-firewall.service
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
cat > /etc/chetiwa-storage-guard.env <<'EOF'
CHETIWA_STORAGE_ROOT_MOUNT=/
CHETIWA_RRQPE_CACHE_DIR=/var/lib/docker/volumes/librewxr_librewxr-cache/_data/rrqpe
CHETIWA_LIBREWXR_CONTAINER=librewxr-librewxr-1
CHETIWA_STORAGE_WARNING_PERCENT=70
CHETIWA_STORAGE_CRITICAL_PERCENT=85
CHETIWA_STORAGE_EMERGENCY_PERCENT=90
CHETIWA_RRQPE_WARNING_BYTES=536870912
CHETIWA_RRQPE_CRITICAL_BYTES=1073741824
CHETIWA_DOCKER_WRITABLE_WARNING_BYTES=1610612736
CHETIWA_DOCKER_WRITABLE_CRITICAL_BYTES=2684354560
EOF
chmod 0600 /etc/chetiwa-storage-guard.env
docker compose --env-file '$remote_dir/.env' \
  --project-directory '$remote_dir' config --quiet
docker compose --env-file '$remote_dir/.env' \
  --project-directory '$remote_dir' up -d --build --force-recreate
systemctl daemon-reload
systemctl enable --now chetiwa-radar-watchdog.timer
systemctl enable --now chetiwa-radar-prewarm.timer
systemctl enable --now chetiwa-storage-guard.timer
systemctl enable --now chetiwa-origin-firewall.service
attempt=1
while [ \"\$attempt\" -le 90 ]; do
  if curl --fail --silent --max-time 12 \
    http://127.0.0.1:8080/public/weather-maps.json >/dev/null; then
    curl --fail --silent --max-time 12 \
      https://radar.ezplatforms.com/public/weather-maps.json >/dev/null
    docker compose --env-file '$remote_dir/.env' \
      --project-directory '$remote_dir' ps
    curl --fail --silent --max-time 12 http://127.0.0.1:8080/health
    if docker builder prune --all --force >/dev/null 2>&1; then
      echo 'Docker build cache removed after successful deployment.'
    else
      echo 'Warning: Docker build cache cleanup failed.' >&2
    fi
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
