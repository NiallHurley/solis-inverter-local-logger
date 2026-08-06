# Solis Inverter Local Logger

Capture data from an older Solis/Ginlong Wi-Fi datalogger without depending on the vendor cloud.

This project sets up a dedicated 2.4 GHz access point, lets the inverter datalogger join it, receives the raw TCP packets locally, decodes them, and stores the results in SQLite.

## Why this exists

Some older inverter Wi-Fi sticks are awkward to integrate locally but will happily talk to a nearby 2.4 GHz access point and push their telemetry over TCP. This project turns a Linux host into that access point and packet collector.

## How it works

1. A Linux host exposes a dedicated 2.4 GHz Wi-Fi AP.
2. The Solis/Ginlong datalogger joins that AP.
3. The datalogger opens a TCP connection to the host on port `9999`.
4. `src/solis_logger_to_sqlite.py` decodes the packets.
5. Decoded values are stored in SQLite for local dashboards, exporters, or further automation.

## Packet Flow

```text
Solis inverter
  -> Wi-Fi datalogger
  -> 2.4 GHz AP on Linux host
  -> TCP packets to :9999
  -> solis_logger_to_sqlite.py
  -> SQLite
  -> dashboards / MQTT / automation
```

## Repository layout

- `src/`: packet listener and SQLite writer
- `scripts/hotspot/`: hotspot lifecycle helpers
- `scripts/install/`: install helpers for systemd-based hosts
- `configs/`: example `hostapd` and network config
- `systemd/`: example unit files
- `docs/`: architecture and rebuild notes

## Quick Start

1. Review and customize:
   - `configs/hostapd/hostapd.conf`
   - `configs/systemd-network/30-wlp2s0-solis-ap.network`
   - `systemd/solis-hotspot.env.example`
2. Install the hotspot service:
   - `sudo ./scripts/install/install-solis-hotspot-service.sh`
3. Install the logger service:
   - `sudo ./scripts/install/install-solis-logger-to-sqlite.sh`
4. Start the services:
   - `sudo systemctl start solis-hotspot.service`
   - `sudo systemctl start solis-logger-to-sqlite.service`
5. Point your Solis/Ginlong datalogger at the host running this project.
6. Verify data is being written to SQLite:
   - `sudo /usr/local/lib/solis-hotspot/solis-hotspot-status.sh`
   - `sqlite3 /var/lib/solis-logger/solis_inverter.sqlite3 "select max(received_at), count(*) from inverter_packets;"`

## Default assumptions

These are examples, not requirements:

- Wi-Fi interface: `wlp2s0`
- Upstream interface: `enp1s0`
- Hotspot subnet: `10.44.0.0/24`
- Listen port: `9999`
- SQLite path: `/var/lib/solis-logger/solis_inverter.sqlite3`

## What to customize

- Wi-Fi SSID and passphrase
- interface names
- hotspot subnet and DHCP range
- database path
- whether MQTT publishing should be enabled

## Notes

- `configs/` and `systemd/` are examples intended to be adapted.
- The logger can run without MQTT by setting `SOLIS_MQTT_ENABLED=0`.
- The hotspot side is designed to avoid fighting with an existing DNS service by using `dnsmasq` in DHCP-only mode.

See `docs/ARCHITECTURE.md`, `docs/RECREATE.md`, and `docs/PROTOCOL-NOTES.md`.

## License

MIT. See `LICENSE`.

## Suggested GitHub Topics

`solis`, `ginlong`, `solar`, `inverter`, `wifi-hotspot`, `sqlite`, `systemd`, `homelab`
