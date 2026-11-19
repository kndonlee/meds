"""Control logic, independent of sensors and devices.

A Controller owns one device and any number of Conditions. Each Condition is a hysteresis band on one
metric (CO2 ppm, temperature, ...) that *demands* the device on. The device is:

  - turned ON when any condition demands it,
  - kept ON while any condition still demands it,
  - turned OFF only when no condition demands it,

subject to minimum on/off times. Example: cooling turns on at CO2 >= 1350 OR temp >= 78F, and runs at
least 15 minutes until CO2 <= 900 AND temp <= 75F.
"""

import time
from collections import deque


def _fmt(v):
    return "?" if v is None else f"{v:.0f}" if abs(v) >= 100 else f"{v:.1f}"


class Condition:
    """Hysteresis band on one metric: demand starts at >= on_above, ends at <= off_below."""

    def __init__(self, metric, on_above, off_below, smooth_seconds=0):
        if off_below >= on_above:
            raise ValueError(f"{metric}: off_below ({off_below}) must be lower than on_above ({on_above})")
        self.metric, self.on_above, self.off_below = metric, on_above, off_below
        self.smooth = smooth_seconds
        self.samples = deque()
        self.demand = False
        self.level = None

    def update(self, value, now):
        self.samples.append((now, value))
        if self.smooth:
            while now - self.samples[0][0] > self.smooth:
                self.samples.popleft()
        else:
            while len(self.samples) > 1:
                self.samples.popleft()
        self.level = sum(v for _, v in self.samples) / len(self.samples)
        if self.level >= self.on_above:
            self.demand = True
        elif self.level <= self.off_below:
            self.demand = False
        # in between: keep the current demand (hysteresis); starts False
        return self.demand

    def describe(self):
        lvl = "?" if self.level is None else f"{self.level:.0f}" if self.level >= 100 else f"{self.level:.1f}"
        flag = "*" if self.demand else ""
        return f"{self.metric}={lvl}{flag} [on>={self.on_above} off<={self.off_below}]"


class Controller:
    def __init__(self, conditions, min_on_seconds=900, min_off_seconds=600, stale_seconds=900):
        if not conditions:
            raise ValueError("need at least one condition")
        self.conditions = conditions
        self.min_on, self.min_off, self.stale = min_on_seconds, min_off_seconds, stale_seconds
        self.on = None              # unknown until synced from the device or the first reading
        self.changed_at = -1e9
        self.last_reading_at = None
        self._seed_from_device_on = False
        self.manual_until = None    # monotonic time until which a manual on/off overrides automation

    def manual(self, on, hold_seconds, now=None):
        """Someone switched the device by hand: adopt it and keep automation off it for hold_seconds."""
        now = time.monotonic() if now is None else now
        self.on, self.changed_at = bool(on), now
        self.manual_until = now + hold_seconds
        self._seed_from_device_on = False

    def manual_remaining(self, now=None):
        now = time.monotonic() if now is None else now
        return 0 if self.manual_until is None else max(0, int(self.manual_until - now))

    def sync(self, device_on, now=None):
        """Adopt the device's real state at startup (so a restart mid-run keeps managing it).

        If the device is already on, conditions whose first reading is above off_below are treated as
        demanding (the device is mid-run), so it stays on until they fall to off_below. The min-on
        timer restarts from now.
        """
        if self.on is not None or device_on is None:
            return
        now = time.monotonic() if now is None else now
        self.on = bool(device_on)
        if self.on:
            self.changed_at = now
            self._seed_from_device_on = True

    @property
    def metrics(self):
        return [c.metric for c in self.conditions]

    def reasons(self):
        """Conditions currently demanding on."""
        return [c for c in self.conditions if c.demand]

    def update(self, values, now=None):
        """values: {metric: value}. Returns True/False when the device should change, else None.

        Commands are only issued on transitions, so manual changes (remote/app) stick until the next one.
        """
        now = time.monotonic() if now is None else now
        self.last_reading_at = now
        for c in self.conditions:
            if values.get(c.metric) is not None:
                c.update(values[c.metric], now)
        if self._seed_from_device_on:
            self._seed_from_device_on = False
            for c in self.conditions:
                if c.level is not None and c.level > c.off_below:
                    c.demand = True
        want = bool(self.reasons())
        if self.manual_until is not None:
            if now < self.manual_until:
                return None
            self.manual_until = None

        if self.on is None:
            # Startup: act only if something already demands on. Otherwise assume off silently
            # (don't override a device someone turned on by hand) and don't start the min-off timer.
            self.on = want
            if want:
                self.changed_at = now
                return True
            return None

        if want == self.on:
            return None
        held = now - self.changed_at
        if (self.on and held < self.min_on) or (not self.on and held < self.min_off):
            return None
        self.on, self.changed_at = want, now
        return want

    def check_stale(self, now=None):
        """Returns False (turn off) once if readings stopped arriving while on."""
        now = time.monotonic() if now is None else now
        if self.on and self.last_reading_at is not None and now - self.last_reading_at > self.stale:
            self.on, self.changed_at = False, now
            for c in self.conditions:
                c.demand = False
            return False
        return None

    def explain(self, turned_on):
        """Reason for a transition, e.g. 'co2 1362 >= 1350' or 'co2 884 <= 900, temp_f 74.1 <= 75'."""
        if turned_on:
            parts = [f"{c.metric} {_fmt(c.level)} >= {c.on_above}" for c in self.conditions if c.demand]
        else:
            parts = [f"{c.metric} {_fmt(c.level)} <= {c.off_below}" for c in self.conditions if c.level is not None]
        return ", ".join(parts)

    def snapshot(self, now=None):
        """Machine-readable state for status.json / the dashboard."""
        now = time.monotonic() if now is None else now
        held = now - self.changed_at
        lock = self.min_on if self.on else self.min_off
        return {
            "on": bool(self.on),
            "hold_remaining_s": int(max(0, lock - held)) if self.changed_at > 0 else 0,
            "min_on_s": self.min_on, "min_off_s": self.min_off,
            "manual_remaining_s": self.manual_remaining(now),
            "conditions": [{"metric": c.metric, "level": None if c.level is None else round(c.level, 1),
                            "demand": c.demand, "on_above": c.on_above, "off_below": c.off_below}
                           for c in self.conditions],
        }

    def status(self, now=None):
        now = time.monotonic() if now is None else now
        state = "ON" if self.on else "off"
        held = now - self.changed_at
        lock = self.min_on if self.on else self.min_off
        hold = f", held {int(lock - held)}s more" if self.on is not None and held < lock else ""
        if self.manual_remaining(now):
            hold = f", manual for {self.manual_remaining(now) // 60}m more"
        return f"{state}{hold}; " + "; ".join(c.describe() for c in self.conditions)
