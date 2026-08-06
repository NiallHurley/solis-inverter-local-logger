#!/usr/bin/env python3
import binascii
import json
import logging
import os
import re
import signal
import socket
import sqlite3
import subprocess
import sys
from contextlib import closing
from datetime import datetime, timezone


LISTEN_HOST = os.environ.get("SOLIS_LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("SOLIS_LISTEN_PORT", "9999"))
DB_PATH = os.environ.get(
    "SOLIS_DB_PATH", "/var/lib/solis-logger/solis_inverter.sqlite3"
)
LOG_LEVEL = os.environ.get("SOLIS_LOG_LEVEL", "INFO").upper()
MQTT_ENABLED = os.environ.get("SOLIS_MQTT_ENABLED", "1") == "1"
MQTT_TOPIC_PREFIX = os.environ.get("SOLIS_MQTT_TOPIC_PREFIX", "solis/inverter")
MQTT_DOCKER_CONTAINER = os.environ.get("SOLIS_MQTT_DOCKER_CONTAINER", "mosquitto")

HEADER = bytes.fromhex("685951b0")
EXPECTED_PACKET_BYTES = 103

# Byte offsets from the original read-ginlong script.
OFFSETS = {
    "inverter_temp": 31,
    "inverter_vdc1": 33,
    "inverter_vdc2": 35,
    "inverter_adc1": 39,
    "inverter_adc2": 41,
    "inverter_aac": 45,
    "inverter_vac": 51,
    "inverter_freq": 57,
    "inverter_now": 59,
    "inverter_yes": 67,
    "inverter_day": 69,
    "inverter_tot": 73,
    "inverter_mth": 87,
    "inverter_lmth": 91,
}

stop_requested = False


def setup_logging() -> None:
    logging.basicConfig(
        level=getattr(logging, LOG_LEVEL, logging.INFO),
        format="%(asctime)s %(levelname)s %(message)s",
    )


def handle_signal(signum, frame) -> None:  # noqa: ARG001
    global stop_requested
    stop_requested = True


def ensure_db(path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with sqlite3.connect(path) as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS inverter_packets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                received_at TEXT NOT NULL,
                source_ip TEXT NOT NULL,
                source_port INTEGER NOT NULL,
                serial TEXT,
                watts_now INTEGER,
                day_kwh REAL,
                total_kwh REAL,
                temp_c REAL,
                dc_volts1 REAL,
                dc_volts2 REAL,
                dc_amps1 REAL,
                dc_amps2 REAL,
                ac_volts REAL,
                ac_amps REAL,
                ac_freq REAL,
                kwh_yesterday REAL,
                kwh_month REAL,
                kwh_lastmonth REAL,
                raw_hex TEXT NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_inverter_packets_received_at
            ON inverter_packets(received_at)
            """
        )
        conn.commit()


def u16(packet: bytes, offset: int) -> int:
    start = offset
    end = offset + 2
    return int.from_bytes(packet[start:end], byteorder="big", signed=False)


def decode(packet: bytes) -> dict:
    ascii_slice = packet[8:32].decode("ascii", errors="ignore")
    serial_match = re.search(r"(\d{8,})", ascii_slice)
    serial = serial_match.group(1) if serial_match else ascii_slice.strip("\x00").strip()
    return {
        "serial": serial,
        "watts_now": u16(packet, OFFSETS["inverter_now"]),
        "day_kwh": u16(packet, OFFSETS["inverter_day"]) / 100.0,
        "total_kwh": u16(packet, OFFSETS["inverter_tot"]) / 10.0,
        "temp_c": u16(packet, OFFSETS["inverter_temp"]) / 10.0,
        "dc_volts1": u16(packet, OFFSETS["inverter_vdc1"]) / 10.0,
        "dc_volts2": u16(packet, OFFSETS["inverter_vdc2"]) / 10.0,
        "dc_amps1": u16(packet, OFFSETS["inverter_adc1"]) / 10.0,
        "dc_amps2": u16(packet, OFFSETS["inverter_adc2"]) / 10.0,
        "ac_volts": u16(packet, OFFSETS["inverter_vac"]) / 10.0,
        "ac_amps": u16(packet, OFFSETS["inverter_aac"]) / 10.0,
        "ac_freq": u16(packet, OFFSETS["inverter_freq"]) / 100.0,
        "kwh_yesterday": u16(packet, OFFSETS["inverter_yes"]) / 100.0,
        "kwh_month": float(u16(packet, OFFSETS["inverter_mth"])),
        "kwh_lastmonth": float(u16(packet, OFFSETS["inverter_lmth"])),
        "raw_hex": binascii.hexlify(packet).decode(),
    }


def insert_row(path: str, source_ip: str, source_port: int, row: dict) -> None:
    with sqlite3.connect(path) as conn:
        conn.execute(
            """
            INSERT INTO inverter_packets (
                received_at, source_ip, source_port, serial, watts_now, day_kwh,
                total_kwh, temp_c, dc_volts1, dc_volts2, dc_amps1, dc_amps2,
                ac_volts, ac_amps, ac_freq, kwh_yesterday, kwh_month,
                kwh_lastmonth, raw_hex
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                datetime.now(timezone.utc).isoformat(),
                source_ip,
                source_port,
                row["serial"],
                row["watts_now"],
                row["day_kwh"],
                row["total_kwh"],
                row["temp_c"],
                row["dc_volts1"],
                row["dc_volts2"],
                row["dc_amps1"],
                row["dc_amps2"],
                row["ac_volts"],
                row["ac_amps"],
                row["ac_freq"],
                row["kwh_yesterday"],
                row["kwh_month"],
                row["kwh_lastmonth"],
                row["raw_hex"],
            ),
        )
        conn.commit()


def publish_mqtt(row: dict) -> None:
    if not MQTT_ENABLED:
        return

    topic = f"{MQTT_TOPIC_PREFIX}/state"
    payload = json.dumps(row, separators=(",", ":"), sort_keys=True)
    cmd = [
        "docker",
        "exec",
        MQTT_DOCKER_CONTAINER,
        "mosquitto_pub",
        "-h",
        "127.0.0.1",
        "-p",
        "1883",
        "-t",
        topic,
        "-m",
        payload,
        "-r",
    ]
    subprocess.run(cmd, check=True, capture_output=True, text=True)


def valid_packet(packet: bytes) -> bool:
    return len(packet) == EXPECTED_PACKET_BYTES and packet.startswith(HEADER)


def main() -> int:
    setup_logging()
    ensure_db(DB_PATH)
    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    with closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as server:
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((LISTEN_HOST, LISTEN_PORT))
        server.listen(5)
        server.settimeout(1.0)

        logging.info(
            "Listening for Solis packets on %s:%s, writing to %s",
            LISTEN_HOST,
            LISTEN_PORT,
            DB_PATH,
        )

        while not stop_requested:
            try:
                conn, addr = server.accept()
            except TimeoutError:
                continue

            with closing(conn):
                conn.settimeout(5.0)
                try:
                    payload = conn.recv(4096)
                except TimeoutError:
                    logging.warning("Timed out waiting for payload from %s:%s", *addr)
                    continue

                if not valid_packet(payload):
                    logging.warning(
                        "Ignoring unexpected packet from %s:%s, bytes=%d, header=%s",
                        addr[0],
                        addr[1],
                        len(payload),
                        binascii.hexlify(payload[:8]).decode(),
                    )
                    continue

                row = decode(payload)
                insert_row(DB_PATH, addr[0], addr[1], row)
                try:
                    publish_mqtt(row)
                except subprocess.CalledProcessError as exc:
                    logging.warning(
                        "MQTT publish failed: returncode=%s stderr=%s",
                        exc.returncode,
                        exc.stderr.strip(),
                    )
                logging.info(
                    "Stored packet from %s:%s serial=%s watts=%s day_kwh=%.2f total_kwh=%.1f",
                    addr[0],
                    addr[1],
                    row["serial"],
                    row["watts_now"],
                    row["day_kwh"],
                    row["total_kwh"],
                )

    logging.info("Stopped.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
