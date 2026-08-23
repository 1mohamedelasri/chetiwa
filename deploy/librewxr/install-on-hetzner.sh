#!/usr/bin/env sh
# Bootstrap only. Run this manually on a fresh, dedicated Hetzner VM after
# Docker and cloudflared are installed. It does not open a firewall port.
set -eu

target_dir=${CHETIWA_LIBREWXR_DIR:-/opt/chetiwa/librewxr}
source_ref=ceb22b4406bd58553531a795226e22ec5f4f350f
source_repo=https://github.com/JoshuaKimsey/LibreWXR.git
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ -e "$target_dir" ]; then
  echo "Refusing to overwrite existing directory: $target_dir" >&2
  exit 1
fi

mkdir -p "$(dirname -- "$target_dir")"
git clone --depth 1 "$source_repo" "$target_dir"
git -C "$target_dir" checkout --detach "$source_ref"
git -C "$target_dir" apply "$script_dir/chetiwa-drops-palette.patch"
cp "$script_dir/hetzner-small.env" "$target_dir/.env"
mkdir -p "$target_dir/logs"

printf '%s\n' "LibreWXR source installed in $target_dir."
printf '%s\n' "Before starting it, configure Cloudflare Tunnel to target http://127.0.0.1:8080 and set the real LIBREWXR_PUBLIC_URL in $target_dir/.env."
printf '%s\n' "Then run: cd $target_dir && docker compose up --build -d"
