# IR sender for the Twin-Star / Duraflame heater (QT Py ESP32-S3, CircuitPython).
#
# HTTP (on Wi-Fi, http://heater-ir.local/):
#   GET /                      -> JSON status
#   GET /press/<button>?n=1    -> send a named button n times (power, up, down, timer)
#   GET /send/<12 bits>?frames=7
# USB serial: lines "<12 bits> [frames]" (or a button name) -> send.
#
# Wi-Fi credentials live in settings.toml on the board (WIFI_SSID, WIFI_PASSWORD, HOSTNAME); never in git.
# Protocol: 38 kHz carrier; bit 1 = 1280us mark + 410us space, bit 0 = 440us mark + 1250us space,
# ~8000us between frames.
import array
import json
import os
import time

import board
import pulseio
import supervisor
import sys

PIN = getattr(board, "SCL1", None) or board.SCL   # STEMMA QT yellow wire (GPIO40)
ir = pulseio.PulseOut(PIN, frequency=38000, duty_cycle=21845)

ONE, ZERO, GAP = (1280, 410), (440, 1250), 8000
BUTTONS = {
    "power": "110110000100",
    "up": "110110000001",
    "down": "110110010000",
    "timer": "110110000010",
}
PRESS_GAP_S = 0.6
sent_count = 0
last_sent = None


def pulses(bits, frames):
    out = []
    for f in range(frames):
        for b in bits:
            out.extend(ONE if b == "1" else ZERO)
        if f < frames - 1:
            out[-1] = GAP
    out.pop()  # must end on a mark
    return array.array("H", out)


def send(bits, frames=7):
    global sent_count, last_sent
    if len(bits) != 12 or set(bits) - {"0", "1"}:
        raise ValueError("need 12 bits")
    ir.send(pulses(bits, max(1, min(frames, 40))))
    sent_count += 1
    last_sent = bits


def press(name, n=1):
    bits = BUTTONS[name]
    for i in range(max(1, min(n, 40))):
        if i:
            time.sleep(PRESS_GAP_S)
        send(bits)


# ---------- USB serial (non-blocking) ----------
serial_buf = ""


def poll_serial():
    global serial_buf
    while supervisor.runtime.serial_bytes_available:
        ch = sys.stdin.read(1)
        if ch in "\r\n":
            line, serial_buf = serial_buf.strip(), ""
            if line:
                handle_serial(line)
        else:
            serial_buf += ch


def handle_serial(line):
    parts = line.split()
    try:
        if parts[0] in BUTTONS:
            press(parts[0], int(parts[1]) if len(parts) > 1 else 1)
        else:
            send(parts[0], int(parts[1]) if len(parts) > 1 else 7)
        print("sent", line)
    except Exception as e:
        print("err", e)


# ---------- Wi-Fi + HTTP ----------
server = None
pool = None
ip = None


def start_wifi():
    global server, pool, ip
    ssid = os.getenv("WIFI_SSID")
    if not ssid:
        print("no WIFI_SSID in settings.toml; serial only")
        return
    import wifi
    import socketpool
    try:
        wifi.radio.hostname = os.getenv("HOSTNAME") or "heater-ir"
        wifi.radio.connect(ssid, os.getenv("WIFI_PASSWORD"))
        ip = str(wifi.radio.ipv4_address)
        pool = socketpool.SocketPool(wifi.radio)
        try:
            import mdns
            global mdns_server
            mdns_server = mdns.Server(wifi.radio)
            mdns_server.hostname = os.getenv("HOSTNAME") or "heater-ir"
            mdns_server.advertise_service(service_type="_http", protocol="_tcp", port=80)
        except Exception as e:
            print("mdns failed:", e)
        server = pool.socket(pool.AF_INET, pool.SOCK_STREAM)
        server.setsockopt(pool.SOL_SOCKET, pool.SO_REUSEADDR, 1)
        server.bind(("0.0.0.0", 80))
        server.listen(2)
        server.setblocking(False)
        print("wifi ok", ip)
    except Exception as e:
        print("wifi failed:", e)
        server = None


def respond(conn, code, obj):
    body = json.dumps(obj)
    reason = {200: "OK", 400: "Bad Request", 404: "Not Found"}.get(code, "OK")
    conn.send(("HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\n"
               "Connection: close\r\n\r\n%s" % (code, reason, len(body), body)).encode())


def status():
    import wifi
    return {"ok": True, "ip": ip, "rssi": wifi.radio.ap_info.rssi if wifi.radio.ap_info else None,
            "buttons": BUTTONS, "sent": sent_count, "last": last_sent, "uptime_s": int(time.monotonic())}


def handle_http(conn):
    conn.settimeout(2)
    buf = bytearray(512)
    n = conn.recv_into(buf)
    req = bytes(buf[:n]).decode("utf-8", "replace")
    first = req.split("\r\n", 1)[0].split(" ")
    if len(first) < 2:
        return respond(conn, 400, {"error": "bad request"})
    path, _, query = first[1].partition("?")
    args = {}
    for kv in query.split("&"):
        if "=" in kv:
            k, v = kv.split("=", 1)
            args[k] = v
    parts = [p for p in path.split("/") if p]
    try:
        if not parts:
            return respond(conn, 200, status())
        if parts[0] == "press" and len(parts) == 2 and parts[1] in BUTTONS:
            n_press = int(args.get("n", "1"))
            press(parts[1], n_press)
            return respond(conn, 200, {"ok": True, "pressed": parts[1], "n": n_press})
        if parts[0] == "send" and len(parts) == 2:
            send(parts[1], int(args.get("frames", "7")))
            return respond(conn, 200, {"ok": True, "sent": parts[1]})
        return respond(conn, 404, {"error": "not found", "try": ["/", "/press/<%s>?n=1" % "|".join(BUTTONS),
                                                                  "/send/<12 bits>?frames=7"]})
    except Exception as e:
        return respond(conn, 400, {"error": str(e)})


def poll_http():
    if server is None:
        return
    try:
        conn, _ = server.accept()
    except OSError:
        return
    try:
        handle_http(conn)
    except Exception as e:
        print("http error:", e)
    finally:
        conn.close()


start_wifi()
print("ready")
last_wifi_check = time.monotonic()
while True:
    poll_serial()
    poll_http()
    if time.monotonic() - last_wifi_check > 30:
        last_wifi_check = time.monotonic()
        import wifi
        if not wifi.radio.connected:
            print("wifi lost; reconnecting")
            start_wifi()
    time.sleep(0.01)
