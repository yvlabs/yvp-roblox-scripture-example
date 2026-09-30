#!/usr/bin/env bash
# Upload a Home Page (discovery) thumbnail via the Open Cloud Thumbnail
# Personalization API, then confirm it through the status endpoint.
#
# The key needs universe.thumbnail:write AND
# :read (read is only for confirmation; without it the status call 403s).
#
# This fills the HOME PAGE slot only. The Experience Detail Page slot is a
# separate legacy endpoint that returns 403 for this key; set it in Creator Hub.
set -euo pipefail
cd "$(dirname "$0")/.."
UNIVERSE_ID="${ROBLOX_UNIVERSE_ID:?set ROBLOX_UNIVERSE_ID to your experience (universe) id}"
FILE="${1:?usage: $0 <image.jpg>}"
[ -f "$FILE" ] || { echo "no such file: $FILE" >&2; exit 1; }
KEY="${ROBLOX_API_KEY:?set ROBLOX_API_KEY to an Open Cloud API key (see README)}"
BASE="https://apis.roblox.com/thumbnail-personalization-api/v1/universes/${UNIVERSE_ID}/thumbnails"

RESP="$(curl -sS -X POST "$BASE/uploads" -H "x-api-key: $KEY" -F "files=@${FILE};type=image/jpeg")"
OP="$(printf '%s' "$RESP" | python3 -c 'import json,sys; print(next(iter(json.load(sys.stdin)["fileToOperationIdDict"].values())))')" \
  || { echo "upload failed: $RESP" >&2; exit 1; }
echo "uploaded $FILE; polling status"

for i in $(seq 1 24); do
  S="$(curl -sS -G "$BASE/uploads/status" -H "x-api-key: $KEY" --data-urlencode "operationIds=$OP")"
  MOD="$(printf '%s' "$S" | python3 -c 'import json,sys; d=json.load(sys.stdin).get("uploadThumbnailStatusDict") or {}; v=next(iter(d.values()),{}); print(v.get("moderationStatus",""))')"
  if [ -n "$MOD" ]; then echo "moderation: $MOD"; break; fi
  sleep 5
done

echo "active home page thumbnails:"
curl -sS "$BASE" -H "x-api-key: $KEY" | python3 -c '
import json,sys
for t in json.load(sys.stdin).get("homepageThumbnails",[]):
    print(" ", t["assetId"], t["moderationStatus"], t["homepageThumbnailStatus"])'
