#!/usr/bin/env python3
"""Tivoo POC: talk to a Divoom Tivoo over Bluetooth Classic (RFCOMM) from macOS.

Uses Apple's IOBluetooth framework via PyObjC (pip install pyobjc-framework-IOBluetooth).

Protocol reference: hass-divoom (github.com/d03n3rfr1tz3/hass-divoom), devices/divoom.py
  message = 0x01 | len(LE16) | cmd | args... | checksum(LE16 = sum of len..args) | 0x02
  len     = len(args) + 3, no byte escaping for this device generation.
"""

import argparse
import math
import os
import sys

import objc
from Foundation import NSDate, NSDefaultRunLoopMode, NSObject, NSRunLoop
from IOBluetooth import (
    IOBluetoothDevice,
    IOBluetoothDeviceInquiry,
    IOBluetoothDevicePair,
)

kIOReturnSuccess = 0


# ---------------------------------------------------------------- helpers

def pump(timeout, until=lambda: False):
    """Spin the run loop (IOBluetooth delivers callbacks there)."""
    end = NSDate.dateWithTimeIntervalSinceNow_(timeout)
    while not until() and NSDate.date().compare_(end) < 0:
        NSRunLoop.currentRunLoop().runMode_beforeDate_(
            NSDefaultRunLoopMode, NSDate.dateWithTimeIntervalSinceNow_(0.05))


def fail(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


def hexs(b):
    return " ".join(f"{x:02x}" for x in b)


# ---------------------------------------------------------------- protocol

def message(cmd, args):
    length = len(args) + 3
    payload = [length & 0xFF, length >> 8, cmd] + list(args)
    s = sum(payload)
    payload += [s & 0xFF, (s >> 8) & 0xFF]
    return bytes([0x01] + payload + [0x02])


def msg_color(r, g, b, brightness=100):
    """'set view' light mode with a solid color."""
    return message(0x45, [0x01, r, g, b, brightness, 0x00, 0x01, 0, 0, 0])


def msg_brightness(v):
    return message(0x74, [v])


def msg_volume(percent):
    """'set volume'; the device uses a 0-15 scale (same conversion as hass-divoom)."""
    return message(0x08, [int(percent * 15 / 100)])


def msg_image(pixels, palette):
    """'set image' with a single 16x16 frame. pixels = palette indices, row-major."""
    assert len(pixels) == 256 and 1 <= len(palette) <= 255
    bits = max(1, math.ceil(math.log2(len(palette))))
    packed, acc, n = [], 0, 0
    for p in pixels:
        acc |= (p & ((1 << bits) - 1)) << n
        n += bits
        while n >= 8:
            packed.append(acc & 0xFF)
            acc >>= 8
            n -= 8
    if n:
        packed.append(acc & 0xFF)

    frame = [0x00, 0x00, 0x00, len(palette)]  # time, palette flag, color count
    for c in palette:
        frame += list(c)
    frame += packed
    flen = len(frame) + 3
    framed = [0xAA, flen & 0xFF, flen >> 8] + frame
    return message(0x44, [0x00, 0x0A, 0x0A, 0x04] + framed)


FONT_3X5 = {
    "0": ["###", "#.#", "#.#", "#.#", "###"],
    "1": [".#.", "##.", ".#.", ".#.", "###"],
    "2": ["###", "..#", "###", "#..", "###"],
    "3": ["###", "..#", "###", "..#", "###"],
    "4": ["#.#", "#.#", "###", "..#", "..#"],
    "5": ["###", "#..", "###", "..#", "###"],
    "6": ["###", "#..", "###", "#.#", "###"],
    "7": ["###", "..#", ".#.", ".#.", ".#."],
    "8": ["###", "#.#", "###", "#.#", "###"],
    "9": ["###", "#.#", "###", "..#", "###"],
    "-": ["...", "...", "###", "...", "..."],
    "C": ["###", "#..", "#..", "#..", "###"],
    "F": ["###", "#..", "##.", "#..", "#.."],
    "%": ["#.#", "..#", ".#.", "#..", "#.#"],
    "A": [".#.", "#.#", "###", "#.#", "#.#"],
    "B": ["##.", "#.#", "##.", "#.#", "##."],
    "E": ["###", "#..", "###", "#..", "###"],
    "H": ["#.#", "#.#", "###", "#.#", "#.#"],
    "M": ["#.#", "###", "###", "#.#", "#.#"],
    "O": ["###", "#.#", "#.#", "#.#", "###"],
    "P": ["###", "#.#", "###", "#..", "#.."],
    "R": ["##.", "#.#", "##.", "#.#", "#.#"],
    "T": ["###", ".#.", ".#.", ".#.", ".#."],
    ".": [".", ".", ".", ".", "#"],
}

# Vertical positions of up to three 5px rows on 16px: 1px gap under the first, colors separate the rest.
LINE_Y = [0, 6, 11]


def text_width(text):
    return sum(len(FONT_3X5[c][0]) for c in text) + len(text) - 1


def render_lines(lines):
    """lines = [(text, palette_index)], up to 3, each <= 16px wide. Returns 256 palette indices."""
    if not 1 <= len(lines) <= 3:
        fail("need 1-3 lines")
    px = [0] * 256
    ys = {1: [5], 2: [2, 9], 3: LINE_Y}[len(lines)]
    for (text, idx), y0 in zip(lines, ys):
        if not text or any(c not in FONT_3X5 for c in text):
            fail(f"unsupported characters in {text!r} (allowed: {''.join(FONT_3X5)})")
        w = text_width(text)
        if w > 16:
            fail(f"{text!r} is {w}px wide; max 16")
        x = (16 - w + 1) // 2
        for ch in text:
            glyph = FONT_3X5[ch]
            for gy, row in enumerate(glyph):
                for gx, c in enumerate(row):
                    if c == "#":
                        px[(y0 + gy) * 16 + x + gx] = idx
            x += len(glyph[0]) + 1
    return px


def render_number(text):
    if not (1 <= len(text) <= 4) or any(c not in FONT_3X5 for c in text):
        fail("number must be 1-4 characters of 0-9 or '-'")
    scale = 2 if len(text) <= 2 else 1
    gw, gh, gap = 3 * scale, 5 * scale, scale
    total_w = len(text) * gw + (len(text) - 1) * gap
    x0, y0 = (16 - total_w) // 2, (16 - gh) // 2
    px = [0] * 256
    for i, ch in enumerate(text):
        for gy, row in enumerate(FONT_3X5[ch]):
            for gx, c in enumerate(row):
                if c != "#":
                    continue
                for sy in range(scale):
                    for sx in range(scale):
                        x = x0 + i * (gw + gap) + gx * scale + sx
                        y = y0 + gy * scale + sy
                        px[y * 16 + x] = 1
    return px


# ---------------------------------------------------------------- bluetooth: scan

class Scanner(NSObject):
    def init(self):
        self = objc.super(Scanner, self).init()
        self.done = False
        self.found = {}
        return self

    def deviceInquiryDeviceFound_device_(self, sender, device):
        self.found[device.addressString()] = device

    def deviceInquiryDeviceNameUpdated_device_devicesRemaining_(self, sender, device, remaining):
        self.found[device.addressString()] = device

    def deviceInquiryComplete_error_aborted_(self, sender, error, aborted):
        self.done = True


def cmd_scan(a):
    s = Scanner.alloc().init()
    inq = IOBluetoothDeviceInquiry.inquiryWithDelegate_(s)
    inq.setInquiryLength_(min(a.seconds, 60))
    inq.setUpdateNewDeviceNames_(True)
    print(f"Scanning {a.seconds}s for Bluetooth Classic devices (Tivoo should be on / in pairing mode)...")
    if inq.start() != kIOReturnSuccess:
        fail("inquiry failed to start (Bluetooth off, or terminal lacks Bluetooth permission?)")
    pump(a.seconds + 15, lambda: s.done)
    if not s.found:
        print("No devices found.")
    for addr, d in sorted(s.found.items()):
        name = d.name() or "(no name)"
        hint = "   <-- Divoom?" if any(k in name.lower() for k in ("voo", "divoom")) else ""
        print(f"{addr}  {name}{hint}")


# ---------------------------------------------------------------- bluetooth: pair

class Pairer(NSObject):
    def init(self):
        self = objc.super(Pairer, self).init()
        self.done = False
        self.status = kIOReturnSuccess
        return self

    def devicePairingUserConfirmationRequest_numericValue_(self, sender, value):
        sender.replyUserConfirmation_(True)

    def devicePairingPINCodeRequest_(self, sender):
        # Legacy pairing; Divoom devices typically accept 0000.
        try:
            sender.replyPINCode_PINCode_(4, (ord("0"),) * 4 + (0,) * 12)
        except Exception as e:  # struct bridging can be finicky
            print(f"Could not answer PIN request ({e}); pair from System Settings instead.")

    def devicePairingFinished_error_(self, sender, error):
        self.status = error
        self.done = True


def get_device(mac):
    d = IOBluetoothDevice.deviceWithAddressString_(mac)
    if d is None:
        fail(f"bad MAC address: {mac}")
    return d


def cmd_pair(a):
    d = get_device(a.mac)
    if d.isPaired():
        print(f"{a.mac} is already paired.")
        return
    p = Pairer.alloc().init()
    pairing = IOBluetoothDevicePair.pairWithDevice_(d)
    pairing.setDelegate_(p)
    print(f"Pairing with {a.mac}...")
    if pairing.start() != kIOReturnSuccess:
        fail("pairing failed to start")
    pump(45, lambda: p.done)
    if not p.done:
        fail("pairing timed out")
    if p.status != kIOReturnSuccess:
        fail(f"pairing failed: 0x{p.status & 0xffffffff:08x}")
    print("Paired.")


# ---------------------------------------------------------------- bluetooth: SDP

class SDPWaiter(NSObject):
    def init(self):
        self = objc.super(SDPWaiter, self).init()
        self.done = False
        return self

    @objc.typedSelector(b"v@:@i")
    def sdpQueryComplete_status_(self, device, status):
        self.done = True


def rfcomm_services(d):
    """[(channel, service name)] for every RFCOMM service, after refreshing SDP."""
    w = SDPWaiter.alloc().init()
    if d.performSDPQuery_(w) == kIOReturnSuccess:
        pump(15, lambda: w.done)
    out = []
    for rec in d.services() or []:
        status, ch = rec.getRFCOMMChannelID_(None)
        if status == kIOReturnSuccess:
            out.append((ch, rec.getServiceName() or "(unnamed)"))
    return out


def pick_channel(d, override):
    if override is not None:
        return override
    services = rfcomm_services(d)
    for ch, name in services:
        print(f"  RFCOMM channel {ch}: {name}")
    for ch, name in services:
        if "serial" in name.lower() or "spp" in name.lower():
            return ch
    if services:
        return services[0][0]
    print("  No RFCOMM services found via SDP, trying channel 1")
    return 1


def cmd_channels(a):
    services = rfcomm_services(get_device(a.mac))
    if not services:
        print("No RFCOMM services found.")
    for ch, name in services:
        print(f"RFCOMM channel {ch}: {name}")


# ---------------------------------------------------------------- bluetooth: RFCOMM send

class Channel(NSObject):
    def init(self):
        self = objc.super(Channel, self).init()
        self.open_status = None
        self.rx = bytearray()
        self.closed = False
        return self

    def rfcommChannelOpenComplete_status_(self, ch, status):
        self.open_status = status

    def rfcommChannelData_data_length_(self, ch, data, length):
        try:
            self.rx += bytes(data.as_buffer(length)) if hasattr(data, "as_buffer") else bytes(data[:length])
        except Exception:
            pass

    def rfcommChannelClosed_(self, ch):
        self.closed = True


class Link:
    """An open RFCOMM connection. Keeping one open avoids the Tivoo's connect chime per update."""

    def __init__(self, mac, channel, attempts=5):
        self.mac = mac
        self.d = get_device(mac)
        if not self.d.isPaired():
            print(f"Warning: {mac} is not paired; run `pair` first if this fails.")
        self.ch_id = pick_channel(self.d, channel)
        self.chan = None
        self.open(attempts)

    def _try_open(self):
        """One attempt. Returns None on success, else an error string."""
        self.delegate = Channel.alloc().init()
        status, self.chan = self.d.openRFCOMMChannelAsync_withChannelID_delegate_(None, self.ch_id, self.delegate)
        if status != kIOReturnSuccess or self.chan is None:
            return f"open failed: 0x{status & 0xffffffff:08x}"
        pump(10, lambda: self.delegate.open_status is not None)
        if self.delegate.open_status is None:
            return "timed out opening channel"
        if self.delegate.open_status != kIOReturnSuccess:
            return f"channel open failed: 0x{self.delegate.open_status & 0xffffffff:08x}"
        return None

    def open(self, attempts=5):
        for i in range(1, attempts + 1):
            print(f"Connecting to {self.mac} on RFCOMM channel {self.ch_id} (attempt {i})...", flush=True)
            err = self._try_open()
            if err is None:
                self.mtu = self.chan.getMTU()
                print(f"Connected (MTU {self.mtu}).", flush=True)
                pump(0.5)  # let the device settle, like hass-divoom does
                return
            print(f"  {err}", flush=True)
            # macOS often auto-connects the Tivoo as a hands-free audio device, which holds the
            # same RFCOMM channel. Drop the baseband link and back off before retrying.
            if self.chan is not None:
                self.chan.closeChannel()
            self.d.closeConnection()
            pump(min(2 * i, 8))
        fail("could not connect to the Tivoo (is your phone or the Divoom app connected to it?)")

    def write(self, msg, verbose=True):
        """Send one message. Returns False if the connection dropped."""
        if verbose:
            print(f"-> {hexs(msg)}")
        self.delegate.rx.clear()
        for off in range(0, len(msg), self.mtu):
            chunk = msg[off:off + self.mtu]
            wr = self.chan.writeSync_length_(chunk, len(chunk))
            if wr != kIOReturnSuccess:
                print(f"write failed: 0x{wr & 0xffffffff:08x}", file=sys.stderr)
                return False
        pump(0.3)
        if verbose and self.delegate.rx:
            print(f"<- {hexs(self.delegate.rx)}")
        return True

    def reconnect(self):
        print("Tivoo connection lost; reconnecting...", file=sys.stderr, flush=True)
        if self.chan is not None:
            self.chan.closeChannel()
        self.d.closeConnection()
        pump(2)
        self.open(attempts=10)

    def close(self):
        if self.chan is not None:
            self.chan.closeChannel()
        self.d.closeConnection()


def send(mac, channel, messages):
    link = Link(mac, channel)
    for msg in messages:
        if not link.write(msg):
            fail("connection dropped")
    pump(0.3)
    link.close()
    print("Done.")


def _spec(spec, palette):
    text, _, rgb = spec.rpartition(":")
    if not text:
        text, rgb = rgb, "255,255,255"
    color = tuple(int(v) for v in rgb.split(","))
    if len(color) != 3 or not all(0 <= v <= 255 for v in color):
        raise ValueError(f"bad color in {spec!r}")
    if color not in palette:
        palette.append(color)
    return text, palette.index(color)


def _draw_text(px, text, idx, y0, yscale=1):
    if any(c not in FONT_3X5 for c in text):
        fail(f"unsupported characters in {text!r} (allowed: {''.join(FONT_3X5)})")
    w = text_width(text)
    if w > 16:
        fail(f"{text!r} is {w}px wide; max 16")
    x = (16 - w + 1) // 2
    for ch in text:
        glyph = FONT_3X5[ch]
        for gy, row in enumerate(glyph):
            for gx, c in enumerate(row):
                if c == "#":
                    for sy in range(yscale):
                        px[(y0 + gy * yscale + sy) * 16 + x + gx] = idx
        x += len(glyph[0]) + 1


def msg_page(specs):
    """Single-metric page: ["LABEL:r,g,b", "VALUE:r,g,b", "@x,y:r,g,b"...].

    Row 0 is free for pixels (progress/status dots), label on rows 1-5, value double-height on rows 6-15.
    """
    palette, texts, dots = [(0, 0, 0)], [], []
    for spec in specs:
        text, idx = _spec(spec, palette)
        if text.startswith("@"):
            x, y = (int(v) for v in text[1:].split(","))
            if not (0 <= x < 16 and 0 <= y < 16):
                raise ValueError(f"pixel out of range in {spec!r}")
            dots.append((x, y, idx))
        else:
            texts.append((text, idx))
    if len(texts) != 2:
        raise ValueError("page needs a label and a value")
    px = [0] * 256
    _draw_text(px, texts[0][0], texts[0][1], 1)
    _draw_text(px, texts[1][0], texts[1][1], 6, yscale=2)
    for x, y, idx in dots:
        px[y * 16 + x] = idx
    return msg_image(px, palette)


def msg_lines(specs):
    """specs = ["TEXT:r,g,b", ...] -> image message with one text line per spec.

    A spec of the form "@x,y:r,g,b" sets a single pixel instead (e.g. status dots)."""
    palette, lines, dots = [(0, 0, 0)], [], []
    for spec in specs:
        text, _, rgb = spec.rpartition(":")
        if not text:
            text, rgb = rgb, "255,255,255"
        color = tuple(int(v) for v in rgb.split(","))
        if len(color) != 3 or not all(0 <= v <= 255 for v in color):
            raise ValueError(f"bad color in {spec!r}")
        if color not in palette:
            palette.append(color)
        if text.startswith("@"):
            x, y = (int(v) for v in text[1:].split(","))
            if not (0 <= x < 16 and 0 <= y < 16):
                raise ValueError(f"pixel out of range in {spec!r}")
            dots.append((x, y, palette.index(color)))
        else:
            lines.append((text, palette.index(color)))
    px = render_lines(lines) if lines else [0] * 256
    for x, y, idx in dots:
        px[y * 16 + x] = idx
    return msg_image(px, palette)


def parse_line(line):
    """One stream command -> message bytes, or None if blank/invalid."""
    parts = line.split()
    if not parts:
        return None
    cmd, rest = parts[0].lower(), parts[1:]
    try:
        if cmd == "number" and rest:
            fg = tuple(int(x) for x in rest[1:4]) if len(rest) >= 4 else (255, 160, 0)
            return msg_image(render_number(rest[0]), [(0, 0, 0), fg])
        if cmd == "lines" and rest:
            return msg_lines(rest)
        if cmd == "page" and rest:
            return msg_page(rest)
        if cmd == "black":
            return msg_image([0] * 256, [(0, 0, 0)])
        if cmd == "color" and len(rest) == 3:
            return msg_color(*(int(x) for x in rest))
        if cmd == "brightness" and len(rest) == 1:
            return msg_brightness(int(rest[0]))
        if cmd == "volume" and len(rest) == 1:
            return msg_volume(int(rest[0]))
        if cmd.lstrip("-").isdigit():  # bare number shorthand
            return msg_image(render_number(cmd), [(0, 0, 0), (255, 160, 0)])
    except (ValueError, SystemExit):
        pass
    print(f"?? ignoring: {line.strip()}", file=sys.stderr)
    return None


def cmd_stream(a):
    """Connect once, then apply one command per stdin line until EOF."""
    link = Link(a.mac, a.channel)
    print("Streaming: one command per line (e.g. `42`, `number 7 0 200 255`, `color 0 255 0`). Ctrl-D to stop.")
    import select
    buf, last_msg = "", None
    try:
        while True:
            # keep the Bluetooth run loop serviced while waiting for input (updates may be a minute apart)
            ready, _, _ = select.select([sys.stdin], [], [], 0.1)
            if not ready:
                pump(0.1)
                if link.delegate.closed:
                    link.reconnect()
                    if last_msg:
                        link.write(last_msg, verbose=a.verbose)
                continue
            chunk = os.read(sys.stdin.fileno(), 4096).decode(errors="replace")
            if not chunk:
                break  # EOF
            buf += chunk
            while "\n" in buf:
                line, buf = buf.split("\n", 1)
                msg = parse_line(line)
                if msg:
                    if not link.write(msg, verbose=a.verbose):
                        link.reconnect()
                        link.write(msg, verbose=a.verbose)
                    last_msg = msg
                    print(f"ok: {line.strip()}", flush=True)
    except KeyboardInterrupt:
        pass
    finally:
        link.close()
        print("Disconnected.")


def byte(s):
    v = int(s)
    if not 0 <= v <= 255:
        raise argparse.ArgumentTypeError("expected 0-255")
    return v


def main():
    ap = argparse.ArgumentParser(description="Divoom Tivoo Bluetooth POC (macOS)")
    ap.add_argument("--channel", type=byte, help="force RFCOMM channel (skip SDP)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("scan", help="find nearby Bluetooth Classic devices")
    p.add_argument("seconds", nargs="?", type=int, default=10)
    p.set_defaults(fn=cmd_scan)

    p = sub.add_parser("pair", help="pair with the Tivoo")
    p.add_argument("mac")
    p.set_defaults(fn=cmd_pair)

    p = sub.add_parser("channels", help="list RFCOMM channels via SDP")
    p.add_argument("mac")
    p.set_defaults(fn=cmd_channels)

    p = sub.add_parser("color", help="solid color light")
    p.add_argument("mac")
    p.add_argument("rgb", nargs=3, type=byte)
    p.set_defaults(fn=lambda a: send(a.mac, a.channel, [msg_color(*a.rgb)]))

    p = sub.add_parser("brightness", help="set brightness 0-100")
    p.add_argument("mac")
    p.add_argument("value", type=byte)
    p.set_defaults(fn=lambda a: send(a.mac, a.channel, [msg_brightness(a.value)]))

    p = sub.add_parser("volume", help="set speaker volume 0-100")
    p.add_argument("mac")
    p.add_argument("value", type=byte)
    p.set_defaults(fn=lambda a: send(a.mac, a.channel, [msg_volume(a.value)]))

    p = sub.add_parser("stream", help="stay connected; read one command per stdin line (no chime per update)")
    p.add_argument("mac")
    p.add_argument("-v", "--verbose", action="store_true", help="print bytes sent/received")
    p.set_defaults(fn=cmd_stream)

    p = sub.add_parser("lines", help="show 1-3 text lines, e.g. 1241:255,0,0 75F 43%%:0,140,255")
    p.add_argument("mac")
    p.add_argument("specs", nargs="+", help="TEXT[:r,g,b]; chars 0-9 - . C F %%")
    p.set_defaults(fn=lambda a: send(a.mac, a.channel, [msg_lines(a.specs)]))

    p = sub.add_parser("number", help="show a 1-4 digit number")
    p.add_argument("mac")
    p.add_argument("n")
    p.add_argument("rgb", nargs="*", type=byte, help="foreground color (default orange)")
    p.set_defaults(fn=lambda a: send(a.mac, a.channel, [
        msg_image(render_number(a.n), [(0, 0, 0), tuple(a.rgb) if len(a.rgb) == 3 else (255, 160, 0)])]))

    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
