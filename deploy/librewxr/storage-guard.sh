#!/usr/bin/env sh
# Reports filesystem, inode, RRQPE and Docker writable-layer pressure.
# It never deletes active data. Intended for chetiwa-storage-guard.timer.
set -eu

root_mount=${CHETIWA_STORAGE_ROOT_MOUNT:-/}
rrqpe_dir=${CHETIWA_RRQPE_CACHE_DIR:-/var/lib/docker/volumes/librewxr_librewxr-cache/_data/rrqpe}
container=${CHETIWA_LIBREWXR_CONTAINER:-librewxr-librewxr-1}
state_dir=${CHETIWA_STORAGE_GUARD_STATE_DIR:-/var/lib/chetiwa-storage-guard}
warning_percent=${CHETIWA_STORAGE_WARNING_PERCENT:-70}
critical_percent=${CHETIWA_STORAGE_CRITICAL_PERCENT:-85}
emergency_percent=${CHETIWA_STORAGE_EMERGENCY_PERCENT:-90}
rrqpe_warning_bytes=${CHETIWA_RRQPE_WARNING_BYTES:-536870912}
rrqpe_critical_bytes=${CHETIWA_RRQPE_CRITICAL_BYTES:-1073741824}
docker_warning_bytes=${CHETIWA_DOCKER_WRITABLE_WARNING_BYTES:-1610612736}
docker_critical_bytes=${CHETIWA_DOCKER_WRITABLE_CRITICAL_BYTES:-2684354560}

number_or_die() {
  case $2 in
    ''|*[!0-9]*) echo "$1 must be a non-negative integer." >&2; exit 2 ;;
  esac
}

for pair in \
  "warning_percent:$warning_percent" \
  "critical_percent:$critical_percent" \
  "emergency_percent:$emergency_percent" \
  "rrqpe_warning_bytes:$rrqpe_warning_bytes" \
  "rrqpe_critical_bytes:$rrqpe_critical_bytes" \
  "docker_warning_bytes:$docker_warning_bytes" \
  "docker_critical_bytes:$docker_critical_bytes"; do
  number_or_die "${pair%%:*}" "${pair#*:}"
done

mkdir -p "$state_dir"

disk_percent=$(df -P "$root_mount" | awk 'NR == 2 { gsub("%", "", $5); print $5 }')
inode_percent=$(df -Pi "$root_mount" | awk 'NR == 2 { gsub("%", "", $5); print $5 }')
rrqpe_bytes=0
if [ -d "$rrqpe_dir" ]; then
  rrqpe_bytes=$(du -sb "$rrqpe_dir" 2>/dev/null | awk '{ print $1 }')
fi
docker_writable_bytes=0
if docker inspect "$container" >/dev/null 2>&1; then
  docker_writable_bytes=$(docker inspect --size --format '{{.SizeRw}}' "$container" 2>/dev/null || printf '0')
fi

for pair in \
  "disk_percent:$disk_percent" \
  "inode_percent:$inode_percent" \
  "rrqpe_bytes:$rrqpe_bytes" \
  "docker_writable_bytes:$docker_writable_bytes"; do
  number_or_die "${pair%%:*}" "${pair#*:}"
done

severity=ok
if [ "$disk_percent" -ge "$emergency_percent" ] || \
   [ "$inode_percent" -ge "$emergency_percent" ]; then
  severity=emergency
elif [ "$disk_percent" -ge "$critical_percent" ] || \
     [ "$inode_percent" -ge "$critical_percent" ] || \
     [ "$rrqpe_bytes" -ge "$rrqpe_critical_bytes" ] || \
     [ "$docker_writable_bytes" -ge "$docker_critical_bytes" ]; then
  severity=critical
elif [ "$disk_percent" -ge "$warning_percent" ] || \
     [ "$inode_percent" -ge "$warning_percent" ] || \
     [ "$rrqpe_bytes" -ge "$rrqpe_warning_bytes" ] || \
     [ "$docker_writable_bytes" -ge "$docker_warning_bytes" ]; then
  severity=warning
fi

status_file="$state_dir/status.env"
temporary_status="$status_file.tmp"
cat > "$temporary_status" <<EOF
measured_at=$(date -u +%FT%TZ)
severity=$severity
disk_percent=$disk_percent
inode_percent=$inode_percent
rrqpe_bytes=$rrqpe_bytes
docker_writable_bytes=$docker_writable_bytes
EOF
mv "$temporary_status" "$status_file"

message="Chetiwa storage severity=$severity disk=${disk_percent}% inodes=${inode_percent}% rrqpe_bytes=$rrqpe_bytes docker_writable_bytes=$docker_writable_bytes"
case $severity in
  ok) echo "$message" ;;
  warning) echo "$message" >&2 ;;
  critical|emergency)
    echo "$message" >&2
    exit 1
    ;;
esac
