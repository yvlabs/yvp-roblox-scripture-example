--!strict
local H = require("./harness")
local Reference = require("../src/shared/Reference")

return function()
	H.describe("Reference", function()
		H.it("parses a verse reference", function()
			local parsed = Reference.parse("JHN.3.16")
			H.expectTrue(parsed, "parsed")
			H.expectEqual(parsed.book, "JHN")
			H.expectEqual(parsed.chapter, 3)
			H.expectEqual(parsed.verse, 16)
		end)

		H.it("parses a chapter reference", function()
			local parsed = Reference.parse("PSA.23")
			H.expectTrue(parsed, "parsed")
			H.expectEqual(parsed.chapter, 23)
			H.expectEqual(parsed.verse, nil)
		end)

		H.it("round-trips through canonical form", function()
			H.expectEqual(Reference.canonical("JHN.3.16"), "JHN.3.16")
			H.expectEqual(Reference.canonical("PSA.23"), "PSA.23")
		end)

		H.it("derives the containing chapter", function()
			H.expectEqual(Reference.chapterOf("JHN.3.16"), "JHN.3")
		end)

		H.it("accepts a verse range within one chapter", function()
			-- Verse of the Day uses this form for 16 of its 366 entries.
			H.expectEqual(Reference.canonical("ISA.43.18-19"), "ISA.43.18-19")
			H.expectEqual(Reference.canonical("PSA.8.3-4"), "PSA.8.3-4")
			H.expectEqual(Reference.canonical("1CO.13.4-7"), "1CO.13.4-7")
			local parsed = Reference.parse("ISA.43.18-19")
			H.expectEqual(parsed.verse, 18)
			H.expectEqual(parsed.endVerse, 19)
		end)

		H.it("rejects a backwards or empty range", function()
			H.expectFalsy(Reference.canonical("ISA.43.19-18"))
			H.expectFalsy(Reference.canonical("ISA.43.18-18"))
			H.expectFalsy(Reference.canonical("ISA.43.0-19"))
		end)

		H.it("rejects the fully-qualified range form", function()
			-- BOK.C.V-BOK.C.V returns 404 from the API, so it must not be
			-- built into a request.
			H.expectFalsy(Reference.canonical("JHN.3.16-JHN.3.17"))
		end)

		-- Security: these are the inputs a hostile client would send.
		H.it("rejects path traversal", function()
			H.expectFalsy(Reference.canonical("../../v1/bibles/1"))
			H.expectFalsy(Reference.canonical("JHN.3.16/../../../etc"))
		end)

		H.it("rejects query and fragment injection", function()
			H.expectFalsy(Reference.canonical("JHN.3.16?format=html"))
			H.expectFalsy(Reference.canonical("JHN.3.16&x=1"))
			H.expectFalsy(Reference.canonical("JHN.3.16#frag"))
		end)

		H.it("rejects absolute URLs", function()
			H.expectFalsy(Reference.canonical("https://evil.example/x"))
		end)

		H.it("rejects non-strings and empty input", function()
			H.expectFalsy(Reference.canonical(nil))
			H.expectFalsy(Reference.canonical(42))
			H.expectFalsy(Reference.canonical({}))
			H.expectFalsy(Reference.canonical(""))
		end)

		H.it("rejects lowercase and malformed book codes", function()
			H.expectFalsy(Reference.canonical("jhn.3.16"))
			H.expectFalsy(Reference.canonical("JOHN.3.16"))
			H.expectFalsy(Reference.canonical("JH.3.16"))
		end)

		H.it("rejects out-of-range chapters and verses", function()
			H.expectFalsy(Reference.canonical("JHN.0.16"))
			H.expectFalsy(Reference.canonical("JHN.3.0"))
			H.expectFalsy(Reference.canonical("JHN.999.1"))
			H.expectFalsy(Reference.canonical("JHN.3.999"))
		end)

		H.it("accepts numbered book codes", function()
			H.expectEqual(Reference.canonical("1CO.13.4"), "1CO.13.4")
			H.expectEqual(Reference.canonical("2TI.3.16"), "2TI.3.16")
			H.expectEqual(Reference.canonical("3JN.1.4"), "3JN.1.4")
			H.expectEqual(Reference.canonical("1SA.17.45"), "1SA.17.45")
		end)

		H.it("accepts a deuterocanonical book present in this version", function()
			H.expectEqual(Reference.canonical("SIR.2.1"), "SIR.2.1")
		end)

		H.it("rejects a book code that is not in this version", function()
			H.expectFalsy(Reference.canonical("ZZZ.1.1"))
			H.expectFalsy(Reference.canonical("9XX.1.1"))
		end)

		H.it("rejects an all-digit book code", function()
			H.expectFalsy(Reference.canonical("123.1.1"))
		end)

		H.it("bounds chapters per book, not globally", function()
			H.expectEqual(Reference.canonical("GEN.50.1"), "GEN.50.1", "Genesis 50 exists")
			H.expectFalsy(Reference.canonical("GEN.51.1"), "Genesis 51 does not")
			H.expectEqual(Reference.canonical("PSA.150.1"), "PSA.150.1", "Psalm 150 exists")
			H.expectFalsy(Reference.canonical("PSA.151.1"), "Psalm 151 not in this version")
			H.expectEqual(Reference.canonical("JUD.1.3"), "JUD.1.3", "Jude has one chapter")
			H.expectFalsy(Reference.canonical("JUD.2.1"), "Jude 2 does not exist")
		end)

		H.it("exposes book titles and chapter counts", function()
			H.expectEqual(Reference.title("GEN"), "Genesis")
			H.expectEqual(Reference.title("REV"), "Revelation")
			H.expectEqual(Reference.chapterCount("PSA"), 150)
			H.expectEqual(Reference.chapterCount("JUD"), 1)
			H.expectEqual(Reference.chapterCount("NOPE"), 0)
			H.expectEqual(Reference.book("GEN").canon, "old_testament")
		end)

		H.it("exposes the full book allowlist", function()
			H.expectEqual(#Reference.BOOKS, 80)
			H.expectTrue(Reference.isKnownBook("REV"))
			H.expectFalsy(Reference.isKnownBook("rev"))
			H.expectFalsy(Reference.isKnownBook(nil))
		end)

		H.it("rejects an over-long reference", function()
			H.expectFalsy(Reference.canonical(string.rep("A", 40)))
		end)
	end)
end
