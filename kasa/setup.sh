#!/usr/bin/env bash
#
# One-time setup for kasad. Safe to re-run (the auto-update pulls new code,
# this refreshes the venv to match).

set -euo pipefail
cd "$(dirname "$0")"

VENV=".venv"

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 not found. brew install python3" >&2
  exit 1
fi

if [[ ! -d $VENV ]]; then
  echo "Creating venv..."
  python3 -m venv "$VENV"
fi

echo "Installing python-kasa..."
"$VENV/bin/pip" install -q --disable-pip-version-check --upgrade pip python-kasa

if [[ ! -f kasa.conf ]]; then
  cp kasa.conf.example kasa.conf
  chmod 600 kasa.conf
  echo
  echo "Created kasa.conf -- edit it with your TP-Link credentials, then:"
  echo "    ./kasactl list"
else
  chmod 600 kasa.conf
  echo "kasa.conf already present, leaving it alone."
fi

echo "Done."
