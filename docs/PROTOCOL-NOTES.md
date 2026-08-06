# Protocol Notes

The current decoder expects Solis/Ginlong packets with:

- fixed header: `685951b0`
- fixed size: `103` bytes

The implementation currently extracts:

- serial number
- instantaneous watts
- day kWh
- total kWh
- inverter temperature
- DC voltages and currents
- AC voltage, current, and frequency
- yesterday, month, and last-month energy values

See `src/solis_logger_to_sqlite.py` for the byte offsets and decode logic.
