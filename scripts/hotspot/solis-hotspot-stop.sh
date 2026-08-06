#!/usr/bin/env bash
set -euo pipefail

WIFI_IF="${WIFI_IF:-wlp2s0}"
RUNTIME_DIR="${RUNTIME_DIR:-/run/solis-hotspot}"
DNSMASQ_PID="${RUNTIME_DIR}/dnsmasq.pid"
HOSTAPD_PID="${RUNTIME_DIR}/hostapd.pid"
DNSMASQ_CONF="${RUNTIME_DIR}/dnsmasq.conf"
NFT_TABLE="${NFT_TABLE:-solis_hotspot}"

log() {
  echo "[solis-hotspot] $*"
}

stop_pidfile() {
  local pidfile="$1"
  if [[ -f "${pidfile}" ]]; then
    kill "$(cat "${pidfile}")" 2>/dev/null || true
    rm -f "${pidfile}"
  fi
}

main() {
  log "Stopping hotspot helpers"
  stop_pidfile "${DNSMASQ_PID}"
  stop_pidfile "${HOSTAPD_PID}"
  pkill -f "dnsmasq --conf-file=${DNSMASQ_CONF}" 2>/dev/null || true
  pkill -f "hostapd .*${WIFI_IF}" 2>/dev/null || true

  log "Removing nftables table"
  nft delete table ip "${NFT_TABLE}" 2>/dev/null || true

  log "Resetting ${WIFI_IF}"
  ip addr flush dev "${WIFI_IF}" || true
  ip link set "${WIFI_IF}" down || true

  rm -f "${DNSMASQ_CONF}"
  rmdir "${RUNTIME_DIR}" 2>/dev/null || true

  log "Hotspot stopped"
}

main "$@"
