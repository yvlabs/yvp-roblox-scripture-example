--!strict
local H = require("./harness")

local specs = {
	require("./Reference.spec"),
	require("./Usfm.spec"),
	require("./RichText.spec"),
	require("./Attribution.spec"),
	require("./Cache.spec"),
	require("./Quota.spec"),
	require("./RateLimit.spec"),
	require("./YvpClient.spec"),
	require("./ScriptureService.spec"),
}

for _, spec in specs do
	spec()
end

local failed = H.summary()
if failed > 0 then
	error(string.format("%d test(s) failed", failed))
end
