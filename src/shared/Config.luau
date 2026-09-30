--!strict
-- Central configuration for the Scripture Kiosk example.
--
-- No secret values live here. The YouVersion Platform app key is read at
-- runtime from the experience's Secrets Store (see README).

return {
	API_BASE = "https://api.youversion.com",

	-- Default version: World English Bible, American English Edition (206),
	-- which is public domain.
	BIBLE_ID = 206,

	-- Versions the reader offers, and the single source of truth for which
	-- version ids a client may request. A client-supplied id is checked
	-- against this list before it can reach a URL.
	--
	-- The picker is served from this table rather than from GET /v1/bibles,
	-- so opening it costs no Platform request and cannot fail. The trade-off
	-- is that the list can go stale if your app loses access to a version;
	-- run tools/check-versions.mjs to verify it against your app key.
	--
	-- `label` is a short display name for the picker. The full official title
	-- and the publisher's copyright always come from live version metadata and
	-- are shown with the text.
	--
	-- The defaults are public domain or Creative Commons. Licensed versions
	-- (for example NIV or Amplified) work the same way once your Platform app
	-- has accepted their licence, but each publisher's terms have their own
	-- display requirements. Read them for your surface before enabling one.
	VERSIONS = {
		{ id = 206, abbreviation = "WEB", label = "World English Bible" },
		{ id = 12, abbreviation = "ASV", label = "American Standard Version" },
		{ id = 3034, abbreviation = "BSB", label = "Berean Standard Bible" },
		{ id = 1932, abbreviation = "FBV", label = "Free Bible Version" },
		-- { id = 111, abbreviation = "NIV", label = "New International Version" },
		-- { id = 1588, abbreviation = "AMP", label = "Amplified Bible" },
	},
	LANGUAGE_RANGE = "eng",

	-- Version used for the Verse of the Day board. Any id in VERSIONS works.
	VOTD_BIBLE_ID = 206,

	-- Verse of the Day is keyed by day of the year, 1-366. os.date("!*t") is
	-- used so every server agrees on the day regardless of where it runs.
	VOTD_DAY_PROVIDER = function(): number
		return os.date("!*t").yday
	end,

	-- Name of the entry in the experience's Secrets Store.
	APP_KEY_SECRET = "YVP_APP_KEY",

	-- Requests per rolling hour one server will spend against the Platform.
	--
	-- This is a runaway guard, not a capacity plan: it stops a bug (a loop, a
	-- cache that stopped working) from hammering the API. A person reading a
	-- Bible cannot approach it.
	--
	-- It is per SERVER. Roblox runs many servers for a popular experience,
	-- with no shared state, so experience-wide spend is this number times the
	-- server count. Size it against your app key's hourly limit. 429 responses
	-- are handled separately by honouring Retry-After in YvpClient.
	HOURLY_BUDGET = 1000,

	-- Scripture text for a given passage id is immutable, so it is cached on
	-- the server and shared by every player. Check your publishers' terms for
	-- any limits on caching licensed text.
	PASSAGE_CACHE_TTL = 86400, -- 24 hours
	METADATA_CACHE_TTL = 86400, -- 24 hours
	MAX_CACHE_ENTRIES = 2048,

	-- Per-player throttle, so one player cannot drain the shared budget.
	PLAYER_BURST = 5,
	PLAYER_REFILL_SECONDS = 3,

	HTTP_TIMEOUT = 10,
	MAX_RETRIES = 2,
}
