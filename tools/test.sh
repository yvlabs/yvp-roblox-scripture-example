#!/usr/bin/env bash
# Offline unit suite. Spends no Platform requests.
set -euo pipefail
cd "$(dirname "$0")/.."
echo "== syntax =="
fail=0
for f in $(find src tests -name "*.luau" | sort); do
  if ! luau-compile --binary "$f" >/dev/null 2>/tmp/yvp-lc.txt; then
    echo "FAIL $f"; cat /tmp/yvp-lc.txt; fail=1
  fi
done
[ "$fail" -eq 0 ] || { echo "syntax errors"; exit 1; }
echo "all modules compile"
echo
echo "== ui overlay z-order =="
python3 tools/check-ui-overlays.py
echo
echo "== unit tests =="
luau tests/run.luau
