--!strict
local H = require("./harness")
local Attribution = require("../src/shared/Attribution")

-- Shapes observed from the live API on 2026-09-27.
local NIV = {
	versionTitle = "New International Version 2011",
	versionAbbreviation = "NIV11",
	copyright = "The Holy Bible, New International Version\u{00AE} NIV\u{00AE}\nCopyright \u{00A9} 1973, 1978, 1984, 2011 by Biblica, Inc.\u{00AE}\nUsed by Permission of Biblica, Inc.\u{00AE} All rights reserved worldwide.",
	promotionalContent = "Biblica is the worldwide publisher.",
	publisherUrl = "https://www.biblica.com/yv-learn-more/",
}

-- ASV returns no attribution fields at all.
local ASV = {
	versionTitle = "American Standard Version",
	versionAbbreviation = "ASV",
	copyright = "",
	promotionalContent = nil,
	publisherUrl = nil,
}

return function()
	H.describe("Attribution", function()
		H.it("folds a multi-line copyright into one line", function()
			local line = Attribution.line(NIV)
			H.expectEqual(string.find(line, "\n", 1, true), nil, "no raw newline")
		end)

		H.it("preserves every word of a publisher notice", function()
			local line = Attribution.line(NIV)
			for _, word in { "Holy", "Bible", "New", "International", "Version",
				"Copyright", "1973", "2011", "Biblica", "Permission",
				"rights", "reserved", "worldwide" } do
				H.expectTrue(string.find(line, word, 1, true), "kept: " .. word)
			end
		end)

		H.it("includes the publisher url when present", function()
			H.expectTrue(string.find(Attribution.line(NIV), "biblica.com", 1, true))
		end)

		H.it("still credits the platform when a version has no metadata", function()
			local line = Attribution.line(ASV)
			H.expectTrue(string.find(line, "American Standard Version", 1, true), "title kept")
			H.expectTrue(string.find(line, Attribution.PLATFORM_CREDIT, 1, true), "platform credited")
			H.expectEqual(string.find(line, "|  |", 1, true), nil, "no empty separator runs")
		end)

		H.it("is explicit when attribution is missing entirely", function()
			local line = Attribution.line(nil)
			H.expectTrue(string.find(line, "unavailable", 1, true))
			H.expectTrue(string.find(line, Attribution.PLATFORM_CREDIT, 1, true))
		end)

		H.it("never truncates a long notice", function()
			local long = { versionTitle = "T", copyright = string.rep("word ", 200) }
			local line = Attribution.line(long)
			H.expectTrue(#line > 900, "full notice retained")
		end)

		H.it("collapses runs of whitespace", function()
			H.expectEqual(Attribution.fold("a   b\n\n c"), "a b c")
			H.expectEqual(Attribution.fold("  padded  "), "padded")
			H.expectEqual(Attribution.fold(""), nil)
			H.expectEqual(Attribution.fold(nil), nil)
		end)
	end)
end
