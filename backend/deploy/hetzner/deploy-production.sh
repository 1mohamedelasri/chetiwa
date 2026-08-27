#!/usr/bin/env bash
# Atomically deploys the Chetiwa API beside LibreWXR on the launch Hetzner VM.
# Production secrets are copied from the existing host file and never leave it.
set -euo pipefail

server="${1:-root@116.203.124.254}"
remote_root="${CHETIWA_API_REMOTE_ROOT:-/opt/chetiwa/api}"
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
backend_dir="$(CDPATH= cd -- "$script_dir/../.." && pwd)"
release_id="$(date -u +%Y%m%dT%H%M%SZ)"
staging="/tmp/chetiwa-api-release-$release_id"
backup="$remote_root/backend.backup-$release_id"

ssh "$server" "set -eu; docker network inspect librewxr_default >/dev/null; mkdir -p '$staging/backend'"
rsync -az --delete \
  --exclude '.dart_tool/' \
  --exclude 'build/' \
  --exclude 'deploy/hetzner/production.env' \
  "$backend_dir/" "$server:$staging/backend/"

ssh "$server" "set -eu
target='$remote_root/backend'
staging='$staging/backend'
backup='$backup'
production_env=\"\$target/deploy/hetzner/production.env\"
test -f \"\$production_env\"
install -m 0600 \"\$production_env\" \"\$staging/deploy/hetzner/production.env\"

set_env() {
  key=\"\$1\"
  value=\"\$2\"
  file=\"\$staging/deploy/hetzner/production.env\"
  temporary=\"\$file.tmp\"
  awk -v key=\"\$key\" -v value=\"\$value\" '
    BEGIN { replaced = 0 }
    index(\$0, key \"=\") == 1 { print key \"=\" value; replaced = 1; next }
    { print }
    END { if (!replaced) print key \"=\" value }
  ' \"\$file\" >\"\$temporary\"
  install -m 0600 \"\$temporary\" \"\$file\"
  rm -f \"\$temporary\"
}

set_env LIBREWXR_DOCKER_NETWORK librewxr_default
set_env RADAR_METADATA_URL http://librewxr:8080/public/weather-maps.json
set_env RADAR_TILE_URL_TEMPLATE 'http://librewxr:8080{frame}/256/{z}/{x}/{y}/14/1_0.png?presentation=crisp-v2'

cd \"\$staging/deploy/hetzner\"
docker compose config --quiet
docker compose build api

mv \"\$target\" \"\$backup\"
mv \"\$staging\" \"\$target\"
rollback() {
  echo 'API deployment failed; restoring the previous release.' >&2
  rm -rf \"\$target.failed-$release_id\"
  mv \"\$target\" \"\$target.failed-$release_id\" || true
  mv \"\$backup\" \"\$target\" || true
  cd \"\$target/deploy/hetzner\"
  docker compose up -d --force-recreate || true
}
trap rollback EXIT HUP INT TERM

cd \"\$target/deploy/hetzner\"
docker compose up -d --force-recreate
for attempt in \$(seq 1 30); do
  if curl --fail --silent --max-time 5 http://127.0.0.1:8081/healthz >/dev/null; then
    curl --fail --silent --max-time 8 https://chetiwa-api.ezplatforms.com/healthz >/dev/null
    docker compose ps
    trap - EXIT HUP INT TERM
    rm -rf '$staging'
    echo \"Previous API release retained at \$backup\"
    exit 0
  fi
  sleep 2
done
docker compose logs --tail=120 api >&2
exit 1"
