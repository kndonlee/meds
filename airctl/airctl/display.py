"""Displays: show readings + feature states. Add new types to DISPLAYS."""

import asyncio
import logging
import math
import os
import sys
import time

log = logging.getLogger(__name__)

APP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GREEN, ORANGE, RED = (0, 220, 0), (255, 170, 0), (255, 0, 0)
LABEL = (110, 110, 110)
PROGRESS = (90, 90, 90)


def rgb(c):
    return f"{c[0]},{c[1]},{c[2]}"


class NoneDisplay:
    def __init__(self, **_ignored):
        pass

    def target_brightness(self, lux):
        """Brightness % for a lux level from the curve (log-lux interpolation, clamped at the ends)."""
        pts = self.curve
        if lux <= pts[0][0]:
            return round(pts[0][1])
        if lux >= pts[-1][0]:
            return round(pts[-1][1])
        for (l0, p0), (l1, p1) in zip(pts, pts[1:]):
            if l0 <= lux <= l1:
                f = (math.log10(lux) - math.log10(l0)) / (math.log10(l1) - math.log10(l0))
                return round(p0 + f * (p1 - p0))

    async def set_lux(self, lux):
        """Called on every ambient reading: adjust brightness toward the curve (not while dark)."""
        if not self.curve or lux is None or lux <= 0:
            return
        target = self.target_brightness(lux)
        if abs(target - self.brightness) < self.step:
            self._first_lux = False
            return
        delta = target - self.brightness if self._first_lux else max(-self.ramp, min(self.ramp, target - self.brightness))
        self._first_lux = False
        self.brightness = int(max(1, min(100, self.brightness + delta)))
        if self.dark:
            return  # remembered; applied when the room gets light again
        try:
            await self._send(f"brightness {self.brightness}")
            log.info("tivoo brightness %d%% (%.1f lux, target %d%%)", self.brightness, lux, target)
        except Exception as e:
            log.warning("tivoo brightness command failed: %s", e)

    async def set_dark(self, dark):
        pass

    async def set_lux(self, lux):
        pass

    async def show(self, reading, states):
        pass

    async def close(self):
        pass


class TivooDisplay:
    """Rotating single-metric pages on the Tivoo (limits LED burn-in).

    Each page shows for `page_seconds`: label on top, value in double-height digits. A dim dot walks
    across the top row during the page (the screen is about to change when it reaches the right),
    and per-feature status dots sit at the top-right. Drives `tivoo.py stream` as a subprocess
    (IOBluetooth needs its own run loop/process).
    """

    # Status dots while a feature is on: name -> [x, y, [r, g, b]] (top-right corner).
    DEFAULT_DOTS = {"ventilation": [14, 0, [0, 255, 120]], "cooling": [15, 0, [0, 120, 255]]}
    PROGRESS_SPAN = 12          # progress dot walks x = 0..11, leaving room for status dots

    def __init__(self, mac, channel=1, colors=(1100, 1500), celsius=False, dots=None,
                 pages=("co2", "temp", "humidity"), page_seconds=5, frame_seconds=0.5, battery_warn_below=15,
                 brightness=100, auto_brightness=None, brightness_step=5, brightness_ramp=10):
        """colors = (orange_from, red_from) in ppm: green below the first, red at/above the second.
        pages: any of co2, temp, humidity, pressure, battery (battery is also added automatically
        when it drops below battery_warn_below %).
        brightness: fixed level, or the fallback until a lux reading arrives when auto_brightness is set.
        auto_brightness: [[lux, percent], ...] curve, interpolated on a log-lux scale; changes smaller
        than brightness_step are ignored and each update moves at most brightness_ramp points."""
        self.mac, self.channel = mac, channel
        self.orange_from, self.red_from = colors
        self.celsius = celsius
        self.dots = dots if dots is not None else self.DEFAULT_DOTS
        self.pages = list(pages)
        self.page_seconds = page_seconds
        self.frame_seconds = frame_seconds
        self.battery_warn = battery_warn_below
        self.proc = None
        self.reading = None
        self.states = {}
        self.ticker = None
        self.brightness = brightness       # level currently applied (or to restore after dark)
        self.curve = sorted((float(l), float(p)) for l, p in auto_brightness) if auto_brightness else None
        self.step, self.ramp = brightness_step, brightness_ramp
        self._first_lux = True
        self.dark = False           # set by set_dark(): screen off, no frames sent

    async def _ensure(self):
        if self.proc and self.proc.returncode is None:
            return
        if self.proc:
            log.warning("tivoo display exited (%s); restarting", self.proc.returncode)
            await asyncio.sleep(5)
        self.proc = await asyncio.create_subprocess_exec(
            sys.executable, os.path.join(APP_DIR, "tivoo.py"), "--channel", str(self.channel),
            "stream", self.mac, stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.DEVNULL)
        # The Tivoo keeps its last brightness across reconnects; apply ours (matters for a fixed level).
        self.proc.stdin.write(f"brightness {0 if self.dark else self.brightness}\n".encode())
        await self.proc.stdin.drain()
        log.info("tivoo link starting (connecting), brightness %d%%", 0 if self.dark else self.brightness)

    def page_content(self, page, r):
        """(label, value, color) for a page, or None if the reading lacks it."""
        if page == "co2":
            co2 = min(r.co2, 9999)
            c = RED if co2 >= self.red_from else ORANGE if co2 >= self.orange_from else GREEN
            return "CO2", str(co2), c
        if page == "temp":
            t = r.temp_c if self.celsius else r.temp_f
            return None if t is None else ("TEMP", f"{round(t)}{'C' if self.celsius else 'F'}", (220, 220, 220))
        if page == "humidity":
            return None if r.humidity is None else ("RH", f"{min(round(r.humidity), 99)}%", (0, 140, 255))
        if page == "pressure":
            return None if r.pressure_hpa is None else ("HPA", str(round(r.pressure_hpa)), (180, 120, 255))
        if page == "battery":
            if r.battery is None:
                return None
            return "BAT", f"{min(r.battery, 99)}%", RED if r.battery < self.battery_warn else (220, 200, 0)
        return None

    def active_pages(self, r):
        pages = list(self.pages)
        if r.battery is not None and r.battery < self.battery_warn and "battery" not in pages:
            pages.append("battery")
        return [p for p in pages if self.page_content(p, r)]

    def frame(self, now=None):
        """Stream command for the current moment."""
        now = time.time() if now is None else now
        r = self.reading
        pages = self.active_pages(r)
        slot = int(now // self.page_seconds)
        page = pages[slot % len(pages)]
        label, value, color = self.page_content(page, r)
        progress = (now % self.page_seconds) / self.page_seconds
        parts = [f"{label}:{rgb(LABEL)}", f"{value}:{rgb(color)}",
                 f"@{min(int(progress * self.PROGRESS_SPAN), self.PROGRESS_SPAN - 1)},0:{rgb(PROGRESS)}"]
        for name, on in self.states.items():
            if on and name in self.dots:
                x, y, c = self.dots[name]
                parts.append(f"@{x},{y}:{rgb(c)}")
        return "page " + " ".join(parts) + "\n"

    async def _tick(self):
        # Frames aligned to the wall clock so pages change exactly on page_seconds boundaries.
        interval = self.frame_seconds
        while True:
            await asyncio.sleep(interval - (time.time() % interval) + 0.01)
            if self.reading is None or self.dark:
                continue
            try:
                await self._ensure()
                self.proc.stdin.write(self.frame().encode())
                await self.proc.stdin.drain()
            except (BrokenPipeError, ConnectionResetError) as e:
                log.warning("tivoo display write failed: %s", e)
            except Exception as e:
                log.warning("tivoo frame error: %s", e)

    async def _send(self, *lines):
        await self._ensure()
        self.proc.stdin.write("".join(f"{l}\n" for l in lines).encode())
        await self.proc.stdin.drain()

    def target_brightness(self, lux):
        """Brightness % for a lux level from the curve (log-lux interpolation, clamped at the ends)."""
        pts = self.curve
        if lux <= pts[0][0]:
            return round(pts[0][1])
        if lux >= pts[-1][0]:
            return round(pts[-1][1])
        for (l0, p0), (l1, p1) in zip(pts, pts[1:]):
            if l0 <= lux <= l1:
                f = (math.log10(lux) - math.log10(l0)) / (math.log10(l1) - math.log10(l0))
                return round(p0 + f * (p1 - p0))

    async def set_lux(self, lux):
        """Called on every ambient reading: adjust brightness toward the curve (not while dark)."""
        if not self.curve or lux is None or lux <= 0:
            return
        target = self.target_brightness(lux)
        if abs(target - self.brightness) < self.step:
            self._first_lux = False
            return
        delta = target - self.brightness if self._first_lux else max(-self.ramp, min(self.ramp, target - self.brightness))
        self._first_lux = False
        self.brightness = int(max(1, min(100, self.brightness + delta)))
        if self.dark:
            return  # remembered; applied when the room gets light again
        try:
            await self._send(f"brightness {self.brightness}")
            log.info("tivoo brightness %d%% (%.1f lux, target %d%%)", self.brightness, lux, target)
        except Exception as e:
            log.warning("tivoo brightness command failed: %s", e)

    async def set_dark(self, dark):
        """Dark: black frame + brightness 0, stop sending frames. Light: restore brightness, resume."""
        self.dark = dark
        try:
            if dark:
                await self._send("black", "brightness 0")
            else:
                await self._send(f"brightness {self.brightness}")
                if self.reading is not None:
                    await self._send(self.frame().strip())
        except Exception as e:
            log.warning("tivoo dark-mode command failed: %s", e)

    async def show(self, reading, states):
        self.reading, self.states = reading, dict(states)
        if self.ticker is None:
            self.ticker = asyncio.create_task(self._tick())

    async def close(self):
        if self.ticker:
            self.ticker.cancel()
        if self.proc and self.proc.returncode is None:
            self.proc.stdin.close()
            await self.proc.wait()


DISPLAYS = {"none": NoneDisplay, "tivoo": TivooDisplay}


def make_display(cfg):
    cfg = dict(cfg)
    kind = cfg.pop("type")
    if "colors" in cfg:
        cfg["colors"] = tuple(cfg["colors"])
    if "pages" in cfg:
        cfg["pages"] = tuple(cfg["pages"])
    return DISPLAYS[kind](**cfg)
