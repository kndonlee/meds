#!/usr/bin/env bash
#
# Install/update the "airctl CO2" Stream Deck plugin (live CO2 key) and restart the Stream Deck app.
# The key reads http://127.0.0.1:8788/status from the airctl daemon on this Mac.
#
#   ./install.sh            # copy plugin, restart Stream Deck app
#   ./install.sh --remove   # uninstall plugin, restart app
#
# After a first install, add the "CO2" action (category "airctl") to a key in the Stream Deck app,
# or place it by editing the profile JSON with the app quit.

set -euo pipefail
cd "$(dirname "$0")"

NAME="com.kndonlee.airctl.sdPlugin"
PLUGINS="$HOME/Library/Application Support/com.elgato.StreamDeck/Plugins"
APP="/Applications/Elgato Stream Deck.app"

quit_app() {
  pkill -x "Stream Deck" 2>/dev/null || true
  for _ in $(seq 1 40); do pgrep -x "Stream Deck" >/dev/null || return 0; sleep 0.5; done
  echo "Stream Deck app did not quit" >&2; exit 1
}

quit_app
if [[ "${1:-}" == "--remove" ]]; then
  rm -rf "${PLUGINS:?}/$NAME"
  echo "Removed $NAME"
else
  mkdir -p "$PLUGINS"
  rm -rf "${PLUGINS:?}/$NAME"
  cp -R "$NAME" "$PLUGINS/"
  echo "Installed $NAME"
fi
open -g "$APP"
echo "Stream Deck app restarted."
