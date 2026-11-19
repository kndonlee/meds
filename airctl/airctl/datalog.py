"""Files the meds dashboard reads (data/ is gitignored):

  readings-YYYY-MM-DD.jsonl  one line per sensor measurement
  events-YYYY-MM-DD.jsonl    switches (with reasons), errors, starts; the dashboard appends feedback here
  status.json                current snapshot, atomically replaced on every reading

Every line has "ts" (unix seconds) and "time" (local ISO). Files older than keep_days are deleted.
"""

import json
import os
import time
from datetime import datetime


class DataLog:
    def __init__(self, directory="data", keep_days=14):
        base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.dir = directory if os.path.isabs(directory) else os.path.join(base, directory)
        self.keep_days = keep_days
        os.makedirs(self.dir, exist_ok=True)
        self._pruned_day = None

    def _stamp(self, rec):
        now = time.time()
        return {"ts": round(now, 1), "time": datetime.fromtimestamp(now).isoformat(timespec="seconds"), **rec}

    def _append(self, kind, rec):
        day = datetime.now().strftime("%Y-%m-%d")
        with open(os.path.join(self.dir, f"{kind}-{day}.jsonl"), "a") as f:
            f.write(json.dumps(self._stamp(rec)) + "\n")
        if self._pruned_day != day:
            self._prune()
            self._pruned_day = day

    def reading(self, r):
        self._append("readings", {"co2": r.co2, "temp_f": _r1(r.temp_f), "humidity": _r1(r.humidity),
                                  "pressure_hpa": _r1(r.pressure_hpa), "source": r.source})

    def event(self, type_, **fields):
        self._append("events", {"type": type_, **fields})

    def status(self, snapshot):
        tmp = os.path.join(self.dir, ".status.json.tmp")
        with open(tmp, "w") as f:
            json.dump(self._stamp(snapshot), f, indent=1)
        os.replace(tmp, os.path.join(self.dir, "status.json"))

    def _prune(self):
        cutoff = time.time() - self.keep_days * 86400
        for name in os.listdir(self.dir):
            if name.endswith(".jsonl"):
                path = os.path.join(self.dir, name)
                if os.path.getmtime(path) < cutoff:
                    os.remove(path)


def _r1(v):
    return None if v is None else round(v, 1)
