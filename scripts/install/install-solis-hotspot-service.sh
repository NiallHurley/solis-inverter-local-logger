#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo or as root." >&2
  exit 1
fi

install -d /usr/local/lib/solis-hotspot
install -m 0755 "${PROJECT_ROOT}/scripts/hotspot/solis-hotspot-start.sh" /usr/local/lib/solis-hotspot/solis-hotspot-start.sh
install -m 0755 "${PROJECT_ROOT}/scripts/hotspot/solis-hotspot-stop.sh" /usr/local/lib/solis-hotspot/solis-hotspot-stop.sh
install -m 0755 "${PROJECT_ROOT}/scripts/hotspot/solis-hotspot-status.sh" /usr/local/lib/solis-hotspot/solis-hotspot-status.sh
install -m 0644 "${PROJECT_ROOT}/systemd/solis-hotspot.service" /etc/systemd/system/solis-hotspot.service

if [[ ! -e /etc/default/solis-hotspot ]]; then
  install -m 0644 "${PROJECT_ROOT}/systemd/solis-hotspot.env.example" /etc/default/solis-hotspot
  echo "Created /etc/default/solis-hotspot. Edit AP_SSID, AP_PASS, and COUNTRY_CODE before starting the service."
fi

systemctl daemon-reload
systemctl enable solis-hotspot.service

echo
echo "Installed solis-hotspot.service"
echo "Next steps:"
echo "  1. sudoedit /etc/default/solis-hotspot"
echo "  2. sudo systemctl start solis-hotspot"
echo "  3. sudo systemctl status solis-hotspot --no-pager"
