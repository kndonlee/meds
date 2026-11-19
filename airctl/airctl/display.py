"""Displays: show readings + ventilation state. Add new types to DISPLAYS."""

import asyncio
import logging
import os
import sys

log = logging.getLogger(__name__)

POC_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GREEN, ORANGE, RED = (0, 220, 0), (255, 170, 0), (255, 0, 0)


class NoneDisplay:
    def __init__(self, **_ignored):
        pass

    async def show(self, reading, states):
        pass

    async def close(self):
        pass


class TivooDisplay:
    """Drives `tivoo.py stream` as a subprocess (IOBluetooth needs its own run loop/process)."""

    # Status dots for control loops, by name: (x, y, color). Bottom corners are free next to "43%".
    DEFAULT_DOTS = {"ventilation": [0, 15, [0, 255, 120]], "cooling": [15, 15, [0, 120, 255]]}

    def __init__(self, mac, channel=1, colors=(1100, 1500), celsius=False, dots=None):
        """colors = (orange_from, red_from) in ppm: green below the first, red at/above the second."""
        self.mac, self.channel = mac, channel
        self.orange_from, self.red_from = colors
        self.celsius = celsius
        self.dots = dots if dots is not None else self.DEFAULT_DOTS
        self.proc = None

    async def _ensure(self):
        if self.proc and self.proc.returncode is None:
            return
        if self.proc:
            log.warning("tivoo display exited (%s); restarting", self.proc.returncode)
            await asyncio.sleep(5)
        self.proc = await asyncio.create_subprocess_exec(
            sys.executable, os.path.join(POC_DIR, "tivoo.py"), "--channel", str(self.channel),
            "stream", self.mac, stdin=asyncio.subprocess.PIPE)

    def format(self, reading, states):
        co2 = min(reading.co2, 9999)
        c = RED if co2 >= self.red_from else ORANGE if co2 >= self.orange_from else GREEN
        parts = [f"{co2}:{c[0]},{c[1]},{c[2]}"]
        temp = reading.temp_c if self.celsius else reading.temp_f
        if temp is not None:
            parts.append(f"{round(temp)}{'C' if self.celsius else 'F'}:220,220,220")
        if reading.humidity is not None:
            parts.append(f"{min(round(reading.humidity), 99)}%:0,140,255")
        for name, on in states.items():
            if on and name in self.dots:
                x, y, (r, g, b) = self.dots[name]
                parts.append(f"@{x},{y}:{r},{g},{b}")
        return "lines " + " ".join(parts) + "\n"

    async def show(self, reading, states):
        try:
            await self._ensure()
            self.proc.stdin.write(self.format(reading, states).encode())
            await self.proc.stdin.drain()
        except (BrokenPipeError, ConnectionResetError) as e:
            log.warning("tivoo display write failed: %s", e)

    async def close(self):
        if self.proc and self.proc.returncode is None:
            self.proc.stdin.close()
            await self.proc.wait()


DISPLAYS = {"none": NoneDisplay, "tivoo": TivooDisplay}


def make_display(cfg):
    cfg = dict(cfg)
    kind = cfg.pop("type")
    if "colors" in cfg:
        cfg["colors"] = tuple(cfg["colors"])
    return DISPLAYS[kind](**cfg)
