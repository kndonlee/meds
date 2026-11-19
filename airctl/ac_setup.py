#!/usr/bin/env python3
"""One-time setup for a Midea-based (e.g. Toshiba) AC: fetch its local token/key using your app account.

Prompts for your MSmartHome (or other Midea) app login (not stored), authenticates against the AC on the LAN, and saves
ip/device_id/token/key to ac.json (gitignored). After this, control is purely local.

  .venv/bin/python ac_setup.py              # finds the AC automatically
  .venv/bin/python ac_setup.py 192.168.1.204
"""

import asyncio
import getpass
import json
import os
import sys

from msmart.cloud import NetHomePlusCloud, SmartHomeCloud
from msmart.discover import Discover
from msmart.lan import Security

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ac.json")


async def main(ip=None):
    if ip:
        dev = await Discover.discover_single(ip, auto_connect=False)
    else:
        print("Searching the local network for the AC...")
        found = await Discover.discover(auto_connect=False)
        dev = found[0] if found else None
        if dev is not None:
            ip = dev.ip
        if len(found or []) > 1:
            print(f"Found {len(found)} devices; using {ip}. Pass an IP to pick another.")
    if dev is None:
        sys.exit(f"No Midea device answered{' at ' + ip if ip else ''}. Is the AC on Wi-Fi?")
    print(f"Found {type(dev).__name__} id={dev.id} version={getattr(dev, 'version', '?')}")

    account = input("App account email: ").strip()
    password = getpass.getpass("App password (not stored): ")

    for cls in (SmartHomeCloud, NetHomePlusCloud):
        cloud = cls("US", account=account, password=password)
        try:
            await cloud.login()
        except Exception as e:
            print(f"  {cls.__name__}: login failed ({e})")
            continue
        for endian in ("little", "big"):
            udpid = Security.udpid(dev.id.to_bytes(6, endian)).hex()
            try:
                token, key = await cloud.get_token(udpid, dev.id)
                await dev.authenticate(token, key)
            except Exception as e:
                print(f"  {cls.__name__} ({endian}): {e}")
                continue
            with open(OUT, "w") as f:
                json.dump({"ip": ip, "port": 6444, "device_id": dev.id, "token": token, "key": key}, f, indent=2)
            os.chmod(OUT, 0o600)
            print(f"Success via {cls.__name__}. Saved {OUT}")
            return
    sys.exit("Could not get a working token/key. Check the login, or try again in a few minutes "
             "(a freshly paired AC can take a while to register in the cloud).")


if __name__ == "__main__":
    if len(sys.argv) > 2:
        sys.exit(__doc__)
    asyncio.run(main(sys.argv[1] if len(sys.argv) == 2 else None))
