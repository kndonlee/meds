# IR sender for the Twin-Star heater (QT Py ESP32-S3 + CircuitPython)

Hardware: Adafruit QT Py ESP32-S3 (No PSRAM) + Adafruit 940nm IR LED emitter (STEMMA, product 5639).
The STEMMA QT cable is wired yellow (GPIO40/SCL1) to IN, red (3.3V) to V+, and black to GND.

Flashing CircuitPython: `esptool write-flash -z 0x0 adafruit-circuitpython-adafruit_qtpy_esp32s3_nopsram-en_US-10.3.2.bin`
(erase first). Then copy `code.py` onto the CIRCUITPY drive.

Wi-Fi: create `settings.toml` on the CIRCUITPY drive. It is never committed:

```toml
WIFI_SSID = "your network"
WIFI_PASSWORD = "your password"
HOSTNAME = "heater-ir"
```

HTTP on port 80:
- `GET /` returns JSON status.
- `GET /press/<power|up|down|timer>?n=1` presses a button n times, 0.6s apart.
- `GET /send/<12 bits>?frames=7` sends a raw code.

USB serial also works: send `<12 bits> [frames]` or `<button> [n]`, ended with `\r`.

Twin-Star 12-bit IR protocol (from Flipper-IRDB captures):
- 38 kHz carrier
- bit 1 = 1280us mark + 410us space; bit 0 = 440us mark + 1250us space
- about 8000us between frames, about 7 frames per press

Codes verified on the 10QI085ARA heater:

| button      | code           |
|-------------|----------------|
| power toggle| `110110000100` |
| temp up     | `110110000001` |
| temp down   | `110110010000` |
| timer       | `110110000010` |
| eco         | unknown (`110110001000` does nothing) |

The first up or down press only shows the setpoint (it blinks). Each later press changes it by 1°F.
