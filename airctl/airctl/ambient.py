"""Room-light detection from the Mac's ambient light sensor (no special permissions needed).

Reads the built-in display's `AmbientBrightness` (lux as 16.16 fixed point, e.g. 217245 -> 3.3) from the
IORegistry, falling back to the integer `CurrentLux` from the ALS driver. On Kimberly's iMac (M3) at
night: lights on ~3.3, lights off with the screen on ~1.4.

`dark` turns True once lux stays <= dark_below for dark_after_seconds, and back to False once lux stays
>= light_above for light_after_seconds (hysteresis + dwell so shadows/passers-by don't flicker it).
"""

import asyncio
import logging
import re
import time

log = logging.getLogger(__name__)


async def read_lux():
    async def ioreg(*args):
        proc = await asyncio.create_subprocess_exec("/usr/sbin/ioreg", *args, stdout=asyncio.subprocess.PIPE,
                                                    stderr=asyncio.subprocess.DEVNULL)
        out, _ = await proc.communicate()
        return out.decode(errors="replace")

    out = await ioreg("-r", "-c", "AppleCLCD2", "-k", "AmbientBrightness", "-w0", "-d1")
    vals = [int(v) for v in re.findall(r'"AmbientBrightness" = (\d+)', out)]
    if vals:
        return vals[0] / 65536
    out = await ioreg("-r", "-c", "AppleSPUHIDDriver", "-k", "CurrentLux", "-w0")
    m = re.search(r'"CurrentLux" = (\d+)', out)
    return float(m.group(1)) if m else None


class AmbientLight:
    def __init__(self, dark_below=2.0, light_above=2.6, dark_after_seconds=120, light_after_seconds=10,
                 poll_seconds=5, on_change=None, on_reading=None):
        if dark_below >= light_above:
            raise ValueError("dark_below must be lower than light_above")
        self.dark_below, self.light_above = dark_below, light_above
        self.dark_after, self.light_after = dark_after_seconds, light_after_seconds
        self.poll = poll_seconds
        self.on_change = on_change
        self.on_reading = on_reading
        self.lux = None
        self.dark = False
        self._candidate_since = None

    def update(self, lux, now):
        """Feed one reading; returns the new `dark` value if it changed, else None."""
        self.lux = lux
        if lux is None:
            return None
        crossing = (not self.dark and lux <= self.dark_below) or (self.dark and lux >= self.light_above)
        if not crossing:
            self._candidate_since = None
            return None
        if self._candidate_since is None:
            self._candidate_since = now
        needed = self.light_after if self.dark else self.dark_after
        if now - self._candidate_since >= needed:
            self.dark = not self.dark
            self._candidate_since = None
            return self.dark
        return None

    async def run(self):
        log.info("ambient light: dark <= %.1f lux for %ss, light >= %.1f lux for %ss",
                 self.dark_below, self.dark_after, self.light_above, self.light_after)
        while True:
            try:
                lux = await read_lux()
                changed = self.update(lux, time.monotonic())
                if changed is not None:
                    log.info("room is now %s (%.1f lux)", "DARK" if changed else "light", lux)
                    if self.on_change:
                        await self.on_change(changed, lux)
                if self.on_reading and lux is not None:
                    await self.on_reading(lux)
            except Exception as e:
                log.debug("ambient read failed: %s", e)
            await asyncio.sleep(self.poll)
