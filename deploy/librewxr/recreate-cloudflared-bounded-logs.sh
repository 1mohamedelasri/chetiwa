#!/usr/bin/env sh
# Recreate the named Cloudflare Tunnel container with bounded json-file logs.
# The existing token stays on the remote host and is never printed.
set -eu

server=${1:-root@116.203.124.254}

ssh "$server" 'set -eu
container=cloudflared
backup=cloudflared-unbounded-backup

test "$(docker inspect --format "{{.State.Running}}" "$container")" = true
image=$(docker inspect --format "{{.Config.Image}}" "$container")
network_mode=$(docker inspect --format "{{.HostConfig.NetworkMode}}" "$container")
token=$(docker inspect --format "{{index .Config.Cmd 4}}" "$container")
test -n "$token"

rollback() {
  echo "Cloudflare replacement failed; restoring the previous container." >&2
  docker rm -f "$container" >/dev/null 2>&1 || true
  docker rename "$backup" "$container" >/dev/null 2>&1 || true
  docker start "$container" >/dev/null 2>&1 || true
}
trap rollback EXIT HUP INT TERM

docker rm -f "$backup" >/dev/null 2>&1 || true
docker rename "$container" "$backup"
docker stop "$backup" >/dev/null
docker run -d \
  --name "$container" \
  --restart unless-stopped \
  --network "$network_mode" \
  --log-driver json-file \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  "$image" \
  tunnel --no-autoupdate run --token "$token" >/dev/null

attempt=1
while [ "$attempt" -le 12 ]; do
  if curl --fail --silent --max-time 12 \
       https://radar.ezplatforms.com/public/weather-maps.json >/dev/null && \
     curl --fail --silent --max-time 12 \
       https://chetiwa-api.ezplatforms.com/healthz >/dev/null; then
    docker inspect --format \
      "cloudflared running={{.State.Running}} log={{.HostConfig.LogConfig.Type}} options={{json .HostConfig.LogConfig.Config}}" \
      "$container"
    docker rm "$backup" >/dev/null
    docker container prune --force --filter until=24h >/dev/null
    trap - EXIT HUP INT TERM
    exit 0
  fi
  sleep 5
  attempt=$((attempt + 1))
done
exit 1'
