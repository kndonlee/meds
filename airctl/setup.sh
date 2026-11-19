#!/usr/bin/env bash
#
# One-time setup for airctl. Safe to re-run (refreshes the venv to match requirements.txt).
#
#   ./setup.sh
#   .venv/bin/python tivoo.py scan / pair <mac>   # pair the Tivoo with this Mac (once)
#   .venv/bin/python ac_setup.py                  # fetch the AC's local key -> ac.json (once)
#   ./airctlctl install-service

set -euo pipefail
cd "$(dirname "$0")"

VENV=".venv"

# Need Python >= 3.11 (tomllib). Homebrew isn't on PATH in non-interactive shells, so look there too.
PY=""
for cand in python3.14 python3.13 python3.12 python3.11 /opt/homebrew/bin/python3 /usr/local/bin/python3 python3; do
  p=$(command -v "$cand" 2>/dev/null || true)
  [[ -z $p && -x $cand ]] && p=$cand
  [[ -z $p ]] && continue
  if "$p" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then PY=$p; break; fi
done
if [[ -z $PY ]]; then
  echo "Error: need Python >= 3.11. Install with: brew install python" >&2
  exit 1
fi

if [[ -d $VENV ]] && ! "$VENV/bin/python" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
  echo "Existing venv is too old; recreating..."
  rm -rf "$VENV"
fi
if [[ ! -d $VENV ]]; then
  echo "Creating venv with $PY ($("$PY" --version))..."
  "$PY" -m venv "$VENV"
fi

echo "Installing requirements..."
"$VENV/bin/pip" install -q --disable-pip-version-check --upgrade pip
"$VENV/bin/pip" install -q --disable-pip-version-check -r requirements.txt

# Audio guard (keeps macOS from using the Tivoo as a speaker) needs SwitchAudioSource.
BREW=$(command -v brew || ls /opt/homebrew/bin/brew /usr/local/bin/brew 2>/dev/null | head -1 || true)
if ! command -v SwitchAudioSource >/dev/null && [[ ! -x /opt/homebrew/bin/SwitchAudioSource ]]; then
  if [[ -n $BREW ]]; then
    echo "Installing switchaudio-osx (audio guard)..."
    "$BREW" install -q switchaudio-osx || echo "Warning: could not install switchaudio-osx"
  else
    echo "Warning: Homebrew not found; install switchaudio-osx for the audio guard."
  fi
fi

if [[ ! -f config.toml ]]; then
  cp config.example.toml config.toml
  echo "Created config.toml from the example -- review thresholds and device addresses."
fi
[[ -f ac.json ]] && chmod 600 ac.json || echo "Note: no ac.json yet -- run: .venv/bin/python ac_setup.py"

echo "Done."
