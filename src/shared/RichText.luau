--!strict
-- Helpers for rendering Scripture into Roblox RichText labels.
--
-- SCRIPTURE INTEGRITY: escaping is a rendering concern, not an edit. Roblox
-- RichText treats <, > and & as markup, so an unescaped ampersand would either
-- vanish or corrupt the line. Escaping makes the displayed characters match
-- the source exactly; it does not change the text.

local RichText = {}

-- Escape must handle & first, or the & of a later escape gets double-escaped.
function RichText.escape(text: string): string
	local out = string.gsub(text, "&", "&amp;")
	out = string.gsub(out, "<", "&lt;")
	out = string.gsub(out, ">", "&gt;")
	return out
end

-- A verse number, rendered smaller and dimmer so it reads as an apparatus
-- mark rather than part of the sentence.
function RichText.verseMark(verse: number, color: string, size: number): string
	return string.format('<font color="%s" size="%d">%d </font>', color, size, verse)
end

function RichText.colored(text: string, color: string): string
	return string.format('<font color="%s">%s</font>', color, text)
end

function RichText.italic(text: string): string
	return "<i>" .. text .. "</i>"
end

return RichText
