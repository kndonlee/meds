# airctl: CO₂ / temperature thermostat + Tivoo display

Runs on Kimberly's iMac as a LaunchAgent. It reads an Aranet4, switches the Toshiba portable AC
(and later a vent fan) on configurable thresholds, shows CO₂/temp/humidity on a Divoom Tivoo, and
logs every decision so the meds **Climate** page (`c`, or space to cycle) can explain what happened.

```
Aranet4 ─BLE─► airctl ─┬─► cooling:     Toshiba AC (msmart-ng, local LAN)
                       ├─► ventilation: Kasa outlet via kasad :8787   (disabled until the fan exists)
                       ├─► Tivoo (tivoo.py subprocess, Bluetooth Classic)
                       ├─► data/ readings-*.jsonl, events-*.jsonl, status.json
                       └─► HTTP :8788  /status  /history?hours=24  /feedback?value=…
meds.rb Climate page ◄── HTTP 127.0.0.1:8788 on the same Mac (CLIMATE_URL=http://host.local:8788 to view another)
```

## Setup (once per machine)

```sh
cd ~/meds/airctl            # ~/repos/meds/airctl on the laptop
./setup.sh                  # venv (Python >= 3.11, Homebrew's), deps, config.toml from the example
.venv/bin/python tivoo.py scan            # Tivoo shows up as "Tivoo-audio"
.venv/bin/python tivoo.py pair <mac>
.venv/bin/python ac_setup.py              # or copy ac.json from another machine (chmod 600)
./airctlctl run                           # foreground test (Ctrl-C to stop)
./airctlctl install-service               # LaunchAgent: starts at login, restarts if it exits
```

The first Bluetooth use under launchd may show a macOS permission prompt on the iMac's screen; click Allow.
The Tivoo accepts one controller at a time, so only one machine should run the service.

## Operating

```sh
./airctlctl status      # launchd state + live snapshot
./airctlctl logs        # ~/Library/Logs/airctl.log
./airctlctl restart     # after editing config.toml or pulling code
./airctlctl uninstall-service
```

## Tuning (config.toml)

Each `[[control]]` is an independent feature: it turns **on** when *any* condition reaches `on_above`,
and **off** only when *all* conditions are at/below `off_below`, never sooner than `min_on_seconds`
after turning on (or `min_off_seconds` after turning off). Commands are only sent on transitions, so
remote/app changes stick until the next crossing. If the sensor goes quiet for `stale_seconds`, the
feature turns off.

Defaults: **cooling** on at CO₂ ≥ 1350 or ≥ 78°F, runs ≥ 20 min, off when CO₂ ≤ 900 and ≤ 75°F.
Setpoint 60°F (clamped to the unit's 61°F) keeps the compressor, and so the exhaust, running.
Tivoo CO₂ colors: green < 1100 ≤ orange < 1500 ≤ red. Dots: bottom-right blue = AC on,
bottom-left green = vent fan on.

Kim's comfort notes (Climate page keys 1–4, 0) land in the event log with the readings at that moment.

## Secrets

`ac.json` (AC LAN token/key), `config.toml`, `data/` and `.venv/` are gitignored. Copy `ac.json` between
machines by hand. If the AC is ever re-paired or its Wi-Fi reset, rerun `ac_setup.py` (needs the
**MSmartHome** login; the Toshiba AC NA app's cloud can no longer issue keys).

## Notes

- AC pairing mode: remote **LED ×7**; hotspot `net_ac_XXXX`, password `12345678`.
- Fan-only mode doesn't exhaust on this single-hose portable; only Cool vents room air.
- Tivoo protocol: see `tivoo.py` (bytes match hass-divoom's Tivoo goldens).
