#!/usr/bin/env sh
# Blocks direct public access to LibreWXR's host port while preserving local
# probes and Docker-network traffic used by the API and Cloudflare Tunnel.
set -eu

action=${1:-apply}
origin_port=${CHETIWA_LIBREWXR_ORIGIN_PORT:-8080}
public_interface=${CHETIWA_PUBLIC_INTERFACE:-}
if [ -z "$public_interface" ]; then
  public_interface=$(ip -4 route show default | awk 'NR == 1 { print $5 }')
fi
if [ -z "$public_interface" ]; then
  echo 'Unable to determine the public network interface.' >&2
  exit 2
fi

rule_exists() {
  iptables -C DOCKER-USER \
    -i "$public_interface" -p tcp --dport "$origin_port" -j DROP \
    >/dev/null 2>&1
}

case $action in
  apply)
    if ! rule_exists; then
      iptables -I DOCKER-USER 1 \
        -i "$public_interface" -p tcp --dport "$origin_port" -j DROP
    fi
    ;;
  remove)
    if rule_exists; then
      iptables -D DOCKER-USER \
        -i "$public_interface" -p tcp --dport "$origin_port" -j DROP
    fi
    ;;
  *)
    echo 'usage: chetiwa-origin-firewall apply|remove' >&2
    exit 2
    ;;
esac
