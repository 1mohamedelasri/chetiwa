#!/usr/bin/env bash
# Shared controller for the coordinate/remap patches; keep dependencies,
# Compose overrides, environment settings, volumes and other services intact.
set -euo pipefail

server=${1:-root@116.203.124.254}
patch_variant=${2:-float32}
case "$patch_variant" in
  float32) patch_name=chetiwa-float32-coordinate-grids.patch ;;
  sparse) patch_name=chetiwa-sparse-coordinate-grids.patch ;;
  chunked) patch_name=chetiwa-chunked-nowcast-remap.patch ;;
  row-clamp) patch_name=chetiwa-row-clamp-nowcast.patch ;;
  *) echo 'Patch must be float32, sparse, chunked or row-clamp.' >&2; exit 2 ;;
esac
remote_dir=${CHETIWA_LIBREWXR_DIR:-/opt/chetiwa/librewxr}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
release_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
staging_dir="/tmp/chetiwa-coordinate-grids-$release_id"
printf -v prepare 'mkdir -m 0700 -- %q' "$staging_dir"
ssh "$server" "$prepare"
scp "$script_dir/$patch_name" "$server:$staging_dir/patch.diff"
# Let the original command recognize an already installed successor as well.
scp "$script_dir/chetiwa-sparse-coordinate-grids.patch" "$server:$staging_dir/sparse.diff"
scp "$script_dir/chetiwa-chunked-nowcast-remap.patch" "$server:$staging_dir/chunked.diff"
scp "$script_dir/chetiwa-row-clamp-nowcast.patch" "$server:$staging_dir/row-clamp.diff"
printf -v command 'bash -s -- %q %q %q %q %q' "$remote_dir" "$staging_dir" "$release_id" "${CHETIWA_RADAR_HEALTH_ATTEMPTS:-90}" "$patch_variant"
ssh "$server" "$command" <<'REMOTE_COORDINATE_DEPLOY'
set -euo pipefail
remote_dir=$1
staging_dir=$2
release_id=$3
health_attempts=$4
patch_variant=$5
[[ "$release_id" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9]+$ ]]
[[ "$health_attempts" =~ ^[1-9][0-9]*$ ]]
[[ "$patch_variant" == float32 || "$patch_variant" == sparse || "$patch_variant" == chunked || "$patch_variant" == row-clamp ]]
source_file="$remote_dir/src/librewxr/data/nowcast.py"
patch_file="$staging_dir/patch.diff"
lock_dir="$remote_dir/.chetiwa-coordinate-deploy.lock"
backup_dir="$(dirname -- "$remote_dir")/librewxr-coordinate-backups/$release_id"
backup_tag="chetiwa-librewxr-coordinate-rollback:$release_id"
candidate_tag="chetiwa-librewxr-coordinate:$release_id"
compose=(docker compose --env-file "$remote_dir/.env" --project-directory "$remote_dir" --profile single)
test -f "$source_file"
test -f "$remote_dir/docker-compose.yml"
test -f "$patch_file"
mkdir -- "$lock_dir" || { echo 'Another coordinate deployment holds the lock.' >&2; exit 1; }

success=0
source_changed=0
image_retagged=0
restart_attempted=0
backup_ready=0
image_ref=''
health() {
  curl --fail --silent --show-error --max-time 10 \
    http://127.0.0.1:8080/public/weather-maps.json |
    python3 -c 'import json, sys; d=json.load(sys.stdin); assert isinstance(d.get("radar", {}).get("past"), list) and d["radar"]["past"], "No radar frames available"'
}
rollback() {
  local failed=0
  echo 'Deployment failed; restoring the exact previous source and image.' >&2
  if [[ "$source_changed" == 1 ]]; then
    cp -p -- "$backup_dir/nowcast.py" "$source_file" || failed=1
  fi
  if [[ "$backup_ready" == 1 && "$image_retagged" == 1 ]]; then
    docker image tag "$backup_tag" "$image_ref" || failed=1
  fi
  if [[ "$restart_attempted" == 1 ]]; then
    "${compose[@]}" up -d --no-build --pull never --no-deps --force-recreate librewxr || failed=1
    local restored_id restored_image
    restored_id=$("${compose[@]}" ps -q librewxr) || failed=1
    restored_image=$(docker inspect --format '{{.Image}}' "$restored_id") || failed=1
    [[ "$restored_image" == "$running_image" ]] || failed=1
    local restored_ready=0 attempt
    for ((attempt=1; attempt<=health_attempts; attempt++)); do
      if health >/dev/null 2>&1; then restored_ready=1; break; fi
      sleep 5
    done
    [[ "$restored_ready" == 1 ]] || failed=1
  fi
  if [[ "$failed" != 0 ]]; then
    echo "ROLLBACK NEEDS ATTENTION. Source backup: $backup_dir; image: $backup_tag" >&2
  fi
  return "$failed"
}
finish() {
  local status=$?
  trap - EXIT HUP INT TERM
  if [[ "$success" != 1 && ( "$source_changed" == 1 || "$image_retagged" == 1 || "$restart_attempted" == 1 ) ]]; then
    rollback || status=1
  fi
  rmdir -- "$lock_dir" || status=1
  exit "$status"
}
trap finish EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

"${compose[@]}" config --quiet
container_id=$("${compose[@]}" ps -q librewxr)
[[ -n "$container_id" && "$container_id" != *$'\n'* ]]
[[ "$(docker inspect --format '{{.State.Running}}' "$container_id")" == true ]]
image_ref=$(docker inspect --format '{{.Config.Image}}' "$container_id")
running_image=$(docker inspect --format '{{.Image}}' "$container_id")
configured_image=$("${compose[@]}" config --images)
[[ "$configured_image" == "$image_ref" ]] || { echo 'Refusing an unexpected Compose image/service topology.' >&2; exit 1; }
# The installed wheel is separate from the source retained under /app/src.
installed_path=$(docker exec "$container_id" python -c 'import importlib.util, pathlib; print(pathlib.Path(importlib.util.find_spec("librewxr").origin).parent / "data/nowcast.py")')
[[ "$installed_path" =~ ^/usr/local/lib/python3\.[0-9]+/site-packages/librewxr/data/nowcast\.py$ ]]
source_sha=$(sha256sum "$source_file" | cut -d ' ' -f 1)
installed_sha=$(docker exec "$container_id" sha256sum "$installed_path" | cut -d ' ' -f 1)
image_source_sha=$(docker exec "$container_id" sha256sum /app/src/librewxr/data/nowcast.py | cut -d ' ' -f 1)
[[ "$source_sha" == "$installed_sha" && "$source_sha" == "$image_source_sha" ]] || {
  echo 'Source and running image differ; refusing to include unrelated changes.' >&2; exit 1;
}
if git -C "$remote_dir" apply -R --check "$patch_file" >/dev/null 2>&1 ||
   { [[ "$patch_variant" == float32 ]] && git -C "$remote_dir" apply -R --check "$staging_dir/sparse.diff" >/dev/null 2>&1; } ||
   { [[ "$patch_variant" == float32 || "$patch_variant" == sparse ]] && git -C "$remote_dir" apply -R --check "$staging_dir/chunked.diff" >/dev/null 2>&1; } ||
   { [[ "$patch_variant" != row-clamp ]] && git -C "$remote_dir" apply -R --check "$staging_dir/row-clamp.diff" >/dev/null 2>&1; }; then
  echo 'Coordinate patch already exists in source and running image; no build or restart needed.'
  success=1
  exit 0
fi
git -C "$remote_dir" apply --check "$patch_file"
health
mkdir -p -m 0700 -- "$backup_dir"
cp -p -- "$source_file" "$backup_dir/nowcast.py"
printf '%s\n' "$running_image" > "$backup_dir/original-image-id"
printf '%s\n' "$image_ref" > "$backup_dir/original-image-ref"
# Save the image actually used by the container, not a tag a previous build may
# already have changed. This must happen before any patch or image build.
docker image tag "$running_image" "$backup_tag"
[[ "$(docker image inspect --format '{{.Id}}' "$backup_tag")" == "$running_image" ]]
backup_ready=1
source_changed=1
git -C "$remote_dir" apply "$patch_file"
git -C "$remote_dir" apply -R --check "$patch_file"
python3 - "$source_file" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
compile(path.read_bytes(), str(path), 'exec')
PY
cp -p -- "$source_file" "$staging_dir/nowcast.py"
cat > "$staging_dir/Dockerfile" <<DOCKERFILE
FROM $backup_tag
COPY nowcast.py /app/src/librewxr/data/nowcast.py
COPY nowcast.py $installed_path
DOCKERFILE
# No upstream base fetch or pip install: the build adds two files to a local,
# immutable backup of the running image. It does not change runtime config.
docker build --pull=false --network=none --tag "$candidate_tag" "$staging_dir"
candidate_image=$(docker image inspect --format '{{.Id}}' "$candidate_tag")
patched_sha=$(sha256sum "$source_file" | cut -d ' ' -f 1)
docker run --rm --network none --entrypoint python "$candidate_tag" -c '
import hashlib, pathlib, sys
for name in (sys.argv[1], "/app/src/librewxr/data/nowcast.py"):
    content = pathlib.Path(name).read_bytes()
    compile(content, name, "exec")
    assert hashlib.sha256(content).hexdigest() == sys.argv[2]
' "$installed_path" "$patched_sha"
image_retagged=1
docker image tag "$candidate_tag" "$image_ref"
restart_attempted=1
"${compose[@]}" up -d --no-build --pull never --no-deps --force-recreate librewxr
ready=0
for ((attempt=1; attempt<=health_attempts; attempt++)); do
  if health >/dev/null 2>&1; then ready=1; break; fi
  sleep 5
done
[[ "$ready" == 1 ]] || { echo 'Radar did not recover healthy frames in time.' >&2; exit 1; }
container_id=$("${compose[@]}" ps -q librewxr)
[[ "$(docker inspect --format '{{.Image}}' "$container_id")" == "$candidate_image" ]]
[[ "$(docker exec "$container_id" sha256sum "$installed_path" | cut -d ' ' -f 1)" == "$patched_sha" ]]
success=1
echo "Coordinate patch ($patch_variant) healthy. Previous image: $backup_tag; source backup: $backup_dir/nowcast.py"
REMOTE_COORDINATE_DEPLOY
