"""Tiny read-mostly HTTP API for dashboards (stdlib asyncio, no extra deps).

  GET /status                      current snapshot (status.json)
  GET /history?hours=24            {"status", "events", "readings"} for the last N hours
  GET /feedback?value=too_warm     log a comfort note (too_warm, too_cold, stuffy, too_loud, ok)
  GET /healthz
"""

import asyncio
import glob
import json
import logging
import os
import time
from urllib.parse import parse_qs, urlparse

log = logging.getLogger(__name__)

FEEDBACK = {"too_warm", "too_cold", "stuffy", "too_loud", "ok"}


def read_jsonl_since(directory, kind, since):
    out = []
    for path in sorted(glob.glob(os.path.join(directory, f"{kind}-*.jsonl")))[-3:]:
        if os.path.getmtime(path) < since:
            continue
        with open(path) as f:
            for line in f:
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if rec.get("ts", 0) >= since:
                    out.append(rec)
    return out


class Web:
    def __init__(self, datalog, state_fn, host="0.0.0.0", port=8788):
        self.datalog, self.state_fn = datalog, state_fn
        self.host, self.port = host, port

    async def start(self):
        server = await asyncio.start_server(self._handle, self.host, self.port)
        log.info("http on %s:%d", self.host, self.port)
        return server

    async def _handle(self, reader, writer):
        try:
            request = await asyncio.wait_for(reader.readline(), 5)
            while (await asyncio.wait_for(reader.readline(), 5)) not in (b"\r\n", b"\n", b""):
                pass  # skip headers
            parts = request.decode(errors="replace").split()
            if len(parts) < 2 or parts[0] != "GET":
                return await self._send(writer, 405, {"ok": False, "error": "GET only"})
            url = urlparse(parts[1])
            q = {k: v[0] for k, v in parse_qs(url.query).items()}
            code, body = self._route(url.path, q)
            await self._send(writer, code, body)
        except Exception as e:  # never let a bad request hurt the control loop
            log.debug("http error: %s", e)
        finally:
            writer.close()

    def _route(self, path, q):
        if path == "/healthz":
            return 200, {"ok": True}
        if path == "/status":
            return 200, self.state_fn()
        if path == "/history":
            hours = min(float(q.get("hours", 24)), 24 * 14)
            since = time.time() - hours * 3600
            return 200, {"status": self.state_fn(),
                         "events": read_jsonl_since(self.datalog.dir, "events", since),
                         "readings": read_jsonl_since(self.datalog.dir, "readings", since)}
        if path == "/feedback":
            value = q.get("value", "")
            if value not in FEEDBACK:
                return 400, {"ok": False, "error": f"value must be one of {sorted(FEEDBACK)}"}
            st = self.state_fn()
            self.datalog.event("feedback", value=value, note=q.get("note", "")[:200],
                               co2=st.get("co2"), temp_f=st.get("temp_f"), humidity=st.get("humidity"),
                               features={k: v.get("on") for k, v in st.get("features", {}).items()})
            return 200, {"ok": True, "value": value}
        return 404, {"ok": False, "error": "not found"}

    async def _send(self, writer, code, body):
        data = json.dumps(body).encode()
        reason = {200: "OK", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed"}.get(code, "")
        writer.write(f"HTTP/1.1 {code} {reason}\r\nContent-Type: application/json\r\n"
                     f"Content-Length: {len(data)}\r\nAccess-Control-Allow-Origin: *\r\n"
                     f"Connection: close\r\n\r\n".encode() + data)
        await writer.drain()
