--!strict
-- Minimal test harness for the Luau CLI.

local Harness = {}

local results = { passed = 0, failed = 0, failures = {} :: { string } }
local currentSuite = ""

function Harness.describe(name: string, body: () -> ())
	currentSuite = name
	body()
	currentSuite = ""
end

function Harness.it(name: string, body: () -> ())
	local ok, err = pcall(body)
	if ok then
		results.passed += 1
		print(string.format("  ok   %s", name))
	else
		results.failed += 1
		local label = string.format("%s > %s: %s", currentSuite, name, tostring(err))
		table.insert(results.failures, label)
		print(string.format("  FAIL %s\n       %s", name, tostring(err)))
	end
end

function Harness.expectEqual(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(string.format("%s expected %s, got %s",
			label or "value", tostring(expected), tostring(actual)), 2)
	end
end

function Harness.expectTrue(value: any, label: string?)
	if not value then
		error(string.format("%s expected truthy, got %s", label or "value", tostring(value)), 2)
	end
end

function Harness.expectFalsy(value: any, label: string?)
	if value then
		error(string.format("%s expected falsy, got %s", label or "value", tostring(value)), 2)
	end
end

function Harness.summary(): number
	print("")
	print(string.format("%d passed, %d failed", results.passed, results.failed))
	for _, failure in results.failures do
		print("  - " .. failure)
	end
	return results.failed
end

-- Controllable clock for time-dependent modules.
function Harness.fakeClock()
	local now = 1000
	return {
		now = function() return now end,
		advance = function(seconds: number) now += seconds end,
	}
end

-- Fake HttpService transport. Queue responses per URL substring.
function Harness.fakeHttp(routes: { { match: string, status: number, body: string, times: number? } })
	local calls = {}
	local queue = {}
	for _, route in routes do
		table.insert(queue, {
			match = route.match,
			status = route.status,
			body = route.body,
			remaining = route.times or math.huge,
		})
	end
	return {
		calls = calls,
		request = function(_self, options)
			table.insert(calls, options)
			for _, route in queue do
				if route.remaining > 0 and string.find(options.Url, route.match, 1, true) then
					route.remaining -= 1
					return { StatusCode = route.status, Body = route.body }
				end
			end
			return { StatusCode = 418, Body = "{}" }
		end,
	}
end

return Harness
