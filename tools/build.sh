#!/usr/bin/env bash
# Build the place file. Runs the offline suite first.
set -euo pipefail
cd "$(dirname "$0")/.."
./tools/test.sh
mkdir -p build
rojo build default.project.json --output build/ScriptureKiosk.rbxlx
echo
echo "built: build/ScriptureKiosk.rbxlx"
python3 tools/scan-secrets.py build/ScriptureKiosk.rbxlx
