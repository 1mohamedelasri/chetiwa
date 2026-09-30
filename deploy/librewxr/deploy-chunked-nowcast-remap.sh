#!/usr/bin/env bash
# Reuse the tested exact-image rollback controller with bounded remap rows.
set -euo pipefail
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec bash "$script_dir/deploy-float32-coordinate-grids.sh" "${1:-root@116.203.124.254}" chunked
