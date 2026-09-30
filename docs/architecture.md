# Architecture


## Trust boundary

The Roblox client is untrusted. It holds no credential, never contacts the
Platform, and cannot choose what the server asks for beyond a reference string
that is validated server-side.

| Concern | Where it is enforced |
|---|---|
| Credential custody | Server only, via Secrets Store |
| Reference validation | `Reference.canonical`, server-side, before any URL is built |
| Per-player throttle | Keyed on `player.UserId`, which the server reads, not the client |
| Hourly budget | `Quota`, server-wide and shared across all players |

A client that sends `../../v1/bibles/1` or `JHN.3.16?format=html` is rejected
before a request is constructed; a unit test asserts no network call is
attempted in that case.

## Dependency injection

Every logic-bearing module takes its collaborators as constructor arguments:

- `Cache`, `Quota`, `RateLimit` take a clock, so tests advance time instead of
  sleeping.
- `YvpClient` takes a transport, a key source, a sleep function, and a JSON
  decoder, so it runs under the Luau CLI with no Roblox globals.
- `ScriptureService` takes all of the above.

Composition happens in exactly two places: `src/server/init.server.luau` for
the real runtime, and the test files. No module reaches for a global service at
require time, which is what makes the offline suite possible.

## Request path

1. Client invokes `RequestPassage` with a reference string.
2. Server canonicalises it. Invalid input returns immediately.
3. Per-player token bucket is checked.
4. Attribution is resolved (cached after the first fetch).
5. Cache is checked. A hit returns immediately and is marked `cached = true`.
6. The hourly budget is checked. Exhaustion returns a player-facing message
   with an estimated wait, not an error code.
7. `YvpClient` issues the request, retrying 429 and 5xx with exponential
   backoff, and never retrying 404 or 401/403.
8. The result is cached and returned with its attribution.

## Failure behaviour

| Failure | Player sees |
|---|---|
| Invalid reference | Validation message; no request spent |
| Player throttled | "reading faster than the kiosk can fetch" |
| Hourly budget spent | Estimated minutes until retry |
| 404 | "not available in this version" |
| 5xx / transport | "unavailable right now"; no status code exposed |
| No key configured | World still loads; board reports unavailability |
| Attribution fetch failed | Text still shown; attribution explicitly marked unavailable |

The last row is deliberate. Dropping the text would be worse for the reader,
and silently implying an attribution we did not receive would be dishonest, so
the UI states that version information is unavailable.

## Rendering pipeline

1. The server requests passages as `format=html&include_headings=true&include_notes=true`.
   The HTML carries verse markers, poetry indent levels (`q1`, `q2`), headings,
   words-of-Jesus spans (`wj`) and footnotes (`yv-n`), none of which the
   `format=text` rendering includes.
2. `Usfm.parse` turns that markup into blocks of segments. Spans are matched
   by depth, because some versions nest markup (the Amplified Bible puts
   `<span class="it">` inside `<span class="wj">`).
3. Footnotes are kept but marked, so they are never rendered as Scripture.
   Editorial section headings ("The New Birth") are distinguished from psalm
   descriptors ("A Psalm of David"): `format=text` omits the former and
   includes the latter.
4. The client renders each block as its own `TextLabel` inside a
   `UIListLayout`, escaping text for RichText so every character displays
   as received.

`tests/integration/parser-integrity.mjs` fetches real chapters in both formats
and asserts the parsed text preserves every character of the plain-text
rendering. It compares with whitespace removed, because the Platform's
`format=text` sometimes joins blocks with no space ("disobeysthe Son") where
the parsed structure correctly separates them.
