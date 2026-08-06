# Architecture

## Problem

Older Solis/Ginlong dataloggers often expect to push their telemetry over Wi-Fi rather than exposing a convenient local API.

## Solution

Run your own dedicated 2.4 GHz access point and let the datalogger connect to it directly.

## Flow

1. `hostapd` exposes a 2.4 GHz access point.
2. A dedicated `dnsmasq` process hands out DHCP leases on the hotspot subnet.
3. The datalogger joins that AP and receives an IP address.
4. The datalogger sends TCP packets to the Linux host on port `9999`.
5. `solis_logger_to_sqlite.py` validates the packet, decodes fields, and writes a row into SQLite.
6. Optional: the decoded state is published to MQTT.

## Why this design is useful

- no dependency on the vendor cloud
- local historical data in SQLite
- simple integration point for dashboards or Home Assistant
- easy to debug with standard Linux tooling

## Main components

- `hostapd`: Wi-Fi AP
- `dnsmasq`: DHCP only
- `nftables`: NAT and forwarding rules
- `systemd`: service lifecycle
- `SQLite`: local storage
- optional `mosquitto_pub`: publish latest state to MQTT

## Packet handling

The logger listens on TCP port `9999` and expects packets with:

- header: `685951b0`
- packet length: `103` bytes

Selected fields are decoded from known byte offsets and written to the `inverter_packets` table.
