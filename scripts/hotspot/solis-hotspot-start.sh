#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_IF="${UPSTREAM_IF:-enp1s0}"
WIFI_IF="${WIFI_IF:-wlp2s0}"
HOTSPOT_CIDR="${HOTSPOT_CIDR:-10.44.0.1/24}"
HOTSPOT_GATEWAY="${HOTSPOT_GATEWAY:-10.44.0.1}"
DHCP_RANGE_START="${DHCP_RANGE_START:-10.44.0.50}"
DHCP_RANGE_END="${DHCP_RANGE_END:-10.44.0.150}"
DHCP_LEASE_TIME="${DHCP_LEASE_TIME:-12h}"
HOSTAPD_CONF="${HOSTAPD_CONF:-/etc/hostapd/hostapd.conf}"
RUNTIME_DIR="${RUNTIME_DIR:-/run/solis-hotspot}"
DNSMASQ_CONF="${RUNTIME_DIR}/dnsmasq.conf"
DNSMASQ_PID="${RUNTIME_DIR}/dnsmasq.pid"
HOSTAPD_PID="${RUNTIME_DIR}/hostapd.pid"
NFT_TABLE="${NFT_TABLE:-solis_hotspot}"

log() {
  echo "[solis-hotspot] $*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

cleanup_stale_processes() {
  if [[ -f "${DNSMASQ_PID}" ]]; then
    kill "$(cat "${DNSMASQ_PID}")" 2>/dev/null || true
    rm -f "${DNSMASQ_PID}"
  fi

  if [[ -f "${HOSTAPD_PID}" ]]; then
    kill "$(cat "${HOSTAPD_PID}")" 2>/dev/null || true
    rm -f "${HOSTAPD_PID}"
  fi

  pkill -f "dnsmasq --conf-file=${DNSMASQ_CONF}" 2>/dev/null || true
  pkill -x hostapd 2>/dev/null || true

  for _ in 1 2 3 4 5; do
    pgrep -x hostapd >/dev/null 2>&1 || break
    sleep 1
  done
}

write_dnsmasq_conf() {
  cat >"${DNSMASQ_CONF}" <<EOF
interface=${WIFI_IF}
bind-interfaces
port=0
dhcp-range=${DHCP_RANGE_START},${DHCP_RANGE_END},${DHCP_LEASE_TIME}
dhcp-option=3,${HOTSPOT_GATEWAY}
log-dhcp
EOF
}

apply_nft_rules() {
  nft delete table ip "${NFT_TABLE}" 2>/dev/null || true
  nft -f - <<EOF
table ip ${NFT_TABLE} {
  chain forward {
    type filter hook forward priority filter; policy accept;
    iifname "${WIFI_IF}" oifname "${UPSTREAM_IF}" accept
    iifname "${UPSTREAM_IF}" oifname "${WIFI_IF}" ct state established,related accept
  }

  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip saddr 10.44.0.0/24 oifname "${UPSTREAM_IF}" masquerade
  }
}
EOF
}

main() {
  require_command ip
  require_command hostapd
  require_command dnsmasq
  require_command nft
  require_command sysctl

  ip route | grep -q "^default .* dev ${UPSTREAM_IF}\\b" || {
    echo "No default route via ${UPSTREAM_IF}" >&2
    exit 1
  }

  [[ -f "${HOSTAPD_CONF}" ]] || {
    echo "Missing hostapd config: ${HOSTAPD_CONF}" >&2
    exit 1
  }

  mkdir -p "${RUNTIME_DIR}"
  cleanup_stale_processes

  log "Preparing ${WIFI_IF}"
  ip link set "${WIFI_IF}" down || true
  ip addr flush dev "${WIFI_IF}" || true
  ip addr add "${HOTSPOT_CIDR}" dev "${WIFI_IF}"
  ip link set "${WIFI_IF}" up

  log "Ensuring IPv4 forwarding"
  sysctl -w net.ipv4.ip_forward=1 >/dev/null

  log "Starting dedicated hotspot dnsmasq"
  write_dnsmasq_conf
  dnsmasq --conf-file="${DNSMASQ_CONF}" --pid-file="${DNSMASQ_PID}"

  log "Starting hostapd"
  hostapd -B -P "${HOSTAPD_PID}" "${HOSTAPD_CONF}"

  log "Applying nftables rules"
  apply_nft_rules

  log "Hotspot started on ${WIFI_IF} (${HOTSPOT_CIDR})"
}

main "$@"
