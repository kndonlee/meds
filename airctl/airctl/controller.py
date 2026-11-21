"""Control logic, independent of sensors and devices.

A Controller owns one device and any number of Conditions. Each Condition is a hysteresis band on one
metric (CO2 ppm, temperature, ...) that *demands* the device on. The device is:

  - turned ON when any condition demands it,
  - kept ON while any condition still demands it,
  - turned OFF only when no condition demands it,

subject to minimum on/off times, manual runs/holds and AUTO/MANUAL mode (see Controller). Example: cooling turns on at CO2 >= 1350 OR temp >= 78F, and runs at
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
    """One device's state machine.

    AUTO mode (default):
      - conditions switch it: ON when any demands, OFF when none do (min on/off times apply)
      - manual ON (Stream Deck, remote, ...) starts a *manual run*: stays on, ignoring the conditions,
        until temp_f <= run_until_temp_f (and at least run_min_seconds), then OFF and back to conditions
      - manual OFF (incl. the unit stopping itself): off, and conditions can't switch it for off_hold_seconds
      - no sensor readings for stale_seconds: switches to MANUAL ("no_sensor") and turns the device off;
        the first new reading returns it to AUTO
    MANUAL mode: automation never switches the device; manual on/off is simply recorded.
    """

    def __init__(self, conditions, min_on_seconds=900, min_off_seconds=600, stale_seconds=900,
                 run_until_temp_f=None, run_min_seconds=600, off_hold_seconds=600):
        if not conditions:
            raise ValueError("need at least one condition")
        self.conditions = conditions
        self.min_on, self.min_off, self.stale = min_on_seconds, min_off_seconds, stale_seconds
        self.run_until, self.run_min, self.off_hold = run_until_temp_f, run_min_seconds, off_hold_seconds
        self.on = None              # unknown until synced from the device or the first reading
        self.changed_at = -1e9
        self.last_reading_at = time.monotonic()   # a sensor that never reports also counts as quiet
        self._seed_from_device_on = False
        self.mode, self.mode_reason = "auto", None   # "auto" | "manual"; reason "user" | "no_sensor"
        self.run_since = None       # monotonic start of a manual run (AUTO mode, after a manual ON)
        self.manual_until = None    # monotonic end of the hold after a manual OFF
        self.temp_f = None
        self.last_explain = ""

    # --- manual input -------------------------------------------------------------------------------

    def manual(self, on, now=None):
        """Someone switched the device (Stream Deck, remote, the unit itself): adopt it."""
        now = time.monotonic() if now is None else now
        self.on, self.changed_at = bool(on), now
        self._seed_from_device_on = False
        self.run_since = self.manual_until = None
        if self.mode == "manual":
            return
        if on and self.run_until is not None:
            self.run_since = now
        else:
            self.manual_until = now + self.off_hold
            self._align_demand()

    def set_mode(self, mode, reason="user", now=None):
        """Switch AUTO/MANUAL. Never switches the device by itself; returns True if the mode changed.
        Entering AUTO re-reads the bands from the device's state (on and above off_below keeps running,
        off and below on_above stays off); call decide() afterwards to act on it."""
        if mode not in ("auto", "manual"):
            raise ValueError("mode must be auto or manual")
        reason = reason if mode == "manual" else None
        if (mode, reason) == (self.mode, self.mode_reason):
            return False
        self.mode, self.mode_reason = mode, reason
        self.run_since = self.manual_until = None
        if mode == "auto":
            self._align_demand()
        return True

    def _align_demand(self):
        """Band state matching the device's current state, for the levels last seen."""
        for c in self.conditions:
            if c.level is not None:
                c.demand = c.level > c.off_below if self.on else c.level >= c.on_above

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
            self._seed_from_device_on = self.run_since is None
        else:
            self.run_since = None

    @property
    def metrics(self):
        return [c.metric for c in self.conditions]

    def reasons(self):
        """Conditions currently demanding on."""
        return [c for c in self.conditions if c.demand]

    # --- automation ---------------------------------------------------------------------------------

    def update(self, values, now=None):
        """values: {metric: value} (temp_f is also used to end a manual run).
        Returns True/False when the device should change, else None; last_explain says why."""
        now = time.monotonic() if now is None else now
        self.last_reading_at = now
        for c in self.conditions:
            if values.get(c.metric) is not None:
                c.update(values[c.metric], now)
        if values.get("temp_f") is not None:
            self.temp_f = values["temp_f"]
        if self._seed_from_device_on:
            self._seed_from_device_on = False
            for c in self.conditions:
                if c.level is not None and c.level > c.off_below:
                    c.demand = True
        return self.decide(now)

    def decide(self, now=None):
        """Apply the AUTO rules to the latest levels. Commands are only issued on transitions."""
        now = time.monotonic() if now is None else now
        self.last_explain = ""
        if self.mode != "auto":
            return None
        if self.run_since is not None:
            if not self.on:
                self.run_since = None
            elif (self.temp_f is not None and self.temp_f <= self.run_until
                  and now - self.run_since >= self.run_min):
                self.run_since = None
                self.on, self.changed_at = False, now
                self._align_demand()
                self.last_explain = f"manual run done: temp_f {self.temp_f:.1f} <= {self.run_until}"
                return False
            else:
                return None
        if self.manual_until is not None:
            if now < self.manual_until:
                return None
            self.manual_until = None

        want = bool(self.reasons())
        if self.on is None:
            # Startup: act only if something already demands on. Otherwise assume off silently
            # (don't override a device someone turned on by hand) and don't start the min-off timer.
            self.on = want
            if want:
                self.changed_at = now
                self.last_explain = self.explain(True)
                return True
            return None

        if want == self.on:
            return None
        held = now - self.changed_at
        if (self.on and held < self.min_on) or (not self.on and held < self.min_off):
            return None
        self.on, self.changed_at = want, now
        self.last_explain = self.explain(want)
        return want

    def check_stale(self, now=None):
        """In AUTO, once readings stop for stale_seconds: switch to MANUAL (no_sensor).
        Returns None (nothing to do), or True if the device was on and must be turned off."""
        now = time.monotonic() if now is None else now
        if self.mode != "auto" or not self.stale or now - self.last_reading_at <= self.stale:
            return None
        was_on = bool(self.on)
        self.set_mode("manual", "no_sensor")
        if was_on:
            self.on, self.changed_at = False, now
        for c in self.conditions:
            c.demand = False
        return was_on

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
            "mode": self.mode, "mode_reason": self.mode_reason,
            "manual_run": self.run_since is not None,
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
        if self.mode == "manual":
            hold = f", MANUAL mode ({'no sensor' if self.mode_reason == 'no_sensor' else 'user'})"
        elif self.run_since is not None:
            hold = f", manual run until temp_f <= {self.run_until}"
        elif self.manual_remaining(now):
            hold = f", manual off for {self.manual_remaining(now) // 60}m more"
        return f"{state}{hold}; " + "; ".join(c.describe() for c in self.conditions)
