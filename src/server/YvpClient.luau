--!strict
-- YouVersion Platform HTTP client.
--
-- Dependencies (http, getKey, sleep) are injected so this module contains no
-- Roblox globals and can be exercised against a fake transport in tests.
--
-- CREDENTIAL HANDLING: the App Key is obtained through getKey() at call time
-- and placed only in the request header. It is never written to a log, an
-- error message, a returned table, or the place file.

local YvpClient = {}
YvpClient.__index = YvpClient

export type Response = {
	ok: boolean,
	status: number?,
	body: any?,
	reason: string?,
	retryable: boolean?,
	retryAfter: number?,
}

function YvpClient.new(options: {
	http: any,
	getKey: () -> string,
	base: string,
	timeout: number?,
	maxRetries: number?,
	sleep: ((number) -> ())?,
	maxSleep: number?,
	decode: (string) -> any,
})
	-- Guard the transport seam. A transport missing :request would otherwise
	-- fail identically to a network outage on every call, which is exactly the
	-- confusion that shipped once already. Fail at startup instead, where the
	-- message can name the cause.
	if type(options.http) ~= "table" and typeof(options.http) ~= "Instance" then
		error("YvpClient: http transport must be a table exposing :request", 2)
	end
	if type((options.http :: any).request) ~= "function" then
		error(
			"YvpClient: http transport does not expose a :request function. "
				.. "Roblox HttpService uses RequestAsync; wrap it in an adapter.",
			2
		)
	end

	return setmetatable({
		_http = options.http,
		_getKey = options.getKey,
		_base = options.base,
		_timeout = options.timeout or 10,
		_maxRetries = options.maxRetries or 2,
		_sleep = options.sleep or function(_) end,
		_maxSleep = options.maxSleep or 10,
		lastRetryAfter = nil :: number?,
		_decode = options.decode,
		requests = 0,
	}, YvpClient)
end

-- Classify a thrown HttpService error into a safe, fixed reason string.
--
-- The raw error is never surfaced: Roblox includes the full request URL in
-- some HttpService errors, and headers must never reach a log line. Only the
-- fixed strings below are returned, after matching known substrings that
-- themselves contain no request detail.
local function classifyError(err: unknown): (string, boolean)
	local text = typeof(err) == "string" and (err :: string) or tostring(err)

	if string.find(text, "Http requests are not enabled", 1, true)
		or string.find(text, "HttpService is not enabled", 1, true) then
		-- Configuration fault, not a transient one. Retrying cannot help.
		return "http disabled", false
	end
	if string.find(text, "not allowed to access", 1, true)
		or string.find(text, "Trust check failed", 1, true)
		or string.find(text, "domain", 1, true) then
		-- The Secret's configured domain does not match the request host.
		return "secret domain mismatch", false
	end
	return "transport error", true
end

function YvpClient:_requestOnce(path: string): Response
	self.requests += 1
	local ok, result = pcall(function()
		return self._http:request({
			Url = self._base .. path,
			Method = "GET",
			Headers = {
				["X-YVP-App-Key"] = self._getKey(),
				["Accept"] = "application/json",
			},
		})
	end)

	if not ok then
		local reason, retryable = classifyError(result)
		return { ok = false, reason = reason, retryable = retryable }
	end

	local status = result.StatusCode
	if status == 200 then
		local decodeOk, decodedOrError = pcall(self._decode, result.Body)
		if not decodeOk then
			return { ok = false, status = status, reason = "malformed response body", retryable = false }
		end
		return { ok = true, status = status, body = decodedOrError }
	end

	if status == 404 then
		return { ok = false, status = status, reason = "not found", retryable = false }
	end
	if status == 401 or status == 403 then
		return { ok = false, status = status, reason = "credential rejected", retryable = false }
	end
	if status == 429 then
		-- The Platform DOES send Retry-After on a 429, even though successful
		-- responses carry no rate-limit headers. Observed values: 600s for a
		-- non-live key, 300s once live. Honour it rather than guessing.
		local retryAfter: number? = nil
		local headers = result.Headers
		if type(headers) == "table" then
			for name, value in headers do
				if string.lower(tostring(name)) == "retry-after" then
					retryAfter = tonumber(value)
					break
				end
			end
		end
		return {
			ok = false,
			status = status,
			reason = "rate limited",
			retryable = true,
			retryAfter = retryAfter,
		}
	end
	if status >= 500 then
		return { ok = false, status = status, reason = "platform unavailable", retryable = true }
	end
	return { ok = false, status = status, reason = "unexpected status", retryable = false }
end

function YvpClient:get(path: string): Response
	local attempt = 0
	local last: Response = { ok = false, reason = "not attempted" }
	while attempt <= self._maxRetries do
		last = self:_requestOnce(path)
		if last.ok or not last.retryable then
			return last
		end
		attempt += 1
		if attempt <= self._maxRetries then
			-- Prefer the server's own Retry-After when it sends one. A 429
			-- penalty box is minutes long, so retrying on a two-second
			-- exponential schedule just burns attempts against a closed door.
			if last.retryAfter and last.retryAfter > 0 then
				self.lastRetryAfter = last.retryAfter
				-- Do not sleep out a multi-minute penalty inside a player
				-- request; surface it instead.
				if last.retryAfter > self._maxSleep then
					return last
				end
				self._sleep(last.retryAfter)
			else
				self._sleep(2 ^ attempt)
			end
		end
	end
	return last
end

-- Version metadata, including the fields required for attribution.
function YvpClient:getVersion(bibleId: number): Response
	return self:get(string.format("/v1/bibles/%d", bibleId))
end

-- Passage text. The caller must pass an already-canonicalised passage id.
--
-- format=html is requested because it carries verse numbers, poetry indent
-- levels, headings and words-of-Jesus markup, none of which format=text
-- provides. Usfm.parse turns it back into text plus structure, and a live
-- integrity test proves the round trip loses no characters.
function YvpClient:getPassage(bibleId: number, passageId: string, format: string?): Response
	local chosen = format == "text" and "text" or "html"
	-- Footnotes are requested because Biblica's fast-track terms call for the
	-- text to be shown with them. They are marked in parsing and rendered
	-- distinctly, never as ordinary prose.
	local query = chosen == "html"
		and "format=html&include_headings=true&include_notes=true"
		or "format=text"
	return self:get(string.format("/v1/bibles/%d/passages/%s?%s", bibleId, passageId, query))
end

-- Verse of the Day. Returns { day, passage_id } for a day of the year.
--
-- Path note: /v1/verse_of_the_days is deprecated and answers with
-- `deprecation: true` plus a successor-version link to the kebab-case path,
-- so the kebab-case form is used.
--
-- The passage_id is a reference, not text: 350 of the 366 entries are single
-- verses and 16 are verse ranges (e.g. ISA.43.18-19). The caller resolves it
-- against whichever Bible version it wants to display.
function YvpClient:getVerseOfTheDay(dayOfYear: number): Response
	return self:get(string.format("/v1/verse-of-the-days/%d", dayOfYear))
end

-- Note: there is deliberately no version-list call here. The picker is served
-- from configuration instead. The list endpoint needs "language_ranges[]",
-- whose brackets are reserved characters that Roblox HttpService may reject,
-- and building that path with string.format would also require escaping the
-- percent signs of an encoded form. Removing the call removes both hazards
-- and a network round trip.

return YvpClient
