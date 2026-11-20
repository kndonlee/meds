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

    async def get(self):
        return None

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
        self.lock = asyncio.Lock()   # state checks and commands share one connection

    async def _connect(self):
        from msmart.device import AirConditioner as AC
        ac = AC(ip=self.cfg["ip"], device_id=self.cfg["device_id"], port=self.cfg.get("port", 6444))
        await ac.authenticate(self.cfg["token"], self.cfg["key"])
        await ac.get_capabilities()
        self.ac, self.AC = ac, AC

    async def get(self):
        """Current power state (None if unreachable)."""
        async with self.lock:
            return await self._get()

    async def _get(self):
        try:
            if self.ac is None:
                await self._connect()
            await self.ac.refresh()
            if not self.ac.online:
                raise RuntimeError("no response")
            return bool(self.ac.power_state)
        except Exception as e:
            log.warning("AC state read failed: %s", e)
            self.ac = None
            return None

    def _clamped_c(self):
        """Target in C as the unit takes it: 0.5 C steps within its range (this Toshiba: 16-30 C)."""
        lo = getattr(self.ac, "min_target_temperature", None) or 16
        hi = getattr(self.ac, "max_target_temperature", None) or 30
        return min(max(round(self.target_c * 2) / 2, lo), hi)

    @property
    def target_f(self):
        return round(self._clamped_c() * 9 / 5 + 32)

    async def adjust_target(self, steps):
        """Move the setpoint by `steps` x 0.5 C (about 1 F on the unit's display). Kept for later ON
        commands until restart; sent to the unit right away if it is running."""
        async with self.lock:
            before = self._clamped_c()
            self.target_c = before + 0.5 * steps
            after = self._clamped_c()
            self.target_c = after
            if after == before:
                return self.target_f
            try:
                if self.ac is None:
                    await self._connect()
                await self.ac.refresh()
                if not self.ac.online:
                    raise RuntimeError("no response")
                if self.ac.power_state:
                    self.ac.sound = self.beep
                    self.ac.target_temperature = after
                    await self.ac.apply()
            except Exception as e:
                self.ac = None
                raise RuntimeError(f"setpoint {self.target_f}F saved, but the unit did not take it: {e}")
            log.info("AC setpoint %.1f C (%d F)", after, self.target_f)
            return self.target_f

    async def set(self, on, attempts=3):
        async with self.lock:
            return await self._set(on, attempts)

    async def _set(self, on, attempts):
        """Send the command, then read the unit back; retry until it reports the requested state.

        msmart logs timeouts instead of raising, so `online` and a read-back are the only proof it worked.
        """
        last = "unknown"
        for attempt in range(1, attempts + 1):
            try:
                if self.ac is None:
                    await self._connect()
                await self.ac.refresh()
                if not self.ac.online:
                    raise RuntimeError("no response")
                # refresh() can report the unit's sound flag back as on; set it every time
                self.ac.sound = self.beep
                self.ac.power_state = on
                if on:
                    self.ac.operational_mode = self.AC.OperationalMode[self.mode]
                    self.ac.fan_speed = self.AC.FanSpeed[self.fan_speed]
                    self.ac.target_temperature = self._clamped_c()
                await self.ac.apply()
                await asyncio.sleep(2)
                await self.ac.refresh()
                if not self.ac.online:
                    raise RuntimeError("no response after command")
                if bool(self.ac.power_state) != on:
                    raise RuntimeError(f"unit still reports {'ON' if self.ac.power_state else 'off'}")
                log.info("AC %s (%s, fan %s), confirmed", "ON" if on else "OFF", self.mode.lower(),
                         self.fan_speed.lower())
                return
            except Exception as e:
                last = str(e)
                log.warning("AC command failed (attempt %d/%d): %s", attempt, attempts, e)
                self.ac = None
                await asyncio.sleep(3)
        raise RuntimeError(f"AC did not confirm {'ON' if on else 'OFF'}: {last}")


class KasadPlug:
    """A Kasa outlet through the local kasad daemon (~/repos/meds/kasa): GET /on|off/<alias>."""

    def __init__(self, alias, url="http://127.0.0.1:8787"):
        self.alias, self.url = alias, url.rstrip("/")

    async def get(self):
        import httpx
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                body = (await client.get(f"{self.url}/state/{self.alias}")).json()
            return body.get("state") == "on" if body.get("ok") else None
        except Exception as e:
            log.warning("plug state read failed: %s", e)
            return None

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
