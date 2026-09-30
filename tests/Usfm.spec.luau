--!strict
local H = require("./harness")
local Usfm = require("../src/shared/Usfm")

-- Synthetic markup in the shape the Platform returns. The words are invented
-- so that no Scripture text is committed to this repository; the live contract
-- test covers real responses.
local PROSE = '<div><div class="p"><span class="yv-v" v="1"></span>'
	.. '<span class="yv-vlbl">1</span>Alpha bravo charlie. '
	.. '<span class="yv-v" v="2"></span><span class="yv-vlbl">2</span>Delta echo.</div></div>'

local POETRY = '<div><div class="q1"><span class="yv-v" v="1"></span>'
	.. '<span class="yv-vlbl">1</span>First line here</div>'
	.. '<div class="q2">Second line indented</div></div>'

local HEADING = '<div><div class="d">A descriptor line.</div>'
	.. '<div class="q1"><span class="yv-v" v="1"></span>'
	.. '<span class="yv-vlbl">1</span>Poetry follows.</div></div>'

local JESUS = '<div><div class="p"><span class="yv-v" v="16"></span>'
	.. '<span class="yv-vlbl">16</span>He said, <span class="wj">quoted words</span> afterwards.</div></div>'

return function()
	H.describe("Usfm", function()
		H.it("splits prose into verse-tagged segments", function()
			local blocks = Usfm.parse(PROSE)
			H.expectEqual(#blocks, 1)
			H.expectEqual(blocks[1].style, "p")
			local segments = blocks[1].segments
			H.expectEqual(#segments, 2)
			H.expectEqual(segments[1].verse, 1)
			H.expectEqual(segments[1].text, "Alpha bravo charlie. ")
			H.expectEqual(segments[2].verse, 2)
			H.expectEqual(segments[2].text, "Delta echo.")
		end)

		H.it("does not emit the verse label twice", function()
			local text = Usfm.plainText(Usfm.parse(PROSE))
			H.expectEqual(string.find(text, "1Alpha", 1, true), nil, "label not inlined")
			H.expectEqual(text, "Alpha bravo charlie. Delta echo.")
		end)

		H.it("separates blocks with a single space", function()
			-- Regression: concatenating blocks with no separator ran adjacent
			-- paragraphs together ("them.Now"), which a live comparison against
			-- format=text caught.
			local blocks = Usfm.parse(POETRY)
			H.expectEqual(Usfm.plainText(blocks), "First line here Second line indented")
		end)

		H.it("keeps poetry lines as separate blocks with indent levels", function()
			local blocks = Usfm.parse(POETRY)
			H.expectEqual(#blocks, 2)
			H.expectEqual(blocks[1].style, "q1")
			H.expectEqual(blocks[2].style, "q2")
			H.expectEqual(Usfm.indentFor("q1"), 1)
			H.expectEqual(Usfm.indentFor("q2"), 2)
			H.expectEqual(Usfm.indentFor("p"), 0)
		end)

		H.it("marks headings", function()
			local blocks = Usfm.parse(HEADING)
			H.expectEqual(blocks[1].style, "d")
			H.expectTrue(Usfm.isHeading("d"))
			H.expectFalsy(Usfm.isHeading("p"))
		end)

		H.it("flags words of Jesus without losing surrounding text", function()
			local blocks = Usfm.parse(JESUS)
			local segments = blocks[1].segments
			H.expectEqual(#segments, 3)
			H.expectEqual(segments[1].verse, 16)
			H.expectEqual(segments[2].text, "quoted words")
			H.expectTrue(segments[2].wordsOfJesus)
			H.expectFalsy(segments[3].wordsOfJesus)
			H.expectEqual(Usfm.plainText(blocks), "He said, quoted words afterwards.")
		end)

		H.it("decodes HTML entities so none are displayed literally", function()
			local blocks = Usfm.parse('<div class="p">Smith &amp; Sons &lt;note&gt; &#8217;quoted&#x2019;</div>')
			local text = Usfm.plainText(blocks)
			H.expectEqual(string.find(text, "&amp;", 1, true), nil, "no raw entity")
			H.expectTrue(string.find(text, "Smith & Sons", 1, true), "ampersand decoded")
			H.expectTrue(string.find(text, "<note>", 1, true), "angle brackets decoded")
			H.expectTrue(string.find(text, "\u{2019}quoted\u{2019}", 1, true), "numeric entities decoded")
		end)

		H.it("survives markup with no classed blocks", function()
			local blocks = Usfm.parse("<div>bare text</div>")
			H.expectEqual(Usfm.plainText(blocks), "bare text")
		end)

		H.it("survives a malformed tail rather than dropping text", function()
			local blocks = Usfm.parse('<div class="p">kept text <span unclosed')
			H.expectTrue(string.find(Usfm.plainText(blocks), "kept text", 1, true))
		end)

		H.it("handles multi-class heading blocks", function()
			-- NIV section headings arrive as class="s1 yv-h"; matching the
			-- whole attribute missed them entirely.
			local blocks = Usfm.parse('<div><div class="s1 yv-h">A Heading</div>'
				.. '<div class="p">Body text.</div></div>')
			H.expectTrue(Usfm.isHeading(blocks[1].style), "s1 yv-h is a heading")
			H.expectFalsy(Usfm.isHeading("p"))
			H.expectEqual(Usfm.indentFor("q1 extra"), 1, "indent found in a token list")
		end)

		H.it("keeps footnotes but marks them as not Scripture", function()
			local html = '<div><div class="p"><span class="yv-v" v="3"></span>'
				.. '<span class="yv-vlbl">3</span>Verse words.'
				.. '<span class="yv-n f"><span class="fr">3:3 </span>'
				.. '<span class="ft">The Greek for </span><span class="fq">again</span></span>'
				.. ' more verse words.</div></div>'
			local blocks = Usfm.parse(html)
			local segments = blocks[1].segments
			local footnotes, scripture = 0, {}
			for _, seg in segments do
				if seg.footnote then
					footnotes += 1
					H.expectTrue(string.find(seg.text, "The Greek for", 1, true), "note text kept")
				else
					table.insert(scripture, seg.text)
				end
			end
			H.expectEqual(footnotes, 1, "exactly one footnote segment")
			H.expectEqual(table.concat(scripture), "Verse words. more verse words.")
		end)

		H.it("excludes footnotes from plain text", function()
			local html = '<div><div class="p">Scripture.'
				.. '<span class="yv-n f"><span class="ft">a note</span></span></div></div>'
			H.expectEqual(Usfm.plainText(Usfm.parse(html)), "Scripture.")
		end)

		H.it("does not let a footnote swallow following text", function()
			local html = '<div><div class="p">A<span class="yv-n f">'
				.. '<span class="ft">n</span></span>B<span class="wj">C</span></div></div>'
			H.expectEqual(Usfm.plainText(Usfm.parse(html)), "ABC")
		end)

		H.it("separates editorial section headings from psalm descriptors", function()
			-- format=text includes "d" descriptors but omits "s1" section
			-- headings, so only the latter are excluded from verse text.
			H.expectTrue(Usfm.isSectionHeading("s1 yv-h"))
			H.expectTrue(Usfm.isSectionHeading("s2"))
			H.expectFalsy(Usfm.isSectionHeading("d"), "descriptor is text")
			H.expectFalsy(Usfm.isSectionHeading("p"))
			-- Both still render with heading styling.
			H.expectTrue(Usfm.isHeading("d"))
			H.expectTrue(Usfm.isHeading("s1 yv-h"))
		end)

		H.it("omits section headings and footnotes from verse text", function()
			local html = '<div><div class="s1 yv-h">The New Birth</div>'
				.. '<div class="d">A Psalm of David.</div>'
				.. '<div class="p">Verse words.<span class="yv-n f">'
				.. '<span class="ft">note</span></span></div></div>'
			local blocks = Usfm.parse(html)
			H.expectEqual(Usfm.verseText(blocks), "A Psalm of David. Verse words.")
			-- plainText keeps headings, because they are shown to readers.
			H.expectTrue(string.find(Usfm.plainText(blocks), "The New Birth", 1, true))
		end)

		H.it("handles markup nested inside words of Jesus", function()
			-- Regression: the Amplified Bible wraps <span class="it"> inside
			-- <span class="wj">. Taking the first </span> closed the wrong
			-- element and leaked raw markup into the displayed text.
			local html = '<div><div class="p"><span class="wj">Truly '
				.. '<span class="it">I say</span> to you</span> he said.</div></div>'
			local blocks = Usfm.parse(html)
			local text = Usfm.plainText(blocks)
			H.expectEqual(string.find(text, "<span", 1, true), nil, "no leaked markup")
			H.expectEqual(text, "Truly I say to you he said.")
			local jesus = {}
			for _, seg in blocks[1].segments do
				if seg.wordsOfJesus then table.insert(jesus, seg.text) end
			end
			H.expectEqual(table.concat(jesus), "Truly I say to you", "nested text still marked")
		end)

		H.it("keeps a footnote nested inside words of Jesus out of Scripture", function()
			local html = '<div><div class="p"><span class="wj">Spoken'
				.. '<span class="yv-n f"><span class="ft">a note</span></span>'
				.. ' words</span></div></div>'
			local blocks = Usfm.parse(html)
			H.expectEqual(Usfm.verseText(blocks), "Spoken words")
			local noteMarked = false
			for _, seg in blocks[1].segments do
				if seg.footnote then
					noteMarked = true
					H.expectFalsy(seg.wordsOfJesus, "a footnote is not Jesus speaking")
				end
			end
			H.expectTrue(noteMarked, "footnote preserved")
		end)

		H.it("returns nothing for non-string input", function()
			H.expectEqual(#Usfm.parse(nil), 0)
			H.expectEqual(#Usfm.parse(42), 0)
			H.expectEqual(#Usfm.parse({}), 0)
		end)

		H.it("preserves every character of a multi-block document", function()
			local blocks = Usfm.parse(POETRY)
			H.expectEqual(Usfm.plainText(blocks), "First line here Second line indented")
		end)
	end)
end
