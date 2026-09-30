--!strict
-- Composition root for Scripture retrieval.
--
-- Design rule: the client never talks to the Platform. Every player request is
-- served from a server-wide cache, and only a cache miss may spend budget.
-- With a shared cache, one hundred players reading John 3 cost one request,
-- not one hundred.
--
-- Scripture text is passed through verbatim. Nothing in this file edits,
-- truncates, reflows, summarises, or annotates returned content.

local ScriptureService = {}
ScriptureService.__index = ScriptureService

export type Passage = {
	ok: boolean,
	reference: string?,
	content: string?,
	blocks: { any }?,
	bibleId: number?,
	attribution: Attribution?,
	reason: string?,
	cached: boolean?,
	isVerseOfTheDay: boolean?,
	day: number?,
}

export type Attribution = {
	versionTitle: string,
	versionAbbreviation: string,
	copyright: string,
	promotionalContent: string?,
	publisherUrl: string?,
}

function ScriptureService.new(deps: {
	client: any,
	cache: any,
	quota: any,
	rateLimit: any,
	reference: any,
	usfm: any,
	config: any,
	log: ((string) -> ())?,
})
	return setmetatable({
		_client = deps.client,
		_cache = deps.cache,
		_quota = deps.quota,
		_rateLimit = deps.rateLimit,
		_reference = deps.reference,
		_usfm = deps.usfm,
		_config = deps.config,
		_log = deps.log or function(_) end,
		_attributions = {} :: { [number]: Attribution },
	}, ScriptureService)
end

-- Fetch and memoise the attribution block. Required before any passage is
-- displayed: publisher metadata must accompany the text, not trail it.
function ScriptureService:getAttribution(bibleId: number?): Attribution?
	local id = bibleId or self._config.BIBLE_ID
	if self._attributions[id] then
		return self._attributions[id]
	end

	local cacheKey = string.format("version:%d", id)
	local cached = self._cache:get(cacheKey)
	if cached then
		self._attributions[id] = cached
		return cached
	end

	if not self._quota:tryConsume() then
		self._log("attribution fetch skipped: hourly budget exhausted")
		return nil
	end

	local response = self._client:getVersion(id)
	if not response.ok or type(response.body) ~= "table" then
		self._log("attribution fetch failed: " .. tostring(response.reason))
		return nil
	end

	local body = response.body
	local attribution: Attribution = {
		versionTitle = tostring(body.title or "Unknown version"),
		versionAbbreviation = tostring(body.abbreviation or "?"),
		copyright = tostring(body.copyright or ""),
		promotionalContent = body.promotional_content,
		publisherUrl = body.publisher_url,
	}

	self._cache:set(cacheKey, attribution, self._config.METADATA_CACHE_TTL)
	self._attributions[id] = attribution
	return attribution
end

-- Retrieve one passage on behalf of a player.
-- requesterKey identifies the caller for throttling; pass nil for server-
-- initiated prefetches, which bypass the per-player limit but still spend
-- from the shared hourly budget.
function ScriptureService:getPassage(rawReference: unknown, requesterKey: string?, rawBibleId: unknown): Passage
	local passageId, referenceError = self._reference.canonical(rawReference)
	if not passageId then
		return { ok = false, reason = referenceError or "invalid reference" }
	end

	-- The version is client-supplied, so it is validated against the allowed
	-- set rather than trusted into a URL.
	local bibleId = self:_resolveBibleId(rawBibleId)
	if not bibleId then
		return { ok = false, reason = "That Bible version is not available here." }
	end

	if requesterKey and not self._rateLimit:allow(requesterKey) then
		return { ok = false, reason = "You are reading faster than the kiosk can fetch. Try again in a moment." }
	end

	local attribution = self:getAttribution(bibleId)
	local cacheKey = string.format("passage:%d:%s", bibleId, passageId)

	local cached = self._cache:get(cacheKey)
	if cached then
		return {
			ok = true,
			reference = cached.reference,
			content = cached.content,
			blocks = cached.blocks,
			bibleId = bibleId,
			attribution = attribution,
			cached = true,
		}
	end

	if not self._quota:tryConsume() then
		local wait = math.ceil(self._quota:retryAfter() / 60)
		self._log("passage fetch denied by local budget: " .. passageId)
		return {
			ok = false,
			reason = string.format("The kiosk has reached its hourly reading limit. Please try again in about %d minute(s).", math.max(1, wait)),
		}
	end

	local response = self._client:getPassage(bibleId, passageId)
	if not response.ok then
		if response.status == 404 then
			return { ok = false, reason = "That passage is not available in this version." }
		end
		self._log("passage fetch failed: " .. tostring(response.reason))
		-- Configuration faults get their own message. An operator seeing the
		-- generic "unavailable" text has no way to tell a misconfigured
		-- experience from an outage, which costs real debugging time.
		if response.reason == "http disabled" then
			return {
				ok = false,
				reason = "This kiosk cannot reach the Bible service: HTTP requests are disabled for this experience.",
			}
		end
		if response.reason == "secret domain mismatch" then
			return {
				ok = false,
				reason = "This kiosk cannot reach the Bible service: its credential is not permitted for that address.",
			}
		end
		return { ok = false, reason = "The Bible service is unavailable right now. Please try again shortly." }
	end

	local body = response.body
	if type(body) ~= "table" or type(body.content) ~= "string" then
		return { ok = false, reason = "The Bible service returned an unexpected response." }
	end

	-- Parse once on the server and cache the structure. Every player then
	-- receives render-ready blocks without reparsing, and the raw markup never
	-- crosses to the client.
	local blocks = self._usfm.parse(body.content)
	local record = {
		reference = tostring(body.reference or passageId),
		content = self._usfm.plainText(blocks),
		blocks = blocks,
	}
	self._cache:set(cacheKey, record, self._config.PASSAGE_CACHE_TTL)

	return {
		ok = true,
		reference = record.reference,
		content = record.content,
		blocks = record.blocks,
		bibleId = bibleId,
		attribution = attribution,
		cached = false,
	}
end

-- Validate a client-supplied version id against the allowed set.
function ScriptureService:_resolveBibleId(raw: unknown): number?
	if raw == nil then
		return self._config.BIBLE_ID
	end
	local id = tonumber(raw)
	if not id or id ~= math.floor(id) then
		return nil
	end
	for _, version in self._config.VERSIONS do
		if version.id == id then
			return id
		end
	end
	return nil
end

-- The versions this kiosk offers. Served from configuration, so the picker
-- costs no Platform request and has no failure mode. Verified against the
-- live key by tools/check-versions.mjs.
function ScriptureService:getVersions(): { { id: number, abbreviation: string, label: string } }
	return table.clone(self._config.VERSIONS)
end

-- Warm the cache for a set of references at server start, so the first
-- player to walk up to the board sees text immediately.
function ScriptureService:prefetch(passageIds: { string }): number
	local warmed = 0
	for _, id in passageIds do
		if self._quota:remaining() <= 5 then
			self._log("prefetch stopped early to preserve budget headroom")
			break
		end
		local result = self:getPassage(id, nil)
		if result.ok then
			warmed += 1
		end
	end
	return warmed
end

-- Resolve the Verse of the Day for a day of the year into a displayable
-- passage in the requested version.
--
-- The reference is cached for a day: the mapping from day to passage is fixed,
-- so a server that stays up re-uses it, and the passage itself is cached by
-- the ordinary passage cache.
function ScriptureService:getVerseOfTheDay(dayOfYear: number, bibleId: unknown): Passage
	local day = tonumber(dayOfYear)
	if not day or day < 1 or day > 366 then
		return { ok = false, reason = "invalid day of year" }
	end
	day = math.floor(day)

	local cacheKey = string.format("votd:%d", day)
	local reference = self._cache:get(cacheKey)

	if not reference then
		if not self._quota:tryConsume() then
			self._log("verse of the day lookup denied by local budget")
			return { ok = false, reason = "The verse of the day is unavailable right now." }
		end
		local response = self._client:getVerseOfTheDay(day)
		if not response.ok or type(response.body) ~= "table" then
			self._log("verse of the day lookup failed: " .. tostring(response.reason))
			return { ok = false, reason = "The verse of the day is unavailable right now." }
		end
		local passageId = response.body.passage_id
		-- The reference comes from the Platform, but it still goes through the
		-- same validation as client input before it can reach a URL.
		local canonical = self._reference.canonical(passageId)
		if not canonical then
			self._log("verse of the day returned an unusable reference")
			return { ok = false, reason = "The verse of the day is unavailable right now." }
		end
		reference = canonical
		self._cache:set(cacheKey, reference, 86400)
	end

	-- nil requester: this is a server-initiated fetch for a shared board, so
	-- it is not charged against any player's throttle.
	local passage = self:getPassage(reference, nil, bibleId)
	if passage.ok then
		passage.isVerseOfTheDay = true
		passage.day = day
	end
	return passage
end

function ScriptureService:stats(): { [string]: number }
	return {
		cacheHits = self._cache.hits,
		cacheMisses = self._cache.misses,
		cacheEntries = self._cache:count(),
		quotaRemaining = self._quota:remaining(),
		quotaDenied = self._quota.denied,
		httpRequests = self._client.requests,
	}
end

return ScriptureService
