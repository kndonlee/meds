"""Relay to the heater-ir board (QT Py ESP32-S3 IR sender, see esp32-ir/), for the Stream Deck keys.

Only passes button presses through; no heater automation here. The board's DHCP address can change,
so it is found by name. macOS's default lookup of a .local name also asks for an IPv6 address, which
the board's mDNS never answers (a 5 s wait), so this asks for IPv4 only (milliseconds), remembers the
address, and looks it up again when a connection fails.
"""

import asyncio
import json
import logging
import re
import socket

log = logging.getLogger(__name__)


class HeaterIR:
    def __init__(self, host="heater-ir.local", port=80, timeout_seconds=10):
        self.host, self.port, self.timeout = host, port, timeout_seconds
        self.ip = None
        self.lock = asyncio.Lock()   # the board serves one request at a time

    async def _resolve(self):
        infos = await asyncio.wait_for(asyncio.get_running_loop().getaddrinfo(
            self.host, self.port, family=socket.AF_INET, type=socket.SOCK_STREAM), 5)
        ip = infos[0][4][0]
        if ip != self.ip:
            log.info("heater-ir: %s is %s", self.host, ip)
        self.ip = ip
        return ip

    async def _get(self, path):
        """Connect (re-resolving once if that fails), then send. A press that reached the board is
        never resent, so a slow reply can't turn into a double press."""
        try:
            ip = self.ip or await self._resolve()
            conn = await asyncio.wait_for(asyncio.open_connection(ip, self.port), 4)
        except (OSError, asyncio.TimeoutError):
            self.ip = None
            ip = await self._resolve()
            conn = await asyncio.wait_for(asyncio.open_connection(ip, self.port), 4)
        reader, writer = conn
        try:
            writer.write(f"GET {path} HTTP/1.1\r\nHost: {self.host}\r\nConnection: close\r\n\r\n".encode())
            await writer.drain()
            raw = await asyncio.wait_for(reader.read(), self.timeout)
        finally:
            writer.close()
        head, _, body = raw.partition(b"\r\n\r\n")
        code = int(head.split()[1]) if len(head.split()) > 1 else 502
        try:
            data = json.loads(body or b"{}")
        except ValueError:
            data = {"raw": body.decode(errors="replace")[:200]}
        return code, data

    async def request(self, path):
        async with self.lock:
            try:
                code, data = await self._get(path)
            except Exception as e:
                log.warning("heater-ir %s failed: %s", path, e)
                return 502, {"ok": False, "error": f"heater-ir unreachable: {e}"}
        if isinstance(data, dict):
            data.setdefault("ok", code == 200)
            data["board_ip"] = self.ip
        return code, data

    async def press(self, button, n=1):
        if not re.fullmatch(r"[a-z]{1,16}", button or ""):
            return 400, {"ok": False, "error": "bad button name"}
        n = max(1, min(int(n), 10))
        log.info("heater-ir: press %s x%d", button, n)
        return await self.request(f"/press/{button}?n={n}")

    async def status(self):
        return await self.request("/")
