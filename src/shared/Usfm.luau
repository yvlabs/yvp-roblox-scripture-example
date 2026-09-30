--!strict
-- Parses the Platform's HTML passage format into render-ready blocks.
--
-- Observed 2026-09-27 for version 206: the markup uses only <div> and <span>,
-- with classes p (prose), m (margin prose), q1/q2 (poetry indent levels),
-- d (psalm descriptor / heading), wj (words of Jesus), plus the verse markers
-- <span class="yv-v" v="N"></span> and <span class="yv-vlbl">N</span>.
--
-- SCRIPTURE INTEGRITY: this module never edits Scripture characters. It splits
-- the document into structural blocks and records where verses begin. The
-- concatenation of every emitted segment equals the document's text content,
-- and a test asserts exactly that.

local Usfm = {}

export type Segment = {
	text: string,
	verse: number?, -- verse that begins AT this segment, if any
	wordsOfJesus: boolean?,
	footnote: boolean?, -- publisher footnote, not Scripture prose
}

export type Block = {
	style: string, -- p, m, q1, q2, d, s
	segments: { Segment },
}

-- Minimal entity decoding. The sampled output carried no entities, but the
-- format does not promise that, and a literal "&amp;" on screen would be a
-- visible corruption of the text.
local ENTITIES = {
	["&amp;"] = "&",
	["&lt;"] = "<",
	["&gt;"] = ">",
	["&quot;"] = '"',
	["&apos;"] = "'",
	["&nbsp;"] = "\u{00A0}",
}

function Usfm.decodeEntities(text: string): string
	local out = text
	for entity, replacement in ENTITIES do
		out = string.gsub(out, entity, replacement)
	end
	-- Numeric entities, decimal and hex.
	out = string.gsub(out, "&#(%d+);", function(code)
		local n = tonumber(code)
		return n and utf8.char(n) or ""
	end)
	out = string.gsub(out, "&#[xX](%x+);", function(code)
		local n = tonumber(code, 16)
		return n and utf8.char(n) or ""
	end)
	return out
end

-- Find the </span> matching an opening <span> whose tag ends at `from`.
-- Spans nest: the Amplified Bible wraps <span class="it"> inside
-- <span class="wj">, so taking the first </span> closed the wrong element and
-- leaked raw markup into the text.
local function matchingSpanEnd(html: string, from: number): (number?, number?)
	local depth = 1
	local cursor = from + 1
	while cursor <= #html do
		local nextOpen = string.find(html, "<span", cursor, true)
		local nextClose = string.find(html, "</span>", cursor, true)
		if not nextClose then
			return nil, nil
		end
		if nextOpen and nextOpen < nextClose then
			depth += 1
			cursor = nextOpen + 5
		else
			depth -= 1
			if depth == 0 then
				return nextClose, nextClose + 7
			end
			cursor = nextClose + 7
		end
	end
	return nil, nil
end

-- Parse the inner content of one block into ordered segments.
local parseSegments: (string) -> { Segment }
function parseSegments(html: string): { Segment }
	local segments: { Segment } = {}
	local pendingVerse: number? = nil
	local position = 1

	local function pushText(raw: string, wordsOfJesus: boolean?, footnote: boolean?)
		if #raw == 0 then
			return
		end
		local text = Usfm.decodeEntities(raw)
		if #text == 0 then
			return
		end
		table.insert(segments, {
			text = text,
			verse = pendingVerse,
			wordsOfJesus = wordsOfJesus or nil,
			footnote = footnote or nil,
		})
		pendingVerse = nil
	end

	while position <= #html do
		local tagStart = string.find(html, "<", position, true)
		if not tagStart then
			pushText(string.sub(html, position))
			break
		end

		if tagStart > position then
			pushText(string.sub(html, position, tagStart - 1))
		end

		local tagEnd = string.find(html, ">", tagStart, true)
		if not tagEnd then
			-- Malformed tail; treat the remainder as text rather than dropping it.
			pushText(string.sub(html, tagStart))
			break
		end

		local tag = string.sub(html, tagStart, tagEnd)

		-- Verse anchor carries the number.
		local verseNumber = string.match(tag, '<span%s+class="yv%-v"%s+v="(%d+)"')
		if verseNumber then
			pendingVerse = tonumber(verseNumber)
			position = tagEnd + 1
			continue
		end

		-- The visible label duplicates the anchor; drop its inner text so the
		-- number is not emitted twice.
		if string.match(tag, '<span%s+class="yv%-vlbl"') then
			local closeStart = string.find(html, "</span>", tagEnd, true)
			position = closeStart and (closeStart + 7) or (tagEnd + 1)
			continue
		end

		-- Footnotes arrive inline as <span class="yv-n f"> wrapping further
		-- spans (fr/ft/fq/fqa). Biblica's terms call for the text to be shown
		-- with its footnotes, so they are kept -- but marked, because rendering
		-- them as ordinary prose would read as Scripture and change what the
		-- verse appears to say.
		if string.match(tag, '<span%s+class="yv%-n') then
			local closeStart, after = matchingSpanEnd(html, tagEnd)
			if closeStart and after then
				local inner = string.sub(html, tagEnd + 1, closeStart - 1)
				pushText((string.gsub(inner, "<[^>]*>", "")), nil, true)
				position = after
			else
				position = tagEnd + 1
			end
			continue
		end

		-- Words of Jesus: a styled span whose inner text is Scripture, and which
		-- may itself contain nested markup and footnotes. Parse it recursively
		-- so that structure survives instead of being flattened or leaked.
		if string.match(tag, '<span%s+class="wj"') then
			local closeStart, after = matchingSpanEnd(html, tagEnd)
			if closeStart and after then
				local inner = string.sub(html, tagEnd + 1, closeStart - 1)
				local nested = parseSegments(inner)
				for index, segment in nested do
					if index == 1 and pendingVerse then
						segment.verse = pendingVerse
						pendingVerse = nil
					end
					if not segment.footnote then
						segment.wordsOfJesus = true
					end
					table.insert(segments, segment)
				end
				position = after
			else
				position = tagEnd + 1
			end
			continue
		end

		-- Any other tag contributes no characters.
		position = tagEnd + 1
	end

	return segments
end

-- Parse a full passage document into blocks.
function Usfm.parse(html: unknown): { Block }
	if type(html) ~= "string" then
		return {}
	end
	local document = html :: string
	local blocks: { Block } = {}

	for style, inner in string.gmatch(document, '<div%s+class="([^"]+)">(.-)</div>') do
		local segments = parseSegments(inner)
		if #segments > 0 then
			table.insert(blocks, { style = style, segments = segments })
		end
	end

	-- A document with no classed blocks still has text worth showing.
	if #blocks == 0 then
		local segments = parseSegments(document)
		if #segments > 0 then
			table.insert(blocks, { style = "p", segments = segments })
		end
	end

	return blocks
end

-- The plain text of a parsed document, used to prove nothing was dropped.
--
-- Segments within a block concatenate directly, because the markup already
-- carries the spacing between them. Blocks are separate paragraphs or poetry
-- lines, so they are joined with a single space, which is how the Platform's
-- own text rendering separates them. A live integrity test compares this
-- output against format=text for the same chapter.
function Usfm.plainText(blocks: { Block }): string
	local blockTexts = {}
	for _, block in blocks do
		local parts = {}
		for _, segment in block.segments do
			-- Footnotes are publisher apparatus, not the passage itself, so
			-- they are excluded here. This keeps the integrity comparison
			-- against format=text meaningful.
			if not segment.footnote then
				table.insert(parts, segment.text)
			end
		end
		local text = table.concat(parts)
		if #text > 0 then
			table.insert(blockTexts, text)
		end
	end
	return table.concat(blockTexts, " ")
end

Usfm.POETRY_STYLES = { q1 = 1, q2 = 2, q3 = 3, q4 = 4 }
Usfm.HEADING_STYLES = {
	d = true, s = true, s1 = true, s2 = true, s3 = true, ms = true, mt = true,
}

-- A block's class attribute can carry several tokens, e.g. "s1 yv-h" on NIV
-- section headings. Matching the whole string missed those entirely.
local function tokens(style: string): { string }
	local out = {}
	for token in string.gmatch(style, "[^%s]+") do
		table.insert(out, token)
	end
	return out
end

Usfm.tokens = tokens

function Usfm.indentFor(style: string): number
	for _, token in tokens(style) do
		local level = Usfm.POETRY_STYLES[token]
		if level then
			return level
		end
	end
	return 0
end

-- Editorial section headings ("The New Birth"). These are supplied by the
-- publisher as navigation aids and are NOT part of the verse text: the
-- Platform's own format=text rendering omits them. Psalm descriptors (class
-- "d", e.g. "A Psalm of David") are different -- they ARE in format=text and
-- are treated as text.
function Usfm.isSectionHeading(style: string): boolean
	for _, token in tokens(style) do
		if token == "yv-h" or token == "ms" or token == "mt"
			or string.match(token, "^s%d?$") then
			return true
		end
	end
	return false
end

-- Scripture only: no editorial section headings, no footnotes. This is what a
-- live test compares against the Platform's format=text rendering.
function Usfm.verseText(blocks: { Block }): string
	local blockTexts = {}
	for _, block in blocks do
		if not Usfm.isSectionHeading(block.style) then
			local parts = {}
			for _, segment in block.segments do
				if not segment.footnote then
					table.insert(parts, segment.text)
				end
			end
			local text = table.concat(parts)
			if #text > 0 then
				table.insert(blockTexts, text)
			end
		end
	end
	return table.concat(blockTexts, " ")
end

function Usfm.isHeading(style: string): boolean
	for _, token in tokens(style) do
		-- yv-h is the Platform's own marker for a heading block.
		if Usfm.HEADING_STYLES[token] or token == "yv-h" then
			return true
		end
	end
	return false
end

return Usfm
