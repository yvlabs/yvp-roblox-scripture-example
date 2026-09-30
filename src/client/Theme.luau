--!strict
-- Single source of visual constants, so spacing and colour stay consistent
-- and can be adjusted in one place.

return {
	PANEL = Color3.fromRGB(22, 24, 30),
	PANEL_RAISED = Color3.fromRGB(30, 33, 41),
	SIDEBAR = Color3.fromRGB(17, 19, 24),
	ACCENT = Color3.fromRGB(129, 165, 226),
	ACCENT_DIM = Color3.fromRGB(88, 110, 150),
	TEXT = Color3.fromRGB(238, 239, 244),
	TEXT_MUTED = Color3.fromRGB(150, 154, 168),
	TEXT_FAINT = Color3.fromRGB(112, 116, 130),
	SELECTED = Color3.fromRGB(46, 58, 80),
	DIVIDER = Color3.fromRGB(44, 47, 57),

	-- Hex forms for RichText, which takes colours as strings.
	VERSE_HEX = "#7f93b8",
	JESUS_HEX = "#d98a7a",
	FOOTNOTE_HEX = "#7d8494",
	ACCENT_HEX = "#81a5e2",

	BODY_SIZE = 19,
	BODY_LINE_SPACING = 1.28,
	VERSE_MARK_SIZE = 13,
	FOOTNOTE_SIZE = 14,
	FOOTNOTE_MARK_SIZE = 12,
	HEADING_SIZE = 17,
	INDENT_STUDS = 26,

	PAD = 18,
	GAP = 10,
	CORNER = 10,
}
