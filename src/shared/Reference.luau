--!strict
-- USFM passage-reference handling.
--
-- SECURITY: every reference that reaches the network layer is built by this
-- module. Player input is never interpolated into a URL directly; it is parsed
-- into typed fields, checked against a fixed book allowlist, and re-formatted,
-- so a hostile client cannot escape the path (e.g. "../", query injection, or
-- an arbitrary host).
--
-- The allowlist below was read from GET /v1/bibles/206/index on 2026-09-27
-- (80 books: old_testament, deuterocanon, new_testament). It is specific to
-- the configured version. Regenerate with tools/fetch-books.mjs if Config
-- BIBLE_ID changes; an unknown code is rejected locally rather than spending a
-- Platform request on a guaranteed 404.

local Reference = {}

local MAX_VERSE = 176 -- Psalm 119, the longest chapter.

-- Book metadata read from GET /v1/bibles/206/index on 2026-09-27: id, display
-- title, chapter count and canon. Embedding it means book and chapter
-- navigation costs no Platform requests at all, and an out-of-range chapter is
-- rejected locally instead of spending a request on a certain 404.
--
-- This is structural metadata, not Scripture. Regenerate with
-- tools/fetch-books.mjs if Config.BIBLE_ID changes.
export type BookInfo = { id: string, title: string, chapters: number, canon: string }

local BOOKS: { BookInfo } = {
	{ id = "GEN", title = "Genesis", chapters = 50, canon = "old_testament" },
	{ id = "EXO", title = "Exodus", chapters = 40, canon = "old_testament" },
	{ id = "LEV", title = "Leviticus", chapters = 27, canon = "old_testament" },
	{ id = "NUM", title = "Numbers", chapters = 36, canon = "old_testament" },
	{ id = "DEU", title = "Deuteronomy", chapters = 34, canon = "old_testament" },
	{ id = "JOS", title = "Joshua", chapters = 24, canon = "old_testament" },
	{ id = "JDG", title = "Judges", chapters = 21, canon = "old_testament" },
	{ id = "RUT", title = "Ruth", chapters = 4, canon = "old_testament" },
	{ id = "1SA", title = "1 Samuel", chapters = 31, canon = "old_testament" },
	{ id = "2SA", title = "2 Samuel", chapters = 24, canon = "old_testament" },
	{ id = "1KI", title = "1 Kings", chapters = 22, canon = "old_testament" },
	{ id = "2KI", title = "2 Kings", chapters = 25, canon = "old_testament" },
	{ id = "1CH", title = "1 Chronicles", chapters = 29, canon = "old_testament" },
	{ id = "2CH", title = "2 Chronicles", chapters = 36, canon = "old_testament" },
	{ id = "EZR", title = "Ezra", chapters = 10, canon = "old_testament" },
	{ id = "NEH", title = "Nehemiah", chapters = 13, canon = "old_testament" },
	{ id = "EST", title = "Esther", chapters = 10, canon = "old_testament" },
	{ id = "JOB", title = "Job", chapters = 42, canon = "old_testament" },
	{ id = "PSA", title = "Psalms", chapters = 150, canon = "old_testament" },
	{ id = "PRO", title = "Proverbs", chapters = 31, canon = "old_testament" },
	{ id = "ECC", title = "Ecclesiastes", chapters = 12, canon = "old_testament" },
	{ id = "SNG", title = "Song of Solomon", chapters = 8, canon = "old_testament" },
	{ id = "ISA", title = "Isaiah", chapters = 66, canon = "old_testament" },
	{ id = "JER", title = "Jeremiah", chapters = 52, canon = "old_testament" },
	{ id = "LAM", title = "Lamentations", chapters = 5, canon = "old_testament" },
	{ id = "EZK", title = "Ezekiel", chapters = 48, canon = "old_testament" },
	{ id = "DAN", title = "Daniel", chapters = 12, canon = "old_testament" },
	{ id = "HOS", title = "Hosea", chapters = 14, canon = "old_testament" },
	{ id = "JOL", title = "Joel", chapters = 3, canon = "old_testament" },
	{ id = "AMO", title = "Amos", chapters = 9, canon = "old_testament" },
	{ id = "OBA", title = "Obadiah", chapters = 1, canon = "old_testament" },
	{ id = "JON", title = "Jonah", chapters = 4, canon = "old_testament" },
	{ id = "MIC", title = "Micah", chapters = 7, canon = "old_testament" },
	{ id = "NAM", title = "Nahum", chapters = 3, canon = "old_testament" },
	{ id = "HAB", title = "Habakkuk", chapters = 3, canon = "old_testament" },
	{ id = "ZEP", title = "Zephaniah", chapters = 3, canon = "old_testament" },
	{ id = "HAG", title = "Haggai", chapters = 2, canon = "old_testament" },
	{ id = "ZEC", title = "Zechariah", chapters = 14, canon = "old_testament" },
	{ id = "MAL", title = "Malachi", chapters = 4, canon = "old_testament" },
	{ id = "TOB", title = "Tobit", chapters = 14, canon = "deuterocanon" },
	{ id = "JDT", title = "Judith", chapters = 16, canon = "deuterocanon" },
	{ id = "ESG", title = "Esther (Greek)", chapters = 10, canon = "deuterocanon" },
	{ id = "WIS", title = "Wisdom", chapters = 19, canon = "deuterocanon" },
	{ id = "SIR", title = "Sirach", chapters = 51, canon = "deuterocanon" },
	{ id = "BAR", title = "Baruch", chapters = 6, canon = "deuterocanon" },
	{ id = "1MA", title = "1 Maccabees", chapters = 16, canon = "deuterocanon" },
	{ id = "2MA", title = "2 Maccabees", chapters = 15, canon = "deuterocanon" },
	{ id = "1ES", title = "1 Esdras", chapters = 9, canon = "deuterocanon" },
	{ id = "2ES", title = "2 Esdras", chapters = 16, canon = "deuterocanon" },
	{ id = "MAN", title = "Prayer of Manasses", chapters = 1, canon = "deuterocanon" },
	{ id = "3MA", title = "3 Maccabees", chapters = 7, canon = "deuterocanon" },
	{ id = "4MA", title = "4 Maccabees", chapters = 18, canon = "deuterocanon" },
	{ id = "PS2", title = "Psalm 151", chapters = 1, canon = "deuterocanon" },
	{ id = "MAT", title = "Matthew", chapters = 28, canon = "new_testament" },
	{ id = "MRK", title = "Mark", chapters = 16, canon = "new_testament" },
	{ id = "LUK", title = "Luke", chapters = 24, canon = "new_testament" },
	{ id = "JHN", title = "John", chapters = 21, canon = "new_testament" },
	{ id = "ACT", title = "Acts", chapters = 28, canon = "new_testament" },
	{ id = "ROM", title = "Romans", chapters = 16, canon = "new_testament" },
	{ id = "1CO", title = "1 Corinthians", chapters = 16, canon = "new_testament" },
	{ id = "2CO", title = "2 Corinthians", chapters = 13, canon = "new_testament" },
	{ id = "GAL", title = "Galatians", chapters = 6, canon = "new_testament" },
	{ id = "EPH", title = "Ephesians", chapters = 6, canon = "new_testament" },
	{ id = "PHP", title = "Philippians", chapters = 4, canon = "new_testament" },
	{ id = "COL", title = "Colossians", chapters = 4, canon = "new_testament" },
	{ id = "1TH", title = "1 Thessalonians", chapters = 5, canon = "new_testament" },
	{ id = "2TH", title = "2 Thessalonians", chapters = 3, canon = "new_testament" },
	{ id = "1TI", title = "1 Timothy", chapters = 6, canon = "new_testament" },
	{ id = "2TI", title = "2 Timothy", chapters = 4, canon = "new_testament" },
	{ id = "TIT", title = "Titus", chapters = 3, canon = "new_testament" },
	{ id = "PHM", title = "Philemon", chapters = 1, canon = "new_testament" },
	{ id = "HEB", title = "Hebrews", chapters = 13, canon = "new_testament" },
	{ id = "JAS", title = "James", chapters = 5, canon = "new_testament" },
	{ id = "1PE", title = "1 Peter", chapters = 5, canon = "new_testament" },
	{ id = "2PE", title = "2 Peter", chapters = 3, canon = "new_testament" },
	{ id = "1JN", title = "1 John", chapters = 5, canon = "new_testament" },
	{ id = "2JN", title = "2 John", chapters = 1, canon = "new_testament" },
	{ id = "3JN", title = "3 John", chapters = 1, canon = "new_testament" },
	{ id = "JUD", title = "Jude", chapters = 1, canon = "new_testament" },
	{ id = "REV", title = "Revelation", chapters = 22, canon = "new_testament" },
}

local BY_ID: { [string]: BookInfo } = {}
local BOOK_LIST: { string } = {}
for _, book in BOOKS do
	BY_ID[book.id] = book
	table.insert(BOOK_LIST, book.id)
end

Reference.BOOKS = BOOK_LIST
Reference.BOOK_INFO = BOOKS

function Reference.book(code: unknown): BookInfo?
	if type(code) ~= "string" then
		return nil
	end
	return BY_ID[code :: string]
end

function Reference.chapterCount(code: unknown): number
	local info = Reference.book(code)
	return info and info.chapters or 0
end

function Reference.title(code: unknown): string
	local info = Reference.book(code)
	return info and info.title or tostring(code)
end

function Reference.isKnownBook(code: unknown): boolean
	return Reference.book(code) ~= nil
end

-- Parse a USFM passage id such as "JHN.3.16", "PSA.23", or "1CO.13.4".
-- Returns nil plus a reason when the input is not a well-formed reference.
function Reference.parse(raw: unknown): ({ book: string, chapter: number, verse: number?, endVerse: number? }?, string?)
	if type(raw) ~= "string" then
		return nil, "reference must be a string"
	end
	local text = raw :: string
	if #text == 0 or #text > 16 then
		return nil, "reference length out of range"
	end

	-- Book codes are three characters: three uppercase letters, or a leading
	-- digit followed by two uppercase letters (1CO, 2TI, 3JN).
	--
	-- Three accepted forms:
	--   BOK.C      whole chapter
	--   BOK.C.V    single verse
	--   BOK.C.V-V  verse range within one chapter
	--
	-- The range form is what Verse of the Day uses for 16 of its 366 entries
	-- (e.g. ISA.43.18-19) and it fetches successfully. The fully-qualified
	-- form BOK.C.V-BOK.C.V does NOT work - it returns 404 - so it is not
	-- accepted here either.
	local book, chapter, verse, endVerse = string.match(text, "^([%u%d]%u%u)%.(%d+)%.(%d+)%-(%d+)$")
	if not book then
		book, chapter, verse = string.match(text, "^([%u%d]%u%u)%.(%d+)%.(%d+)$")
	end
	if not book then
		book, chapter = string.match(text, "^([%u%d]%u%u)%.(%d+)$")
	end
	if not book then
		return nil, "reference must look like BOK.C, BOK.C.V or BOK.C.V-V"
	end

	local info = BY_ID[book]
	if not info then
		return nil, "unknown book code"
	end

	local chapterNumber = tonumber(chapter)
	if not chapterNumber or chapterNumber < 1 or chapterNumber > info.chapters then
		-- Per-book bound, so Genesis 51 is rejected here rather than costing a
		-- Platform request that is certain to 404.
		return nil, "chapter out of range"
	end

	local verseNumber: number? = nil
	if verse then
		verseNumber = tonumber(verse)
		if not verseNumber or verseNumber < 1 or verseNumber > MAX_VERSE then
			return nil, "verse out of range"
		end
	end

	local endVerseNumber: number? = nil
	if endVerse then
		endVerseNumber = tonumber(endVerse)
		if not endVerseNumber or endVerseNumber < 1 or endVerseNumber > MAX_VERSE then
			return nil, "range end out of range"
		end
		if not verseNumber or endVerseNumber <= verseNumber then
			return nil, "range must end after it starts"
		end
	end

	return {
		book = book,
		chapter = chapterNumber,
		verse = verseNumber,
		endVerse = endVerseNumber,
	}, nil
end

function Reference.format(parsed: { book: string, chapter: number, verse: number?, endVerse: number? }): string
	if parsed.verse and parsed.endVerse then
		return string.format("%s.%d.%d-%d", parsed.book, parsed.chapter, parsed.verse, parsed.endVerse)
	end
	if parsed.verse then
		return string.format("%s.%d.%d", parsed.book, parsed.chapter, parsed.verse)
	end
	return string.format("%s.%d", parsed.book, parsed.chapter)
end

function Reference.canonical(raw: unknown): (string?, string?)
	local parsed, err = Reference.parse(raw)
	if not parsed then
		return nil, err
	end
	return Reference.format(parsed), nil
end

function Reference.chapterOf(raw: unknown): (string?, string?)
	local parsed, err = Reference.parse(raw)
	if not parsed then
		return nil, err
	end
	return string.format("%s.%d", parsed.book, parsed.chapter), nil
end

return Reference
