--!strict
-- Scripture Kiosk client.
--
-- Holds no credentials and never contacts the Platform. It asks the server for
-- a reference and renders exactly the blocks that come back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("ScriptureKiosk")
local Reference = require(Shared:WaitForChild("Reference"))
local Config = require(Shared:WaitForChild("Config"))
local Attribution = require(Shared:WaitForChild("Attribution"))

local KioskUI = require(script:WaitForChild("KioskUI"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("ScriptureKioskRemotes")
local requestPassage = remotes:WaitForChild("RequestPassage") :: RemoteFunction
local requestVersions = remotes:WaitForChild("RequestVersions") :: RemoteFunction
local requestVerseOfTheDay = remotes:WaitForChild("RequestVerseOfTheDay") :: RemoteFunction
local votdDay = remotes:WaitForChild("VerseOfTheDayDay") :: IntValue

local ui = KioskUI.new(playerGui)

local state = {
	book = "JHN",
	chapter = 3,
	bibleId = Config.BIBLE_ID,
	inFlight = false,
}

local function attributionOf(result: any): string
	return Attribution.line(result and result.attribution)
end

local function currentReference(): string
	return string.format("%s.%d", state.book, state.chapter)
end

local function render()
	ui:setTitle(string.format("%s %d", Reference.title(state.book), state.chapter))
	ui:highlightBook(state.book)
	ui:setChapters(state.book, state.chapter, function(chapter)
		state.chapter = chapter
		load()
	end)
end

function load()
	if state.inFlight then
		return
	end
	state.inFlight = true
	render()
	ui:showMessage("Loading...")

	task.spawn(function()
		local ok, result = pcall(function()
			return requestPassage:InvokeServer(currentReference(), state.bibleId)
		end)
		state.inFlight = false

		if not ok or not result then
			ui:showMessage("The kiosk could not be reached. Please try again.")
			return
		end

		ui:setAttribution(result.attribution)
		if result.ok then
			ui:setTitle(result.reference or currentReference())
			ui:showBlocks(result.blocks or {})
		else
			ui:showMessage(result.reason or "That passage could not be loaded.")
		end
	end)
end

--------------------------------------------------------------- interaction --
ui.closeButton.Activated:Connect(function()
	ui:setOpen(false)
end)

ui.versionButton.Activated:Connect(function()
	ui:toggleVersionPopup()
end)

for code, bookButton in ui.bookButtons do
	bookButton.Activated:Connect(function()
		state.book = code
		state.chapter = 1
		load()
	end)
end

-- The version list comes from shared configuration, so it is available
-- immediately with no round trip and no failure mode. The previous build
-- fetched it over a RemoteFunction and silently returned on failure, which
-- left an empty popup with no explanation.
local function applyVersionLabel()
	for _, version in Config.VERSIONS do
		if version.id == state.bibleId then
			ui:setVersionLabel(version.abbreviation)
			return
		end
	end
	ui:setVersionLabel("Version")
end

local function buildVersionPicker()
	ui:setVersions(Config.VERSIONS, state.bibleId, function(bibleId)
		if bibleId == state.bibleId then
			return
		end
		state.bibleId = bibleId
		applyVersionLabel()
		buildVersionPicker()
		load()
	end)
end

applyVersionLabel()
buildVersionPicker()

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer ~= player or prompt.Name ~= "OpenReader" then
		return
	end
	ui:setOpen(true)
	load()
end)

------------------------------------------------------------------- board ----
-- The board shows the Verse of the Day. It needs no interaction: a player who
-- walks past reads Scripture without opening anything.
local Usfm = require(Shared:WaitForChild("Usfm"))
local RichText = require(Shared:WaitForChild("RichText"))

local function boardLabels()
	local model = Workspace:FindFirstChild("ScriptureKiosk")
	local board = model and model:FindFirstChild("Board")
	local surface = board and board:FindFirstChild("BoardSurface")
	local frame = surface and surface:FindFirstChildWhichIsA("Frame")
	if not frame then
		return nil
	end
	local reference = frame:FindFirstChild("Reference") :: TextLabel?
	local body = frame:FindFirstChild("Body") :: TextLabel?
	local attribution = frame:FindFirstChild("Attribution") :: TextLabel?
	if not (reference and body and attribution) then
		return nil
	end
	return { reference = reference, body = body, attribution = attribution }
end

-- Render blocks as one wrapped string. The board is read at a distance, so it
-- keeps verse numbers but drops footnote markers, which would be unreadable
-- and unusable there.
local function boardText(blocks: { any }): string
	local parts = {}
	local verseCount = 0
	for _, block in blocks do
		for _, segment in block.segments do
			if segment.verse then verseCount += 1 end
		end
	end
	local multiVerse = verseCount > 1
	for _, block in blocks do
		if not Usfm.isSectionHeading(block.style) then
			for _, segment in block.segments do
				if not segment.footnote then
					if segment.verse then
						-- Only for ranges; a lone "19" before a single verse is noise.
						-- Colour only: a size tag is absolute and would defeat
						-- TextScaled on the board.
						if multiVerse then
							table.insert(parts, string.format('<font color="#9fb4d8">%d </font>', segment.verse))
						end
					end
					table.insert(parts, RichText.escape(segment.text))
				end
			end
			table.insert(parts, " ")
		end
	end
	return table.concat(parts)
end

local function updateBoard()
	local labels = boardLabels()
	if not labels then
		return
	end

	local ok, result = pcall(function()
		return requestVerseOfTheDay:InvokeServer()
	end)

	if ok and result and result.ok then
		labels.reference.Text = result.reference or ""
		labels.body.RichText = true
		labels.body.Text = boardText(result.blocks or {})
		local attribution = result.attribution
		labels.attribution.Text = Attribution.line(attribution and {
			versionTitle = attribution.versionTitle,
			copyright = attribution.copyright,
			publisherUrl = attribution.publisherUrl,
		})
	else
		labels.reference.Text = ""
		labels.body.Text = (result and result.reason) or "The verse of the day could not be loaded."
		labels.attribution.Text = Attribution.PLATFORM_CREDIT
	end
end

task.spawn(function()
	-- The server warms this at startup; a short wait avoids racing it.
	task.wait(2)
	updateBoard()
end)

votdDay.Changed:Connect(updateBoard)
