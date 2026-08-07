#!/usr/bin/env python3
"""kasad - local HTTP control plane for TP-Link Kasa outlets.

Replaces the IFTTT webhook round-trip (Stream Deck -> IFTTT cloud -> TP-Link
cloud -> plug) with a direct LAN call. The daemon holds warm, authenticated
sessions to each strip so a button press is one local request, not a
rediscover-and-handshake every time.

  GET /toggle/<alias>    flip an outlet
  GET /on/<alias>        force on
  GET /off/<alias>       force off
  GET /state/<alias>     current state as JSON
  GET /list              every known alias
  GET /healthz           daemon + device reachability
  GET /rediscover        force a broadcast sweep
  GET /urls              every endpoint as copy-paste text (Stream Deck)
  GET /                  live control panel (ui.html)

Devices are identified by MAC address, never by IP. IPs live in a throwaway
cache; when one stops answering -- power outage, DHCP reshuffle, router reboot
-- the daemon broadcasts to find where the strip moved and reattaches to it by
MAC. Nothing to update by hand.

The HS300s speak KLAP, which needs TP-Link account credentials to complete its
handshake -- but that handshake is device-to-device on the LAN. Nothing leaves
the house at press time.
"""

import argparse
import asyncio
import configparser
import json
import logging
import os
import re
import socket
import sys
import time

from aiohttp import web
from kasa import Credentials, Discover, device_factory, discover as _discover_mod
from kasa.deviceconfig import DeviceEncryptionType
from kasa.exceptions import AuthenticationError
from kasa.iot import IotStrip
from kasa.protocols import IotProtocol
from kasa.transports import KlapTransportV2

import blinds as blinds_mod

log = logging.getLogger("kasad")

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CONF = os.path.join(HERE, "kasa.conf")
CACHE_PATH = os.path.join(HERE, ".kasa-cache.json")
UI_PATH = os.path.join(HERE, "ui.html")

# Don't let a burst of failures trigger a broadcast storm.
REDISCOVER_COOLDOWN = 10.0


def patch_iot_klap_v2():
    """Work around a python-kasa transport-selection bug (as of 0.10.2).

    device_factory.get_protocol() picks a transport with the lookup key
    f"{family}.{encryption}" and never consults login_version:

        "IOT.KLAP":   (IotProtocol,   KlapTransport)      # v1: md5(md5(u)+md5(p))
        "SMART.KLAP": (SmartProtocol, KlapTransportV2)    # v2: sha256(sha1(u)+sha1(p))

    An HS300 hw 2.0 reports family IOT.SMARTPLUGSWITCH, encryption KLAP and
    login_version 2, so it lands on the v1 md5 hash and every handshake is
    rejected -- indistinguishable from a wrong password.

    Confirmed against the device's own handshake1 challenge: it verifies
    against sha256(sha1(user)+sha1(pass)) and not against the md5 form.

    discover.py binds get_protocol by name at import, so both references need
    replacing. Applied at runtime rather than by editing site-packages, which
    setup.sh would overwrite.
    """
    original = device_factory.get_protocol

    def get_protocol(config, *, strict=False):
        ctype = config.connection_type
        if (ctype.device_family.value.split(".")[0] == "IOT"
                and ctype.encryption_type is DeviceEncryptionType.Klap
                and (ctype.login_version or 1) >= 2):
            return IotProtocol(transport=KlapTransportV2(config=config))
        return original(config, strict=strict)

    device_factory.get_protocol = get_protocol
    _discover_mod.get_protocol = get_protocol


patch_iot_klap_v2()


def slugify(name):
    """'Bedroom Lamp #2' -> 'bedroom-lamp-2'"""
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return slug or "outlet"


def norm_mac(mac):
    """Any of E4-FA-C4.., e4:fa:c4.., E4FAC4.. -> 'e4fac4561133'."""
    return re.sub(r"[^0-9a-f]", "", (mac or "").lower())


def pretty_mac(mac):
    m = norm_mac(mac).upper()
    return "-".join(m[i:i + 2] for i in range(0, len(m), 2)) or "?"


def looks_like_ip(value):
    return re.match(r"^\d{1,3}(\.\d{1,3}){3}$", value.strip()) is not None


def local_broadcast():
    """Best-effort /24 broadcast address for the primary interface."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))       # no packets sent, just routing
        ip = sock.getsockname()[0]
    except Exception:
        return None
    finally:
        sock.close()
    return ip.rsplit(".", 1)[0] + ".255"


# ------------------------------------------------------------------ discovery

class Fleet:
    """Owns credentials, the MAC->IP cache, and broadcast rediscovery."""

    def __init__(self, creds, broadcast=None, discovery_timeout=5):
        self.creds = creds
        self.broadcast = broadcast
        self.discovery_timeout = discovery_timeout
        self.cache, self.names = self._load_cache()
        self.lock = asyncio.Lock()
        self.last_sweep = 0.0
        self.last_result = {}          # mac -> ip, from the most recent sweep

    # -- cache ------------------------------------------------------------

    def _load_cache(self):
        """Returns (mac->ip, configname->mac). Both are throwaway hints."""
        try:
            with open(CACHE_PATH) as fh:
                raw = json.load(fh)
        except Exception:
            return {}, {}
        if "ips" in raw or "names" in raw:
            return ({norm_mac(k): v for k, v in raw.get("ips", {}).items()},
                    {k: norm_mac(v) for k, v in raw.get("names", {}).items()})
        return {norm_mac(k): v for k, v in raw.items()}, {}   # legacy flat form

    def save_cache(self):
        try:
            tmp = CACHE_PATH + ".tmp"
            with open(tmp, "w") as fh:
                json.dump({"ips": self.cache, "names": self.names},
                          fh, indent=2, sort_keys=True)
            os.replace(tmp, CACHE_PATH)
        except Exception as exc:
            log.debug("could not write cache: %s", exc)

    def remember(self, mac, ip):
        mac = norm_mac(mac)
        if mac and self.cache.get(mac) != ip:
            self.cache[mac] = ip
            self.save_cache()

    def remember_name(self, name, mac):
        """Pin an IP-configured name to the MAC that actually answered, so the
        device stays findable after it moves."""
        mac = norm_mac(mac)
        if name and mac and self.names.get(name) != mac:
            self.names[name] = mac
            self.save_cache()

    # -- discovery --------------------------------------------------------

    async def sweep(self, force=False):
        """Broadcast for every Kasa device. Returns {mac: (ip, alias)}.

        Discovery builds a Device -- and an aiohttp session -- for everything
        it finds, but _attach() opens its own connection afterwards. Keeping
        those objects would leak a session per device per sweep ("Unclosed
        client session"), so only the address and name are retained and every
        discovered device is disconnected before returning.
        """
        async with self.lock:
            age = time.monotonic() - self.last_sweep
            if not force and age < REDISCOVER_COOLDOWN and self.last_result:
                log.debug("reusing sweep from %.1fs ago", age)
                return self.last_result

            targets = [self.broadcast] if self.broadcast else []
            targets += [t for t in ("255.255.255.255", local_broadcast())
                        if t and t not in targets]

            found = {}
            for target in targets:
                log.info("broadcasting discovery on %s", target)
                try:
                    devices = await Discover.discover(
                        target=target, credentials=self.creds,
                        discovery_timeout=self.discovery_timeout)
                except Exception as exc:
                    log.warning("discovery on %s failed: %s", target, exc)
                    continue
                for ip, dev in devices.items():
                    mac = norm_mac(getattr(dev, "mac", "") or "")
                    if mac:
                        found[mac] = (ip, getattr(dev, "alias", "") or "")
                    try:
                        await dev.disconnect()
                    except Exception:
                        pass
                if found:
                    break                 # first target that works is enough

            self.last_sweep = time.monotonic()
            self.last_result = found
            for mac, (ip, _alias) in found.items():
                self.cache[mac] = ip
            self.save_cache()
            log.info("discovery found %d device(s)", len(found))
            return found

    async def find(self, mac, force=False):
        """Locate one device by MAC. Returns (ip, alias) or None."""
        found = await self.sweep(force=force)
        return found.get(norm_mac(mac))


# --------------------------------------------------------------------- model

class Outlet:
    """One controllable endpoint.

    Holds no Device reference -- it resolves through the Strip every time, so
    a reconnect or an IP change can swap the underlying object out from under
    it without leaving anything pointing at a dead session.
    """

    def __init__(self, alias, strip, child_id=None, child_index=None):
        self.alias = alias
        self.strip = strip
        self.child_id = child_id
        self.child_index = child_index
        self.commanded = None       # what we last told it to do
        self.commanded_at = 0.0

    def remember(self, state):
        self.commanded = state
        self.commanded_at = time.monotonic()

    @property
    def device(self):
        dev = self.strip.device
        if dev is None:
            return None
        if self.child_id is None and self.child_index is None:
            return dev
        for child in dev.children:
            if getattr(child, "device_id", None) == self.child_id:
                return child
        if self.child_index is not None and self.child_index < len(dev.children):
            return dev.children[self.child_index]     # fallback: position
        return None

    @property
    def is_on(self):
        # turn_on/turn_off leave the device's cached sysinfo untouched, so
        # trust the command we just issued until a real read supersedes it.
        # Without this, /list reports the pre-command state and the UI's
        # optimistic flip visibly reverts.
        if self.commanded is not None:
            if self.strip.updated_at <= self.commanded_at:
                return self.commanded
            self.commanded = None
        dev = self.device
        return bool(dev and dev.is_on)

    async def turn_on(self):
        await self.strip.act(self, "turn_on")
        return True

    async def turn_off(self):
        await self.strip.act(self, "turn_off")
        return False

    async def toggle(self):
        await self.strip.refresh_if_stale()
        return await (self.turn_off() if self.is_on else self.turn_on())


class Strip:
    """A physical device, identified by MAC, wherever it currently lives."""

    def __init__(self, fleet, mac, name, host=None, stale_after=5.0):
        self.fleet = fleet
        self.mac = norm_mac(mac)
        self.name = name
        self.pinned_by_ip = not self.mac
        if not self.mac:
            # Configured by IP, but we may have learned its MAC on a past run.
            self.mac = fleet.names.get(name, "")
        self.host = host or fleet.cache.get(self.mac)
        self.stale_after = stale_after
        self.device = None
        self.updated_at = 0.0
        self.lock = asyncio.Lock()
        self.error = None
        self.on_topology_change = None    # set by Daemon to rebuild aliases

    # -- connection -------------------------------------------------------

    async def connect(self):
        """Cached IP first (fast unicast), broadcast only if that fails."""
        if self.host:
            try:
                await self._attach(self.host)
                return self.device
            except AuthenticationError:
                # The device is right there and said no. Broadcasting for it
                # would just find the same device and get rejected again.
                raise
            except Exception as exc:
                log.info("%s not at %s (%s) -- searching",
                         self.name, self.host, exc)

        if not self.mac:
            raise RuntimeError(
                "%s was pinned to IP %s, nothing answered there, and its MAC "
                "was never learned -- leave [devices] empty in kasa.conf to "
                "auto-discover instead" % (self.name, self.host))

        located = await self.fleet.find(self.mac)
        if located is None:
            located = await self.fleet.find(self.mac, force=True)
        if located is None:
            raise RuntimeError("no device with MAC %s on the network"
                               % pretty_mac(self.mac))

        ip, _alias = located
        await self._attach(ip)
        return self.device

    async def _attach(self, ip):
        dev = await Discover.discover_single(ip, credentials=self.fleet.creds)
        if dev is None:
            raise RuntimeError("no response from %s" % ip)
        try:
            await dev.update()

            # Discovery hands back an IotPlug for a strip, so the six children
            # stay invisible. Re-wrap as IotStrip, reusing the already
            # authenticated protocol rather than handshaking a second time.
            if not dev.children and dev.sys_info.get("children"):
                strip = IotStrip(dev.host, protocol=dev.protocol)
                await strip.update()
                dev = strip

            found_mac = norm_mac(getattr(dev, "mac", "") or "")
            if self.mac and found_mac and found_mac != self.mac:
                # Someone else took this IP. Don't command the wrong device.
                raise RuntimeError(
                    "%s is %s, not %s"
                    % (ip, pretty_mac(found_mac), pretty_mac(self.mac)))
        except Exception:
            await self._close(dev)      # don't leak the aiohttp session
            raise

        if self.device is not None and self.device is not dev:
            await self._close(self.device)

        if not self.mac:
            self.mac = found_mac
        moved = self.host != ip
        self.host = ip
        self.device = dev
        self.updated_at = time.monotonic()
        self.error = None
        self.fleet.remember(self.mac, ip)
        if self.pinned_by_ip:
            # Learn the identity behind the IP so a future move is recoverable.
            self.fleet.remember_name(self.name, self.mac)
        log.info("%s%s at %s: %s (%d outlets)",
                 self.name, " moved" if moved else "", ip, dev.alias,
                 len(dev.children))
        return dev

    @staticmethod
    async def _refresh_device(dev):
        """Refresh state as cheaply as the device allows.

        IotStrip.update() issues a separate query per child (~1.5s on an
        HS300). The parent's sysinfo already carries every child's relay
        state, so the shallow update returns the same information in ~40ms.
        """
        if isinstance(dev, IotStrip):
            await dev.update(update_children=False)
        else:
            await dev.update()

    @staticmethod
    async def _close(dev):
        try:
            await dev.disconnect()
        except Exception:
            pass

    # -- operations -------------------------------------------------------

    async def act(self, outlet, method):
        """Run a device method, re-resolving and relocating on failure."""
        async with self.lock:
            try:
                await self._invoke(outlet, method)
            except Exception as exc:
                log.warning("%s: %s failed (%s) -- relocating",
                            self.name, method, exc)
                await self.connect()
                await self._invoke(outlet, method)
                if self.on_topology_change:
                    self.on_topology_change()

            outlet.remember(method == "turn_on")
            self.error = None
        # Confirm out of band: the caller already knows the outcome, and the
        # remembered state keeps /list correct until this lands.
        asyncio.create_task(self._settle())

    async def _invoke(self, outlet, method):
        target = outlet.device
        if target is None:
            raise RuntimeError("outlet %s not present on %s"
                               % (outlet.alias, self.name))
        await getattr(target, method)()

    async def _settle(self):
        try:
            await self.refresh()
        except Exception as exc:
            log.debug("%s: confirming read failed: %s", self.name, exc)

    async def refresh(self):
        async with self.lock:
            try:
                await self._refresh_device(self.device)
                self.updated_at = time.monotonic()
                self.error = None
            except Exception as exc:
                self.error = str(exc)
                log.warning("%s: refresh failed (%s) -- relocating",
                            self.name, exc)
                await self.connect()
                if self.on_topology_change:
                    self.on_topology_change()

    async def refresh_if_stale(self):
        if self.device is None or time.monotonic() - self.updated_at > self.stale_after:
            await self.refresh()

    def outlets(self):
        found = {}
        dev = self.device
        if dev is None:
            return found
        if dev.children:
            for idx, child in enumerate(dev.children):
                outlet = Outlet(slugify(child.alias), self,
                                getattr(child, "device_id", None), idx)
                found[outlet.alias] = outlet
                found["%s/%d" % (self.name, idx)] = outlet
        else:
            outlet = Outlet(slugify(dev.alias), self)
            found[outlet.alias] = outlet
            found[self.name] = outlet
        return found


# -------------------------------------------------------------------- daemon

class Daemon:
    def __init__(self, conf):
        self.conf = conf
        creds = Credentials(conf["auth"]["username"], conf["auth"]["password"])
        self.stale_after = conf.getfloat("server", "stale_after", fallback=5.0)
        self.poll_interval = conf.getfloat("server", "poll_interval", fallback=30.0)
        self.fleet = Fleet(
            creds,
            broadcast=conf.get("server", "broadcast", fallback="").strip() or None,
            discovery_timeout=conf.getint("server", "discovery_timeout", fallback=5))
        self.pins = dict(conf["devices"]) if conf.has_section("devices") else {}
        self.pins = {k: v.strip() for k, v in self.pins.items() if v.strip()}
        self.overrides = dict(conf["aliases"]) if conf.has_section("aliases") else {}
        self.strips = []
        self.outlets = {}

        # Motion Blinds / Connector shades. Optional: absent config just means
        # no shade routes, and a missing key still allows read-only status.
        self.blinds = None
        if conf.has_section("blinds"):
            key = conf.get("blinds", "key", fallback="").strip()
            bridge_mac = conf.get("blinds", "bridge", fallback="").strip()
            shade_aliases = dict(conf["shades"]) if conf.has_section("shades") else {}
            # Built even with no key: ReadDevice is unauthenticated, so shades
            # are still discoverable and reportable, just not movable.
            self.blinds = blinds_mod.BlindFleet(
                key, bridge_mac, shade_aliases,
                stale_after=conf.getfloat("blinds", "stale_after", fallback=10.0),
                limits=dict(conf["shade_limits"]) if conf.has_section("shade_limits") else {},
                presets=dict(conf["shade_presets"]) if conf.has_section("shade_presets") else {})

    async def start(self):
        if self.pins:
            await self._start_pinned()
        else:
            await self._start_auto()
        for strip in self.strips:
            strip.on_topology_change = self.rebuild_outlets
        self.rebuild_outlets()
        self._warn_if_all_rejected()

        if self.blinds is not None:
            try:
                await self.blinds.start()
                if not self.blinds.has_key:
                    log.warning("shades are READ-ONLY: no 16-character key in "
                                "[blinds]. Connector app -> Settings / About -> "
                                "tap the version number 5 times.")
            except Exception as exc:
                log.error("blinds bridge unavailable: %s", exc)

    def _warn_if_all_rejected(self):
        """Bad credentials look like a network problem unless we say otherwise."""
        if not self.strips or any(s.device is not None for s in self.strips):
            return
        blob = " ".join((s.error or "").lower() for s in self.strips)
        if "challenge" in blob or "authentic" in blob or "credential" in blob:
            log.error("")
            log.error("Every device rejected the credentials in kasa.conf.")
            log.error("The devices ARE reachable -- this is an auth failure, "
                      "not a network one.")
            log.error("  * use your TP-Link/Kasa ACCOUNT email + password")
            log.error("  * both are case-sensitive")
            log.error("  * if you sign in with Google/Apple SSO, set a native "
                      "TP-Link password in the Kasa app first")
            log.error("")

    async def _start_pinned(self):
        """Config named specific devices, by MAC (preferred) or IP (a hint)."""
        for name, value in self.pins.items():
            if looks_like_ip(value):
                # IP given: identity still comes from whatever MAC answers there.
                strip = Strip(self.fleet, "", name, host=value,
                              stale_after=self.stale_after)
            else:
                strip = Strip(self.fleet, value, name,
                              stale_after=self.stale_after)
            self.strips.append(strip)

        results = await asyncio.gather(
            *(s.connect() for s in self.strips), return_exceptions=True)
        for strip, res in zip(self.strips, results):
            if isinstance(res, Exception):
                log.error("could not reach %s: %s", strip.name, res)
                strip.error = str(res)

    async def _start_auto(self):
        """No devices configured: adopt every Kasa device on the LAN."""
        log.info("no [devices] pinned -- discovering everything on the LAN")
        found = await self.fleet.sweep(force=True)
        if not found:
            log.error("no Kasa devices found on the network")
        for mac, (ip, alias) in sorted(found.items(), key=lambda kv: kv[1][0]):
            name = slugify(alias or "kasa-%s" % mac[-4:])
            strip = Strip(self.fleet, mac, name, host=ip,
                          stale_after=self.stale_after)
            try:
                await strip._attach(ip)
            except Exception as exc:
                log.error("could not attach %s (%s): %s", name, ip, exc)
                strip.error = str(exc)
            self.strips.append(strip)

    def rebuild_outlets(self):
        outlets = {}
        for strip in self.strips:
            outlets.update(strip.outlets())
        for alias, target in self.overrides.items():
            if target in outlets:
                outlets[alias] = outlets[target]
            else:
                log.warning("alias %r points at unknown outlet %r", alias, target)
        self.outlets = outlets
        log.info("%d outlet names available", len(outlets))

    def resolve(self, alias):
        alias = alias.lower()
        return self.outlets.get(alias) or self.outlets.get(slugify(alias))

    async def shutdown(self):
        """Close every device session explicitly, rather than letting the
        garbage collector complain about unclosed aiohttp connectors."""
        for strip in self.strips:
            if strip.device is not None:
                await strip._close(strip.device)
                strip.device = None

    async def poller(self):
        """Keep sessions warm; relocate anything that wandered off."""
        while True:
            await asyncio.sleep(self.poll_interval)
            for strip in self.strips:
                try:
                    if strip.device is None:
                        await strip.connect()
                        self.rebuild_outlets()
                    else:
                        await strip.refresh()
                except Exception as exc:
                    strip.error = str(exc)
                    log.debug("poll of %s failed: %s", strip.name, exc)
            if self.blinds is not None:
                try:
                    await self.blinds.refresh_all()
                except Exception as exc:
                    log.debug("poll of shades failed: %s", exc)


# ---------------------------------------------------------------- http layer

def json_error(message, status=404):
    return web.json_response({"ok": False, "error": message}, status=status)


async def handle_action(request):
    daemon = request.app["daemon"]
    action = request.match_info["action"]
    alias = request.match_info["alias"]
    outlet = daemon.resolve(alias)
    if outlet is None:
        return json_error("unknown outlet %r" % alias)

    started = time.monotonic()
    try:
        if action == "toggle":
            state = await outlet.toggle()
        elif action == "on":
            state = await outlet.turn_on()
        elif action == "off":
            state = await outlet.turn_off()
        else:
            await outlet.strip.refresh_if_stale()
            state = outlet.is_on
    except Exception as exc:
        log.error("%s %s failed: %s", action, alias, exc)
        return json_error(str(exc), status=502)

    ms = round((time.monotonic() - started) * 1000, 1)
    log.info("%s %s -> %s (%sms)", action, alias, "on" if state else "off", ms)
    return web.json_response(
        {"ok": True, "outlet": outlet.alias, "state": "on" if state else "off",
         "ms": ms})


async def handle_shade(request):
    """/shade/<alias>/<0-100 | open | close | stop | state>"""
    daemon = request.app["daemon"]
    if daemon.blinds is None:
        return json_error("no shades configured", status=404)

    alias = request.match_info["alias"]
    action = request.match_info["action"].lower()
    shade = daemon.blinds.resolve(alias)
    if shade is None:
        return json_error("unknown shade %r" % alias)

    started = time.monotonic()
    try:
        requested = None
        if action.isdigit():
            target, requested = await shade.set_position(int(action))
        elif action == "open":
            target, requested = await shade.open()
        elif action == "close":
            target, requested = await shade.close()
        elif action == "stop":
            target = await shade.stop()
        else:
            await shade.refresh_if_stale(daemon.blinds.stale_after)
            target = shade.position
    except Exception as exc:
        log.error("shade %s %s failed: %s", alias, action, exc)
        return json_error(str(exc), status=502)

    ms = round((time.monotonic() - started) * 1000, 1)
    log.info("shade %s %s -> %s%% (%sms)", shade.alias, action, target, ms)
    body = {
        "ok": True, "shade": shade.alias, "action": action,
        "target": target, "position": shade.position,
        "battery": shade.battery, "battery_percent": shade.battery_percent,
        "battery_low": shade.battery_low, "charging": shade.charging, "ms": ms,
        "max_position": shade.max_position,
        "note": "0 = open, 100 = closed",
    }
    if requested is not None and requested != target:
        body["clamped"] = True
        body["requested"] = requested
        body["limit"] = shade.max_position
        log.info("shade %s clamped %d%% -> %d%% (configured limit)",
                 shade.alias, requested, target)
    return web.json_response(body)


async def handle_list(request):
    daemon = request.app["daemon"]

    # The web UI polls this, so it is the read path that has to be honest.
    # Refresh anything past its staleness window -- concurrently, so the cost
    # is one device round trip rather than the sum of them -- otherwise a
    # change made from a physical button or the vendor app stays invisible
    # until the slow background poller catches it.
    stale = [s.refresh_if_stale() for s in daemon.strips if s.device is not None]
    if daemon.blinds is not None:
        stale += [sh.refresh_if_stale(daemon.blinds.stale_after)
                  for sh in daemon.blinds.unique()]
    if stale:
        await asyncio.gather(*stale, return_exceptions=True)

    seen, items = set(), []
    # Human aliases before positional ones ("strip1/0"), so 'primary' lands on
    # the readable name rather than whichever happens to sort first.
    for alias, outlet in sorted(daemon.outlets.items(),
                                key=lambda kv: ("/" in kv[0], kv[0])):
        key = (outlet.strip.mac, outlet.child_id, outlet.child_index)
        items.append({
            "alias": alias,
            "device": outlet.strip.name,
            "mac": pretty_mac(outlet.strip.mac),
            "host": outlet.strip.host,
            "state": "on" if outlet.is_on else "off",
            "primary": key not in seen,
        })
        seen.add(key)

    shades = []
    if daemon.blinds is not None:
        for shade in daemon.blinds.unique():
            shades.append({
                "alias": shade.alias, "mac": shade.mac,
                "position": shade.position, "battery": shade.battery,
                "battery_percent": shade.battery_percent,
                "battery_low": shade.battery_low,
                "charging": shade.charging,
                "rssi": shade.rssi, "moving": shade.moving,
                "writable": daemon.blinds.has_key,
                "max_position": shade.max_position,
                "presets": daemon.blinds.preset_for(shade),
            })
    return web.json_response({"ok": True, "outlets": items, "shades": shades,
                              "shade_scale": "0 = open, 100 = closed"})


async def handle_health(request):
    daemon = request.app["daemon"]
    devices = [{"name": s.name, "mac": pretty_mac(s.mac), "host": s.host,
                "connected": s.device is not None, "error": s.error}
               for s in daemon.strips]
    healthy = bool(devices) and all(d["connected"] for d in devices)
    body = {"ok": healthy, "devices": devices}
    if daemon.blinds is not None:
        bridge = daemon.blinds.bridge
        body["blinds"] = {
            "bridge_mac": bridge.mac, "host": bridge.host,
            "firmware": bridge.firmware, "shades": len(bridge.devices),
            "writable": bridge.has_key, "error": bridge.error,
        }
        healthy = healthy and bridge.host is not None
        body["ok"] = healthy
    return web.json_response(body, status=200 if healthy else 503)


async def handle_rediscover(request):
    daemon = request.app["daemon"]
    await daemon.fleet.sweep(force=True)
    for strip in daemon.strips:
        try:
            await strip.connect()
        except Exception as exc:
            strip.error = str(exc)
    daemon.rebuild_outlets()
    return await handle_health(request)


async def handle_urls(request):
    """Every endpoint as plain text, ready to paste into a Stream Deck action.

    The base is taken from the request, so whatever address you browsed with is
    the address you copy -- no guessing about localhost vs LAN IP.
    """
    daemon = request.app["daemon"]
    base = str(request.url.origin())
    out = [
        "# kasad endpoints for %s" % base,
        "# Paste into a Stream Deck HTTP-request action (not the Website action,",
        "# which opens a browser tab).",
        "",
        "# ---- Outlets: one key each -------------------------------------",
        "# /toggle reads the current state on the device and flips it, so it",
        "# stays right even if someone used the physical button.",
        "",
    ]
    primary = []
    seen = set()
    for alias, outlet in sorted(daemon.outlets.items()):
        if "/" in alias or id(outlet) in seen:
            continue
        seen.add(id(outlet))
        primary.append(alias)
        out.append("%-28s %s/toggle/%s" % (alias, base, alias))
    out.append("")
    out += ["# ---- Outlets: dedicated on / off keys (optional) ----------------",
            "# Use these instead if you want one key that only ever turns it on",
            "# and another that only ever turns it off.",
            ""]
    for alias in primary:
        out.append("%-24s on   %s/on/%s" % (alias, base, alias))
        out.append("%-24s off  %s/off/%s" % (alias, base, alias))
    out.append("")

    if daemon.blinds is not None and daemon.blinds.unique():
        out += ["# ---- Shades (0 = open, 100 = closed) ----------------------------", ""]
        for shade in daemon.blinds.unique():
            cap = shade.max_position
            if cap < 100:
                out.append("# %s stops at %d%% (configured limit); higher values clamp."
                           % (shade.alias, cap))
            for pct in sorted({0, 25, 50, 75, cap} | set(daemon.blinds.preset_for(shade))):
                if pct <= cap:
                    out.append("%-24s %3d%%  %s/shade/%s/%d"
                               % (shade.alias, pct, base, shade.alias, pct))
            out.append("%-24s open  %s/shade/%s/open" % (shade.alias, base, shade.alias))
            out.append("%-24s stop  %s/shade/%s/stop" % (shade.alias, base, shade.alias))
            out.append("")

    out += ["# ---- Status ------------------------------------------------------",
            "%-28s      %s/healthz" % ("health", base),
            "%-28s      %s/list" % ("everything as JSON", base), ""]
    return web.Response(text="\n".join(out), content_type="text/plain")


async def handle_index(request):
    """Serve the control panel. Read from disk each time so the UI can be
    edited without restarting the daemon; state arrives separately via /list."""
    try:
        with open(UI_PATH) as fh:
            return web.Response(text=fh.read(), content_type="text/html")
    except FileNotFoundError:
        return web.Response(
            text="ui.html is missing next to kasad.py; the JSON API still works "
                 "at /list, /healthz and /shade/<alias>/<action>.",
            content_type="text/plain", status=500)


def build_app(daemon):
    app = web.Application()
    app["daemon"] = daemon
    app.router.add_get("/", handle_index)
    app.router.add_get("/list", handle_list)
    app.router.add_get("/healthz", handle_health)
    app.router.add_get("/rediscover", handle_rediscover)
    app.router.add_get("/urls", handle_urls)
    # Shades before the generic outlet route, which would otherwise swallow them.
    app.router.add_get("/shade/{alias}/{action}", handle_shade)
    app.router.add_get("/{action:toggle|on|off|state}/{alias:.+}", handle_action)
    return app


# ----------------------------------------------------------------- bootstrap

def load_conf(path):
    if not os.path.exists(path):
        sys.exit("no config at %s -- copy kasa.conf.example and fill it in" % path)
    # interpolation=None: a '%' in a password is a literal, not a format spec.
    conf = configparser.ConfigParser(interpolation=None)
    conf.read(path)
    if not conf.has_section("auth"):
        sys.exit("config %s is missing an [auth] section" % path)
    if not conf["auth"].get("username") or "example.com" in conf["auth"]["username"]:
        sys.exit("fill in your TP-Link credentials in %s" % path)
    return conf


async def main_async(args):
    conf = load_conf(args.config)
    daemon = Daemon(conf)
    await daemon.start()

    if args.list_only:
        for strip in daemon.strips:
            if strip.device is None:
                print("%-10s %-18s %-15s UNREACHABLE (%s)"
                      % (strip.name, pretty_mac(strip.mac), strip.host, strip.error))
                continue
            print("%s  %s  %s  -- %s"
                  % (strip.name, pretty_mac(strip.mac), strip.host,
                     strip.device.alias))
            for idx, child in enumerate(strip.device.children):
                print("    [%d] %-28s %-3s  alias: %s"
                      % (idx, child.alias, "ON" if child.is_on else "off",
                         slugify(child.alias)))
            if not strip.device.children:
                print("    (single outlet)  alias: %s" % slugify(strip.device.alias))

        if daemon.blinds is not None:
            b = daemon.blinds.bridge
            print("\nblinds bridge %s at %s (fw %s)%s"
                  % (b.mac, b.host, b.firmware,
                     "" if b.has_key else "   [READ-ONLY: no key configured]"))
            for shade in daemon.blinds.unique():
                pos = shade.position
                print("    %-16s %s%% closed   battery %sV (%s%%)%s   rssi %s   mac: %s"
                      % (shade.alias, "?" if pos is None else pos,
                         shade.battery, shade.battery_percent,
                         "  CHARGING" if shade.charging else
                         ("  LOW - RECHARGE" if shade.battery_low else ""),
                         shade.rssi, shade.mac))
            if not b.has_key:
                print("\n  To enable movement, put the 16-character key in "
                      "[blinds] of kasa.conf:")
                print("    Connector app -> Settings / About -> tap the version "
                      "number 5 times")
        await daemon.shutdown()
        return

    host = conf.get("server", "host", fallback="127.0.0.1")
    port = conf.getint("server", "port", fallback=8787)

    runner = web.AppRunner(build_app(daemon), access_log=None)
    await runner.setup()
    await web.TCPSite(runner, host, port).start()
    log.info("kasad listening on http://%s:%d", host, port)

    poller = asyncio.create_task(daemon.poller())
    try:
        await asyncio.Event().wait()
    finally:
        poller.cancel()
        await runner.cleanup()
        await daemon.shutdown()


def main():
    ap = argparse.ArgumentParser(description="local Kasa outlet daemon")
    ap.add_argument("-c", "--config", default=DEFAULT_CONF)
    ap.add_argument("-l", "--list-only", action="store_true",
                    help="print every outlet and exit")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)-7s %(message)s",
        datefmt="%H:%M:%S")

    try:
        asyncio.run(main_async(args))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
