"""Run: python -m airctl [-c config.toml]"""

import argparse
import asyncio
import logging
import os
import time
import tomllib

from .actuators import make_actuator, NoneActuator
from .ambient import AmbientLight
from .audioguard import AudioGuard
from .controller import Condition, Controller
from .datalog import DataLog
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

    def __init__(self, cfg, datalog):
        cfg = dict(cfg)
        self.name = cfg.pop("name")
        self.datalog = datalog
        conds = cfg.pop("conditions", None)
        if conds is None:  # single-condition shorthand: metric/on_above/off_below at top level
            conds = [{k: cfg.pop(k) for k in ("metric", "on_above", "off_below", "smooth_seconds") if k in cfg}]
        for c in conds:
            if c.get("metric") not in METRICS:
                raise ValueError(f"{self.name}: unknown metric {c.get('metric')!r} (have {list(METRICS)})")
        self.actuator = make_actuator(cfg.pop("actuator"), label=self.name)
        self.dry_run = isinstance(self.actuator, NoneActuator)
        self.ctl = Controller([Condition(**c) for c in conds], **cfg)
        self.since = None          # wall-clock time of the last switch
        self.error = None

    async def apply(self, decision, reason):
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
            # Leave controller state as decided; the next threshold crossing retries.
            self.error = str(e)
            log.error("%s: actuator failed: %s", self.name, e)
            self.datalog.event("error", feature=self.name, message=str(e))

    async def feed(self, reading):
        values = {m: METRICS[m](reading) for m in self.ctl.metrics}
        decision = self.ctl.update(values)
        if decision is not None:
            await self.apply(decision, self.ctl.explain(decision))

    def snapshot(self):
        return {**self.ctl.snapshot(), "since": self.since, "dry_run": self.dry_run, "error": self.error}

    @property
    def on(self):
        return bool(self.ctl.on)


async def run(cfg):
    lcfg = cfg.get("log", {})
    datalog = DataLog(lcfg.get("directory", "data"), lcfg.get("keep_days", 14))
    sensor = make_sensor(cfg["sensor"])
    dcfg = cfg.get("display", {"type": "none"})
    display = make_display(dcfg)
    controls = [Control(c, datalog) for c in cfg.get("control", []) if c.pop("enabled", True)]
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
        ambient = AmbientLight(on_change=on_dark, **{k: v for k, v in acfg.items() if k != "enabled"})
        ambient_task = asyncio.create_task(ambient.run())

    wcfg = cfg.get("web", {})
    server = None
    if wcfg.get("enabled", True):
        server = await Web(datalog, state, wcfg.get("host", "0.0.0.0"), wcfg.get("port", 8788)).start()

    async def watchdog():
        while True:
            await asyncio.sleep(30)
            for c in controls:
                d = c.ctl.check_stale()
                if d is not None:
                    await c.apply(d, f"no sensor readings for {c.ctl.stale}s, failing safe")

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
