# Twin-Star / Duraflame IR sender. Reads lines on the USB serial console:
#   "<12 bits> [frames]"  e.g. "110110000001 7"   -> send that code
# Encoding (from Flipper-IRDB captures): 38 kHz carrier; bit 1 = 1280us mark + 410us space,
# bit 0 = 440us mark + 1250us space; frames separated by ~8000us.
import array
import board
import pulseio

PIN = getattr(board, "SCL1", None) or board.SCL   # STEMMA QT yellow wire (GPIO40)
ir = pulseio.PulseOut(PIN, frequency=38000, duty_cycle=21845)

ONE, ZERO, GAP = (1280, 410), (440, 1250), 8000


def pulses(bits, frames):
    out = []
    for f in range(frames):
        for b in bits:
            out.extend(ONE if b == "1" else ZERO)
        if f < frames - 1:
            out[-1] = GAP
    out.pop()  # must end on a mark
    return array.array("H", out)


print("ready")
while True:
    try:
        parts = input().split()
    except EOFError:
        continue
    if not parts:
        continue
    bits = parts[0]
    frames = int(parts[1]) if len(parts) > 1 else 7
    if len(bits) != 12 or set(bits) - {"0", "1"}:
        print("err need 12 bits")
        continue
    ir.send(pulses(bits, frames))
    print("sent", bits, frames)
