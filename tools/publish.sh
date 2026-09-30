#!/usr/bin/env bash
# Publish the built place to Roblox via Open Cloud. No Studio required.
#
# Requires an Open Cloud API key with universe-places:write, supplied as
# ROBLOX_API_KEY in the environment. Never commit the key.
set -euo pipefail
cd "$(dirname "$0")/.."

UNIVERSE_ID="${ROBLOX_UNIVERSE_ID:?set ROBLOX_UNIVERSE_ID to your experience (universe) id}"
PLACE_ID="${ROBLOX_PLACE_ID:?set ROBLOX_PLACE_ID to your start place id}"
PLACE_FILE="build/ScriptureKiosk.rbxlx"
VERSION_TYPE="${1:-Published}"   # Published (live) or Saved (draft)

case "$VERSION_TYPE" in
  Published|Saved) ;;
  *) echo "usage: $0 [Published|Saved]" >&2; exit 2 ;;
esac

# Always ship a freshly built, freshly tested artifact.
./tools/build.sh

KEY="${ROBLOX_API_KEY:?set ROBLOX_API_KEY to an Open Cloud API key (see README)}"

echo
echo "publishing $PLACE_FILE -> universe $UNIVERSE_ID / place $PLACE_ID ($VERSION_TYPE)"

RESPONSE="$(mktemp)"
trap 'rm -f "$RESPONSE"' EXIT

# Roblox returns 409 when the place is locked, typically because Studio has it
# open or a previous save is still settling. It clears on its own, so retry
# with backoff rather than failing the release.
ATTEMPT=0
MAX_ATTEMPTS=5
while :; do
  ATTEMPT=$((ATTEMPT + 1))
  STATUS="$(curl -sS -o "$RESPONSE" -w '%{http_code}' \
    -X POST \
    "https://apis.roblox.com/universes/v1/${UNIVERSE_ID}/places/${PLACE_ID}/versions?versionType=${VERSION_TYPE}" \
    -H "x-api-key: ${KEY}" \
    -H "Content-Type: application/xml" \
    --data-binary "@${PLACE_FILE}")"

  if [ "$STATUS" = "200" ]; then
    echo "published. response: $(cat "$RESPONSE")"
    break
  fi

  if [ "$STATUS" = "409" ] && [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; then
    DELAY=$((ATTEMPT * 20))
    echo "place is locked (HTTP 409); attempt ${ATTEMPT}/${MAX_ATTEMPTS}, retrying in ${DELAY}s" >&2
    echo "  (close Roblox Studio if it has this place open)" >&2
    sleep "$DELAY"
    continue
  fi

  echo "publish failed with HTTP $STATUS after ${ATTEMPT} attempt(s)" >&2
  # Body is shown because Open Cloud errors are descriptive and carry no secret.
  cat "$RESPONSE" >&2; echo >&2
  exit 1
done
