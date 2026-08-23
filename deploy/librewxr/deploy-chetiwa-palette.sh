#!/usr/bin/env sh
set -eu

server=${1:-root@116.203.124.254}
remote_dir=${CHETIWA_LIBREWXR_DIR:-/opt/chetiwa/librewxr}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
remote_patch=/tmp/chetiwa-drops-palette.patch

scp "$script_dir/chetiwa-drops-palette.patch" "$server:$remote_patch"
ssh "$server" "set -eu
cd '$remote_dir'
if grep -q 'Chetiwa Grey Red' src/librewxr/colors/schemes.py; then
  echo 'Chetiwa palette already installed.'
else
  git apply --check '$remote_patch'
  git apply '$remote_patch'
fi
docker compose up --build -d
for attempt in 1 2 3 4 5 6; do
  if curl --fail --silent http://127.0.0.1:8080/public/weather-maps.json | grep -q 'Chetiwa Grey Red'; then
    echo 'Chetiwa palette deployed and healthy.'
    exit 0
  fi
  sleep 5
done
echo 'LibreWXR restarted but palette metadata is not healthy.' >&2
docker compose logs --tail=80 librewxr >&2
exit 1"
