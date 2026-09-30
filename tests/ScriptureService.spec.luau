--!strict
local H = require("./harness")
local ScriptureService = require("../src/server/ScriptureService")
local Cache = require("../src/shared/Cache")
local Quota = require("../src/shared/Quota")
local RateLimit = require("../src/shared/RateLimit")
local Reference = require("../src/shared/Reference")
local Usfm = require("../src/shared/Usfm")

-- The exact text the live API returned for JHN.3.16 in version 206 on
-- 2026-09-27. Used to prove the service hands Scripture through untouched.
local VERBATIM =
	"For God so loved the world, that he gave his only born Son, "
	.. "that whoever believes in him should not perish, but have eternal life."

-- The same text as the Platform's html format delivers it.
local VERBATIM_HTML = '<div><div class="p"><span class="yv-v" v="16"></span>'
	.. '<span class="yv-vlbl">16</span>' .. VERBATIM .. "</div></div>"

local CONFIG = {
	BIBLE_ID = 206,
	VERSIONS = {
		{ id = 206, abbreviation = "WEB", label = "World English Bible" },
		{ id = 12, abbreviation = "ASV", label = "American Standard Version" },
		{ id = 111, abbreviation = "NIV", label = "New International Version" },
	},
	LANGUAGE_RANGE = "eng",
	PASSAGE_CACHE_TTL = 600,
	METADATA_CACHE_TTL = 3600,
}

-- Fake client recording every call it receives.
local function fakeClient(behaviour)
	return {
		requests = 0,
		calls = {},
		getVersion = function(self, bibleId)
			self.requests += 1
			table.insert(self.calls, { kind = "version", bibleId = bibleId })
			return behaviour.version or {
				ok = true,
				body = {
					title = "World English Bible, American English Edition",
					abbreviation = "engWEBUS",
					copyright = "PUBLIC DOMAIN (not copyrighted)",
					promotional_content = "This Public Domain Bible text is courtesy of eBible.org.",
					publisher_url = nil,
				},
			}
		end,
		getVerseOfTheDay = function(self, day)
			self.requests += 1
			table.insert(self.calls, { kind = "votd", day = day })
			return behaviour.votd or { ok = true, body = { day = day, passage_id = "PHP.4.19" } }
		end,
		getPassage = function(self, bibleId, passageId)
			self.requests += 1
			table.insert(self.calls, { kind = "passage", passageId = passageId })
			if behaviour.passage then
				return behaviour.passage
			end
			return { ok = true, body = { content = VERBATIM_HTML, reference = "John 3:16" } }
		end,
	}
end

local function newService(behaviour, overrides)
	overrides = overrides or {}
	local clock = H.fakeClock()
	local client = fakeClient(behaviour or {})
	local service = ScriptureService.new({
		client = client,
		cache = Cache.new(overrides.maxEntries or 64, clock.now),
		quota = Quota.new(overrides.quotaLimit or 100, 3600, clock.now),
		rateLimit = RateLimit.new(overrides.burst or 10, 3, clock.now),
		reference = Reference,
		usfm = Usfm,
		config = CONFIG,
	})
	return service, client, clock
end

return function()
	H.describe("ScriptureService", function()
		H.it("returns Scripture text byte-for-byte unaltered", function()
			local service = newService()
			local result = service:getPassage("JHN.3.16", "player1")
			H.expectTrue(result.ok, "ok")
			H.expectEqual(result.content, VERBATIM, "content verbatim")
			H.expectEqual(#result.content, #VERBATIM, "length unchanged")
		end)

		H.it("attaches publisher attribution to every passage", function()
			local service = newService()
			local result = service:getPassage("JHN.3.16", "player1")
			local attribution = result.attribution
			H.expectTrue(attribution, "attribution present")
			H.expectEqual(attribution.copyright, "PUBLIC DOMAIN (not copyrighted)")
			H.expectEqual(attribution.versionAbbreviation, "engWEBUS")
			H.expectTrue(attribution.promotionalContent, "promotional content carried")
		end)

		H.it("serves a repeat read from cache without a second request", function()
			local service, client = newService()
			service:getPassage("JHN.3.16", "player1")
			local passageCalls = 0
			for _, call in client.calls do
				if call.kind == "passage" then passageCalls += 1 end
			end
			H.expectEqual(passageCalls, 1)

			local second = service:getPassage("JHN.3.16", "player2")
			H.expectTrue(second.cached, "served from cache")
			H.expectEqual(second.content, VERBATIM)

			passageCalls = 0
			for _, call in client.calls do
				if call.kind == "passage" then passageCalls += 1 end
			end
			H.expectEqual(passageCalls, 1, "still one network call")
		end)

		H.it("fetches version metadata only once", function()
			local service, client = newService()
			service:getPassage("JHN.3.16", "p1")
			service:getPassage("PSA.23", "p2")
			local versionCalls = 0
			for _, call in client.calls do
				if call.kind == "version" then versionCalls += 1 end
			end
			H.expectEqual(versionCalls, 1)
		end)

		H.it("rejects a hostile reference before any network call", function()
			local service, client = newService()
			local result = service:getPassage("../../../secrets", "player1")
			H.expectFalsy(result.ok)
			H.expectEqual(#client.calls, 0, "no network call attempted")
		end)

		H.it("throttles a single noisy player", function()
			local service = newService(nil, { burst = 2 })
			service:getPassage("JHN.3.16", "noisy")
			service:getPassage("PSA.23", "noisy")
			local third = service:getPassage("GEN.1.1", "noisy")
			H.expectFalsy(third.ok, "third request blocked")
			H.expectTrue(string.find(third.reason, "moment", 1, true), "player-facing message")
		end)

		H.it("keeps one player's throttle from affecting another", function()
			local service = newService(nil, { burst = 1 })
			service:getPassage("JHN.3.16", "noisy")
			H.expectFalsy(service:getPassage("PSA.23", "noisy").ok)
			H.expectTrue(service:getPassage("GEN.1.1", "calm").ok, "other player unaffected")
		end)

		H.it("fails closed when the hourly budget is exhausted", function()
			-- Budget of 1 is consumed by the attribution fetch.
			local service = newService(nil, { quotaLimit = 1 })
			local result = service:getPassage("JHN.3.16", "player1")
			H.expectFalsy(result.ok, "denied")
			H.expectTrue(string.find(result.reason, "hourly reading limit", 1, true), "explains the limit")
		end)

		H.it("explains a missing passage without exposing internals", function()
			local service = newService({ passage = { ok = false, status = 404, reason = "not found" } })
			-- A reference that is structurally valid, so it reaches the network.
			local result = service:getPassage("GEN.50.1", "player1")
			H.expectFalsy(result.ok)
			H.expectEqual(result.reason, "That passage is not available in this version.")
		end)

		H.it("rejects an out-of-range chapter locally, spending no request", function()
			-- Genesis has 50 chapters, so this is a certain 404 and the book
			-- metadata lets it be refused without touching the Platform.
			local service, client = newService()
			H.expectFalsy(service:getPassage("GEN.99.1", "player1").ok)
			H.expectEqual(#client.calls, 0, "no request spent")
		end)

		H.it("degrades gracefully when the platform is unavailable", function()
			local service = newService({ passage = { ok = false, status = 503, reason = "platform unavailable" } })
			local result = service:getPassage("JHN.3.16", "player1")
			H.expectFalsy(result.ok)
			H.expectTrue(string.find(result.reason, "unavailable", 1, true))
			H.expectEqual(string.find(result.reason, "503", 1, true), nil, "no raw status shown")
		end)

		H.it("names a disabled-HTTP fault instead of reporting a generic outage", function()
			local service = newService({ passage = { ok = false, reason = "http disabled" } })
			local result = service:getPassage("JHN.3.16", "player1")
			H.expectFalsy(result.ok)
			H.expectTrue(string.find(result.reason, "HTTP requests are disabled", 1, true),
				"operator can see the actual cause")
		end)

		H.it("names a secret domain mismatch", function()
			local service = newService({ passage = { ok = false, reason = "secret domain mismatch" } })
			local result = service:getPassage("JHN.3.16", "player1")
			H.expectTrue(string.find(result.reason, "not permitted for that address", 1, true))
		end)

		H.it("rejects an unexpected response shape", function()
			local service = newService({ passage = { ok = true, body = { content = 12345 } } })
			local result = service:getPassage("JHN.3.16", "player1")
			H.expectFalsy(result.ok)
		end)

		H.it("returns parsed blocks with verse numbers", function()
			local service = newService()
			local result = service:getPassage("JHN.3.16", "player1")
			H.expectTrue(result.blocks, "blocks present")
			H.expectEqual(#result.blocks, 1)
			H.expectEqual(result.blocks[1].segments[1].verse, 16)
		end)

		H.it("defaults to the configured version", function()
			local service = newService()
			H.expectEqual(service:getPassage("JHN.3.16", "p1").bibleId, 206)
		end)

		H.it("accepts an allowed version", function()
			local service = newService()
			H.expectEqual(service:getPassage("JHN.3.16", "p1", 111).bibleId, 111)
		end)

		H.it("rejects a version outside the allowed set", function()
			local service, client = newService()
			local result = service:getPassage("JHN.3.16", "p1", 9999)
			H.expectFalsy(result.ok, "denied")
			H.expectEqual(#client.calls, 0, "no request spent on a rejected version")
		end)

		H.it("rejects a non-numeric version without touching the network", function()
			local service, client = newService()
			for _, bad in { "'; DROP", {}, 1.5, "12abc" } do
				H.expectFalsy(service:getPassage("JHN.3.16", "p1", bad).ok, "rejected " .. typeof(bad))
			end
			H.expectEqual(#client.calls, 0)
		end)

		H.it("serves the picker without any network call", function()
			local service, client = newService()
			local versions = service:getVersions()
			H.expectEqual(#versions, 3)
			H.expectEqual(versions[1].abbreviation, "WEB")
			H.expectEqual(#client.calls, 0, "picker costs no request")
		end)

		H.it("returns a picker copy, not the live config table", function()
			local service = newService()
			local copy = service:getVersions()
			table.remove(copy)
			H.expectEqual(#service:getVersions(), 3, "config unchanged")
		end)

		H.it("caches each version separately", function()
			local service, client = newService()
			service:getPassage("JHN.3.16", "p1", 206)
			service:getPassage("JHN.3.16", "p2", 111)
			local passageCalls = 0
			for _, call in client.calls do
				if call.kind == "passage" then passageCalls += 1 end
			end
			H.expectEqual(passageCalls, 2, "different versions are not conflated")
		end)

		H.it("still serves text when attribution cannot be fetched", function()
			-- Attribution failure must not silently drop Scripture, but the
			-- caller must be able to see that attribution is missing.
			local service = newService({ version = { ok = false, reason = "boom" } })
			local result = service:getPassage("JHN.3.16", "player1")
			H.expectTrue(result.ok, "text still returned")
			H.expectEqual(result.attribution, nil, "attribution absent and visible as such")
		end)

		H.it("stops prefetching before exhausting the budget", function()
			local service = newService(nil, { quotaLimit = 8 })
			local warmed = service:prefetch({
				"JHN.3.16", "PSA.23", "GEN.1.1", "PRO.3.5",
				"ROM.8.28", "PHP.4.13", "ISA.40.31", "MAT.5.9",
			})
			H.expectTrue(warmed < 8, "stopped early")
			H.expectTrue(service:stats().quotaRemaining >= 5, "headroom preserved")
		end)

		H.it("resolves the verse of the day into a passage", function()
			local service = newService()
			local result = service:getVerseOfTheDay(273, 206)
			H.expectTrue(result.ok, result.reason)
			H.expectTrue(result.isVerseOfTheDay)
			H.expectEqual(result.day, 273)
			H.expectTrue(result.blocks, "blocks present")
			H.expectTrue(result.attribution, "attribution present")
		end)

		H.it("accepts a verse range from the verse of the day", function()
			-- 16 of the 366 entries are ranges, e.g. ISA.43.18-19.
			local service, client = newService({
				votd = { ok = true, body = { day = 1, passage_id = "ISA.43.18-19" } },
			})
			H.expectTrue(service:getVerseOfTheDay(1, 206).ok, "range resolved")
			local requested = nil
			for _, call in client.calls do
				if call.kind == "passage" then requested = call.passageId end
			end
			H.expectEqual(requested, "ISA.43.18-19", "range passed through canonicalisation")
		end)

		H.it("looks the day up once and reuses it", function()
			local service, client = newService()
			service:getVerseOfTheDay(273, 206)
			service:getVerseOfTheDay(273, 206)
			local lookups = 0
			for _, call in client.calls do
				if call.kind == "votd" then lookups += 1 end
			end
			H.expectEqual(lookups, 1, "day mapping cached")
		end)

		H.it("rejects an out-of-range day without a request", function()
			local service, client = newService()
			for _, bad in { 0, 367, -5, "abc", nil } do
				H.expectFalsy(service:getVerseOfTheDay(bad, 206).ok, "rejected")
			end
			H.expectEqual(#client.calls, 0, "no request spent")
		end)

		H.it("validates a reference the Platform returns before using it", function()
			-- The reference is trusted no more than client input.
			local service = newService({
				votd = { ok = true, body = { passage_id = "../../etc/passwd" } },
			})
			local result = service:getVerseOfTheDay(5, 206)
			H.expectFalsy(result.ok, "hostile reference refused")
		end)

		H.it("degrades honestly when the day lookup fails", function()
			local service = newService({ votd = { ok = false, reason = "boom" } })
			local result = service:getVerseOfTheDay(273, 206)
			H.expectFalsy(result.ok)
			H.expectTrue(string.find(result.reason, "unavailable", 1, true))
		end)

		H.it("does not charge the verse of the day to a player throttle", function()
			-- The board is shared, so its fetch must not consume a player's
			-- burst allowance.
			local service = newService(nil, { burst = 1 })
			H.expectTrue(service:getVerseOfTheDay(273, 206).ok)
			H.expectTrue(service:getPassage("JHN.3.16", "player1").ok, "player unaffected")
		end)

		H.it("reports operational statistics", function()
			local service = newService()
			service:getPassage("JHN.3.16", "p1")
			service:getPassage("JHN.3.16", "p2")
			local stats = service:stats()
			H.expectTrue(stats.cacheHits >= 1, "hits counted")
			H.expectTrue(stats.httpRequests >= 1, "requests counted")
		end)
	end)
end
