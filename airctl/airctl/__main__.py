"""Run: python -m airctl [-c config.toml]"""

import argparse
import asyncio
import json
import logging
import os
import time
import tomllib

from .actuators import make_actuator, NoneActuator
from .ambient import AmbientLight
from .audioguard import AudioGuard
from .controller import Condition, Controller
from .datalog import DataLog
from .heater_ir import HeaterIR
from .display import make_display
from .sensors import make_sensor
from .web import Web

log = logging.getLogger("airctl")

METRICS = {
    "co2": lambda r: r.co2,
    "temp_f": lambda r: r.temp_f,
    "temp_c": lambda r: r.temp_c,
    "humidity": lambda r: r.humidity,
}


class Control:
    """One feature: conditions (metric bands) + timing + an actuator.

    e.g. cooling = (co2 >= 1350 or temp_f >= 78) -> AC, until co2 <= 900 and temp_f <= 75.
    """

    def __init__(self, cfg, datalog, state_path=None):
        cfg = dict(cfg)
        self.state_path = state_path
        self.name = cfg.pop("name")
        self.datalog = datalog
        conds = cfg.pop("conditions", None)
        if conds is None:  # single-condition shorthand: metric/on_above/off_below at top level
            conds = [{k: cfg.pop(k) for k in ("metric", "on_above", "off_below", "smooth_seconds") if k in cfg}]
        for c in conds:
            if c.get("metric") not in METRICS:
                raise ValueError(f"{self.name}: unknown metric {c.get('metric')!r} (have {list(METRICS)})")
        hold = cfg.pop("manual_off_hold_minutes", cfg.pop("manual_hold_minutes", 10))
        run_until = cfg.pop("manual_run_until_temp_f", None)
        run_min = float(cfg.pop("manual_run_min_minutes", 10)) * 60
        self.reconcile_every = float(cfg.pop("reconcile_seconds", 120))
        self.last_reconcile = time.monotonic()
        self.actuator = make_actuator(cfg.pop("actuator"), label=self.name)
        self.dry_run = isinstance(self.actuator, NoneActuator)
        self.ctl = Controller([Condition(**c) for c in conds], run_until_temp_f=run_until,
                              run_min_seconds=run_min, off_hold_seconds=float(hold) * 60, **cfg)
        self._load_state()
        self.since = None          # wall-clock time of the last switch
        self.error = None

    async def apply(self, decision, reason, prev=None):
        """prev: (on, changed_at) before the decision, restored if the device can't be switched so the
        next reading retries instead of believing a switch that never happened."""
        if decision is None:
            return
        now = time.time()
        ran = None if self.since is None else int(now - self.since)
        log.info("%s -> %s (%s)", self.name, "ON" if decision else "OFF", reason)
        self.datalog.event("switch", feature=self.name, on=decision, reason=reason, dry_run=self.dry_run,
                           previous_state_s=ran, conditions=self.ctl.snapshot()["conditions"])
        self.since = now
        try:
            await self.actuator.set(decision)
            self.error = None
        except Exception as e:
            if prev is not None:
                self.ctl.on, self.ctl.changed_at = prev
            self.error = str(e)
            log.error("%s: actuator failed: %s", self.name, e)
            self.datalog.event("error", feature=self.name, message=str(e))

    # --- persisted mode (so a restart can't quietly turn automation back on) ---
    def _load_state(self):
        try:
            with open(self.state_path) as f:
                st = json.load(f).get(self.name, {})
        except (OSError, ValueError, TypeError):
            return
        if st.get("mode") == "manual":
            self.ctl.set_mode("manual", st.get("mode_reason") or "user")
        elif st.get("manual_run"):
            self.ctl.run_since = time.monotonic() - max(0.0, time.time() - st.get("manual_run_since", time.time()))
        log.info("%s: restored %s mode%s", self.name, self.ctl.mode, ", manual run" if self.ctl.run_since else "")

    def _save_state(self):
        if not self.state_path:
            return
        try:
            with open(self.state_path) as f:
                allst = json.load(f)
        except (OSError, ValueError):
            allst = {}
        run = self.ctl.run_since
        allst[self.name] = {"mode": self.ctl.mode, "mode_reason": self.ctl.mode_reason,
                            "manual_run": run is not None,
                            "manual_run_since": None if run is None else time.time() - (time.monotonic() - run)}
        tmp = self.state_path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(allst, f)
        os.replace(tmp, self.state_path)

    def _describe_manual(self, on):
        if self.ctl.mode == "manual":
            return "MANUAL mode"
        if self.ctl.run_since is not None:
            return f"manual run until temp_f <= {self.ctl.run_until}"
        return f"automation paused {int(self.ctl.off_hold // 60)}m"

    async def manual(self, action, source="manual"):
        """action: on, off or toggle. Switches the device now. In AUTO an ON is a manual run (until
        manual_run_until_temp_f) and an OFF holds for manual_off_hold_minutes; in MANUAL it just sticks."""
        on = (not self.on) if action == "toggle" else action == "on"
        await self.actuator.set(on)  # raises on failure; the caller reports it
        self.ctl.manual(on)
        self.since, self.error = time.time(), None
        why = self._describe_manual(on)
        log.info("%s -> %s (%s, %s)", self.name, "ON" if on else "OFF", source, why)
        self.datalog.event("switch", feature=self.name, on=on, reason=f"{source} ({why})", manual=True,
                           dry_run=self.dry_run, conditions=self.ctl.snapshot()["conditions"])
        self._save_state()
        return on

    async def set_mode(self, mode, source="manual", reason="user"):
        """mode: auto, manual or toggle. Never switches the device itself, but entering AUTO applies
        the rules to the latest readings right away."""
        if mode == "toggle":
            mode = "auto" if self.ctl.mode == "manual" else "manual"
        if self.ctl.set_mode(mode, reason):
            log.info("%s: %s mode (%s)", self.name, mode.upper(), source)
            self.datalog.event("mode", feature=self.name, mode=mode, reason=source)
            self._save_state()
            if mode == "auto":
                prev = (self.ctl.on, self.ctl.changed_at)
                d = self.ctl.decide()
                if d is not None:
                    await self.apply(d, self.ctl.last_explain, prev)
        return self.ctl.mode

    async def feed(self, reading):
        if self.ctl.mode == "manual" and self.ctl.mode_reason == "no_sensor":
            await self.set_mode("auto", "sensor readings are back")
        values = {m: METRICS[m](reading) for m in self.ctl.metrics}
        values["temp_f"] = reading.temp_f
        prev = (self.ctl.on, self.ctl.changed_at)
        run_before = self.ctl.run_since
        decision = self.ctl.update(values)
        if decision is not None:
            await self.apply(decision, self.ctl.last_explain, prev)
        if run_before is not None and self.ctl.run_since is None:
            if decision is False and self.error:   # the OFF failed: keep the run so the next reading retries
                self.ctl.run_since = run_before
            self._save_state()

    async def check_stale(self):
        turn_off = self.ctl.check_stale()
        if turn_off is None:
            return
        log.warning("%s: no sensor readings for %ss; MANUAL mode (no sensor)%s", self.name, self.ctl.stale,
                    ", turning it off" if turn_off else "")
        self.datalog.event("mode", feature=self.name, mode="manual", reason="no sensor readings")
        self._save_state()
        if turn_off:
            await self.apply(False, f"no sensor readings for {self.ctl.stale}s")

    async def reconcile(self):
        """Compare with the device's real state; adopt changes made outside airctl (remote, panel,
        the unit stopping itself, a lost command) and treat them like a manual switch."""
        if self.ctl.on is None:
            return
        device_on = await self.actuator.get()
        if device_on is None or device_on == bool(self.ctl.on):
            return
        self.ctl.manual(device_on)
        self.since = time.time()
        why = self._describe_manual(device_on)
        log.warning("%s: device turned %s outside airctl (remote or the unit itself); %s", self.name,
                    "ON" if device_on else "off", why)
        self.datalog.event("switch", feature=self.name, on=device_on, manual=True,
                           reason=f"changed outside airctl ({why})",
                           dry_run=self.dry_run, conditions=self.ctl.snapshot()["conditions"])
        self._save_state()

    async def adjust_target(self, steps, source="manual"):
        if not hasattr(self.actuator, "adjust_target"):
            raise RuntimeError(f"{self.name}: actuator has no setpoint")
        f = await self.actuator.adjust_target(steps)
        log.info("%s setpoint -> %sF (%s)", self.name, f, source)
        self.datalog.event("setpoint", feature=self.name, target_f=f, reason=source)
        return f

    def snapshot(self):
        snap = {**self.ctl.snapshot(), "since": self.since, "dry_run": self.dry_run, "error": self.error}
        if hasattr(self.actuator, "target_f"):
            snap["target_f"] = self.actuator.target_f
        return snap

    @property
    def on(self):
        return bool(self.ctl.on)


async def run(cfg):
    lcfg = cfg.get("log", {})
    datalog = DataLog(lcfg.get("directory", "data"), lcfg.get("keep_days", 14))
    sensor = make_sensor(cfg["sensor"])
    dcfg = cfg.get("display", {"type": "none"})
    display = make_display(dcfg)
    state_path = os.path.join(datalog.dir, "control-state.json")
    controls = [Control(c, datalog, state_path) for c in cfg.get("control", []) if c.pop("enabled", True)]
    log.info("controls: %s", ", ".join(f"{c.name} ({' or '.join(c.ctl.metrics)})" for c in controls)
             or "none (display only)")
    for c in controls:
        device_on = await c.actuator.get()
        c.ctl.sync(device_on)
        if device_on:
            c.since = time.time()
        log.info("%s: device is %s at startup", c.name, {True: "ON", False: "off", None: "unknown"}[device_on])
    datalog.event("start", features=[c.name for c in controls],
                  device_state={c.name: c.ctl.on for c in controls},
                  config={c.name: c.ctl.snapshot() for c in controls})

    latest = {}

    def state():
        return {**latest, "colors": list(dcfg.get("colors", [1100, 1500])),
                "lux": None if ambient is None or ambient.lux is None else round(ambient.lux, 1),
                "display_dark": bool(ambient and ambient.dark),
                "features": {c.name: c.snapshot() for c in controls}, "server_ts": time.time()}

    gcfg = cfg.get("audio_guard", {})
    guard = None
    if gcfg.get("enabled", True):
        gcfg = {k: v for k, v in gcfg.items() if k != "enabled"}
        guard = asyncio.create_task(AudioGuard(datalog=datalog, **gcfg).run())

    acfg = cfg.get("ambient", {})
    ambient = ambient_task = None
    if acfg.get("enabled", False):
        async def on_dark(dark, lux):
            datalog.event("display", on=not dark, reason=f"room {'dark' if dark else 'light'} ({lux:.1f} lux)")
            await display.set_dark(dark)
        ambient = AmbientLight(on_change=on_dark, on_reading=display.set_lux,
                               **{k: v for k, v in acfg.items() if k != "enabled"})
        ambient_task = asyncio.create_task(ambient.run())

    wcfg = cfg.get("web", {})
    server = None
    if wcfg.get("enabled", True):
        async def control_fn(feature, action, source):
            c = next((c for c in controls if c.name == feature), None)
            if c is None:
                raise KeyError(f"no control named {feature!r} (have {[c.name for c in controls]})")
            if action.startswith("mode:"):
                out = {"mode": await c.set_mode(action[5:], source)}
            elif action in ("temp_up", "temp_down"):
                out = {"target_f": await c.adjust_target(1 if action == "temp_up" else -1, source)}
            else:
                out = {"on": await c.manual(action, source)}
            datalog.status(state())
            return out

        hcfg = dict(cfg.get("heater_ir", {}))
        heater = HeaterIR(**{k: v for k, v in hcfg.items() if k != "enabled"}) if hcfg.pop("enabled", True) else None
        server = await Web(datalog, state, wcfg.get("host", "0.0.0.0"), wcfg.get("port", 8788),
                           control_fn=control_fn, heater=heater).start()

    async def watchdog():
        while True:
            await asyncio.sleep(30)
            for c in controls:
                await c.check_stale()
                if c.reconcile_every and time.monotonic() - c.last_reconcile >= c.reconcile_every:
                    c.last_reconcile = time.monotonic()
                    try:
                        await c.reconcile()
                    except Exception as e:
                        log.warning("%s: reconcile failed: %s", c.name, e)

    wd = asyncio.create_task(watchdog())
    try:
        async for reading in sensor.readings():
            log.info("%s: co2=%s temp=%.1fF hum=%s%%", reading.source, reading.co2,
                     reading.temp_f or float("nan"), reading.humidity)
            latest.update(co2=reading.co2, temp_f=round(reading.temp_f, 1) if reading.temp_f else None,
                          humidity=reading.humidity, pressure_hpa=reading.pressure_hpa,
                          reading_ts=time.time())
            datalog.reading(reading)
            for c in controls:
                await c.feed(reading)
                log.info("  %s: %s", c.name, c.ctl.status())
            datalog.status(state())
            await display.show(reading, {c.name: c.on for c in controls})
    finally:
        wd.cancel()
        if guard:
            guard.cancel()
        if ambient_task:
            ambient_task.cancel()
        if server:
            server.close()
        await display.close()


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser(prog="airctl", description=__doc__)
    ap.add_argument("-c", "--config", default=os.path.join(here, "config.toml"))
    ap.add_argument("-v", "--verbose", action="store_true")
    a = ap.parse_args()
    logging.basicConfig(level=logging.DEBUG if a.verbose else logging.INFO,
                        format="%(asctime)s %(name)s %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
    for noisy in ("bleak", "msmart", "httpx", "httpcore", "asyncio"):
        logging.getLogger(noisy).setLevel(logging.WARNING)
    with open(a.config, "rb") as f:
        cfg = tomllib.load(f)
    try:
        asyncio.run(run(cfg))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
