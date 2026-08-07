#!/usr/bin/env python3
"""Motion Blinds / Connector shade control over the local LAN.

The Connector app is one of several front ends (Motion Blinds, Brel Home,
Bloc Blinds, Gaviota) for the Coulisse/Dooya bridge, which exposes a JSON-over-
UDP API on port 32100. Same idea as kasad's Kasa support: talk to the hardware
directly instead of round-tripping through a vendor cloud.

Two quirks of this bridge, both established by probing real hardware:

  * It answers UNICAST only. Broadcast and multicast GetDeviceList get no
    reply, so finding the bridge means sweeping the subnet -- which is cheap
    (254 datagrams in ~10ms) and doubles as MAC-based relocation, exactly like
    the Kasa strips.

  * ReadDevice needs no credentials at all; only WriteDevice does. Positions
    and battery can be polled with nothing configured, so a missing key
    degrades to read-only rather than to nothing.

Positions follow the protocol's convention: 0 = fully open, 100 = fully closed.
"""

import asyncio
import json
import logging
import re
import socket
import time

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

log = logging.getLogger("kasad.blinds")

PORT = 32100
BRIDGE_TYPE = "02000001"
TIMEOUT = 3.0

# Motion Blinds "operation" verbs for WriteDevice.
OP_CLOSE, OP_OPEN, OP_STOP = 0, 1, 2


def norm_mac(mac):
    return re.sub(r"[^0-9a-f]", "", (mac or "").lower())


def _msg_id():
    return time.strftime("%Y%m%d%H%M%S") + "000"


# Recharge below this fraction. 27% on a 2-cell pack is ~6.8V, i.e. 3.4V per
# cell -- the point where the Li-ion discharge curve turns steep and a motor
# can start failing to finish a full travel.
LOW_BATTERY_PERCENT = 27


def battery_percent(voltage):
    """Voltage -> percent, matching the reference motionblinds implementation.

    The pack size is inferred from the voltage range, since the bridge reports
    volts and never says which pack is fitted:

        2 cell   6.2 - 8.4 V     (what these shades use)
        3 cell  10.27 - 12.34 V
        4 cell  14.6 - 16.8 V

    Readings taken while a motor is running sag under load and read low.
    """
    if voltage is None or voltage <= 0.0:
        return None
    if voltage >= 100.0:
        return None                       # mains-powered motor
    if voltage <= 9.4:
        pct = (voltage - 6.2) * 100 / (8.4 - 6.2)
    elif voltage <= 13.6:
        pct = (voltage - 10.27) * 100 / (12.34 - 10.27)
    elif voltage <= 19.0:
        pct = (voltage - 14.6) * 100 / (16.8 - 14.6)
    else:
        return None
    return max(0, min(100, round(pct)))


def _subnet_hosts():
    """Every address in the local /24, for the unicast sweep."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))          # routing lookup, no packets
        ip = sock.getsockname()[0]
    except Exception:
        return []
    finally:
        sock.close()
    prefix = ip.rsplit(".", 1)[0]
    return ["%s.%d" % (prefix, i) for i in range(1, 255)]


# ------------------------------------------------------------------ transport

def _request_sync(host, payload, timeout=TIMEOUT):
    """One request/response exchange. Blocking; callers use asyncio.to_thread."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    try:
        sock.sendto(json.dumps(payload).encode(), (host, PORT))
        while True:
            data, addr = sock.recvfrom(65535)
            if addr[0] != host:
                continue
            return json.loads(data.decode())
    finally:
        sock.close()


def _sweep_sync(timeout=TIMEOUT):
    """Unicast GetDeviceList to the whole /24. Returns {mac: (ip, reply)}."""
    payload = {"msgType": "GetDeviceList", "msgID": _msg_id()}
    blob = json.dumps(payload).encode()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    found = {}
    try:
        for host in _subnet_hosts():
            try:
                sock.sendto(blob, (host, PORT))
            except Exception:
                pass
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                data, addr = sock.recvfrom(65535)
            except socket.timeout:
                break
            except Exception:
                break
            try:
                reply = json.loads(data.decode())
            except Exception:
                continue
            if reply.get("msgType") == "GetDeviceListAck" and reply.get("mac"):
                found[norm_mac(reply["mac"])] = (addr[0], reply)
    finally:
        sock.close()
    return found


# --------------------------------------------------------------------- model

class Shade:
    """One motor. Identified by MAC, which never changes."""

    def __init__(self, alias, mac, device_type, bridge):
        self.alias = alias
        self.mac = mac
        self.device_type = device_type
        self.bridge = bridge
        self.state = {}
        self.updated_at = 0.0
        self.error = None

    # 0 = open, 100 = closed
    @property
    def position(self):
        return self.state.get("currentPosition")

    @property
    def battery(self):
        raw = self.state.get("batteryLevel")
        return round(raw / 100.0, 2) if isinstance(raw, int) else None

    @property
    def battery_percent(self):
        return battery_percent(self.battery)

    @property
    def battery_low(self):
        pct = self.battery_percent
        return pct is not None and pct <= LOW_BATTERY_PERCENT

    @property
    def rssi(self):
        return self.state.get("RSSI")

    @property
    def moving(self):
        return self.state.get("currentState") in (1, 2)

    async def refresh(self):
        reply = await self.bridge.read(self.mac, self.device_type)
        self.state = reply.get("data", {}) or {}
        self.updated_at = time.monotonic()
        self.error = None
        return self.state

    async def refresh_if_stale(self, max_age):
        if time.monotonic() - self.updated_at > max_age:
            await self.refresh()

    async def set_position(self, percent):
        percent = max(0, min(100, int(percent)))
        await self.bridge.write(self.mac, self.device_type,
                                {"targetPosition": percent})
        # The motor takes 10-20s to travel; report the target, and let the
        # poller correct the cached value once it arrives.
        self.state = dict(self.state, currentPosition=percent)
        self.updated_at = 0.0
        return percent

    async def operate(self, op):
        await self.bridge.write(self.mac, self.device_type, {"operation": op})
        self.updated_at = 0.0

    async def open(self):
        await self.operate(OP_OPEN)
        return 0

    async def close(self):
        await self.operate(OP_CLOSE)
        return 100

    async def stop(self):
        await self.operate(OP_STOP)
        return self.position


class Bridge:
    """The WiFi bridge. Found by MAC via a unicast sweep, never pinned to an IP."""

    def __init__(self, key, mac=None, host=None):
        self.key = (key or "").strip()
        self.mac = norm_mac(mac)
        self.host = host
        self.token = None
        self.firmware = None
        self.devices = []            # [{"mac":..., "deviceType":...}, ...]
        self.lock = asyncio.Lock()
        self.error = None

    @property
    def has_key(self):
        return len(self.key) == 16

    # -- auth -------------------------------------------------------------

    def access_token(self):
        """AES-128-ECB of the bridge's rotating token under the app key.

        The key is the 16-character string from the Connector app
        (Settings / About -> tap the version number five times).
        """
        if not self.has_key:
            raise RuntimeError(
                "no 16-character Connector key configured -- shades are "
                "read-only until [blinds] key is set in kasa.conf")
        if not self.token:
            raise RuntimeError("bridge token unknown; discovery has not run")
        cipher = Cipher(algorithms.AES(self.key.encode()), modes.ECB())
        enc = cipher.encryptor()
        return (enc.update(self.token.encode()) + enc.finalize()).hex().upper()

    # -- discovery --------------------------------------------------------

    async def locate(self):
        """Find the bridge and refresh its token and device list."""
        async with self.lock:
            if self.host:
                try:
                    await self._adopt(await asyncio.to_thread(
                        _request_sync, self.host,
                        {"msgType": "GetDeviceList", "msgID": _msg_id()}))
                    return self
                except Exception as exc:
                    log.info("bridge not at %s (%s) -- sweeping", self.host, exc)

            found = await asyncio.to_thread(_sweep_sync)
            if not found:
                self.error = "no Motion Blinds bridge answered on the LAN"
                raise RuntimeError(self.error)

            if self.mac and self.mac in found:
                ip, reply = found[self.mac]
            elif self.mac:
                self.error = "bridge %s not found (saw %s)" % (
                    self.mac, ", ".join(found) or "nothing")
                raise RuntimeError(self.error)
            else:
                mac = sorted(found)[0]
                ip, reply = found[mac]
                if len(found) > 1:
                    log.warning("multiple bridges found (%s); using %s",
                                ", ".join(found), mac)
            moved = self.host != ip
            self.host = ip
            await self._adopt(reply)
            log.info("blinds bridge%s at %s (%s), %d shade(s)",
                     " moved" if moved else "", ip, self.mac, len(self.devices))
            return self

    async def _adopt(self, reply):
        if reply.get("msgType") != "GetDeviceListAck":
            raise RuntimeError("unexpected reply: %s" % reply.get("msgType"))
        self.mac = norm_mac(reply.get("mac"))
        self.token = reply.get("token")
        self.firmware = reply.get("fwVersion")
        self.devices = [d for d in reply.get("data", [])
                        if norm_mac(d.get("mac")) != self.mac]
        self.error = None

    # -- operations -------------------------------------------------------

    async def read(self, mac, device_type):
        payload = {"msgType": "ReadDevice", "mac": mac,
                   "deviceType": device_type, "msgID": _msg_id()}
        return await self._exchange(payload)

    async def write(self, mac, device_type, data):
        payload = {"msgType": "WriteDevice", "mac": mac,
                   "deviceType": device_type, "AccessToken": self.access_token(),
                   "msgID": _msg_id(), "data": data}
        reply = await self._exchange(payload)
        actual = reply.get("actionResult")
        if actual:
            # The bridge reports a bad AccessToken here rather than by failing.
            raise RuntimeError("bridge rejected the command: %s" % actual)
        return reply

    async def _exchange(self, payload):
        if not self.host:
            await self.locate()
        try:
            return await asyncio.to_thread(_request_sync, self.host, payload)
        except Exception as exc:
            log.info("bridge request failed (%s) -- relocating", exc)
            await self.locate()
            if "AccessToken" in payload:      # token may have rotated
                payload["AccessToken"] = self.access_token()
            payload["msgID"] = _msg_id()
            return await asyncio.to_thread(_request_sync, self.host, payload)


class BlindFleet:
    """All shades behind one bridge, with config-driven aliases."""

    def __init__(self, key, bridge_mac=None, aliases=None, stale_after=10.0):
        self.bridge = Bridge(key, bridge_mac)
        self.overrides = {k.lower(): norm_mac(v) if len(norm_mac(v)) >= 12
                          else v.strip()
                          for k, v in (aliases or {}).items()}
        self.stale_after = stale_after
        self.shades = {}

    @property
    def has_key(self):
        return self.bridge.has_key

    async def start(self):
        await self.bridge.locate()
        self.rebuild()
        await self.refresh_all()

    def rebuild(self):
        """Map aliases -> Shade. Ordinal names always work; config can rename."""
        shades, ordered = {}, []
        for idx, dev in enumerate(self.bridge.devices, start=1):
            mac = norm_mac(dev.get("mac"))
            shade = Shade("shade-%d" % idx, mac, dev.get("deviceType"), self.bridge)
            ordered.append(shade)
            shades[shade.alias] = shade
            shades[mac] = shade

        for alias, target in self.overrides.items():
            match = shades.get(norm_mac(target)) or shades.get(str(target).lower())
            if match is None and str(target).isdigit():
                pos = int(target)
                if 1 <= pos <= len(ordered):
                    match = ordered[pos - 1]
            if match is None:
                log.warning("shade alias %r points at unknown shade %r",
                            alias, target)
                continue
            match.alias = alias
            shades[alias] = match
        self.shades = shades
        log.info("%d shade(s) available", len(ordered))
        return ordered

    def resolve(self, alias):
        alias = (alias or "").lower()
        return self.shades.get(alias) or self.shades.get(norm_mac(alias))

    def unique(self):
        seen, out = set(), []
        for shade in self.shades.values():
            if shade.mac in seen:
                continue
            seen.add(shade.mac)
            out.append(shade)
        return sorted(out, key=lambda s: s.mac)

    async def refresh_all(self):
        for shade in self.unique():
            try:
                await shade.refresh()
            except Exception as exc:
                shade.error = str(exc)
                log.debug("could not read shade %s: %s", shade.alias, exc)
