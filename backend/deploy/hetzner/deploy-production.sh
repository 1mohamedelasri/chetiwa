#!/usr/bin/env bash
# Deploys the Chetiwa API beside LibreWXR, retaining the exact previous image.
# Production secrets are copied from the existing host file and never leave it.
set -euo pipefail

server="${1:-root@116.203.124.254}"
remote_root="${CHETIWA_API_REMOTE_ROOT:-/opt/chetiwa/api}"
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
backend_dir="$(CDPATH= cd -- "$script_dir/../.." && pwd)"
release_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
staging="/tmp/chetiwa-api-release-$release_id"

# Quote arguments for the remote login shell; the deployment itself is passed
# through stdin so neither local expansion nor SSH interpolation touches secrets.
printf -v prepare_command 'bash -s -- %q' "$staging"
ssh "$server" "$prepare_command" <<'REMOTE_PREPARE'
set -euo pipefail
umask 077
staging="$1"
docker network inspect librewxr_default >/dev/null
credential=/opt/chetiwa/secrets/chetiwa-api-firestore.json
test -r "$credential"
test "$(stat -c %a "$credential")" = 600
test "$(stat -c %u "$credential")" = 65532
test "$(stat -c %g "$credential")" = 65532
mkdir -m 0700 "$staging"
mkdir "$staging/backend"
REMOTE_PREPARE

rsync -az --delete \
  --exclude '.dart_tool/' \
  --exclude 'build/' \
  --exclude 'deploy/hetzner/production.env' \
  "$backend_dir/" "$server:$staging/backend/"

printf -v deploy_command 'bash -s -- %q %q %q' "$remote_root" "$staging" "$release_id"
ssh "$server" "$deploy_command" <<'REMOTE_DEPLOY'
set -euo pipefail
umask 077
remote_root="$1"
release_root="$2"
release_id="$3"
target="$remote_root/backend"
staging="$release_root/backend"
backup="$remote_root/backend.backup-$release_id"
failed="$remote_root/backend.failed-$release_id"
rollback_image="chetiwa-api:rollback-$release_id"
lock="$remote_root/.deploy-lock"
image_may_have_changed=false
source_may_have_changed=false
container_may_have_changed=false
succeeded=false

# One deployment may build/re-tag/swap this compose project at a time.
if ! mkdir "$lock"; then
  echo "Another API deployment holds $lock; staged release retained at $release_root" >&2
  exit 1
fi

rollback() {
  echo 'API deployment failed; restoring the previous release and exact image.' >&2
  local rollback_failed=false
  # Check the filesystem, not a flag set after mv: a signal can arrive between
  # a successful move and the next shell assignment.
  if "$source_may_have_changed" && test -d "$backup"; then
    if test -e "$target"; then
      mv "$target" "$failed" || rollback_failed=true
    fi
    if ! test -e "$target"; then
      mv "$backup" "$target" || rollback_failed=true
    else
      rollback_failed=true
    fi
  fi
  if "$image_may_have_changed"; then
    docker image tag "$rollback_image" chetiwa-api:local || rollback_failed=true
  fi
  if "$container_may_have_changed" && ! "$rollback_failed"; then
    # Never rebuild old source or pull a moving tag during recovery.
    (cd "$target/deploy/hetzner" &&
      docker compose up -d --no-build --pull never --force-recreate api) || rollback_failed=true
  fi
  if "$rollback_failed"; then
    echo "Automatic rollback needs attention. Preserve $backup, $failed and $rollback_image." >&2
  else
    echo "Previous API image restored; failed source retained at $failed (or $release_root before source swap)." >&2
  fi
}

finish() {
  local status=$?
  # A signal produces one nonzero EXIT; rollback must never run twice.
  trap - EXIT HUP INT TERM
  if ! "$succeeded"; then
    rollback
    if test "$status" -eq 0; then status=1; fi
  fi
  rmdir "$lock" || true
  exit "$status"
}
trap finish EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

test -d "$target/deploy/hetzner"
test ! -e "$backup"
test ! -e "$failed"
production_env="$target/deploy/hetzner/production.env"
test -f "$production_env"
install -m 0600 "$production_env" "$staging/deploy/hetzner/production.env"

set_env() {
  local key="$1" value="$2"
  local file="$staging/deploy/hetzner/production.env"
  local temporary="$file.tmp"
  awk -v key="$key" -v value="$value" '
    BEGIN { replaced = 0 }
    index($0, key "=") == 1 { print key "=" value; replaced = 1; next }
    { print }
    END { if (!replaced) print key "=" value }
  ' "$file" >"$temporary"
  install -m 0600 "$temporary" "$file"
  rm -f "$temporary"
}

set_env LIBREWXR_DOCKER_NETWORK librewxr_default
set_env RADAR_METADATA_URL http://librewxr:8080/public/weather-maps.json
set_env RADAR_TILE_URL_TEMPLATE 'http://librewxr:8080{frame}/256/{z}/{x}/{y}/15/1_0.png?presentation=neutral-v1'
# This compose file publishes only on loopback; cloudflared supplies the
# authenticated ingress path. Do not copy this trust setting to a public port.
set_env TRUST_CLOUDFLARE_PROXY true

cd "$target/deploy/hetzner"
previous_container="$(docker compose ps -q api)"
test -n "$previous_container"
previous_image="$(docker inspect --format '{{.Image}}' "$previous_container")"
test -n "$previous_image"
# Capture the running container's immutable image ID, which can differ from
# chetiwa-api:local after an earlier failed build.
docker image tag "$previous_image" "$rollback_image"

cd "$staging/deploy/hetzner"
docker compose config --quiet
image_may_have_changed=true
docker compose build api

source_may_have_changed=true
mv "$target" "$backup"
mv "$staging" "$target"
cd "$target/deploy/hetzner"
container_may_have_changed=true
docker compose up -d --no-build --pull never --force-recreate api
for attempt in $(seq 1 30); do
  if curl --fail --silent --max-time 5 http://127.0.0.1:8081/healthz >/dev/null &&
      curl --fail --silent --max-time 8 https://chetiwa-api.ezplatforms.com/healthz >/dev/null; then
    docker compose ps
    succeeded=true
    rmdir "$release_root" || true
    echo "Previous API source retained at $backup"
    echo "Previous API image retained as $rollback_image ($previous_image)"
    exit 0
  fi
  sleep 2
done
docker compose logs --tail=120 api >&2
exit 1
REMOTE_DEPLOY
