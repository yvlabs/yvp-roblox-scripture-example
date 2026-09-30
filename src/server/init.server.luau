--!strict
-- Scripture Kiosk server bootstrap.
--
-- Wires the real Roblox services into the dependency-injected modules, builds
-- the in-world kiosk, and exposes a single RemoteFunction to clients.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("ScriptureKiosk")
local Config = require(Shared:WaitForChild("Config"))
local Reference = require(Shared:WaitForChild("Reference"))
local Cache = require(Shared:WaitForChild("Cache"))
local Quota = require(Shared:WaitForChild("Quota"))
local RateLimit = require(Shared:WaitForChild("RateLimit"))
local Usfm = require(Shared:WaitForChild("Usfm"))

local YvpClient = require(script:WaitForChild("YvpClient"))
local ScriptureService = require(script:WaitForChild("ScriptureService"))
local Kiosk = require(script:WaitForChild("Kiosk"))

local function log(message: string)
	print("[ScriptureKiosk] " .. message)
end

-- Credential resolution.
--
-- Production: the App Key lives in the experience's Secrets Store and is
-- returned as a Secret object, which Roblox permits in a request header but
-- refuses to convert to a string. It therefore cannot be printed or leaked.
--
-- Studio: the Secrets Store is not available, so a developer may place an
-- uncommitted ModuleScript at ServerStorage.DevSecrets returning
-- { YVP_APP_KEY = "..." }. See docs/runbook.md.
local function resolveKey(): (() -> any)?
	local ok, secret = pcall(function()
		return HttpService:GetSecret(Config.APP_KEY_SECRET)
	end)
	if ok and secret then
		log("app key resolved from Secrets Store")
		return function() return secret end
	end

	local ServerStorage = game:GetService("ServerStorage")
	local devSecrets = ServerStorage:FindFirstChild("DevSecrets")
	if devSecrets and devSecrets:IsA("ModuleScript") then
		local loaded = require(devSecrets)
		local value = loaded and loaded[Config.APP_KEY_SECRET]
		if type(value) == "string" and #value > 0 then
			log("app key resolved from Studio DevSecrets (development only)")
			return function() return value end
		end
	end

	return nil
end

local getKey = resolveKey()

local remotes = Instance.new("Folder")
remotes.Name = "ScriptureKioskRemotes"
remotes.Parent = ReplicatedStorage

local requestPassage = Instance.new("RemoteFunction")
requestPassage.Name = "RequestPassage"
requestPassage.Parent = remotes

local requestVersions = Instance.new("RemoteFunction")
requestVersions.Name = "RequestVersions"
requestVersions.Parent = remotes

local requestVerseOfTheDay = Instance.new("RemoteFunction")
requestVerseOfTheDay.Name = "RequestVerseOfTheDay"
requestVerseOfTheDay.Parent = remotes


-- Bumped whenever the day rolls over, so clients refresh the board.
local votdDay = Instance.new("IntValue")
votdDay.Name = "VerseOfTheDayDay"
votdDay.Parent = remotes

Kiosk.build(Workspace)

if not getKey then
	-- Fail loudly but safely: the world still loads and players see an honest
	-- message rather than a broken board.
	log("NO APP KEY CONFIGURED - kiosk will report unavailability")
	requestPassage.OnServerInvoke = function()
		return {
			ok = false,
			reason = "This kiosk is not configured yet. The Bible service is unavailable.",
		}
	end
	-- The board's verse of the day. Served from cache after the first call, so
-- every player on the server shares one lookup and one passage fetch.
requestVerseOfTheDay.OnServerInvoke = function()
	return service:getVerseOfTheDay(Config.VOTD_DAY_PROVIDER(), Config.VOTD_BIBLE_ID)
end

requestVersions.OnServerInvoke = function()
		return {}
	end
	requestVerseOfTheDay.OnServerInvoke = function()
		return {
			ok = false,
			reason = "This kiosk is not configured yet. The Bible service is unavailable.",
		}
	end
	return
end

local cache = Cache.new(Config.MAX_CACHE_ENTRIES, os.time)
local quota = Quota.new(Config.HOURLY_BUDGET, 3600, os.time)
local rateLimit = RateLimit.new(Config.PLAYER_BURST, Config.PLAYER_REFILL_SECONDS, os.time)

-- Adapter, not HttpService itself. HttpService exposes RequestAsync, not
-- request, so injecting the service directly threw "attempt to call a nil
-- value" on every call and surfaced as a generic outage. The injected
-- interface is kept as :request so the test fake and the real transport have
-- the same shape.
local httpTransport = {
	request = function(_self, options)
		return HttpService:RequestAsync(options)
	end,
}

local client = YvpClient.new({
	http = httpTransport,
	getKey = getKey,
	base = Config.API_BASE,
	timeout = Config.HTTP_TIMEOUT,
	maxRetries = Config.MAX_RETRIES,
	sleep = task.wait,
	decode = function(body: string)
		return HttpService:JSONDecode(body)
	end,
})

local service = ScriptureService.new({
	client = client,
	cache = cache,
	quota = quota,
	rateLimit = rateLimit,
	reference = Reference,
	usfm = Usfm,
	config = Config,
	log = log,
})

requestPassage.OnServerInvoke = function(player: Player, reference: unknown, bibleId: unknown)
	-- The client is never trusted: the reference and version are both
	-- validated server-side, and the player's own UserId, not anything they
	-- send, keys the throttle.
	return service:getPassage(reference, tostring(player.UserId), bibleId)
end

-- The board's verse of the day. Served from cache after the first call, so
-- every player on the server shares one lookup and one passage fetch.
requestVerseOfTheDay.OnServerInvoke = function()
	return service:getVerseOfTheDay(Config.VOTD_DAY_PROVIDER(), Config.VOTD_BIBLE_ID)
end

requestVersions.OnServerInvoke = function()
	-- Served from cache after the first call; the list is identical for
	-- everyone, so it is not throttled per player.
	return service:getVersions()
end

Players.PlayerRemoving:Connect(function(player)
	rateLimit:forget(tostring(player.UserId))
end)

task.spawn(function()
	-- Startup self-check. A misconfigured experience should announce the
	-- reason in the server log rather than leaving an operator to guess from
	-- a player-facing "unavailable" message.
	local probe = client:getVersion(Config.BIBLE_ID)
	if not probe.ok then
		if probe.reason == "http disabled" then
			log("SELF-CHECK FAILED: HTTP requests are disabled for this experience.")
			log("  Fix: Roblox Studio > File > Game Settings > Security >")
			log("       Allow HTTP Requests, then republish.")
		elseif probe.reason == "secret domain mismatch" then
			log("SELF-CHECK FAILED: the secret is not permitted for the API host.")
			log("  Fix: Creator Hub > Secrets > " .. Config.APP_KEY_SECRET ..
				" must use domain api.youversion.com")
		elseif probe.status == 401 or probe.status == 403 then
			log("SELF-CHECK FAILED: the Platform rejected the app key.")
			log("  Fix: confirm the secret holds the live application's key.")
		else
			log("SELF-CHECK FAILED: " .. tostring(probe.reason))
		end
	else
		log("self-check passed: Platform reachable and credential accepted")
	end

	local stats = service:stats()
	log(string.format(
		"startup stats: requests=%d quotaRemaining=%d cacheEntries=%d",
		stats.httpRequests, stats.quotaRemaining, stats.cacheEntries
	))
end)

-- Roll the board over when the day changes on a long-lived server.
task.spawn(function()
	while true do
		task.wait(600)
		local day = Config.VOTD_DAY_PROVIDER()
		if day ~= votdDay.Value then
			local votd = service:getVerseOfTheDay(day, Config.VOTD_BIBLE_ID)
			votdDay.Value = day
			log(string.format(
				"verse of the day rolled to day %d (%s)",
				day, votd.ok and tostring(votd.reference) or "unavailable"
			))
		end
	end
end)

log("ready")
