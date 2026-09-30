--!strict
-- Per-player token bucket, so a single client cannot drain the shared
-- server-wide Platform budget by spamming requests.

local RateLimit = {}
RateLimit.__index = RateLimit

function RateLimit.new(burst: number, refillSeconds: number, clock: (() -> number)?)
	return setmetatable({
		_burst = burst,
		_refill = refillSeconds,
		_buckets = {} :: { [string]: { tokens: number, updatedAt: number } },
		_clock = clock or os.time,
	}, RateLimit)
end

function RateLimit:_bucket(key: string)
	local bucket = self._buckets[key]
	if not bucket then
		bucket = { tokens = self._burst, updatedAt = self._clock() }
		self._buckets[key] = bucket
	end
	return bucket
end

function RateLimit:allow(key: string): boolean
	local bucket = self:_bucket(key)
	local now = self._clock()
	local gained = math.floor((now - bucket.updatedAt) / self._refill)
	if gained > 0 then
		bucket.tokens = math.min(self._burst, bucket.tokens + gained)
		bucket.updatedAt = now
	end
	if bucket.tokens <= 0 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function RateLimit:forget(key: string)
	self._buckets[key] = nil
end

return RateLimit
