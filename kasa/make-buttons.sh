#!/usr/bin/env bash
#
# Generates one tiny .app per outlet in ./buttons/. Drag an app onto a Stream
# Deck key using the built-in "System > Open" action -- it fires curl silently,
# with no browser window and no Terminal window.
#
# This is the zero-plugin path. For the lowest latency, use a Stream Deck HTTP
# plugin instead (see README) -- it skips the ~200ms app-launch cost.
#
# Requires the daemon to be running, since it asks it what outlets exist.

set -euo pipefail
cd "$(dirname "$0")"

PY=".venv/bin/python"
OUT="buttons"
ACTION="${1:-toggle}"   # toggle | on | off

[[ -x $PY ]] || { echo "Run ./setup.sh first." >&2; exit 1; }

PORT="$(awk -F= '/^\[server\]/{s=1;next} /^\[/{s=0} s&&/^ *port/{gsub(/ /,"",$2);print $2}' \
  kasa.conf 2>/dev/null | head -1)"
PORT="${PORT:-8787}"

aliases="$("$PY" - "$PORT" <<'EOF'
import json, sys, urllib.request
port = sys.argv[1]
try:
    data = json.load(urllib.request.urlopen(
        "http://127.0.0.1:%s/list" % port, timeout=5))
except Exception as exc:
    sys.exit("could not reach kasad on port %s: %s" % (port, exc))
for o in data["outlets"]:
    # skip positional duplicates like strip1/0
    if o["primary"] and "/" not in o["alias"]:
        print(o["alias"])
EOF
)"

[[ -n $aliases ]] || { echo "No outlets returned." >&2; exit 1; }

mkdir -p "$OUT"
count=0
while read -r alias; do
  [[ -n $alias ]] || continue
  app="${OUT}/${ACTION}-${alias}.app"
  rm -rf "$app"
  osacompile -o "$app" -e \
    "do shell script \"/usr/bin/curl -fsS --max-time 5 'http://127.0.0.1:${PORT}/${ACTION}/${alias}' >/dev/null 2>&1\"" \
    2>/dev/null
  count=$((count+1))
  echo "  $app"
done <<< "$aliases"

echo
echo "Built $count button apps in $(pwd)/${OUT}/"
echo "Stream Deck: add a 'System > Open' action, pick one of these .app bundles."
