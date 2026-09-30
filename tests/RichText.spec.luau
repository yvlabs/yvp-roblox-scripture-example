--!strict
local H = require("./harness")
local RichText = require("../src/shared/RichText")

return function()
	H.describe("RichText", function()
		H.it("escapes the three markup characters", function()
			H.expectEqual(RichText.escape("a & b"), "a &amp; b")
			H.expectEqual(RichText.escape("a < b"), "a &lt; b")
			H.expectEqual(RichText.escape("a > b"), "a &gt; b")
		end)

		H.it("escapes ampersand first so escapes are not double-escaped", function()
			H.expectEqual(RichText.escape("<tag>"), "&lt;tag&gt;")
			H.expectEqual(RichText.escape("&lt;"), "&amp;lt;")
		end)

		H.it("leaves ordinary Scripture punctuation untouched", function()
			local text = "Yahweh\u{2019}s faithfulness endures forever \u{2014} truly!"
			H.expectEqual(RichText.escape(text), text)
		end)

		H.it("does not alter the visible characters of a quoted line", function()
			local line = 'He said, "Come." (Then he left.)'
			H.expectEqual(RichText.escape(line), line)
		end)

		H.it("renders a verse mark with a trailing space", function()
			local mark = RichText.verseMark(16, "#8899bb", 12)
			H.expectTrue(string.find(mark, ">16 <", 1, true), "number then space")
		end)
	end)
end
