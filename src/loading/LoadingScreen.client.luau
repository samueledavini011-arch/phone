--!strict
--[[
	LoadingScreen  (LocalScript, goes in ReplicatedFirst)

	The Grow a Phone loading screen, drawn to look hand-made: wobbly marker
	outlines that jitter like hand-drawn animation, crayon colouring,
	handwritten text and a sticky note for tips.

	A phone grows out of the dirt while the battery gets coloured in with a
	marker. At 100% the phone lights up and a PLAY button pops in. Pressing
	PLAY zooms into the phone's screen and drops the player into the game.

	The progress is real. It waits for the game to load, preloads the
	images, sounds and meshes in ReplicatedStorage and StarterGui, then waits
	for the player's character.

	Remove your old loading screen so the two don't overlap.
	Change the settings in CONFIG below.
]]

local CONFIG = {
	TitleTop = "GROW A",
	TitleBottom = "PHONE",
	PhoneNote = "your phone!", -- the doodled note pointing at the phone
	ReadyNote = "it's ready!!",

	MinimumTime = 4, -- seconds the screen stays up, even if loading is instant
	MaxWait = 25, -- stop waiting for slow assets after this many seconds
	ShowPlayButton = true, -- wait for PLAY at 100%; false goes straight in
	SkipAfter = 8, -- show a skip button after this many seconds (0 = never)

	Statuses = {
		{ At = 0.0, Text = "planting your seeds..." },
		{ At = 0.25, Text = "watering the soil..." },
		{ At = 0.5, Text = "charging batteries..." },
		{ At = 0.75, Text = "bringing back your phones..." },
	},
	ReadyText = "your phones are ready!",

	Tips = {
		"Your plot is saved - your phones will be waiting next time",
		"Plant phones on your plot to earn money",
		"Sell your phones to buy better seeds",
	},
	TipTime = 4, -- seconds each tip stays up

	PreloadFrom = { "ReplicatedStorage", "StarterGui" },
	MaxPreload = 400, -- most assets to preload before moving on

	-- Roblox's own chat and player list are hidden until the game starts.
	HideCoreGui = { Enum.CoreGuiType.Chat, Enum.CoreGuiType.PlayerList },

	-- Sound IDs like "rbxassetid://1234567890". Leave empty for no sound.
	Music = "",
	ReadySound = "",
	ClickSound = "",
}

-- Marker and crayon colours
local COLORS = {
	Paper = Color3.fromRGB(244, 238, 224),
	Grain = Color3.fromRGB(176, 164, 140),
	Ink = Color3.fromRGB(30, 22, 40),
	Sky = Color3.fromRGB(56, 32, 108),
	SkyHatch = Color3.fromRGB(98, 60, 168),
	Ground = Color3.fromRGB(124, 82, 50),
	GroundHatch = Color3.fromRGB(84, 52, 30),
	Building = Color3.fromRGB(38, 22, 78),
	Window = Color3.fromRGB(255, 214, 102),
	Star = Color3.fromRGB(255, 232, 128),
	Moon = Color3.fromRGB(255, 232, 150),
	Mound = Color3.fromRGB(150, 98, 60),
	Leaf = Color3.fromRGB(106, 198, 80),
	PhoneWhite = Color3.fromRGB(252, 250, 244),
	ScreenOff = Color3.fromRGB(70, 72, 104),
	ScreenOn = Color3.fromRGB(92, 172, 250),
	Marker = Color3.fromRGB(86, 198, 70),
	BoxPaper = Color3.fromRGB(250, 245, 232),
	Note = Color3.fromRGB(255, 236, 134),
	Yellow = Color3.fromRGB(255, 214, 64),
	Pink = Color3.fromRGB(255, 122, 172),
	PlayGreen = Color3.fromRGB(112, 214, 90),
	White = Color3.new(1, 1, 1),
}

local TITLE_FONT = Enum.Font.PermanentMarker
local HAND_FONT = Enum.Font.PatrickHand

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

-- The drawing is designed at 1280 x 720 and scaled to fit the screen.
local STAGE_W, STAGE_H = 1280, 720
local CX = STAGE_W / 2
local PANEL_X, PANEL_Y, PANEL_W, PANEL_H = 36, 26, 1208, 668
local GROUND_Y = 500
local PHONE_BOTTOM, PHONE_W, PHONE_H = 470, 104, 176
local PHONE_CY = PHONE_BOTTOM - PHONE_H / 2
local MOUND_Y = 506
local BAR_X, BAR_Y, BAR_W, BAR_H = 610, 584, 440, 50
local STATUS_Y = 642

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local function frame(name: string, parent: Instance, pos: UDim2, size: UDim2, color: Color3?, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = pos
	f.Size = size
	f.BorderSizePixel = 0
	if color then
		f.BackgroundColor3 = color
		f.BackgroundTransparency = transparency or 0
	else
		f.BackgroundTransparency = 1
	end
	f.Parent = parent
	return f
end

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local ROUND = UDim.new(0.5, 0)

local function stroke(parent: Instance, color: Color3, thickness: number, border: boolean?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Round
	if border then
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	s.Parent = parent
	return s
end

local function label(name: string, parent: Instance, text: string, pos: UDim2, size: UDim2, font: Enum.Font, textSize: number, outline: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.Font = font
	l.Text = text
	l.TextSize = textSize
	l.TextColor3 = COLORS.White
	l.Parent = parent
	if outline then
		stroke(l, COLORS.Ink, outline)
	end
	return l
end

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function easeOutBack(x: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function easeInBack(x: number): number
	local c1 = 1.70158
	return (c1 + 1) * x ^ 3 - c1 * x ^ 2
end

local function easeOutCubic(x: number): number
	return 1 - (1 - x) ^ 3
end

local function tween(obj: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local t = TweenService:Create(obj, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function makeSound(id: string, looped: boolean, volume: number): Sound?
	if id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = looped
	s.Volume = volume
	s.Parent = SoundService
	return s
end

local function playOnce(id: string)
	local s = makeSound(id, false, 0.7)
	if s then
		s:Play()
		s.Ended:Once(function()
			s:Destroy()
		end)
	end
end

--------------------------------------------------------------------------
-- The hand-drawn look
--------------------------------------------------------------------------

-- "Boiling" lines: like hand-drawn animation, each line is redrawn eight
-- times a second with a slightly different wobble.
type Boil = { obj: GuiObject, pos: UDim2, rot: number, rotAmp: number, posAmp: number, seed: number }
local boils: { Boil } = {}
local seedCounter = 0

local function boil(obj: GuiObject, rotAmp: number, posAmp: number)
	seedCounter += 1
	table.insert(boils, { obj = obj, pos = obj.Position, rot = obj.Rotation, rotAmp = rotAmp, posAmp = posAmp, seed = seedCounter })
end

local function noise(a: number, b: number): number
	local x = math.sin(a * 127.1 + b * 311.7) * 43758.5453
	return x - math.floor(x)
end

local lastBoilFrame = -1
local function updateBoil(t: number)
	local f = math.floor(t * 8)
	if f == lastBoilFrame then
		return
	end
	lastBoilFrame = f
	for _, b in boils do
		local r = noise(b.seed, f) * 2 - 1
		local dx = (noise(b.seed + 0.37, f) * 2 - 1) * b.posAmp
		local dy = (noise(b.seed + 0.71, f) * 2 - 1) * b.posAmp
		b.obj.Rotation = b.rot + r * b.rotAmp
		b.obj.Position = b.pos + UDim2.fromOffset(dx, dy)
	end
end

-- A shape drawn the way a person would: the colour is a little off the
-- lines, and the outline is two wobbly marker passes.
type Sketch = { root: Frame, fill: Frame?, lines: { Frame } }
local function sketch(parent: Instance, name: string, center: Vector2, size: Vector2, fillColor: Color3?, radius: UDim, z: number, thickness: number): Sketch
	local root = frame(name, parent, UDim2.fromOffset(center.X, center.Y), UDim2.fromOffset(size.X, size.Y))
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.ZIndex = z
	local fill: Frame? = nil
	if fillColor then
		local f = frame("Fill", root, UDim2.fromOffset(3, 3), UDim2.fromScale(1, 1), fillColor)
		f.Rotation = -0.6
		f.ZIndex = z
		corner(f, radius)
		fill = f
	end
	local amp = math.min(0.9, 140 / math.max(size.X, size.Y))
	local lines: { Frame } = {}
	for i = 1, 2 do
		local line = frame("Line", root, if i == 1 then UDim2.new() else UDim2.fromOffset(-2, 1), UDim2.fromScale(1, 1))
		line.Rotation = if i == 1 then 0 else amp * 0.6
		line.ZIndex = z
		corner(line, radius)
		stroke(line, COLORS.Ink, if i == 1 then thickness else math.max(1.5, thickness * 0.55), true)
		boil(line, amp, 1.2)
		table.insert(lines, line)
	end
	return { root = root, fill = fill, lines = lines }
end

-- A single marker stroke from a to b.
local function mark(parent: Instance, a: Vector2, b: Vector2, thickness: number, color: Color3, z: number): Frame
	local mid = (a + b) / 2
	local d = b - a
	local f = frame("Mark", parent, UDim2.fromOffset(mid.X, mid.Y), UDim2.fromOffset(d.Magnitude, thickness), color)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Rotation = math.deg(math.atan2(d.Y, d.X))
	f.ZIndex = z
	corner(f, ROUND)
	return f
end

-- Crayon colouring: lots of slightly uneven parallel strokes.
type HatchStroke = { obj: Frame, x: number }
local function hatch(parent: Instance, w: number, h: number, color: Color3, transparency: number, spacing: number, width: number, angle: number, seed: number, z: number): { HatchStroke }
	local r = Random.new(seed)
	local strokes: { HatchStroke } = {}
	local length = (w + h) * 1.25
	local count = math.ceil((w + 2 * h) / spacing)
	for i = 0, count do
		local x = -h + i * spacing + r:NextNumber(-2, 2)
		local s = frame("Stroke", parent, UDim2.fromOffset(x, h / 2 + r:NextNumber(-6, 6)), UDim2.fromOffset(length * r:NextNumber(0.85, 1), width * r:NextNumber(0.75, 1.25)), color, math.clamp(transparency + r:NextNumber(-0.08, 0.08), 0, 1))
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Rotation = angle + r:NextNumber(-3, 3)
		s.ZIndex = z
		corner(s, ROUND)
		table.insert(strokes, { obj = s, x = x })
	end
	return strokes
end

-- A doodled sparkle: two crossed strokes.
local function sparkle(parent: Instance, center: Vector2, size: number, color: Color3, z: number): Frame
	local holder = frame("Sparkle", parent, UDim2.fromOffset(center.X, center.Y), UDim2.fromOffset(size, size))
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.ZIndex = z
	for _, rot in { 0, 90 } do
		local bar = frame("Bar", holder, UDim2.fromScale(0.5, 0.5), UDim2.new(1, 0, 0, math.max(2.5, size * 0.2)), color)
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Rotation = rot
		bar.ZIndex = z
		corner(bar, ROUND)
	end
	return holder
end

--------------------------------------------------------------------------
-- The page and the drawing on it
--------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local paper = frame("Paper", gui, UDim2.new(), UDim2.fromScale(1, 1), COLORS.Paper)
local rng = Random.new(20261010)
for _ = 1, 90 do
	local size = rng:NextNumber(1.5, 3.2)
	local speck = frame("Grain", paper, UDim2.fromScale(rng:NextNumber(), rng:NextNumber()), UDim2.fromOffset(size, size), COLORS.Grain, 0.5)
	corner(speck, ROUND)
end

local stage = frame("Stage", gui, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(STAGE_W, STAGE_H))
stage.AnchorPoint = Vector2.new(0.5, 0.5)
local fitScale = Instance.new("UIScale")
fitScale.Parent = stage

-- Night sky and dirt, coloured in with crayon strokes
local drawing = Instance.new("CanvasGroup")
drawing.Name = "Drawing"
drawing.BackgroundTransparency = 1
drawing.Position = UDim2.fromOffset(PANEL_X, PANEL_Y)
drawing.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
drawing.ZIndex = 1
drawing.Parent = stage
corner(drawing, UDim.new(0, 18))
frame("Sky", drawing, UDim2.new(), UDim2.fromScale(1, 1), COLORS.Sky)
hatch(drawing, PANEL_W, PANEL_H, COLORS.SkyHatch, 0.55, 15, 20, -35, 1, 1)
local groundTop = GROUND_Y - PANEL_Y
local dirt = frame("Dirt", drawing, UDim2.fromOffset(0, groundTop), UDim2.fromOffset(PANEL_W, PANEL_H - groundTop), COLORS.Ground)
dirt.ClipsDescendants = true
hatch(dirt, PANEL_W, PANEL_H - groundTop, COLORS.GroundHatch, 0.5, 13, 9, 28, 2, 1)

sketch(stage, "Border", Vector2.new(PANEL_X + PANEL_W / 2, PANEL_Y + PANEL_H / 2), Vector2.new(PANEL_W, PANEL_H), nil, UDim.new(0, 18), 3, 5)

-- The horizon, drawn freehand in short strokes
do
	local r = Random.new(5)
	local x, y = PANEL_X + 4, GROUND_Y + r:NextNumber(-3, 3)
	while x < PANEL_X + PANEL_W - 4 do
		local nx = math.min(x + r:NextNumber(70, 130), PANEL_X + PANEL_W - 4)
		local ny = GROUND_Y + r:NextNumber(-4, 4)
		boil(mark(stage, Vector2.new(x, y), Vector2.new(nx, ny), 4, COLORS.Ink, 5), 0.4, 0.8)
		x, y = nx, ny
	end
	for _ = 1, 14 do
		local gx = r:NextNumber(PANEL_X + 30, PANEL_X + PANEL_W - 30)
		if math.abs(gx - CX) > 170 then
			local base = Vector2.new(gx, GROUND_Y + 2)
			boil(mark(stage, base, base + Vector2.new(-7, -14), 3, COLORS.Leaf, 5), 4, 0.6)
			boil(mark(stage, base, base + Vector2.new(6, -12), 3, COLORS.Leaf, 5), 4, 0.6)
		end
	end
end

-- Stars that twinkle by wobbling
for _ = 1, 24 do
	local pos = Vector2.new(rng:NextNumber(PANEL_X + 30, PANEL_X + PANEL_W - 30), rng:NextNumber(PANEL_Y + 25, 300))
	if rng:NextNumber() < 0.7 then
		local s = sparkle(stage, pos, rng:NextNumber(12, 22), if rng:NextNumber() < 0.6 then COLORS.Star else COLORS.White, 2)
		s.Rotation = rng:NextNumber(-20, 20)
		boil(s, 14, 1.5)
	else
		local d = frame("Dot", stage, UDim2.fromOffset(pos.X, pos.Y), UDim2.fromOffset(5, 5), COLORS.Star)
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.ZIndex = 2
		corner(d, ROUND)
		boil(d, 0, 1)
	end
end

-- Moon with craters
local moonPos = Vector2.new(1080, 118)
sketch(stage, "Moon", moonPos, Vector2.new(92, 92), COLORS.Moon, ROUND, 2, 4)
for _, crater in { { -14, -10, 18 }, { 14, 12, 13 }, { 12, -16, 9 } } do
	sketch(stage, "Crater", moonPos + Vector2.new(crater[1], crater[2]), Vector2.new(crater[3], crater[3]), nil, ROUND, 2, 2)
end

-- City skyline standing on the horizon, with a few lit windows
do
	local r = Random.new(29)
	local x = PANEL_X + 18
	while x < PANEL_X + PANEL_W - 90 do
		local w = r:NextNumber(70, 128)
		local h = r:NextNumber(90, 220)
		local cxB = x + w / 2
		local b = sketch(stage, "Building", Vector2.new(cxB, GROUND_Y - h / 2), Vector2.new(w, h), COLORS.Building, UDim.new(0, 3), 2, 3.5)
		b.root.ZIndex = 2
		local cols = if w > 100 then 3 else 2
		local rows = math.floor((h - 24) / 30)
		for row = 0, rows - 1 do
			for col = 0, cols - 1 do
				if r:NextNumber() < 0.4 then
					local wx = x + (col + 0.5) * (w / cols)
					local wy = GROUND_Y - h + 22 + row * 30
					local win = frame("Window", stage, UDim2.fromOffset(wx, wy), UDim2.fromOffset(12, 14), COLORS.Window)
					win.AnchorPoint = Vector2.new(0.5, 0.5)
					win.Rotation = r:NextNumber(-5, 5)
					win.ZIndex = 2
					stroke(win, COLORS.Ink, 2, true)
					boil(win, 3, 0.6)
				end
			end
		end
		if r:NextNumber() < 0.3 then
			local top = Vector2.new(cxB + r:NextNumber(-w / 4, w / 4), GROUND_Y - h)
			boil(mark(stage, top, top + Vector2.new(r:NextNumber(-3, 3), -28), 3, COLORS.Ink, 2), 3, 0.6)
		end
		x += w + r:NextNumber(8, 26)
	end
end

-- Title, lettered by hand: each letter sits a little crooked and wobbles.
type Letter = { scale: UIScale, delay: number }
local function titleRow(text: string, y: number, height: number, textSize: number, fillColor: Color3, shadowColor: Color3, depth: number, outline: number, startDelay: number, seed: number): { Letter }
	local r = Random.new(seed)
	local row = frame("Title", stage, UDim2.fromOffset(0, y), UDim2.fromOffset(STAGE_W, height))
	row.ZIndex = 6
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, -2)
	layout.Parent = row
	local letters: { Letter } = {}
	for i = 1, #text do
		local ch = string.sub(text, i, i)
		local holder = frame("Letter", row, UDim2.new(), UDim2.fromOffset(0, height))
		holder.AutomaticSize = Enum.AutomaticSize.X
		holder.LayoutOrder = i
		holder.ZIndex = 6
		local inner = frame("Inner", holder, UDim2.fromOffset(0, r:NextNumber(-5, 5)), UDim2.fromScale(0, 1))
		inner.AutomaticSize = Enum.AutomaticSize.X
		inner.Rotation = r:NextNumber(-6, 6)
		inner.ZIndex = 6
		local shadow = label("Shadow", inner, ch, UDim2.fromOffset(depth, depth), UDim2.fromScale(0, 1), TITLE_FONT, textSize, outline)
		shadow.AutomaticSize = Enum.AutomaticSize.X
		shadow.TextColor3 = shadowColor
		shadow.ZIndex = 6
		local main = label("Main", inner, ch, UDim2.new(), UDim2.fromScale(0, 1), TITLE_FONT, textSize, outline)
		main.AutomaticSize = Enum.AutomaticSize.X
		main.TextColor3 = fillColor
		main.ZIndex = 7
		local s = Instance.new("UIScale")
		s.Scale = 0
		s.Parent = inner
		boil(inner, 1.8, 1.2)
		table.insert(letters, { scale = s, delay = startDelay + (i - 1) * 0.08 })
	end
	return letters
end
local letters: { Letter } = {}
for _, l in titleRow(CONFIG.TitleTop, 36, 74, 62, COLORS.White, COLORS.Ink, 4, 4, 0.1, 3) do
	table.insert(letters, l)
end
for _, l in titleRow(CONFIG.TitleBottom, 92, 134, 118, COLORS.Yellow, COLORS.Pink, 7, 5, 0.6, 4) do
	table.insert(letters, l)
end

-- Dirt mound, stem and leaves
local mound = sketch(stage, "Mound", Vector2.new(CX, MOUND_Y), Vector2.new(280, 62), COLORS.Mound, ROUND, 7, 4)
for _, dash in { { -80, -4, -60, -8 }, { -24, 12, -4, 10 }, { 40, -6, 62, -10 }, { 86, 10, 104, 6 } } do
	boil(mark(mound.root, Vector2.new(140 + dash[1], 31 + dash[2]), Vector2.new(140 + dash[3], 31 + dash[4]), 3, COLORS.GroundHatch, 7), 3, 0.5)
end
local moundScale = Instance.new("UIScale")
moundScale.Scale = 0
moundScale.Parent = mound.root

local stem = frame("Stem", stage, UDim2.fromOffset(CX, MOUND_Y - 12), UDim2.fromOffset(10, 0), COLORS.Leaf)
stem.AnchorPoint = Vector2.new(0.5, 1)
stem.ZIndex = 6
corner(stem, UDim.new(0, 5))
stroke(stem, COLORS.Ink, 3, true)

local leaves: { UIScale } = {}
for _, info in { { CX - 24, 484, -28 }, { CX + 24, 478, 24 } } do
	local leaf = sketch(stage, "Leaf", Vector2.new(info[1], info[2]), Vector2.new(40, 18), COLORS.Leaf, ROUND, 6, 3)
	leaf.root.Rotation = info[3]
	local s = Instance.new("UIScale")
	s.Scale = 0
	s.Parent = leaf.root
	table.insert(leaves, s)
end

-- The phone, drawn like the one in the game's logo
local phone = frame("Phone", stage, UDim2.fromOffset(CX, PHONE_BOTTOM), UDim2.fromOffset(PHONE_W, PHONE_H))
phone.AnchorPoint = Vector2.new(0.5, 1)
phone.ZIndex = 8
phone.Visible = false
local phoneScale = Instance.new("UIScale")
phoneScale.Parent = phone
sketch(phone, "Body", Vector2.new(PHONE_W / 2, PHONE_H / 2), Vector2.new(PHONE_W, PHONE_H), COLORS.PhoneWhite, UDim.new(0, 22), 8, 5)
local screen = sketch(phone, "Screen", Vector2.new(PHONE_W / 2, PHONE_H / 2), Vector2.new(84, 152), COLORS.ScreenOff, UDim.new(0, 14), 8, 2.5)
local screenFill = screen.fill :: Frame
local notch = frame("Notch", phone, UDim2.fromOffset(PHONE_W / 2, 21), UDim2.fromOffset(30, 7), COLORS.Ink)
notch.AnchorPoint = Vector2.new(0.5, 0.5)
notch.ZIndex = 8
corner(notch, ROUND)
local screenText = label("Percent", phone, "0%", UDim2.fromOffset(0, PHONE_H / 2 - 18), UDim2.fromOffset(PHONE_W, 36), HAND_FONT, 32, 2.5)
screenText.ZIndex = 9
local shineMarks: { Frame } = {
	mark(phone, Vector2.new(22, 50), Vector2.new(36, 36), 4, COLORS.White, 9),
	mark(phone, Vector2.new(22, 66), Vector2.new(48, 40), 4, COLORS.White, 9),
}
for _, m in shineMarks do
	m.BackgroundTransparency = 1
end
local screenFlash = frame("Flash", phone, UDim2.fromOffset(PHONE_W / 2, PHONE_H / 2), UDim2.fromOffset(84, 152), COLORS.White, 1)
screenFlash.AnchorPoint = Vector2.new(0.5, 0.5)
screenFlash.ZIndex = 9
corner(screenFlash, UDim.new(0, 14))

-- Doodled "shine" dashes around the phone when it's ready
local shine = frame("Shine", stage, UDim2.fromOffset(CX, PHONE_CY), UDim2.fromOffset(0, 0))
shine.ZIndex = 5
local shineScale = Instance.new("UIScale")
shineScale.Scale = 0
shineScale.Parent = shine
for i = 0, 9 do
	local angle = i / 10 * math.pi * 2 + 0.2
	local dir = Vector2.new(math.cos(angle), math.sin(angle) * 1.25)
	boil(mark(shine, dir * 108, dir * 138, 6, COLORS.Star, 5), 6, 1.5)
end

-- A note with an arrow pointing at the phone
local note = label("Note", stage, CONFIG.PhoneNote, UDim2.fromOffset(402, 322), UDim2.fromOffset(200, 40), HAND_FONT, 32, 2.5)
note.AnchorPoint = Vector2.new(0.5, 0.5)
note.Rotation = -8
note.TextColor3 = COLORS.Note
note.ZIndex = 7
boil(note, 1.5, 1)
local arrow = frame("Arrow", stage, UDim2.new(), UDim2.fromScale(1, 1))
arrow.ZIndex = 7
do
	local tail, tip = Vector2.new(470, 338), Vector2.new(554, 368)
	local back = (tail - tip).Unit
	local function rotate(v: Vector2, deg: number): Vector2
		local a = math.rad(deg)
		return Vector2.new(v.X * math.cos(a) - v.Y * math.sin(a), v.X * math.sin(a) + v.Y * math.cos(a))
	end
	boil(mark(arrow, tail, tip, 4, COLORS.Note, 7), 1.5, 1)
	boil(mark(arrow, tip, tip + rotate(back, 32) * 18, 4, COLORS.Note, 7), 3, 1)
	boil(mark(arrow, tip, tip + rotate(back, -32) * 18, 4, COLORS.Note, 7), 3, 1)
end
local noteScale = Instance.new("UIScale")
noteScale.Scale = 0
noteScale.Parent = note
local arrowMarks = arrow:GetChildren()

-- The battery, coloured in with a marker as it charges
local battery = sketch(stage, "Battery", Vector2.new(BAR_X, BAR_Y), Vector2.new(BAR_W, BAR_H), COLORS.BoxPaper, UDim.new(0, 12), 7, 4)
local batteryScale = Instance.new("UIScale")
batteryScale.Parent = battery.root
local cap = sketch(battery.root, "Cap", Vector2.new(BAR_W + 14, BAR_H / 2), Vector2.new(14, 26), COLORS.BoxPaper, UDim.new(0, 4), 7, 4)
cap.root.ZIndex = 7
local fillArea = frame("Marker", battery.root, UDim2.fromOffset(6, 6), UDim2.fromOffset(BAR_W - 12, BAR_H - 12))
fillArea.ClipsDescendants = true
fillArea.ZIndex = 7
local markerStrokes = hatch(fillArea, BAR_W - 12, BAR_H - 12, COLORS.Marker, 0.12, 7, 9, 62, 6, 7)
for _, m in markerStrokes do
	m.obj.Visible = false
end
local percent = label("Percent", battery.root, "0%", UDim2.new(1, 34, 0.5, 0), UDim2.fromOffset(120, 44), HAND_FONT, 38, 3)
percent.AnchorPoint = Vector2.new(0, 0.5)
percent.TextXAlignment = Enum.TextXAlignment.Left
percent.ZIndex = 8

local status = label("Status", stage, CONFIG.Statuses[1].Text, UDim2.fromOffset(CX, STATUS_Y), UDim2.fromOffset(900, 44), HAND_FONT, 40, 3)
status.AnchorPoint = Vector2.new(0.5, 0.5)
status.ZIndex = 7
local statusStroke = status:FindFirstChildOfClass("UIStroke") :: UIStroke
boil(status, 0.8, 0.8)

-- Tips on a sticky note
local sticky = frame("StickyNote", stage, UDim2.fromOffset(1090, 606), UDim2.fromOffset(250, 112))
sticky.AnchorPoint = Vector2.new(0.5, 0.5)
sticky.Rotation = -4
sticky.ZIndex = 9
frame("Shadow", sticky, UDim2.fromOffset(6, 7), UDim2.fromScale(1, 1), COLORS.Ink, 0.72).ZIndex = 9
local notePaper = frame("Paper", sticky, UDim2.new(), UDim2.fromScale(1, 1), COLORS.Note)
notePaper.ZIndex = 9
stroke(notePaper, COLORS.Ink, 2, true)
local tape = frame("Tape", sticky, UDim2.new(0.5, 0, 0, 0), UDim2.fromOffset(86, 24), COLORS.White, 0.35)
tape.AnchorPoint = Vector2.new(0.5, 0.5)
tape.Rotation = 5
tape.ZIndex = 10
local tipText = label("Tip", sticky, "", UDim2.fromOffset(16, 20), UDim2.fromOffset(220, 84), HAND_FONT, 24)
tipText.TextColor3 = COLORS.Ink
tipText.TextWrapped = true
tipText.TextXAlignment = Enum.TextXAlignment.Left
tipText.TextYAlignment = Enum.TextYAlignment.Top
tipText.ZIndex = 10
boil(sticky, 0.6, 0.6)

local function showTip(text: string)
	tipText.Text = "TIP: " .. text
end
showTip(CONFIG.Tips[1] or "")

-- PLAY button, drawn on like a sticker
local playButton = Instance.new("TextButton")
playButton.Name = "Play"
playButton.AutoButtonColor = false
playButton.Text = ""
playButton.BackgroundTransparency = 1
playButton.AnchorPoint = Vector2.new(0.5, 0.5)
playButton.Position = UDim2.fromOffset(CX, BAR_Y)
playButton.Size = UDim2.fromOffset(260, 80)
playButton.ZIndex = 10
playButton.Visible = false
playButton.Parent = stage
sketch(playButton, "Body", Vector2.new(130, 40), Vector2.new(260, 80), COLORS.PlayGreen, UDim.new(0, 22), 10, 5)
local playText = label("Label", playButton, "PLAY!", UDim2.new(), UDim2.fromScale(1, 1), TITLE_FONT, 46, 4)
playText.ZIndex = 11
local playScale = Instance.new("UIScale")
playScale.Scale = 0
playScale.Parent = playButton

-- skip, scribbled in the corner for slow connections
local skipButton = Instance.new("TextButton")
skipButton.Name = "Skip"
skipButton.AutoButtonColor = false
skipButton.BackgroundTransparency = 1
skipButton.AnchorPoint = Vector2.new(0.5, 0.5)
skipButton.Position = UDim2.fromOffset(122, 664)
skipButton.Size = UDim2.fromOffset(150, 40)
skipButton.Font = HAND_FONT
skipButton.Text = "skip >>"
skipButton.TextSize = 32
skipButton.TextColor3 = COLORS.White
skipButton.ZIndex = 12
skipButton.Visible = false
skipButton.Parent = stage
stroke(skipButton, COLORS.Ink, 2.5)
boil(mark(skipButton, Vector2.new(30, 36), Vector2.new(120, 34), 3, COLORS.White, 12), 1, 0.6)

local function fit()
	local size = gui.AbsoluteSize
	if size.X > 0 and size.Y > 0 then
		fitScale.Scale = math.min(size.X / STAGE_W, size.Y / STAGE_H)
	end
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

--------------------------------------------------------------------------
-- Show it straight away, then load the game behind it
--------------------------------------------------------------------------

gui.Parent = playerGui
fit()
ReplicatedFirst:RemoveDefaultLoadingScreen()

local hiddenCoreGui: { Enum.CoreGuiType } = {}
for _, coreType in CONFIG.HideCoreGui do
	local ok, enabled = pcall(function()
		return StarterGui:GetCoreGuiEnabled(coreType)
	end)
	if ok and enabled then
		pcall(function()
			StarterGui:SetCoreGuiEnabled(coreType, false)
		end)
		table.insert(hiddenCoreGui, coreType)
	end
end

local music = makeSound(CONFIG.Music, true, 0.5)
if music then
	music:Play()
end

local ASSET_CLASSES = { "ImageLabel", "ImageButton", "Decal", "Texture", "Sound", "MeshPart", "SpecialMesh", "Animation", "ParticleEmitter", "Sky", "SurfaceAppearance" }

local function collectAssets(): { Instance }
	local list: { Instance } = {}
	for _, serviceName in CONFIG.PreloadFrom do
		local service = game:FindFirstChild(serviceName)
		if service then
			for _, item in service:GetDescendants() do
				for _, className in ASSET_CLASSES do
					if item:IsA(className) then
						table.insert(list, item)
						break
					end
				end
				if #list >= CONFIG.MaxPreload then
					return list
				end
			end
		end
	end
	return list
end

local startClock = os.clock()
local realProgress = 0

task.spawn(function()
	-- 0% to 30%: the game itself loading
	while not game:IsLoaded() do
		realProgress = 0.3 * (1 - math.exp(-(os.clock() - startClock) / 2))
		task.wait(0.05)
	end
	realProgress = 0.3

	-- 30% to 90%: images, sounds and meshes, a batch at a time
	local assets = collectAssets()
	local batchSize = 20
	for first = 1, #assets, batchSize do
		if os.clock() - startClock > CONFIG.MaxWait then
			break
		end
		local batch = table.move(assets, first, math.min(first + batchSize - 1, #assets), 1, {})
		pcall(function()
			ContentProvider:PreloadAsync(batch)
		end)
		realProgress = 0.3 + 0.6 * math.min(first + batchSize - 1, #assets) / #assets
	end
	realProgress = 0.9

	-- 90% to 100%: the player's character
	if Players.CharacterAutoLoads then
		local deadline = os.clock() + 8
		while not player.Character and os.clock() < deadline do
			task.wait(0.1)
		end
	end
	realProgress = 1
end)

--------------------------------------------------------------------------
-- Ready, play and the zoom into the phone
--------------------------------------------------------------------------

local shown = 0
local readyAt: number? = nil
local exitAt: number? = nil
local exitStartScale = 1
local hoverScale, hoverTarget = 1, 1
local statusText = status.Text
local loop: RBXScriptConnection? = nil

local function setStatus(text: string)
	if text == statusText then
		return
	end
	statusText = text
	status.Text = text
	status.TextTransparency = 1
	statusStroke.Transparency = 1
	tween(status, 0.25, { TextTransparency = 0 })
	tween(statusStroke, 0.25, { Transparency = 0 })
end

local function burst()
	for i = 1, 10 do
		local angle = (i / 10) * math.pi * 2
		local spark = sparkle(stage, Vector2.new(CX, PHONE_CY), 22, if i % 2 == 0 then COLORS.Star else COLORS.White, 9)
		local distance = 180 + (i % 3) * 30
		tween(spark, 0.7, {
			Position = UDim2.fromOffset(CX + math.cos(angle) * distance, PHONE_CY + math.sin(angle) * distance),
			Rotation = 90,
			Size = UDim2.fromOffset(6, 6),
		}).Completed:Once(function()
			spark:Destroy()
		end)
	end
end

local function onReady(t: number)
	readyAt = t
	setStatus(CONFIG.ReadyText)
	note.Text = CONFIG.ReadyNote
	screenText.Text = "100%"
	screenFill.BackgroundColor3 = COLORS.ScreenOn
	for _, m in shineMarks do
		m.BackgroundTransparency = 0
	end
	screenFlash.BackgroundTransparency = 0
	tween(screenFlash, 0.6, { BackgroundTransparency = 1 })
	burst()
	playOnce(CONFIG.ReadySound)
	if CONFIG.ShowPlayButton then
		playButton.Visible = true
	end
end

local function finish()
	if loop then
		loop:Disconnect()
	end
	-- A full-screen flash in the phone screen's colour, which then fades away.
	local flash = frame("Flash", gui, UDim2.new(), UDim2.fromScale(1, 1), COLORS.ScreenOn)
	flash.ZIndex = 50
	paper:Destroy()
	stage:Destroy()
	for _, coreType in hiddenCoreGui do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(coreType, true)
		end)
	end
	tween(flash, 0.6, { BackgroundTransparency = 1 }).Completed:Once(function()
		gui:Destroy()
	end)
end

local function startExit(t: number)
	if exitAt then
		return
	end
	exitAt = t
	exitStartScale = if phone.Visible then phoneScale.Scale else 0.12
	phone.Visible = true
	phone.AnchorPoint = Vector2.new(0.5, 0.5)
	phone.Position = UDim2.fromOffset(CX, PHONE_CY)
	phone.ZIndex = 30
	-- Clear the screen so the zoom flies into plain blue.
	screenFill.BackgroundColor3 = COLORS.ScreenOn
	tween(screenText, 0.15, { TextTransparency = 1 })
	tween(screenText:FindFirstChildOfClass("UIStroke") :: UIStroke, 0.15, { Transparency = 1 })
	tween(notch, 0.15, { BackgroundTransparency = 1 })
	for _, m in shineMarks do
		tween(m, 0.15, { BackgroundTransparency = 1 })
	end
	if music then
		tween(music, 0.8, { Volume = 0 })
	end
end

playButton.MouseEnter:Connect(function()
	hoverTarget = 1.08
end)
playButton.MouseLeave:Connect(function()
	hoverTarget = 1
end)
playButton.MouseButton1Down:Connect(function()
	hoverTarget = 0.92
end)
playButton.Activated:Connect(function()
	playOnce(CONFIG.ClickSound)
	startExit(os.clock() - startClock)
end)
skipButton.Activated:Connect(function()
	playOnce(CONFIG.ClickSound)
	startExit(os.clock() - startClock)
end)

local tipIndex = 1
local nextTipAt = CONFIG.TipTime

loop = RunService.RenderStepped:Connect(function(dt: number)
	local t = os.clock() - startClock

	-- Smooth the bar, and never let it finish before MinimumTime.
	local target = math.min(realProgress, t / CONFIG.MinimumTime)
	shown += (target - shown) * math.min(1, dt * 5)
	if target >= 1 and shown > 0.995 then
		shown = 1
	end
	local p = shown

	updateBoil(t)
	for _, l in letters do
		l.scale.Scale = easeOutBack(clamp01((t - l.delay) / 0.35))
	end
	moundScale.Scale = easeOutBack(clamp01((t - 0.3) / 0.4))

	-- Stem, leaves and phone grow with the progress.
	stem.Size = UDim2.fromOffset(10, 30 * clamp01(p / 0.22))
	for i, leaf in leaves do
		leaf.Scale = easeOutBack(clamp01((p - 0.1 - i * 0.04) / 0.12))
	end
	local noteK = easeOutBack(clamp01((p - 0.24) / 0.1))
	noteScale.Scale = noteK
	for _, m in arrowMarks do
		if m:IsA("Frame") then
			m.Visible = noteK > 0.05
		end
	end

	local exitTime = exitAt
	if exitTime then
		local k = clamp01((t - exitTime) / 0.7)
		phoneScale.Scale = exitStartScale + (40 - exitStartScale) * k ^ 3
		phone.Rotation = 0
		if k >= 1 then
			finish()
			return
		end
	else
		phone.Visible = p >= 0.22
		local ready = readyAt
		if ready then
			phoneScale.Scale = 1
			phone.Rotation = math.sin((t - ready) * 3) * 2
			phone.Position = UDim2.fromOffset(CX, PHONE_BOTTOM + math.sin((t - ready) * 2.2) * 5)
		else
			phoneScale.Scale = 0.12 + 0.88 * easeOutCubic(clamp01((p - 0.22) / 0.7))
			phone.Rotation = math.sin(t * 2.4) * 5
			screenText.Text = `{math.floor(p * 100)}%`
		end
	end

	-- Colour the battery in, one marker stroke at a time.
	local filled = p * (BAR_W - 12) + 4
	for _, m in markerStrokes do
		m.obj.Visible = m.x <= filled
	end
	percent.Text = `{math.floor(p * 100)}%`
	batteryScale.Scale = easeOutBack(clamp01((t - 0.5) / 0.45))

	if not readyAt then
		for i = #CONFIG.Statuses, 1, -1 do
			if p >= CONFIG.Statuses[i].At then
				setStatus(CONFIG.Statuses[i].Text)
				break
			end
		end
		if p >= 1 then
			onReady(t)
		end
	end

	local ready = readyAt
	if ready then
		local since = t - ready
		batteryScale.Scale = 1 - easeInBack(clamp01(since / 0.25))
		battery.root.Visible = since < 0.25
		shineScale.Scale = easeOutBack(clamp01(since / 0.4))
		hoverScale += (hoverTarget - hoverScale) * math.min(1, dt * 14)
		playScale.Scale = easeOutBack(clamp01((since - 0.25) / 0.4)) * hoverScale
		playButton.Rotation = math.sin(t * 3) * 2
		if not CONFIG.ShowPlayButton and since > 0.9 then
			startExit(t)
		end
	end

	-- Tips take turns on the sticky note.
	if #CONFIG.Tips > 1 and t >= nextTipAt then
		nextTipAt = t + CONFIG.TipTime
		tipIndex = tipIndex % #CONFIG.Tips + 1
		showTip(CONFIG.Tips[tipIndex])
		tipText.TextTransparency = 1
		tween(tipText, 0.3, { TextTransparency = 0 })
	end

	-- skip shows up if loading drags on.
	if CONFIG.SkipAfter > 0 and t >= CONFIG.SkipAfter and not skipButton.Visible and not exitAt then
		skipButton.Visible = true
	end
end)
