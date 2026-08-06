#!/usr/bin/env bash
set -euo pipefail

WIFI_IF="${WIFI_IF:-wlp2s0}"
DB_PATH="${DB_PATH:-/home/nhur/pythonScriptProcesses/solis_inverter.sqlite3}"
NFT_TABLE="${NFT_TABLE:-solis_hotspot}"

echo "== Interface =="
ip -br addr show "${WIFI_IF}" || true
echo

echo "== Stations =="
iw dev "${WIFI_IF}" station dump || true
echo

echo "== Listeners =="
ss -ltnup | grep ':53\|:9999' || true
echo

echo "== nftables =="
nft list table ip "${NFT_TABLE}" 2>/dev/null || echo "table ${NFT_TABLE} not present"
echo

echo "== Solis DB =="
sqlite3 "${DB_PATH}" "select max(received_at), count(*) from inverter_packets;" || true
