--!strict
-- Builds the physical kiosk so the place needs no hand-placed parts and the
-- whole experience is reproducible from source.

local Kiosk = {}

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = true
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

function Kiosk.build(workspace: Instance)
	local existing = workspace:FindFirstChild("ScriptureKiosk")
	if existing then
		existing:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = "ScriptureKiosk"
	model.Parent = workspace

	part({
		Name = "Ground",
		Size = Vector3.new(120, 2, 120),
		Position = Vector3.new(0, -1, 0),
		Color = Color3.fromRGB(122, 145, 112),
		Material = Enum.Material.Grass,
	}, model)

	part({
		Name = "Plaza",
		Size = Vector3.new(34, 0.4, 26),
		Position = Vector3.new(0, 0.2, 0),
		Color = Color3.fromRGB(216, 208, 192),
		Material = Enum.Material.Slate,
	}, model)

	local pedestal = part({
		Name = "Pedestal",
		Size = Vector3.new(9, 4, 2),
		Position = Vector3.new(0, 2.2, -8),
		Color = Color3.fromRGB(94, 78, 62),
		Material = Enum.Material.Wood,
	}, model)

	local board = part({
		Name = "Board",
		Size = Vector3.new(16, 9, 0.6),
		Position = Vector3.new(0, 8.5, -8.7),
		Color = Color3.fromRGB(38, 40, 48),
	}, model)

	-- Board face shows the Verse of the Day to everyone in the world, with no
	-- interaction required.
	local surface = Instance.new("SurfaceGui")
	surface.Name = "BoardSurface"
	-- Back, not Front: Front points along local -Z, away from players.
	surface.Face = Enum.NormalId.Back
	-- FixedSize is required for CanvasSize to take effect. The default,
	-- PixelsPerStud, silently ignores CanvasSize, so a layout designed for a
	-- 1600x900 canvas rendered at a fraction of the intended size.
	surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surface.CanvasSize = Vector2.new(1600, 900)
	surface.LightInfluence = 0
	surface.Parent = board

	local padding = Instance.new("Frame")
	padding.Size = UDim2.fromScale(1, 1)
	padding.BackgroundTransparency = 1
	padding.Parent = surface

	local layout = Instance.new("UIPadding")
	layout.PaddingTop = UDim.new(0, 56)
	layout.PaddingBottom = UDim.new(0, 40)
	layout.PaddingLeft = UDim.new(0, 72)
	layout.PaddingRight = UDim.new(0, 72)
	layout.Parent = padding

	local heading = Instance.new("TextLabel")
	heading.Name = "Heading"
	heading.Size = UDim2.new(1, 0, 0, 64)
	heading.BackgroundTransparency = 1
	heading.Font = Enum.Font.GothamBold
	heading.TextSize = 56
	heading.TextColor3 = Color3.fromRGB(240, 226, 186)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Text = "Verse of the Day"
	heading.Parent = padding

	local reference = Instance.new("TextLabel")
	reference.Name = "Reference"
	reference.Size = UDim2.new(1, 0, 0, 60)
	reference.Position = UDim2.fromOffset(0, 72)
	reference.BackgroundTransparency = 1
	reference.Font = Enum.Font.GothamMedium
	reference.TextSize = 50
	reference.TextColor3 = Color3.fromRGB(190, 205, 230)
	reference.TextXAlignment = Enum.TextXAlignment.Left
	reference.Text = ""
	reference.Parent = padding

	-- The verse gets most of the board and scales to fill it: a single verse
	-- renders large, a two-verse range steps down just enough to fit. Readable
	-- from across the plaza is the point of the board.
	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.Size = UDim2.new(1, 0, 1, -150 - 96)
	body.Position = UDim2.fromOffset(0, 150)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.GothamMedium
	body.TextScaled = true
	body.TextWrapped = true
	body.RichText = true
	body.TextColor3 = Color3.fromRGB(248, 248, 250)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Center
	body.Text = ""
	body.Parent = padding

	local bodyLimit = Instance.new("UITextSizeConstraint")
	bodyLimit.MaxTextSize = 110
	bodyLimit.MinTextSize = 44
	bodyLimit.Parent = body

	-- Attribution is a permanent element of the board, not an overlay that can
	-- be dismissed or scrolled away from the text it belongs to.
	local attribution = Instance.new("TextLabel")
	attribution.Name = "Attribution"
	attribution.Size = UDim2.new(1, 0, 0, 84)
	attribution.Position = UDim2.new(0, 0, 1, -84)
	attribution.BackgroundTransparency = 1
	attribution.Font = Enum.Font.Gotham
	attribution.TextScaled = true
	attribution.TextWrapped = true
	attribution.TextColor3 = Color3.fromRGB(176, 176, 186)
	attribution.TextXAlignment = Enum.TextXAlignment.Left
	attribution.TextYAlignment = Enum.TextYAlignment.Bottom
	attribution.Text = ""
	attribution.Parent = padding

	local attributionLimit = Instance.new("UITextSizeConstraint")
	attributionLimit.MaxTextSize = 28
	attributionLimit.MinTextSize = 16
	attributionLimit.Parent = attribution

	-- Reading desk: walking up to it opens the full browser for that player.
	local desk = part({
		Name = "ReadingDesk",
		Size = Vector3.new(6, 3.2, 3),
		Position = Vector3.new(0, 1.8, 2),
		Color = Color3.fromRGB(120, 96, 70),
		Material = Enum.Material.Wood,
	}, model)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenReader"
	prompt.ActionText = "Read the Bible"
	prompt.ObjectText = "Reading Desk"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = desk

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "Spawn"
	spawnLocation.Size = Vector3.new(8, 0.4, 8)
	spawnLocation.Position = Vector3.new(0, 0.6, 12)
	spawnLocation.Anchored = true
	spawnLocation.Color = Color3.fromRGB(198, 186, 160)
	spawnLocation.Material = Enum.Material.Slate
	spawnLocation.Parent = model

	model.PrimaryPart = pedestal
	return model
end

return Kiosk
