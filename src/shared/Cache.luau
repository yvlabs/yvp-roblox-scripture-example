--!strict
-- TTL cache with a bounded entry count.
--
-- The clock is injected so tests can advance time deterministically instead of
-- sleeping. In Roblox the caller passes os.clock or os.time.

local Cache = {}
Cache.__index = Cache

export type Entry = { value: any, expiresAt: number, storedAt: number }

function Cache.new(maxEntries: number, clock: (() -> number)?)
	return setmetatable({
		_entries = {} :: { [string]: Entry },
		_count = 0,
		_maxEntries = maxEntries,
		_clock = clock or os.time,
		hits = 0,
		misses = 0,
		evictions = 0,
	}, Cache)
end

function Cache:get(key: string): any?
	local entry = self._entries[key]
	if not entry then
		self.misses += 1
		return nil
	end
	if self._clock() >= entry.expiresAt then
		self._entries[key] = nil
		self._count -= 1
		self.misses += 1
		return nil
	end
	self.hits += 1
	return entry.value
end

function Cache:set(key: string, value: any, ttlSeconds: number)
	local now = self._clock()
	if self._entries[key] == nil then
		if self._count >= self._maxEntries then
			self:_evictOldest()
		end
		self._count += 1
	end
	self._entries[key] = { value = value, expiresAt = now + ttlSeconds, storedAt = now }
end

function Cache:_evictOldest()
	local oldestKey: string? = nil
	local oldestAt = math.huge
	for key, entry in self._entries do
		if entry.storedAt < oldestAt then
			oldestAt = entry.storedAt
			oldestKey = key
		end
	end
	if oldestKey then
		self._entries[oldestKey] = nil
		self._count -= 1
		self.evictions += 1
	end
end

function Cache:count(): number
	return self._count
end

function Cache:clear()
	self._entries = {}
	self._count = 0
end

return Cache
