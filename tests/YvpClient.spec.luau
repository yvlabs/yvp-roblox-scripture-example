--!strict
local H = require("./harness")
local YvpClient = require("../src/server/YvpClient")

-- Minimal JSON decode sufficient for the fixtures used here. Roblox supplies
-- HttpService:JSONDecode in the real runtime.
local function decode(text: string): any
	local result = {}
	for key, value in string.gmatch(text, '"([%w_]+)"%s*:%s*"([^"]*)"') do
		result[key] = value
	end
	for key, value in string.gmatch(text, '"([%w_]+)"%s*:%s*(%-?%d+)') do
		result[key] = tonumber(value)
	end
	if next(result) == nil then
		error("undecodable")
	end
	return result
end

local function newClient(routes, sleeps)
	local http = H.fakeHttp(routes)
	local client = YvpClient.new({
		http = http,
		getKey = function() return "SECRET-APP-KEY-VALUE" end,
		base = "https://api.youversion.com",
		maxRetries = 2,
		sleep = function(seconds) table.insert(sleeps, seconds) end,
		decode = decode,
	})
	return client, http
end

return function()
	H.describe("YvpClient", function()
		H.it("decodes a successful passage response", function()
			local client = newClient({
				{ match = "/passages/", status = 200, body = '{"id":1,"content":"For God so loved","reference":"John 3:16"}' },
			}, {})
			local response = client:getPassage(206, "JHN.3.16")
			H.expectTrue(response.ok, "ok")
			H.expectEqual(response.body.reference, "John 3:16")
		end)

		H.it("sends the app key as a header and never in the URL", function()
			local client, http = newClient({
				{ match = "/passages/", status = 200, body = '{"content":"x","reference":"r"}' },
			}, {})
			client:getPassage(206, "JHN.3.16")
			local call = http.calls[1]
			H.expectEqual(call.Headers["X-YVP-App-Key"], "SECRET-APP-KEY-VALUE")
			H.expectEqual(string.find(call.Url, "SECRET", 1, true), nil, "key absent from URL")
		end)

		H.it("does not leak the key into a returned error", function()
			local client = newClient({
				{ match = "/passages/", status = 500, body = "server error" },
			}, {})
			local response = client:getPassage(206, "JHN.3.16")
			H.expectFalsy(response.ok)
			local serialised = tostring(response.reason) .. tostring(response.body)
			H.expectEqual(string.find(serialised, "SECRET", 1, true), nil, "key absent from error")
		end)

		H.it("does not retry a 404", function()
			local client, http = newClient({
				{ match = "/passages/", status = 404, body = "{}" },
			}, {})
			local response = client:getPassage(206, "XXX.1.1")
			H.expectFalsy(response.ok)
			H.expectEqual(response.status, 404)
			H.expectEqual(#http.calls, 1, "single attempt")
		end)

		H.it("does not retry a rejected credential", function()
			local client, http = newClient({
				{ match = "/bibles/", status = 401, body = "{}" },
			}, {})
			local response = client:getVersion(206)
			H.expectEqual(response.reason, "credential rejected")
			H.expectEqual(#http.calls, 1)
		end)

		H.it("retries a 429 and succeeds", function()
			local sleeps = {}
			local client, http = newClient({
				{ match = "/passages/", status = 429, body = "{}", times = 1 },
				{ match = "/passages/", status = 200, body = '{"content":"text","reference":"John 3:16"}' },
			}, sleeps)
			local response = client:getPassage(206, "JHN.3.16")
			H.expectTrue(response.ok, "eventual success")
			H.expectEqual(#http.calls, 2)
			H.expectEqual(sleeps[1], 2, "backoff applied")
		end)

		H.it("gives up after the retry budget on repeated 5xx", function()
			local sleeps = {}
			local client, http = newClient({
				{ match = "/passages/", status = 503, body = "{}" },
			}, sleeps)
			local response = client:getPassage(206, "JHN.3.16")
			H.expectFalsy(response.ok)
			H.expectEqual(#http.calls, 3, "initial attempt plus two retries")
			H.expectEqual(#sleeps, 2)
		end)

		H.it("reports a malformed body without retrying", function()
			local client, http = newClient({
				{ match = "/passages/", status = 200, body = "<html>not json</html>" },
			}, {})
			local response = client:getPassage(206, "JHN.3.16")
			H.expectFalsy(response.ok)
			H.expectEqual(response.reason, "malformed response body")
			H.expectEqual(#http.calls, 1)
		end)

		H.it("identifies a disabled-HttpService fault and does not retry", function()
			local calls = 0
			local client = YvpClient.new({
				http = { request = function()
					calls += 1
					error("Http requests are not enabled. Enable via game settings")
				end },
				getKey = function() return "K" end,
				base = "https://api.youversion.com",
				maxRetries = 2,
				sleep = function() end,
				decode = decode,
			})
			local response = client:getPassage(206, "JHN.3.16")
			H.expectFalsy(response.ok)
			H.expectEqual(response.reason, "http disabled")
			H.expectFalsy(response.retryable, "configuration faults are not retryable")
			H.expectEqual(calls, 1, "no retries wasted on a configuration fault")
		end)

		H.it("identifies a secret domain mismatch", function()
			local client = YvpClient.new({
				http = { request = function()
					error("The secret is not allowed to access this domain")
				end },
				getKey = function() return "K" end,
				base = "https://api.youversion.com",
				maxRetries = 0,
				sleep = function() end,
				decode = decode,
			})
			H.expectEqual(client:getPassage(206, "JHN.3.16").reason, "secret domain mismatch")
		end)

		H.it("never leaks a request URL from a thrown error", function()
			local client = YvpClient.new({
				http = { request = function()
					error("connection failed to https://api.youversion.com/v1/bibles/206?key=SECRETVALUE")
				end },
				getKey = function() return "SECRETVALUE" end,
				base = "https://api.youversion.com",
				maxRetries = 0,
				sleep = function() end,
				decode = decode,
			})
			local response = client:getPassage(206, "JHN.3.16")
			local serialised = tostring(response.reason)
			H.expectEqual(string.find(serialised, "SECRETVALUE", 1, true), nil, "key absent")
			H.expectEqual(string.find(serialised, "api.youversion.com", 1, true), nil, "URL absent")
		end)

		-- Regression: HttpService exposes RequestAsync, not request. Injecting
		-- the service directly threw on every call and looked like an outage.
		-- All 66 tests passed at the time because the fake implemented the
		-- interface the real object did not.
		H.it("rejects a transport shaped like raw HttpService", function()
			local fakeHttpService = {
				RequestAsync = function() return { StatusCode = 200, Body = "{}" } end,
				JSONDecode = function() return {} end,
			}
			local ok, err = pcall(function()
				return YvpClient.new({
					http = fakeHttpService,
					getKey = function() return "K" end,
					base = "https://api.youversion.com",
					decode = decode,
				})
			end)
			H.expectFalsy(ok, "construction must fail")
			H.expectTrue(string.find(tostring(err), "RequestAsync", 1, true),
				"error names the real cause")
		end)

		H.it("rejects a transport that is not a table", function()
			for _, bad in { nil, "http", 42 } do
				local ok = pcall(function()
					return YvpClient.new({
						http = bad,
						getKey = function() return "K" end,
						base = "https://api.youversion.com",
						decode = decode,
					})
				end)
				H.expectFalsy(ok, "construction must fail for " .. typeof(bad))
			end
		end)

		H.it("accepts an adapter that wraps RequestAsync", function()
			local service = {
				RequestAsync = function(_self, options)
					return { StatusCode = 200, Body = '{"content":"text","reference":"John 3:16"}' }
				end,
			}
			-- The adapter used in init.server.luau.
			local adapter = {
				request = function(_self, options)
					return service:RequestAsync(options)
				end,
			}
			local client = YvpClient.new({
				http = adapter,
				getKey = function() return "K" end,
				base = "https://api.youversion.com",
				decode = decode,
			})
			local response = client:getPassage(206, "JHN.3.16")
			H.expectTrue(response.ok, "adapter works end to end")
			H.expectEqual(response.body.reference, "John 3:16")
		end)

		H.it("honours Retry-After on a 429 instead of guessing", function()
			local sleeps = {}
			local calls = 0
			local client = YvpClient.new({
				http = { request = function()
					calls += 1
					if calls == 1 then
						return { StatusCode = 429, Body = "Rate limit exceeded.",
							Headers = { ["Retry-After"] = "3" } }
					end
					return { StatusCode = 200, Body = '{"content":"t","reference":"r"}' }
				end },
				getKey = function() return "K" end,
				base = "https://api.youversion.com",
				maxRetries = 2,
				sleep = function(seconds) table.insert(sleeps, seconds) end,
				decode = decode,
			})
			local response = client:getPassage(206, "JHN.3.16")
			H.expectTrue(response.ok)
			H.expectEqual(sleeps[1], 3, "slept the advertised interval, not 2^n")
		end)

		H.it("matches Retry-After case-insensitively", function()
			local sleeps = {}
			local calls = 0
			local client = YvpClient.new({
				http = { request = function()
					calls += 1
					if calls == 1 then
						return { StatusCode = 429, Body = "", Headers = { ["retry-after"] = "4" } }
					end
					return { StatusCode = 200, Body = '{"content":"t","reference":"r"}' }
				end },
				getKey = function() return "K" end,
				base = "https://api.youversion.com",
				maxRetries = 1,
				sleep = function(s) table.insert(sleeps, s) end,
				decode = decode,
			})
			client:getPassage(206, "JHN.3.16")
			H.expectEqual(sleeps[1], 4)
		end)

		H.it("does not sleep out a multi-minute penalty box", function()
			-- A non-live key gets Retry-After: 600. Blocking a player request
			-- for ten minutes is worse than telling them to come back.
			local sleeps = {}
			local client = YvpClient.new({
				http = { request = function()
					return { StatusCode = 429, Body = "", Headers = { ["Retry-After"] = "600" } }
				end },
				getKey = function() return "K" end,
				base = "https://api.youversion.com",
				maxRetries = 2,
				sleep = function(s) table.insert(sleeps, s) end,
				decode = decode,
			})
			local response = client:getPassage(206, "JHN.3.16")
			H.expectFalsy(response.ok)
			H.expectEqual(#sleeps, 0, "returned immediately rather than sleeping 600s")
			H.expectEqual(response.retryAfter, 600, "interval reported to the caller")
		end)

		H.it("falls back to exponential backoff when Retry-After is absent", function()
			local sleeps = {}
			local client = YvpClient.new({
				http = { request = function() return { StatusCode = 503, Body = "" } end },
				getKey = function() return "K" end,
				base = "https://api.youversion.com",
				maxRetries = 2,
				sleep = function(s) table.insert(sleeps, s) end,
				decode = decode,
			})
			client:getPassage(206, "JHN.3.16")
			H.expectEqual(sleeps[1], 2)
			H.expectEqual(sleeps[2], 4)
		end)

		H.it("survives a transport exception", function()
			local client = YvpClient.new({
				http = { request = function() error("network down") end },
				getKey = function() return "K" end,
				base = "https://api.youversion.com",
				maxRetries = 0,
				sleep = function() end,
				decode = decode,
			})
			local response = client:getPassage(206, "JHN.3.16")
			H.expectFalsy(response.ok)
			H.expectEqual(response.reason, "transport error")
		end)
	end)
end
