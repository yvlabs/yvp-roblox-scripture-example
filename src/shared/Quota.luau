--!strict
-- Rolling-window budget guard for outbound Platform requests.
--
-- The Platform limits requests per app key per hour, and successful responses
-- carry no rate-limit headers (observed 2026-09-27), so a client cannot learn
-- its remaining allowance from a response. This module tracks spend locally
-- and fails closed. A 429 does carry Retry-After, which YvpClient honours.

local Quota = {}
Quota.__index = Quota

function Quota.new(limit: number, windowSeconds: number, clock: (() -> number)?)
	return setmetatable({
		_limit = limit,
		_window = windowSeconds,
		_stamps = {} :: { number },
		_clock = clock or os.time,
		denied = 0,
	}, Quota)
end

function Quota:_prune()
	local cutoff = self._clock() - self._window
	local kept = {}
	for _, stamp in self._stamps do
		if stamp > cutoff then
			table.insert(kept, stamp)
		end
	end
	self._stamps = kept
end

function Quota:remaining(): number
	self:_prune()
	return math.max(0, self._limit - #self._stamps)
end

-- Attempt to spend one request. Returns false when the budget is exhausted.
function Quota:tryConsume(): boolean
	self:_prune()
	if #self._stamps >= self._limit then
		self.denied += 1
		return false
	end
	table.insert(self._stamps, self._clock())
	return true
end

-- Seconds until at least one request frees up, or 0 if budget is available.
function Quota:retryAfter(): number
	self:_prune()
	if #self._stamps < self._limit then
		return 0
	end
	local oldest = math.huge
	for _, stamp in self._stamps do
		if stamp < oldest then
			oldest = stamp
		end
	end
	return math.max(0, (oldest + self._window) - self._clock())
end

return Quota
