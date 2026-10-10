--!strict
--[[
	LoadingScreen  (LocalScript, goes in ReplicatedFirst)

	The Grow a Phone loading screen. A phone grows out of a dirt plot under a
	neon night city while the battery bar charges. At 100% the phone lights
	up and a PLAY button pops in. Pressing PLAY zooms into the phone's screen
	and drops the player into the game.

	The progress is real. It waits for the game to load, preloads the
	images, sounds and meshes in ReplicatedStorage and StarterGui, then waits
	for the player's character.

	Remove your old loading screen so the two don't overlap.
	Change the settings in CONFIG below.
]]

local CONFIG = {
	TitleTop = "GROW A",
	TitleBottom = "PHONE",

	MinimumTime = 4, -- seconds the screen stays up, even if loading is instant
	MaxWait = 25, -- stop waiting for slow assets after this many seconds
	ShowPlayButton = true, -- wait for PLAY at 100%; false goes straight in
	SkipAfter = 8, -- show a SKIP button after this many seconds (0 = never)

	Statuses = {
		{ At = 0.0, Text = "Planting your seeds..." },
		{ At = 0.25, Text = "Watering the soil..." },
		{ At = 0.5, Text = "Charging batteries..." },
		{ At = 0.75, Text = "Bringing back your phones..." },
	},
	ReadyText = "Your phones are ready!",

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

local COLORS = {
	SkyTop = Color3.fromRGB(14, 8, 36),
	SkyBottom = Color3.fromRGB(74, 32, 136),
	Horizon = Color3.fromRGB(255, 92, 196),
	Moon = Color3.fromRGB(255, 240, 206),
	BuildingBack = Color3.fromRGB(46, 24, 94),
	BuildingFront = Color3.fromRGB(27, 14, 60),
	WindowWarm = Color3.fromRGB(255, 220, 120),
	WindowCool = Color3.fromRGB(120, 236, 255),
	Neon = Color3.fromRGB(70, 230, 255),
	NeonPink = Color3.fromRGB(255, 92, 196),
	DirtTop = Color3.fromRGB(104, 66, 42),
	DirtBottom = Color3.fromRGB(56, 33, 22),
	Speck = Color3.fromRGB(40, 22, 14),
	Ink = Color3.fromRGB(22, 12, 40),
	Gold1 = Color3.fromRGB(255, 244, 128),
	Gold2 = Color3.fromRGB(255, 194, 26),
	Leaf = Color3.fromRGB(110, 218, 88),
	LeafDark = Color3.fromRGB(56, 156, 56),
	Bezel = Color3.fromRGB(250, 250, 255),
	ScreenOff1 = Color3.fromRGB(44, 46, 84),
	ScreenOff2 = Color3.fromRGB(22, 22, 48),
	ScreenOn1 = Color3.fromRGB(124, 208, 255),
	ScreenOn2 = Color3.fromRGB(42, 124, 246),
	Track = Color3.fromRGB(30, 17, 62),
	Low = Color3.fromRGB(255, 96, 96),
	Mid = Color3.fromRGB(255, 212, 64),
	High = Color3.fromRGB(112, 240, 90),
	Play1 = Color3.fromRGB(140, 255, 112),
	Play2 = Color3.fromRGB(46, 194, 70),
	Glow = Color3.fromRGB(180, 110, 255),
	White = Color3.new(1, 1, 1),
}

local FONT = Enum.Font.FredokaOne

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

-- The middle of the screen is designed at 1280 x 720 and scaled to fit.
local STAGE_W, STAGE_H = 1280, 720
local CX = STAGE_W / 2
local PHONE_BOTTOM, PHONE_W, PHONE_H = 432, 104, 176
local PHONE_CY = PHONE_BOTTOM - PHONE_H / 2
local MOUND_Y = 500
local BAR_Y, BAR_W, BAR_H = 568, 560, 46
local STATUS_Y, TIP_Y = 624, 684
local GROUND = 0.72 -- where the ground starts, as a fraction of screen height

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

type Animator = (t: number, dt: number) -> ()
local animators: { Animator } = {}
local function animate(fn: Animator)
	table.insert(animators, fn)
end

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

local function round(parent: Instance)
	corner(parent, UDim.new(0.5, 0))
end

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

local function gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

local function label(name: string, parent: Instance, text: string, pos: UDim2, size: UDim2, textSize: number, outline: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.Font = FONT
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
-- Screen and background
--------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local background = frame("Background", gui, UDim2.new(), UDim2.fromScale(1, 1), COLORS.White)
gradient(background, COLORS.SkyTop, COLORS.SkyBottom)

local horizon = frame("HorizonGlow", background, UDim2.fromScale(0, 0.42), UDim2.fromScale(1, GROUND - 0.42), COLORS.Horizon)
horizon.ZIndex = 1
local horizonFade = Instance.new("UIGradient")
horizonFade.Rotation = 90
horizonFade.Transparency = NumberSequence.new(1, 0.5)
horizonFade.Parent = horizon

local rng = Random.new(20261010)

-- Twinkling stars
for _ = 1, 70 do
	local size = rng:NextNumber(2, 4.5)
	local star = frame("Star", background, UDim2.fromScale(rng:NextNumber(), rng:NextNumber(0, 0.62)), UDim2.fromOffset(size, size), COLORS.White)
	star.AnchorPoint = Vector2.new(0.5, 0.5)
	star.ZIndex = 1
	round(star)
	local phase, speed = rng:NextNumber(0, math.pi * 2), rng:NextNumber(0.8, 2.2)
	animate(function(t)
		star.BackgroundTransparency = 0.2 + 0.65 * (0.5 + 0.5 * math.sin(t * speed + phase))
	end)
end

-- Moon with a soft glow
for i, ring in { { 200, 0.93 }, { 136, 0.86 }, { 86, 0 } } do
	local m = frame("Moon", background, UDim2.fromScale(0.83, 0.17), UDim2.fromOffset(ring[1], ring[1]), COLORS.Moon, ring[2])
	m.AnchorPoint = Vector2.new(0.5, 0.5)
	m.ZIndex = 1 + i
	round(m)
	if i == 3 then
		for _, crater in { { 0.32, 0.38, 0.22 }, { 0.62, 0.62, 0.16 }, { 0.6, 0.28, 0.1 } } do
			local c = frame("Crater", m, UDim2.fromScale(crater[1], crater[2]), UDim2.fromScale(crater[3], crater[3]), Color3.fromRGB(236, 216, 176))
			c.AnchorPoint = Vector2.new(0.5, 0.5)
			c.ZIndex = 4
			round(c)
		end
	end
end

-- Two layers of city skyline that slide past slowly. Each layer holds the
-- same row of buildings twice so the scroll can loop without a seam.
local function skyline(name: string, z: number, minH: number, maxH: number, color: Color3, speed: number, seed: number)
	local r = Random.new(seed)
	local holder = frame(name, background, UDim2.new(), UDim2.fromScale(2, GROUND))
	holder.ZIndex = z
	type Building = { x: number, w: number, h: number, edge: Color3?, windows: { { number } } }
	local buildings: { Building } = {}
	local x = 0
	while x < 1 do
		local w = r:NextNumber(0.045, 0.1)
		local h = r:NextNumber(minH, maxH)
		local windows = {}
		local cols = if w > 0.07 then 4 else 3
		local rows = math.floor((h - 0.05) / 0.035)
		for row = 0, rows - 1 do
			for col = 0, cols - 1 do
				if r:NextNumber() < 0.3 then
					table.insert(windows, { (col + 0.5) / cols, (0.04 + row * 0.035) / h, if r:NextNumber() < 0.6 then 1 else 2 })
				end
			end
		end
		local edgeRoll = r:NextNumber()
		local edge = if edgeRoll < 0.2 then COLORS.Neon elseif edgeRoll < 0.32 then COLORS.NeonPink else nil
		table.insert(buildings, { x = x, w = w, h = h, edge = edge, windows = windows })
		x += w + r:NextNumber(0.004, 0.018)
	end
	for copy = 0, 1 do
		for _, b in buildings do
			local block = frame("Building", holder, UDim2.fromScale(b.x / 2 + copy * 0.5, 1), UDim2.fromScale(b.w / 2, b.h), color)
			block.AnchorPoint = Vector2.new(0, 1)
			block.ZIndex = z
			if b.edge then
				local e = frame("NeonEdge", block, UDim2.new(), UDim2.new(1, 0, 0, 3), b.edge, 0.15)
				e.ZIndex = z
			end
			for _, wnd in b.windows do
				local light = frame("Window", block, UDim2.fromScale(wnd[1], wnd[2]), UDim2.fromScale(0.16, 0.017 / b.h), if wnd[3] == 1 then COLORS.WindowWarm else COLORS.WindowCool, 0.25)
				light.AnchorPoint = Vector2.new(0.5, 0)
				light.ZIndex = z
			end
		end
	end
	animate(function(t)
		holder.Position = UDim2.fromScale(-((t * speed) % 1), 0)
	end)
end
skyline("SkylineBack", 2, 0.22, 0.46, COLORS.BuildingBack, 0.008, 11)
skyline("SkylineFront", 3, 0.12, 0.3, COLORS.BuildingFront, 0.016, 29)

-- Dirt plot with a neon rail along the top, like the plots in the game
local ground = frame("Ground", background, UDim2.fromScale(0, GROUND), UDim2.fromScale(1, 1 - GROUND), COLORS.White)
ground.ZIndex = 4
gradient(ground, COLORS.DirtTop, COLORS.DirtBottom)
for _ = 1, 70 do
	local w = rng:NextNumber(4, 12)
	local speck = frame("Speck", ground, UDim2.fromScale(rng:NextNumber(), rng:NextNumber(0.1, 0.95)), UDim2.fromOffset(w, w * 0.6), COLORS.Speck, 0.35)
	speck.ZIndex = 4
	round(speck)
end
for _, glow in { { 30, 0.8 }, { 14, 0.6 }, { 4, 0 } } do
	local rail = frame("NeonRail", background, UDim2.new(0, 0, GROUND, 0), UDim2.new(1, 0, 0, glow[1]), COLORS.Neon, glow[2])
	rail.AnchorPoint = Vector2.new(0, 0.5)
	rail.ZIndex = 5
	if glow[1] > 4 then
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = rail
	end
end

-- Glowing specks drifting up
for i = 1, 24 do
	local size = rng:NextNumber(4, 10)
	local color = ({ COLORS.Neon, COLORS.NeonPink, COLORS.Gold1 })[i % 3 + 1]
	local dot = frame("Particle", background, UDim2.new(), UDim2.fromOffset(size, size), color)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.ZIndex = 6
	round(dot)
	local x0, duration, phase = rng:NextNumber(), rng:NextNumber(7, 13), rng:NextNumber()
	animate(function(t)
		local k = (t / duration + phase) % 1
		dot.Position = UDim2.fromScale(x0 + math.sin(t * 0.8 + phase * 6) * 0.015, 1.02 - k * 0.9)
		dot.BackgroundTransparency = 0.15 + 0.8 * k
	end)
end

--------------------------------------------------------------------------
-- Middle of the screen
--------------------------------------------------------------------------

local stage = frame("Stage", gui, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(STAGE_W, STAGE_H))
stage.AnchorPoint = Vector2.new(0.5, 0.5)
local fitScale = Instance.new("UIScale")
fitScale.Parent = stage

-- Soft glow and light rays behind the phone
local glows: { Frame } = {}
for i, g in { { 560, 0.9 }, { 400, 0.85 }, { 270, 0.78 } } do
	local glow = frame("Glow", stage, UDim2.fromOffset(CX, PHONE_CY), UDim2.fromOffset(g[1], g[1]), COLORS.Glow, g[2])
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.ZIndex = 1
	round(glow)
	glows[i] = glow
end
animate(function(t)
	for i, glow in glows do
		local base = ({ 560, 400, 270 })[i]
		local s = base * (1 + 0.04 * math.sin(t * 2 + i))
		glow.Size = UDim2.fromOffset(s, s)
	end
end)

local rays = frame("Rays", stage, UDim2.fromOffset(CX, PHONE_CY), UDim2.fromOffset(1000, 1000))
rays.AnchorPoint = Vector2.new(0.5, 0.5)
rays.ZIndex = 2
local rayBars: { Frame } = {}
for i = 0, 5 do
	local bar = frame("Ray", rays, UDim2.fromScale(0.5, 0.5), UDim2.new(1, 0, 0, 54), Color3.fromRGB(255, 246, 204), 1)
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Rotation = i * 30
	bar.ZIndex = 2
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.8),
		NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(0.75, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = bar
	table.insert(rayBars, bar)
end
animate(function(t)
	rays.Rotation = (t * 20) % 360
end)

-- Title: each letter drops in, then the word gently waves. PHONE gets a shine.
type Letter = { inner: Frame, main: TextLabel, shine: UIGradient?, index: number, delay: number }

local function titleRow(text: string, y: number, height: number, textSize: number, gold: boolean, startDelay: number): (Frame, { Letter })
	local row = frame("Title", stage, UDim2.fromOffset(0, y), UDim2.fromOffset(STAGE_W, height))
	row.ZIndex = 6
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local depth = if gold then 9 else 6
	local letters: { Letter } = {}
	for i = 1, #text do
		local ch = string.sub(text, i, i)
		local holder = frame("Letter", row, UDim2.new(), UDim2.fromOffset(0, height))
		holder.AutomaticSize = Enum.AutomaticSize.X
		holder.LayoutOrder = i
		holder.ZIndex = 6
		local inner = frame("Inner", holder, UDim2.new(), UDim2.fromScale(0, 1))
		inner.AutomaticSize = Enum.AutomaticSize.X
		inner.ZIndex = 6
		inner.Visible = false

		local function letterLabel(name: string): TextLabel
			local l = label(name, inner, ch, UDim2.new(), UDim2.fromScale(0, 1), textSize, depth)
			l.AutomaticSize = Enum.AutomaticSize.X
			l.ZIndex = 6
			return l
		end
		local shadow = letterLabel("Shadow")
		shadow.TextColor3 = COLORS.Ink
		shadow.Position = UDim2.fromOffset(0, depth)
		local main = letterLabel("Main")
		main.ZIndex = 7

		local shineGradient: UIGradient? = nil
		if gold then
			gradient(main, COLORS.Gold1, COLORS.Gold2)
			local shine = Instance.new("TextLabel")
			shine.Name = "Shine"
			shine.BackgroundTransparency = 1
			shine.Size = UDim2.fromScale(1, 1)
			shine.Font = FONT
			shine.Text = ch
			shine.TextSize = textSize
			shine.TextColor3 = COLORS.White
			shine.ZIndex = 8
			shine.Parent = main
			local g = Instance.new("UIGradient")
			g.Rotation = 20
			g.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 1),
				NumberSequenceKeypoint.new(0.5, 0.1),
				NumberSequenceKeypoint.new(0.7, 1),
				NumberSequenceKeypoint.new(1, 1),
			})
			g.Offset = Vector2.new(-2, 0)
			g.Parent = shine
			shineGradient = g
		end
		table.insert(letters, { inner = inner, main = main, shine = shineGradient, index = i, delay = startDelay + (i - 1) * 0.06 })
	end
	return row, letters
end

local _, topLetters = titleRow(CONFIG.TitleTop, 52, 72, 68, false, 0.1)
local _, bottomLetters = titleRow(CONFIG.TitleBottom, 116, 132, 130, true, 0.45)

local function animateLetters(letters: { Letter }, gold: boolean)
	animate(function(t)
		for _, l in letters do
			local k = (t - l.delay) / 0.55
			l.inner.Visible = k >= 0
			local drop = if k < 1 then -160 * (1 - easeOutBack(clamp01(k))) else 0
			local wave = math.sin(t * 2.6 - l.index * 0.55)
			l.inner.Position = UDim2.fromOffset(0, drop + wave * (if gold then 6 else 4))
			l.inner.Rotation = math.sin(t * 2.6 - l.index * 0.55 + 0.8) * 2.5
		end
		if gold then
			-- One shine band sweeps across the whole word every 3.2 seconds.
			local first, last = letters[1].main, letters[#letters].main
			local left = first.AbsolutePosition.X
			local width = (last.AbsolutePosition.X + last.AbsoluteSize.X) - left
			local p = (t % 3.2) / 1.3
			local bandX = left + (-0.3 + 1.6 * p) * width
			for _, l in letters do
				local shine = l.shine
				if shine and l.main.AbsoluteSize.X > 0 then
					local center = l.main.AbsolutePosition.X + l.main.AbsoluteSize.X / 2
					shine.Offset = Vector2.new((bandX - center) / l.main.AbsoluteSize.X, 0)
				end
			end
		end
	end)
end
animateLetters(topLetters, false)
animateLetters(bottomLetters, true)

-- Dirt mound, stem and leaves
local mound = frame("Mound", stage, UDim2.fromOffset(CX, MOUND_Y), UDim2.fromOffset(300, 58), COLORS.White)
mound.AnchorPoint = Vector2.new(0.5, 0.5)
mound.ZIndex = 4
round(mound)
gradient(mound, Color3.fromRGB(132, 86, 54), COLORS.DirtBottom)
stroke(mound, COLORS.Ink, 4, true)
for _, s in { { 0.22, 0.45, 18 }, { 0.4, 0.7, 12 }, { 0.62, 0.4, 16 }, { 0.8, 0.62, 12 }, { 0.5, 0.3, 10 } } do
	local speck = frame("Speck", mound, UDim2.fromScale(s[1], s[2]), UDim2.fromOffset(s[3], s[3] * 0.6), COLORS.Speck, 0.3)
	speck.AnchorPoint = Vector2.new(0.5, 0.5)
	speck.ZIndex = 4
	round(speck)
end
local moundScale = Instance.new("UIScale")
moundScale.Scale = 0
moundScale.Parent = mound
animate(function(t)
	moundScale.Scale = easeOutBack(clamp01((t - 0.35) / 0.45))
end)

local stem = frame("Stem", stage, UDim2.fromOffset(CX, MOUND_Y - 14), UDim2.fromOffset(12, 0), COLORS.Leaf)
stem.AnchorPoint = Vector2.new(0.5, 1)
stem.ZIndex = 3
corner(stem, UDim.new(0, 6))
stroke(stem, COLORS.Ink, 3, true)

local leaves: { UIScale } = {}
for _, leafInfo in { { CX - 26, 462, -28 }, { CX + 26, 452, 24 } } do
	local leaf = frame("Leaf", stage, UDim2.fromOffset(leafInfo[1], leafInfo[2]), UDim2.fromOffset(46, 20), COLORS.White)
	leaf.AnchorPoint = Vector2.new(0.5, 0.5)
	leaf.Rotation = leafInfo[3]
	leaf.ZIndex = 3
	round(leaf)
	gradient(leaf, COLORS.Leaf, COLORS.LeafDark)
	stroke(leaf, COLORS.Ink, 3, true)
	local s = Instance.new("UIScale")
	s.Scale = 0
	s.Parent = leaf
	table.insert(leaves, s)
end

-- The phone that grows. It looks like the phone in the game's logo.
local phone = frame("Phone", stage, UDim2.fromOffset(CX, PHONE_BOTTOM), UDim2.fromOffset(PHONE_W, PHONE_H), COLORS.Bezel)
phone.AnchorPoint = Vector2.new(0.5, 1)
phone.ZIndex = 5
phone.Visible = false
corner(phone, UDim.new(0, 24))
stroke(phone, COLORS.Ink, 5, true)
local phoneScale = Instance.new("UIScale")
phoneScale.Parent = phone

local screen = frame("Screen", phone, UDim2.fromOffset(8, 8), UDim2.new(1, -16, 1, -16), COLORS.White)
screen.ZIndex = 5
corner(screen, UDim.new(0, 16))
local screenGradient = gradient(screen, COLORS.ScreenOff1, COLORS.ScreenOff2)
local notch = frame("Notch", screen, UDim2.new(0.5, 0, 0, 6), UDim2.fromOffset(34, 8), COLORS.Ink)
notch.AnchorPoint = Vector2.new(0.5, 0)
notch.ZIndex = 5
corner(notch, UDim.new(0, 4))
local homeBar = frame("HomeBar", screen, UDim2.new(0.5, 0, 1, -7), UDim2.fromOffset(32, 4), COLORS.White, 0.4)
homeBar.AnchorPoint = Vector2.new(0.5, 1)
homeBar.ZIndex = 5
corner(homeBar, UDim.new(0, 2))
local screenText = label("Percent", screen, "0%", UDim2.new(0, 0, 0.5, -16), UDim2.new(1, 0, 0, 32), 28, 3)
screenText.ZIndex = 6
local screenFlash = frame("Flash", screen, UDim2.new(), UDim2.fromScale(1, 1), COLORS.White, 1)
screenFlash.ZIndex = 7
corner(screenFlash, UDim.new(0, 16))

-- Battery-style progress bar
local battery = frame("Battery", stage, UDim2.fromOffset(CX, BAR_Y), UDim2.fromOffset(BAR_W, BAR_H), COLORS.Track)
battery.AnchorPoint = Vector2.new(0.5, 0.5)
battery.ZIndex = 6
corner(battery, UDim.new(0, 16))
stroke(battery, COLORS.Ink, 4, true)
local batteryScale = Instance.new("UIScale")
batteryScale.Parent = battery
local cap = frame("Cap", battery, UDim2.new(1, 5, 0.5, 0), UDim2.fromOffset(12, 22), COLORS.Track)
cap.AnchorPoint = Vector2.new(0, 0.5)
cap.ZIndex = 6
corner(cap, UDim.new(0, 4))
stroke(cap, COLORS.Ink, 4, true)

local fill = frame("Fill", battery, UDim2.fromOffset(5, 5), UDim2.fromOffset(36, BAR_H - 10), COLORS.White)
fill.ZIndex = 6
fill.ClipsDescendants = true
corner(fill, UDim.new(0, 12))
local fillGradient = gradient(fill, COLORS.Low, COLORS.Low)
local stripes = frame("Stripes", fill, UDim2.new(), UDim2.fromScale(1, 1))
stripes.ZIndex = 6
for i = -1, 18 do
	local stripe = frame("Stripe", stripes, UDim2.fromOffset(i * 34, -20), UDim2.fromOffset(14, 80), COLORS.White, 0.82)
	stripe.Rotation = 25
	stripe.ZIndex = 6
end
local bolt = label("Bolt", battery, "⚡", UDim2.fromOffset(10, 0), UDim2.new(0, 34, 1, 0), 26)
bolt.ZIndex = 7
local percent = label("Percent", battery, "0%", UDim2.new(), UDim2.fromScale(1, 1), 26, 3)
percent.ZIndex = 7

local status = label("Status", stage, CONFIG.Statuses[1].Text, UDim2.fromOffset(CX, STATUS_Y), UDim2.fromOffset(1000, 36), 32, 3)
status.AnchorPoint = Vector2.new(0.5, 0.5)
status.ZIndex = 6
local statusStroke = status:FindFirstChildOfClass("UIStroke") :: UIStroke

-- Rotating tips at the bottom
local tipRow = frame("Tip", stage, UDim2.fromOffset(0, TIP_Y - 15), UDim2.fromOffset(STAGE_W, 30))
tipRow.ZIndex = 6
local tipLayout = Instance.new("UIListLayout")
tipLayout.FillDirection = Enum.FillDirection.Horizontal
tipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
tipLayout.VerticalAlignment = Enum.VerticalAlignment.Center
tipLayout.Padding = UDim.new(0, 10)
tipLayout.SortOrder = Enum.SortOrder.LayoutOrder
tipLayout.Parent = tipRow
local tipPill = frame("Pill", tipRow, UDim2.new(), UDim2.fromOffset(52, 26), COLORS.Gold2)
tipPill.ZIndex = 6
corner(tipPill, UDim.new(0, 8))
stroke(tipPill, COLORS.Ink, 3, true)
local tipPillText = label("Label", tipPill, "TIP", UDim2.new(), UDim2.fromScale(1, 1), 20)
tipPillText.TextColor3 = COLORS.Ink
tipPillText.ZIndex = 6
local tipText = label("Text", tipRow, CONFIG.Tips[1] or "", UDim2.new(), UDim2.fromOffset(0, 30), 22, 2.5)
tipText.AutomaticSize = Enum.AutomaticSize.X
tipText.ZIndex = 6
tipText.LayoutOrder = 2
local tipStroke = tipText:FindFirstChildOfClass("UIStroke") :: UIStroke

-- PLAY button, shown at 100%
local playButton = Instance.new("TextButton")
playButton.Name = "Play"
playButton.AutoButtonColor = false
playButton.Text = ""
playButton.AnchorPoint = Vector2.new(0.5, 0.5)
playButton.Position = UDim2.fromOffset(CX, BAR_Y)
playButton.Size = UDim2.fromOffset(300, 78)
playButton.BackgroundColor3 = COLORS.White
playButton.ZIndex = 8
playButton.Visible = false
playButton.Parent = stage
corner(playButton, UDim.new(0, 22))
gradient(playButton, COLORS.Play1, COLORS.Play2)
stroke(playButton, COLORS.Ink, 5, true)
local playShine = frame("Shine", playButton, UDim2.fromOffset(5, 5), UDim2.new(1, -10, 1, -10))
playShine.ZIndex = 8
corner(playShine, UDim.new(0, 18))
local shineStroke = stroke(playShine, COLORS.White, 2, true)
shineStroke.Transparency = 0.45
local playText = label("Label", playButton, "PLAY", UDim2.new(), UDim2.fromScale(1, 1), 50, 5)
playText.ZIndex = 9
local playScale = Instance.new("UIScale")
playScale.Scale = 0
playScale.Parent = playButton

-- SKIP button in the corner for slow connections
local skipButton = Instance.new("TextButton")
skipButton.Name = "Skip"
skipButton.AutoButtonColor = false
skipButton.AnchorPoint = Vector2.new(1, 1)
skipButton.Position = UDim2.new(1, -24, 1, -24)
skipButton.Size = UDim2.fromOffset(110, 42)
skipButton.BackgroundColor3 = COLORS.Ink
skipButton.BackgroundTransparency = 1
skipButton.Font = FONT
skipButton.Text = "SKIP  ›"
skipButton.TextSize = 22
skipButton.TextColor3 = COLORS.White
skipButton.TextTransparency = 1
skipButton.ZIndex = 20
skipButton.Visible = false
skipButton.Parent = gui
corner(skipButton, UDim.new(0, 21))

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
	for i = 1, 12 do
		local angle = (i / 12) * math.pi * 2
		local spark = frame("Spark", stage, UDim2.fromOffset(CX, PHONE_CY), UDim2.fromOffset(12, 12), if i % 2 == 0 then COLORS.Gold1 else COLORS.White)
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		spark.ZIndex = 7
		round(spark)
		local distance = 170 + (i % 3) * 30
		tween(spark, 0.7, {
			Position = UDim2.fromOffset(CX + math.cos(angle) * distance, PHONE_CY + math.sin(angle) * distance),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(4, 4),
		}).Completed:Once(function()
			spark:Destroy()
		end)
	end
end

local function onReady(t: number)
	readyAt = t
	setStatus(CONFIG.ReadyText)
	screenText.Text = "READY"
	screenGradient.Color = ColorSequence.new(COLORS.ScreenOn1, COLORS.ScreenOn2)
	screenFlash.BackgroundTransparency = 0
	tween(screenFlash, 0.6, { BackgroundTransparency = 1 })
	for _, bar in rayBars do
		tween(bar, 0.6, { BackgroundTransparency = 0 })
	end
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
	local flash = frame("Flash", gui, UDim2.new(), UDim2.fromScale(1, 1), COLORS.ScreenOn2:Lerp(COLORS.ScreenOn1, 0.5))
	flash.ZIndex = 50
	background:Destroy()
	stage:Destroy()
	skipButton:Destroy()
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
	-- Clear the screen so the zoom flies into plain glowing glass.
	tween(screenText, 0.15, { TextTransparency = 1 })
	tween(screenText:FindFirstChildOfClass("UIStroke") :: UIStroke, 0.15, { Transparency = 1 })
	tween(notch, 0.15, { BackgroundTransparency = 1 })
	tween(homeBar, 0.15, { BackgroundTransparency = 1 })
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

	for _, fn in animators do
		fn(t, dt)
	end

	-- Stem, leaves and phone grow with the progress.
	stem.Size = UDim2.fromOffset(12, 60 * clamp01(p / 0.22))
	for i, leaf in leaves do
		leaf.Scale = easeOutBack(clamp01((p - 0.1 - i * 0.04) / 0.12))
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
		local growth = clamp01((p - 0.22) / 0.7)
		phone.Visible = p >= 0.22
		local ready = readyAt
		if ready then
			phoneScale.Scale = 1
			phone.Rotation = 0
			phone.Position = UDim2.fromOffset(CX, PHONE_BOTTOM + math.sin((t - ready) * 2.2) * 5)
		else
			phoneScale.Scale = 0.12 + 0.88 * easeOutCubic(growth)
			phone.Rotation = math.sin(t * 2.4) * 5
			screenText.Text = `{math.floor(p * 100)}%`
		end
	end

	-- Battery fill: red, then yellow, then green as it charges.
	local color = if p < 0.5 then COLORS.Low:Lerp(COLORS.Mid, p / 0.5) else COLORS.Mid:Lerp(COLORS.High, (p - 0.5) / 0.5)
	fillGradient.Color = ColorSequence.new(color:Lerp(COLORS.White, 0.25), color)
	fill.Size = UDim2.fromOffset(math.max(BAR_H - 10, p * (BAR_W - 10)), BAR_H - 10)
	stripes.Position = UDim2.fromOffset(-((t * 40) % 34), 0)
	percent.Text = `{math.floor(p * 100)}%`
	batteryScale.Scale = easeOutBack(clamp01((t - 0.5) / 0.5))

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
		battery.Visible = since < 0.25
		hoverScale += (hoverTarget - hoverScale) * math.min(1, dt * 14)
		playScale.Scale = easeOutBack(clamp01((since - 0.25) / 0.4)) * hoverScale * (1 + 0.035 * math.sin(t * 5))
		if not CONFIG.ShowPlayButton and since > 0.9 then
			startExit(t)
		end
	end

	-- Tips take turns.
	if #CONFIG.Tips > 1 and t >= nextTipAt then
		nextTipAt = t + CONFIG.TipTime
		tipIndex = tipIndex % #CONFIG.Tips + 1
		tipText.Text = CONFIG.Tips[tipIndex]
		tipText.TextTransparency = 1
		tipStroke.Transparency = 1
		tween(tipText, 0.3, { TextTransparency = 0 })
		tween(tipStroke, 0.3, { Transparency = 0 })
	end

	-- SKIP shows up if loading drags on.
	if CONFIG.SkipAfter > 0 and t >= CONFIG.SkipAfter and not skipButton.Visible and not exitAt then
		skipButton.Visible = true
		tween(skipButton, 0.4, { BackgroundTransparency = 0.35, TextTransparency = 0 })
	end
end)
