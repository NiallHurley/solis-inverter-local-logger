# Recreate The Setup

## Requirements

- Linux host with a Wi-Fi interface capable of AP mode
- `hostapd`
- `dnsmasq`
- `nftables`
- `systemd`
- Python 3

## Install flow

1. Clone this repository to the target host.
2. Review `systemd/solis-hotspot.env.example`.
3. Review `configs/hostapd/hostapd.conf`.
4. Review `configs/systemd-network/30-wlp2s0-solis-ap.network`.
5. Install the hotspot service with `scripts/install/install-solis-hotspot-service.sh`.
6. Install the logger service with `scripts/install/install-solis-logger-to-sqlite.sh`.
7. Enable and start:
   - `solis-hotspot.service`
   - `solis-logger-to-sqlite.service`

## Verification

Useful checks:

```bash
systemctl status solis-hotspot.service --no-pager
systemctl status solis-logger-to-sqlite.service --no-pager
ss -ltnup | grep ':9999'
sqlite3 /var/lib/solis-logger/solis_inverter.sqlite3 \
  "select max(received_at), count(*) from inverter_packets;"
```

## Notes

- The config files in this repository are examples.
- The default subnet and interface names are not mandatory.
- If you already run a DNS service on the host, keep the hotspot `dnsmasq` instance in DHCP-only mode.
