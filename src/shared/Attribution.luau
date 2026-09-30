--!strict
-- Builds the attribution line shown with Scripture.
--
-- Publisher copyright strings are not uniform. Observed 2026-09-27:
--   * WEB   "PUBLIC DOMAIN (not copyrighted)"
--   * NIV   a three-line notice with embedded newlines
--   * AMP   a four-line notice including an address and URL
--   * ASV   no copyright, promotional_content or publisher_url at all
--
-- Newlines are folded to spaces so the notice renders as continuous text in a
-- single label. Every word is preserved; only the line breaks change. Nothing
-- is truncated, because a clipped publisher notice would be a licensing
-- problem, not a layout inconvenience.

local Attribution = {}

local function fold(text: unknown): string?
	if type(text) ~= "string" then
		return nil
	end
	local out = string.gsub(text :: string, "%s+", " ")
	out = string.gsub(out, "^%s*(.-)%s*$", "%1")
	if #out == 0 then
		return nil
	end
	return out
end

Attribution.fold = fold

-- The platform credit is always shown, even when a version carries no
-- publisher metadata, so the source of the text is never ambiguous.
Attribution.PLATFORM_CREDIT = "Scripture delivered by the YouVersion Platform."

function Attribution.line(attribution: any): string
	if type(attribution) ~= "table" then
		return "Version information unavailable. " .. Attribution.PLATFORM_CREDIT
	end

	local parts = {}
	local title = fold(attribution.versionTitle)
	if title then
		table.insert(parts, title)
	end
	local copyright = fold(attribution.copyright)
	if copyright then
		table.insert(parts, copyright)
	end
	local promotional = fold(attribution.promotionalContent)
	if promotional then
		table.insert(parts, promotional)
	end
	local publisher = fold(attribution.publisherUrl)
	if publisher then
		table.insert(parts, publisher)
	end
	table.insert(parts, Attribution.PLATFORM_CREDIT)
	return table.concat(parts, "  |  ")
end

return Attribution
