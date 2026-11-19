"""Keep macOS from using the Tivoo as a speaker/mic.

When the display connects over Bluetooth, macOS may auto-select the Tivoo as the audio output (it is
also a Bluetooth speaker). Every few seconds this checks output/system/input devices and, if one
matches `avoid`, switches back to the last other device in use (or `fallback`).

Needs SwitchAudioSource: brew install switchaudio-osx
"""

import asyncio
import logging
import shutil

log = logging.getLogger(__name__)

CANDIDATES = ["SwitchAudioSource", "/opt/homebrew/bin/SwitchAudioSource", "/usr/local/bin/SwitchAudioSource"]


class AudioGuard:
    def __init__(self, avoid="Tivoo", fallback_output="iMac Speakers", fallback_input="iMac Microphone",
                 interval=1, datalog=None):
        self.avoid = avoid.lower()
        self.fallback = {"output": fallback_output, "system": fallback_output, "input": fallback_input}
        self.interval = interval
        self.datalog = datalog
        self.last_good = {}
        self.bin = next((p for p in map(shutil.which, CANDIDATES) if p), None)

    async def _run(self, *args):
        proc = await asyncio.create_subprocess_exec(self.bin, *args, stdout=asyncio.subprocess.PIPE,
                                                    stderr=asyncio.subprocess.DEVNULL)
        out, _ = await proc.communicate()
        return out.decode().strip()

    async def check_once(self):
        for kind in ("output", "system", "input"):
            current = await self._run("-c", "-t", kind)
            if not current:
                continue
            if self.avoid not in current.lower():
                self.last_good[kind] = current
                continue
            target = (self.fallback.get(kind) if kind == "input" else None) or self.last_good.get(kind) or self.fallback.get(kind)
            if not target:
                devices = (await self._run("-a", "-t", kind)).splitlines()
                target = next((d for d in devices if self.avoid not in d.lower()), None)
            if target:
                await self._run("-t", kind, "-s", target)
                log.warning("audio %s was %r; switched back to %r", kind, current, target)
                if self.datalog:
                    self.datalog.event("audio_guard", kind=kind, was=current, now=target)

    async def run(self):
        if not self.bin:
            log.warning("audio guard disabled: SwitchAudioSource not found (brew install switchaudio-osx)")
            return
        log.info("audio guard: keeping %r off audio output/input", self.avoid)
        while True:
            try:
                await self.check_once()
            except Exception as e:
                log.debug("audio guard error: %s", e)
            await asyncio.sleep(self.interval)
