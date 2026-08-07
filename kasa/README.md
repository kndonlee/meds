# kasad — local Kasa control for the Stream Deck

Replaces the IFTTT webhook with a direct LAN call.

```
before:  Stream Deck ──> IFTTT cloud ──> TP-Link cloud ──> plug     (~2-6s, flaky)
after:   Stream Deck ──> localhost:8787 ──> plug                    (48-87ms measured)
```

Measured on the real strips:

| Path | Latency |
|---|---|
| `/on` or `/off` (HTTP plugin) | **48–87 ms** |
| `/state`, cache warm | ~2 ms |
| `/state`, cache stale | ~40–90 ms |
| Generated `.app` button, end to end | 334–687 ms (macOS app launch dominates) |

The strips are `HS300` power strips (6 outlets each) speaking TP-Link's **KLAP**
protocol. KLAP needs your TP-Link account credentials to complete its handshake,
but that handshake happens **device-to-device on your LAN** — nothing leaves the
house when you press a button, and it works with the internet unplugged.

Written in Python rather than Ruby because `python-kasa` is the only mature KLAP
implementation. It lives in its own venv and does not touch the Gemfile.

## Devices are tracked by MAC, not IP

**There are no IP addresses to maintain.** A power outage, DHCP lease shuffle, or
router reboot can move every strip to a new address and the daemon just finds
them again.

How it works:

1. Identity is the **MAC address**, which never changes.
2. Current IPs live in `.kasa-cache.json` — a disposable cache, gitignored.
3. A press first tries the cached IP (fast unicast, no discovery cost).
4. If that fails, the daemon **broadcasts** for the strip and reattaches by MAC.
5. If an IP now belongs to a *different* device, the MAC check catches it and
   refuses to command the wrong strip.

Discovery is unauthenticated at the UDP layer, so relocation works even if your
credentials are wrong or the cache is deleted.

Static DHCP reservations are therefore **optional**. They shave the one-time
relocation sweep off the first press after an outage, nothing more.

## Setup

```sh
cd ~/repos/meds/kasa
./setup.sh                      # builds .venv, installs python-kasa, seeds kasa.conf
$EDITOR kasa.conf               # add your TP-Link email + password
./kasactl list                  # confirms local auth, prints every outlet
```

`kasa.conf` is gitignored and `chmod 600`. It never gets committed.

Leave `[devices]` **empty** to auto-adopt every Kasa device on the network —
that is the recommended setup, and new strips appear on their own. Pin entries
by MAC only if you want to ignore some devices or force stable internal names.

## Running

```sh
./kasactl run                   # foreground, for testing
./kasactl install-service       # launchd: starts at login, restarts on crash
./kasactl health                # which strips are reachable, and at what IP
./kasactl rediscover            # force a rescan (rarely needed; it self-heals)
./kasactl logs
```

## Endpoints

| Route | Does |
|---|---|
| `GET /toggle/<alias>` | flip an outlet |
| `GET /on/<alias>` / `/off/<alias>` | force a state (better than toggle for buttons — see below) |
| `GET /state/<alias>` | current state |
| `GET /list` | every alias, with MAC and current IP |
| `GET /healthz` | device reachability |
| `GET /rediscover` | force a broadcast sweep |
| `GET /` | clickable page, handy as a phone bookmark |

Aliases are auto-derived from the names you set in the Kasa app — "Desk Lamp"
becomes `desk-lamp`. Positional names (`strip1/0` … `strip1/5`) always work too.
Add friendly overrides in the `[aliases]` section of `kasa.conf`.

## Wiring up the Stream Deck

**Option A — HTTP plugin (lowest latency, recommended).** Install a request
plugin from the Stream Deck store (BarRaider's *Web Requests*, or any
"HTTP Request" plugin). Point a key at `http://127.0.0.1:8787/toggle/desk-lamp`.
The plugin fires the GET in-process — no window, no app launch.

**Option B — generated .app (zero plugins).**

```sh
./make-buttons.sh               # or: ./make-buttons.sh on
```

Creates `buttons/toggle-<alias>.app` for every outlet. In Stream Deck, add a
**System → Open** action and select one. It runs silently. Measured at
334–687ms end to end — the request is still ~50ms, but macOS app launch adds
the rest, so Option A is roughly 7× faster.

Do *not* use Stream Deck's "Website" action — it opens a browser tab.

### Prefer `/on` and `/off` over `/toggle`

`/toggle` reads state first, so a Stream Deck key can drift out of sync if
someone hits the physical button or the app. If you have keys to spare, a
dedicated on key and off key are both faster and unambiguous.

## Two upstream workarounds live in kasad.py

Both are applied at runtime rather than by editing `.venv`, which `setup.sh`
would overwrite on reinstall.

**1. python-kasa picks the wrong KLAP transport (`patch_iot_klap_v2`).**
`device_factory.get_protocol()` selects a transport with the lookup key
`f"{family}.{encryption}"` and never consults `login_version`:

```python
"IOT.KLAP":   (IotProtocol,   KlapTransport)      # v1: md5(md5(u)+md5(p))
"SMART.KLAP": (SmartProtocol, KlapTransportV2)    # v2: sha256(sha1(u)+sha1(p))
```

An HS300 hw 2.0 reports family `IOT.SMARTPLUGSWITCH`, encryption `KLAP` **and
`login_version 2`**, so it lands on the v1 md5 hash and every handshake is
rejected. The failure is reported as "check that your e-mail and password are
correct", which is indistinguishable from a wrong password — it is not.

Verified directly against the device's `handshake1` challenge: it validates
against `sha256(sha1(user)+sha1(pass))` and not against the md5 form. Worth
re-testing after a python-kasa upgrade; if fixed upstream, delete the shim.

**2. Strips come back as `IotPlug`, hiding all six outlets.** Discovery
constructs the wrong class, so `children` is empty even though `sys_info`
lists six. `_attach` re-wraps as `IotStrip`, reusing the already-authenticated
protocol instead of handshaking again.

Related tuning, not a bug: `IotStrip.update()` issues one query per child
(~1.5s on an HS300). The parent's sysinfo already carries every child's relay
state, so refreshes use `update(update_children=False)` — same data, ~40ms.

## Troubleshooting

- **"Device response did not match our challenge"** — the strip is reachable and
  rejected the login. On these HS300s this was *not* a bad password; it was the
  KLAP v1/v2 transport bug above. If it reappears after a python-kasa upgrade,
  check that `patch_iot_klap_v2()` is still being applied before blaming
  credentials. Note that credentials in `kasa.conf` must be **unquoted** —
  configparser passes quote marks through as part of the value.
- **A strip shows UNREACHABLE** — `./kasactl health` shows the MAC it is looking
  for. Confirm the strip has power and is on the same subnet/VLAN as this
  machine. Broadcast discovery does not cross VLANs.
- **Discovery finds nothing** — some routers filter `255.255.255.255`. Set
  `broadcast = 192.168.1.255` in `kasa.conf`.
- **Slow first press after an outage** — expected once, while the daemon
  relocates the strip. Subsequent presses are back to normal.

## Moving this to another machine

Clone the repo, run `./setup.sh`, copy `kasa.conf` over by hand (it is not in
git, by design), and `./kasactl install-service`. No IP addresses to migrate —
the daemon discovers the strips wherever they are.

## Shades (Motion Blinds / Connector)

The Connector app is a front end for the Coulisse/Dooya bridge, which exposes a
JSON-over-UDP API on port 32100. Same approach as the outlets: talk to the
hardware on the LAN instead of through a vendor cloud.

| Route | Does |
|---|---|
| `GET /shade/<alias>/<0-100>` | move to a percentage |
| `GET /shade/<alias>/open` / `close` / `stop` | full travel, or halt mid-move |
| `GET /shade/<alias>/state` | position, battery, signal |

**Positions are `0 = fully open`, `100 = fully closed`** — the protocol's own
convention, kept so it matches anything else you read about these bridges.

### Setup

Put the 16-character key from the Connector app in `[blinds]` of `kasa.conf`:

> Settings / About → tap the **version number** 5 times → **Key**

Reading position needs **no key at all** — `ReadDevice` is unauthenticated on
this bridge. Without one, shades still appear in `/list` and `/healthz`, just
marked `writable: false`. Only movement needs the key, which authenticates as
AES-128-ECB over the bridge's rotating token.

The bridge reports MACs only; the friendly names live in the app and are not
exposed. Shades get ordinal names (`shade-1`…) until you map them in
`[shades]`, by MAC or by 1-based position.

### Two quirks, both found by probing the hardware

- **The bridge answers unicast only.** Broadcast and multicast `GetDeviceList`
  get no reply, so discovery sweeps the /24 — 254 datagrams in ~10ms. That
  doubles as MAC-based relocation, same as the strips.
- **Shades move slowly** (10–20s). `/shade/<a>/<pct>` returns as soon as the
  bridge accepts the command and reports the *target*; the poller corrects the
  cached position once the motor arrives. `stop` is there for mid-travel.

### Stream Deck

Preset keys are the most predictable mapping, since each is idempotent — the
same press always lands the shade in the same place:

```
http://127.0.0.1:8787/shade/kitchen/0      fully open
http://127.0.0.1:8787/shade/kitchen/50     half
http://127.0.0.1:8787/shade/kitchen/100    fully closed
```
