#!/usr/bin/env bash
# Add immutable palette ID 15 without changing data, dependencies or config.
# Shares the coordinate controller's lock to prevent simultaneous image swaps.
set -euo pipefail

server=${1:-root@116.203.124.254}
remote_dir=${CHETIWA_LIBREWXR_DIR:-/opt/chetiwa/librewxr}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
release_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
staging_dir="/tmp/chetiwa-neutral-palette-$release_id"
printf -v prepare 'mkdir -m 0700 -- %q' "$staging_dir"
ssh "$server" "$prepare"
scp "$script_dir/chetiwa-neutral-rain-palette.patch" "$server:$staging_dir/patch.diff"
printf -v command 'bash -s -- %q %q %q %q' "$remote_dir" "$staging_dir" "$release_id" "${CHETIWA_RADAR_HEALTH_ATTEMPTS:-90}"
ssh "$server" "$command" <<'REMOTE_PALETTE_DEPLOY'
set -euo pipefail
remote_dir=$1
staging_dir=$2
release_id=$3
health_attempts=$4
[[ "$release_id" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9]+$ ]]
[[ "$health_attempts" =~ ^[1-9][0-9]*$ ]]
relative_files=(colors/schemes.py tiles/renderer.py)
patch_file="$staging_dir/patch.diff"
lock_dir="$remote_dir/.chetiwa-coordinate-deploy.lock"
backup_dir="$(dirname -- "$remote_dir")/librewxr-palette-backups/$release_id"
backup_tag="chetiwa-librewxr-palette-rollback:$release_id"
candidate_tag="chetiwa-librewxr-palette:$release_id"
compose=(docker compose --env-file "$remote_dir/.env" --project-directory "$remote_dir" --profile single)
for relative_file in "${relative_files[@]}"; do test -f "$remote_dir/src/librewxr/$relative_file"; done
test -f "$remote_dir/docker-compose.yml"
test -f "$patch_file"
mkdir -- "$lock_dir" || { echo 'Another coordinate/palette deployment holds the lock.' >&2; exit 1; }

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
  local failed=0 relative_file
  echo 'Deployment failed; restoring the exact previous sources and image.' >&2
  if [[ "$source_changed" == 1 ]]; then
    for relative_file in "${relative_files[@]}"; do
      cp -p -- "$backup_dir/$relative_file" "$remote_dir/src/librewxr/$relative_file" || failed=1
    done
  fi
  if [[ "$backup_ready" == 1 && "$image_retagged" == 1 ]]; then
    docker image tag "$running_image" "$image_ref" || failed=1
  fi
  if [[ "$restart_attempted" == 1 ]]; then
    "${compose[@]}" up -d --no-build --pull never --no-deps --force-recreate librewxr || failed=1
    local restored_id restored_image restored_ready=0 attempt
    restored_id=$("${compose[@]}" ps -q librewxr) || failed=1
    restored_image=$(docker inspect --format '{{.Image}}' "$restored_id") || failed=1
    [[ "$restored_image" == "$running_image" ]] || failed=1
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
[[ "$running_image" =~ ^sha256:[a-f0-9]{64}$ ]]
configured_image=$("${compose[@]}" config --images)
[[ "$configured_image" == "$image_ref" ]] || { echo 'Refusing an unexpected Compose image/service topology.' >&2; exit 1; }
installed_root=$(docker exec "$container_id" python -c 'import importlib.util, pathlib; print(pathlib.Path(importlib.util.find_spec("librewxr").origin).parent)')
[[ "$installed_root" =~ ^/usr/local/lib/python3\.[0-9]+/site-packages/librewxr$ ]]
for relative_file in "${relative_files[@]}"; do
  source_sha=$(sha256sum "$remote_dir/src/librewxr/$relative_file" | cut -d ' ' -f 1)
  installed_sha=$(docker exec "$container_id" sha256sum "$installed_root/$relative_file" | cut -d ' ' -f 1)
  image_source_sha=$(docker exec "$container_id" sha256sum "/app/src/librewxr/$relative_file" | cut -d ' ' -f 1)
  [[ "$source_sha" == "$installed_sha" && "$source_sha" == "$image_source_sha" ]] || {
    echo "Source and running image differ for $relative_file; refusing unrelated changes." >&2; exit 1;
  }
done
if git -C "$remote_dir" apply -R --check "$patch_file" >/dev/null 2>&1; then
  echo 'Neutral palette 15 already exists in source and running image; no build or restart needed.'
  success=1
  exit 0
fi
git -C "$remote_dir" apply --check "$patch_file"
health
legacy_luts_sha=$(docker exec "$container_id" python -c '
import hashlib
from librewxr.colors.schemes import get_lut
h = hashlib.sha256()
for scheme in (*range(15), 255):
    for snow in (False, True):
        h.update(get_lut(scheme, snow=snow).tobytes())
print(h.hexdigest())
')
[[ "$legacy_luts_sha" =~ ^[a-f0-9]{64}$ ]]
mkdir -p -m 0700 -- "$backup_dir"
mkdir -m 0700 -- "$backup_dir/colors" "$backup_dir/tiles"
for relative_file in "${relative_files[@]}"; do
  cp -p -- "$remote_dir/src/librewxr/$relative_file" "$backup_dir/$relative_file"
done
printf '%s\n' "$running_image" > "$backup_dir/original-image-id"
printf '%s\n' "$image_ref" > "$backup_dir/original-image-ref"
docker image tag "$running_image" "$backup_tag"
[[ "$(docker image inspect --format '{{.Id}}' "$backup_tag")" == "$running_image" ]]
backup_ready=1
source_changed=1
git -C "$remote_dir" apply "$patch_file"
git -C "$remote_dir" apply -R --check "$patch_file"
python3 - "$remote_dir/src/librewxr/colors/schemes.py" "$remote_dir/src/librewxr/tiles/renderer.py" <<'PY'
import pathlib, sys
for name in sys.argv[1:]:
    compile(pathlib.Path(name).read_bytes(), name, 'exec')
PY
mkdir -p -- "$staging_dir/colors" "$staging_dir/tiles"
for relative_file in "${relative_files[@]}"; do
  cp -p -- "$remote_dir/src/librewxr/$relative_file" "$staging_dir/$relative_file"
done
cat > "$staging_dir/Dockerfile" <<DOCKERFILE
FROM $backup_tag
COPY colors/schemes.py /app/src/librewxr/colors/schemes.py
COPY colors/schemes.py $installed_root/colors/schemes.py
COPY tiles/renderer.py /app/src/librewxr/tiles/renderer.py
COPY tiles/renderer.py $installed_root/tiles/renderer.py
DOCKERFILE
# The unique local tag is pinned to the captured immutable running image ID.
[[ "$(docker image inspect --format '{{.Id}}' "$backup_tag")" == "$running_image" ]]
docker build --pull=false --network=none --tag "$candidate_tag" "$staging_dir"
candidate_image=$(docker image inspect --format '{{.Id}}' "$candidate_tag")
schemes_sha=$(sha256sum "$remote_dir/src/librewxr/colors/schemes.py" | cut -d ' ' -f 1)
renderer_sha=$(sha256sum "$remote_dir/src/librewxr/tiles/renderer.py" | cut -d ' ' -f 1)
docker run --rm --network none --entrypoint python "$candidate_image" -c '
import hashlib, pathlib, sys
import numpy as np
from librewxr.colors.schemes import get_lut
for relative, expected in zip(("colors/schemes.py", "tiles/renderer.py"), sys.argv[2:]):
    for root in (sys.argv[1], "/app/src/librewxr"):
        name = str(pathlib.Path(root) / relative)
        content = pathlib.Path(name).read_bytes()
        compile(content, name, "exec")
        assert hashlib.sha256(content).hexdigest() == expected
# Pixel intervals are independent of the implementation loop in the patch.
expected = np.repeat(np.array([(0,0,0,0), (216,220,222,90), (185,190,193,125),
    (135,142,146,160), (83,91,95,190), (225,155,152,195), (214,91,85,215),
    (188,38,32,230), (132,0,0,240)], dtype=np.uint8),
    [73,12,12,12,12,12,12,20,91], axis=0)
for snow in (False, True):
    assert np.array_equal(get_lut(15, snow=snow), expected)
h = hashlib.sha256()
for scheme in (*range(15), 255):
    for snow in (False, True):
        h.update(get_lut(scheme, snow=snow).tobytes())
assert h.hexdigest() == sys.argv[4], "Existing palettes changed"
' "$installed_root" "$schemes_sha" "$renderer_sha" "$legacy_luts_sha"
image_retagged=1
docker image tag "$candidate_image" "$image_ref"
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
for relative_file in "${relative_files[@]}"; do
  patched_sha=$(sha256sum "$remote_dir/src/librewxr/$relative_file" | cut -d ' ' -f 1)
  [[ "$(docker exec "$container_id" sha256sum "$installed_root/$relative_file" | cut -d ' ' -f 1)" == "$patched_sha" ]]
  [[ "$(docker exec "$container_id" sha256sum "/app/src/librewxr/$relative_file" | cut -d ' ' -f 1)" == "$patched_sha" ]]
done
success=1
echo "Neutral palette 15 healthy. Previous image: $backup_tag; source backup: $backup_dir"
REMOTE_PALETTE_DEPLOY
