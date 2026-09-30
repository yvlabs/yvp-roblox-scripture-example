--!strict
-- Reading UI.
--
-- Scripture is rendered block by block from the parsed structure the server
-- sends. Verse numbers, poetry indents, headings and words-of-Jesus styling
-- all come from the publisher's own markup; nothing here decides what the
-- text says. Characters are escaped for RichText so they display exactly as
-- received.
--
-- Scrolling uses a UIListLayout driving AutomaticCanvasSize. The previous
-- version relied on a single auto-sizing TextLabel, whose height the
-- ScrollingFrame did not track, so long chapters were cut off with no way to
-- reach the rest.

local RichText = require(game:GetService("ReplicatedStorage"):WaitForChild("ScriptureKiosk"):WaitForChild("RichText"))
local Usfm = require(game:GetService("ReplicatedStorage"):WaitForChild("ScriptureKiosk"):WaitForChild("Usfm"))
local Reference = require(game:GetService("ReplicatedStorage"):WaitForChild("ScriptureKiosk"):WaitForChild("Reference"))
local Attribution = require(game:GetService("ReplicatedStorage"):WaitForChild("ScriptureKiosk"):WaitForChild("Attribution"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local KioskUI = {}
KioskUI.__index = KioskUI

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or Theme.CORNER)
	c.Parent = parent
	return c
end

local function pad(parent: Instance, amount: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, amount)
	p.PaddingBottom = UDim.new(0, amount)
	p.PaddingLeft = UDim.new(0, amount)
	p.PaddingRight = UDim.new(0, amount)
	p.Parent = parent
	return p
end

local function label(props: { [string]: any }, parent: Instance): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Gotham
	l.TextColor3 = Theme.TEXT
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.RichText = true
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

local function button(props: { [string]: any }, parent: Instance): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = Theme.PANEL_RAISED
	b.Font = Enum.Font.GothamMedium
	b.TextColor3 = Theme.TEXT
	b.BorderSizePixel = 0
	for key, value in props do
		(b :: any)[key] = value
	end
	b.Parent = parent
	return b
end

function KioskUI.new(parent: Instance)
	local self = setmetatable({}, KioskUI)

	local gui = Instance.new("ScreenGui")
	gui.Name = "ScriptureKioskUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.DisplayOrder = 10
	-- Sibling behaviour draws descendants above their parent. Under Global
	-- behaviour the popup children (ZIndex 1) rendered behind their own
	-- opaque parent frame (ZIndex 20), so the list looked like an empty box.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = parent
	self.gui = gui

	local root = Instance.new("Frame")
	root.Name = "Panel"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(0.86, 0.88)
	root.BackgroundColor3 = Theme.PANEL
	root.BorderSizePixel = 0
	root.Parent = gui
	corner(root, 14)
	self.root = root

	----------------------------------------------------------------- header --
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 56)
	header.BackgroundTransparency = 1
	header.Parent = root
	pad(header, Theme.PAD)

	self.titleLabel = label({
		Name = "Title",
		Size = UDim2.new(1, -220, 1, 0),
		Font = Enum.Font.GothamBold,
		TextSize = 22,
		Text = "Reading Desk",
	}, header)

	self.versionButton = button({
		Name = "VersionPicker",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -52, 0.5, 0),
		Size = UDim2.fromOffset(150, 32),
		TextSize = 14,
		Text = "Version",
	}, header)
	corner(self.versionButton, 8)

	self.closeButton = button({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(36, 32),
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		Text = "X",
	}, header)
	corner(self.closeButton, 8)

	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, -Theme.PAD * 2, 0, 1)
	divider.Position = UDim2.fromOffset(Theme.PAD, 56)
	divider.BackgroundColor3 = Theme.DIVIDER
	divider.BorderSizePixel = 0
	divider.Parent = root

	------------------------------------------------------------ book column --
	local books = Instance.new("ScrollingFrame")
	books.Name = "Books"
	books.Position = UDim2.fromOffset(Theme.PAD, 68)
	books.Size = UDim2.new(0.2, 0, 1, -68 - Theme.PAD - 66)
	books.BackgroundColor3 = Theme.SIDEBAR
	books.BorderSizePixel = 0
	books.ScrollBarThickness = 5
	books.ScrollBarImageColor3 = Theme.ACCENT_DIM
	books.CanvasSize = UDim2.new()
	books.AutomaticCanvasSize = Enum.AutomaticSize.Y
	books.Parent = root
	corner(books, 8)
	pad(books, 6)

	local booksLayout = Instance.new("UIListLayout")
	booksLayout.Padding = UDim.new(0, 1)
	booksLayout.SortOrder = Enum.SortOrder.LayoutOrder
	booksLayout.Parent = books

	self.bookButtons = {}
	local lastCanon = nil
	local order = 0
	for _, info in Reference.BOOK_INFO do
		order += 1
		if info.canon ~= lastCanon then
			lastCanon = info.canon
			local heading = label({
				Name = "Canon_" .. info.canon,
				LayoutOrder = order,
				Size = UDim2.new(1, 0, 0, 22),
				Font = Enum.Font.GothamBold,
				TextSize = 10,
				TextColor3 = Theme.TEXT_FAINT,
				Text = string.upper((string.gsub(info.canon, "_", " "))),
			}, books)
			heading.TextYAlignment = Enum.TextYAlignment.Bottom
			order += 1
		end
		local b = button({
			Name = info.id,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Font = Enum.Font.Gotham,
			TextSize = 14,
			TextColor3 = Theme.TEXT_MUTED,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "  " .. info.title,
		}, books)
		corner(b, 6)
		self.bookButtons[info.id] = b
	end

	--------------------------------------------------------- chapter grid --
	-- A wrapping grid, not a single row. Genesis has 50 chapters and Psalms
	-- 150; a horizontal strip put most of them off-screen with no scroll
	-- affordance, so they were simply unreachable.
	local chapters = Instance.new("ScrollingFrame")
	chapters.Name = "Chapters"
	chapters.Position = UDim2.new(0.2, Theme.PAD + Theme.GAP, 0, 68)
	chapters.Size = UDim2.new(0.8, -Theme.PAD * 2 - Theme.GAP, 0, 74)
	chapters.BackgroundTransparency = 1
	chapters.BorderSizePixel = 0
	chapters.ScrollBarThickness = 5
	chapters.ScrollBarImageColor3 = Theme.ACCENT_DIM
	chapters.ScrollingDirection = Enum.ScrollingDirection.Y
	chapters.CanvasSize = UDim2.new()
	chapters.AutomaticCanvasSize = Enum.AutomaticSize.Y
	chapters.Parent = root
	self.chapterStrip = chapters

	local chapterLayout = Instance.new("UIGridLayout")
	chapterLayout.CellSize = UDim2.fromOffset(34, 28)
	chapterLayout.CellPadding = UDim2.fromOffset(5, 5)
	chapterLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chapterLayout.Parent = chapters

	------------------------------------------------------------- passage ----
	local passage = Instance.new("ScrollingFrame")
	passage.Name = "Passage"
	passage.Position = UDim2.new(0.2, Theme.PAD + Theme.GAP, 0, 150)
	passage.Size = UDim2.new(0.8, -Theme.PAD * 2 - Theme.GAP, 1, -150 - 66)
	passage.BackgroundTransparency = 1
	passage.BorderSizePixel = 0
	passage.ScrollBarThickness = 6
	passage.ScrollBarImageColor3 = Theme.ACCENT_DIM
	passage.CanvasSize = UDim2.new()
	passage.AutomaticCanvasSize = Enum.AutomaticSize.Y
	passage.Parent = root
	self.passageFrame = passage

	local passageLayout = Instance.new("UIListLayout")
	passageLayout.Padding = UDim.new(0, 7)
	passageLayout.SortOrder = Enum.SortOrder.LayoutOrder
	passageLayout.Parent = passage
	self.passageLayout = passageLayout

	---------------------------------------------------------- attribution ---
	-- Auto-sizing, because publisher notices vary from four words (WEB) to a
	-- four-line notice with an address (AMP). A fixed height would clip a
	-- licensed publisher's copyright, which is a licensing problem rather
	-- than a layout one. The passage frame yields space as this grows.
	self.attributionLabel = label({
		Name = "Attribution",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, Theme.PAD, 1, -Theme.PAD),
		Size = UDim2.new(1, -Theme.PAD * 2 - 160, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 12,
		TextWrapped = true,
		TextColor3 = Theme.TEXT_FAINT,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Text = "",
	}, root)

	local function resizePassage()
		local reserved = self.attributionLabel.AbsoluteSize.Y + Theme.PAD * 2 + 8
		self.passageFrame.Size = UDim2.new(0.8, -Theme.PAD * 2 - Theme.GAP, 1, -150 - reserved)
		books.Size = UDim2.new(0.2, 0, 1, -68 - reserved)
	end
	self.attributionLabel:GetPropertyChangedSignal("AbsoluteSize"):Connect(resizePassage)
	resizePassage()

	----------------------------------------------------- footnote control --
	-- Always visible. The previous build put this at the end of the scrolling
	-- passage, so in a long chapter a reader never saw it.
	self.footnoteButton = button({
		Name = "FootnoteToggle",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -Theme.PAD, 1, -Theme.PAD),
		Size = UDim2.fromOffset(150, 28),
		BackgroundColor3 = Theme.PANEL_RAISED,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = Theme.TEXT_MUTED,
		Text = "Footnotes",
		Visible = false,
	}, root)
	corner(self.footnoteButton, 6)

	local footnotePanel = Instance.new("ScrollingFrame")
	footnotePanel.Name = "FootnotePanel"
	footnotePanel.AnchorPoint = Vector2.new(1, 1)
	footnotePanel.Position = UDim2.new(1, -Theme.PAD, 1, -Theme.PAD - 34)
	footnotePanel.Size = UDim2.fromOffset(420, 240)
	footnotePanel.BackgroundColor3 = Theme.PANEL_RAISED
	footnotePanel.BorderSizePixel = 0
	footnotePanel.ScrollBarThickness = 5
	footnotePanel.ScrollBarImageColor3 = Theme.ACCENT_DIM
	footnotePanel.Visible = false
	footnotePanel.ZIndex = 20
	footnotePanel.CanvasSize = UDim2.new()
	footnotePanel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	footnotePanel.Parent = root
	corner(footnotePanel, 8)
	pad(footnotePanel, 10)
	self.footnotePanel = footnotePanel

	local footnoteLayout = Instance.new("UIListLayout")
	footnoteLayout.Padding = UDim.new(0, 6)
	footnoteLayout.SortOrder = Enum.SortOrder.LayoutOrder
	footnoteLayout.Parent = footnotePanel

	self.footnoteButton.Activated:Connect(function()
		footnotePanel.Visible = not footnotePanel.Visible
		self:_refreshFootnoteButton()
	end)

	------------------------------------------------------- version popup ----
	local popup = Instance.new("ScrollingFrame")
	popup.Name = "VersionList"
	popup.AnchorPoint = Vector2.new(1, 0)
	popup.Position = UDim2.new(1, -52 - Theme.PAD, 0, 56)
	popup.Size = UDim2.fromOffset(300, 268)
	popup.BackgroundColor3 = Theme.PANEL_RAISED
	popup.BorderSizePixel = 0
	popup.ScrollBarThickness = 5
	popup.Visible = false
	popup.ZIndex = 20
	popup.CanvasSize = UDim2.new()
	popup.AutomaticCanvasSize = Enum.AutomaticSize.Y
	popup.Parent = root
	corner(popup, 8)
	pad(popup, 6)
	self.versionPopup = popup

	local popupLayout = Instance.new("UIListLayout")
	popupLayout.Padding = UDim.new(0, 2)
	popupLayout.SortOrder = Enum.SortOrder.LayoutOrder
	popupLayout.Parent = popup

	self.versionButtons = {}
	return self
end

function KioskUI:setOpen(open: boolean)
	self.gui.Enabled = open
	if not open then
		self.versionPopup.Visible = false
		self.footnotePanel.Visible = false
		self:_refreshFootnoteButton()
	end
end

function KioskUI:isOpen(): boolean
	return self.gui.Enabled
end

function KioskUI:setTitle(text: string)
	self.titleLabel.Text = text
end

function KioskUI:setVersionLabel(abbreviation: string)
	-- Plain ASCII. U+25BE rendered as a missing-glyph box in the Roblox font.
	self.versionButton.Text = abbreviation .. "  v"
end

function KioskUI:highlightBook(code: string)
	for id, b in self.bookButtons do
		local selected = id == code
		b.BackgroundTransparency = selected and 0 or 1
		b.BackgroundColor3 = Theme.SELECTED
		b.TextColor3 = selected and Theme.TEXT or Theme.TEXT_MUTED
	end
end

-- Build the chapter chips for a book. Uses the embedded chapter count, so it
-- costs no Platform request.
function KioskUI:setChapters(bookCode: string, current: number, onPick: (number) -> ())
	for _, child in self.chapterStrip:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local count = Reference.chapterCount(bookCode)
	for chapter = 1, count do
		local chip = button({
			Name = "Ch" .. chapter,
			LayoutOrder = chapter,
			Size = UDim2.fromOffset(34, 28),
			TextSize = 13,
			Text = tostring(chapter),
			BackgroundColor3 = chapter == current and Theme.ACCENT or Theme.PANEL_RAISED,
			TextColor3 = chapter == current and Color3.fromRGB(16, 18, 24) or Theme.TEXT_MUTED,
		}, self.chapterStrip)
		corner(chip, 6)
		chip.Activated:Connect(function()
			onPick(chapter)
		end)
	end
end

function KioskUI:_clearPassage()
	for _, child in self.passageFrame:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	self.passageFrame.CanvasPosition = Vector2.new()
end

function KioskUI:showMessage(message: string)
	self:_clearPassage()
	self:_setFootnotes({})
	label({
		Name = "Message",
		LayoutOrder = 1,
		Size = UDim2.new(1, -12, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = Theme.BODY_SIZE,
		TextWrapped = true,
		TextColor3 = Theme.TEXT_MUTED,
		Text = message,
	}, self.passageFrame)
end

-- Render parsed blocks. One TextLabel per block keeps poetry lines on their
-- own rows and lets the list layout drive the scroll canvas.
--
-- Footnotes are NOT set inline. A note printed in the middle of a verse breaks
-- the sentence a reader is in and, worse, can be mistaken for Scripture. Each
-- note leaves a small marker where it occurs and its text is collected into a
-- panel below the passage, revealed on demand. The notes are still present and
-- one click away, which is what the publisher terms ask for.
function KioskUI:showBlocks(blocks: { any })
	self:_clearPassage()
	if #blocks == 0 then
		self:showMessage("This passage came back empty.")
		return
	end

	local notes: { { index: number, text: string } } = {}
	local order = 0

	for _, block in blocks do
		order += 1
		local indent = Usfm.indentFor(block.style) * Theme.INDENT_STUDS
		local heading = Usfm.isHeading(block.style)

		local parts = {}
		for _, segment in block.segments do
			if segment.footnote then
				-- Marker only; the text goes to the panel below.
				table.insert(notes, { index = #notes + 1, text = segment.text })
				table.insert(parts, string.format(
					'<font color="%s" size="%d">[%d]</font>',
					Theme.ACCENT_HEX, Theme.FOOTNOTE_MARK_SIZE, #notes
				))
			else
				if segment.verse then
					table.insert(parts, RichText.verseMark(segment.verse, Theme.VERSE_HEX, Theme.VERSE_MARK_SIZE))
				end
				local escaped = RichText.escape(segment.text)
				if segment.wordsOfJesus then
					escaped = RichText.colored(escaped, Theme.JESUS_HEX)
				end
				table.insert(parts, escaped)
			end
		end

		local body = table.concat(parts)
		if heading then
			body = RichText.italic(body)
		end

		local line = label({
			Name = "Block" .. order,
			LayoutOrder = order,
			Size = UDim2.new(1, -12 - indent, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = heading and Theme.HEADING_SIZE or Theme.BODY_SIZE,
			TextColor3 = heading and Theme.TEXT_MUTED or Theme.TEXT,
			TextWrapped = true,
			LineHeight = Theme.BODY_LINE_SPACING,
			Text = body,
		}, self.passageFrame)

		if indent > 0 then
			local shift = Instance.new("UIPadding")
			shift.PaddingLeft = UDim.new(0, indent)
			shift.Parent = line
		end
	end

	self:_setFootnotes(notes)
end

function KioskUI:_refreshFootnoteButton()
	local count = self._footnoteCount or 0
	if count == 0 then
		self.footnoteButton.Visible = false
		self.footnotePanel.Visible = false
		return
	end
	self.footnoteButton.Visible = true
	self.footnoteButton.Text = string.format(
		"%s %d note%s",
		self.footnotePanel.Visible and "Hide" or "Show",
		count,
		count == 1 and "" or "s"
	)
end

function KioskUI:_setFootnotes(notes: { { index: number, text: string } })
	for _, child in self.footnotePanel:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	self._footnoteCount = #notes
	self.footnotePanel.CanvasPosition = Vector2.new()

	for _, note in notes do
		label({
			Name = "Note" .. note.index,
			LayoutOrder = note.index,
			ZIndex = 21,
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = Theme.FOOTNOTE_SIZE,
			TextWrapped = true,
			TextColor3 = Theme.TEXT_MUTED,
			Text = string.format(
				'<font color="%s">[%d]</font>  %s',
				Theme.ACCENT_HEX, note.index, RichText.escape(note.text)
			),
		}, self.footnotePanel)
	end

	self:_refreshFootnoteButton()
end

function KioskUI:setAttribution(attribution: any)
	self.attributionLabel.Text = Attribution.line(attribution)
end

function KioskUI:setVersionsMessage(message: string)
	for _, child in self.versionPopup:GetChildren() do
		if child:IsA("TextButton") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	label({
		Name = "VersionsMessage",
		LayoutOrder = 1,
		ZIndex = 21,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 13,
		TextWrapped = true,
		TextColor3 = Theme.TEXT_MUTED,
		Text = message,
	}, self.versionPopup)
end

function KioskUI:setVersions(versions: { any }, current: number, onPick: (number) -> ())
	for _, child in self.versionPopup:GetChildren() do
		if child:IsA("TextButton") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	if #versions == 0 then
		-- An empty box with no explanation is what shipped before; say why.
		self:setVersionsMessage("No other versions are available right now.")
		return
	end
	for index, version in versions do
		local row = button({
			Name = "V" .. version.id,
			LayoutOrder = index,
			ZIndex = 21,
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = version.id == current and 0 or 1,
			BackgroundColor3 = Theme.SELECTED,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = version.id == current and Theme.TEXT or Theme.TEXT_MUTED,
			Text = string.format("  %s  -  %s", version.abbreviation, version.label or version.title),
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, self.versionPopup)
		corner(row, 6)
		row.Activated:Connect(function()
			self.versionPopup.Visible = false
			onPick(version.id)
		end)
	end
end

function KioskUI:toggleVersionPopup()
	self.versionPopup.Visible = not self.versionPopup.Visible
end

return KioskUI
