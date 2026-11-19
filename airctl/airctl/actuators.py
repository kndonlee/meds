"""Actuators: devices a control loop switches on/off. Each has `async set(on: bool)`.
Add new types to ACTUATORS."""

import asyncio
import json
import logging
import os

log = logging.getLogger(__name__)


class NoneActuator:
    """Dry run: logs what would happen."""

    def __init__(self, label="device"):
        self.label = label

    async def set(self, on):
        log.info("[dry run] would turn %s %s", self.label, "ON" if on else "OFF")


class MideaAC:
    """Midea-based AC (e.g. Toshiba portable) via msmart-ng, fully local.

    Credentials come from ac.json written by ac_setup.py. Note: on single-hose portables only COOL
    (maybe DRY) exhausts room air, so ventilating with the AC also cools.
    """

    def __init__(self, credentials="ac.json", mode="cool", fan_speed="auto", target_temp_f=72, beep=False):
        self.beep = beep
        path = credentials if os.path.isabs(credentials) else os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))), credentials)
        with open(path) as f:
            self.cfg = json.load(f)
        self.mode, self.fan_speed, self.target_c = mode.upper(), fan_speed.upper(), (target_temp_f - 32) * 5 / 9
        self.ac = None

    async def _connect(self):
        from msmart.device import AirConditioner as AC
        ac = AC(ip=self.cfg["ip"], device_id=self.cfg["device_id"], port=self.cfg.get("port", 6444))
        await ac.authenticate(self.cfg["token"], self.cfg["key"])
        await ac.get_capabilities()
        self.ac, self.AC = ac, AC

    async def set(self, on):
        for attempt in (1, 2):
            try:
                if self.ac is None:
                    await self._connect()
                await self.ac.refresh()
                # refresh() can report the unit's sound flag back as on; set it every time
                self.ac.sound = self.beep
                self.ac.power_state = on
                if on:
                    self.ac.operational_mode = self.AC.OperationalMode[self.mode]
                    self.ac.fan_speed = self.AC.FanSpeed[self.fan_speed]
                    # clamp to what the unit accepts (this Toshiba: 16-30 C)
                    lo = getattr(self.ac, "min_target_temperature", None) or 16
                    hi = getattr(self.ac, "max_target_temperature", None) or 30
                    self.ac.target_temperature = min(max(round(self.target_c * 2) / 2, lo), hi)
                await self.ac.apply()
                log.info("AC %s (%s, fan %s)", "ON" if on else "OFF", self.mode.lower(), self.fan_speed.lower())
                return
            except Exception as e:
                log.warning("AC command failed (attempt %d): %s", attempt, e)
                self.ac = None
        raise RuntimeError("AC unreachable")


class KasadPlug:
    """A Kasa outlet through the local kasad daemon (~/repos/meds/kasa): GET /on|off/<alias>."""

    def __init__(self, alias, url="http://127.0.0.1:8787"):
        self.alias, self.url = alias, url.rstrip("/")

    async def set(self, on):
        import httpx
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.get(f"{self.url}/{'on' if on else 'off'}/{self.alias}")
            body = r.json()
        if not body.get("ok"):
            raise RuntimeError(f"kasad: {body.get('error')}")
        log.info("plug %s %s", self.alias, body.get("state"))


ACTUATORS = {"none": NoneActuator, "midea_ac": MideaAC, "kasad": KasadPlug}


def make_actuator(cfg, label="device"):
    cfg = dict(cfg)
    kind = cfg.pop("type")
    if cfg.pop("dry_run", False) or kind == "none":
        return NoneActuator(f"{label} ({kind})")
    return ACTUATORS[kind](**cfg)
