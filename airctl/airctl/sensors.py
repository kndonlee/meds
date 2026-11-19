"""Sensors: async iterators of Reading. Add new types (e.g. an ESP32 over MQTT/HTTP) to SENSORS."""

import asyncio
import logging

from . import Reading

log = logging.getLogger(__name__)


class AranetSensor:
    """Passively reads an Aranet4's BLE advertisements (needs Smart Home integration enabled)."""

    def __init__(self, name="Aranet4"):
        self.name_filter = name.lower()

    async def readings(self):
        from aranet4.client import Aranet4Scanner

        queue: asyncio.Queue = asyncio.Queue()
        last_ago = None

        def on_adv(adv):
            nonlocal last_ago
            r = adv.readings
            if not r or r.co2 <= 0:
                return
            if self.name_filter not in (adv.device.name or "").lower():
                return
            # Advertisements repeat every few seconds with the same measurement; `ago` (seconds since
            # it was taken) only goes *down* when a new measurement lands.
            is_new = last_ago is None or r.ago < last_ago
            last_ago = r.ago
            if is_new:
                queue.put_nowait(Reading(co2=r.co2, temp_c=r.temperature, humidity=r.humidity,
                                         pressure_hpa=r.pressure, source=adv.device.name or "aranet"))

        scanner = Aranet4Scanner(on_adv)
        await scanner.start()
        log.info("listening for Aranet advertisements (filter: %s)", self.name_filter)
        try:
            while True:
                yield await queue.get()
        finally:
            await scanner.stop()


SENSORS = {"aranet": AranetSensor}


def make_sensor(cfg):
    cfg = dict(cfg)
    kind = cfg.pop("type")
    return SENSORS[kind](**cfg)
