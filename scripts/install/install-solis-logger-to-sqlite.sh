#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo or as root." >&2
  exit 1
fi

install -d /usr/local/lib/solis-logger
install -d /var/lib/solis-logger
install -m 0755 "${PROJECT_ROOT}/src/solis_logger_to_sqlite.py" /usr/local/lib/solis-logger/solis_logger_to_sqlite.py
install -m 0644 "${PROJECT_ROOT}/systemd/solis-logger-to-sqlite.service" /etc/systemd/system/solis-logger-to-sqlite.service
install -d /etc/systemd/system/solis-logger-to-sqlite.service.d
install -m 0644 "${PROJECT_ROOT}/systemd/solis-logger-to-sqlite.service.d/hotspot.conf" /etc/systemd/system/solis-logger-to-sqlite.service.d/hotspot.conf

systemctl daemon-reload
systemctl enable --now solis-logger-to-sqlite.service

echo "Installed and started solis-logger-to-sqlite.service"
echo "Database: /var/lib/solis-logger/solis_inverter.sqlite3"
echo
systemctl --no-pager --full status solis-logger-to-sqlite.service | sed -n '1,40p'
