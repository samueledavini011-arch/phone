--!strict
--[[
	ShopClient  (LocalScript, goes in StarterPlayer > StarterPlayerScripts)

	Builds the gamepass shop from the video in code, runs its effects,
	and opens the Roblox purchase prompt when a pass is clicked.

	Effects, named like the layer tags in the video:
	  _spin   rotating light rays behind the cards
	  _gleam  white shine that sweeps across the titles
	  _jelly  wobbling S H O P letters
	  _smooth buttons grow on hover and squish on click
	  _lean   card icons tilt while hovered
	  _turn   the close button spins while hovered
	  _fall   background pattern that keeps falling

	Other scripts can open or close the shop with:
	  player.PlayerGui.GamepassShop:SetAttribute("Open", true)
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("ShopConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local THEME = Config.Theme
local FX = Config.Effects
local FONT = Config.Font
local WHITE = Color3.new(1, 1, 1)

-- Layout of the original design in design pixels. A UIScale fits it to any screen.
local PANEL_W, PANEL_H = 1010, 600
local TITLE_H = 104
local PAD = 26
local CARD_W, CARD_H, CARD_GAP = 300, 202, 29
local VIP_Y, VIP_H = 160, 182
local VIP_W = PANEL_W - PAD * 2
local CARDS_Y = VIP_Y + VIP_H + 28

type Pass = typeof(Config.Passes[1])
type Animator = (t: number) -> ()

--------------------------------------------------------------------------
-- Small helpers for building UI
--------------------------------------------------------------------------

local animators: { Animator } = {}

local function animate(fn: Animator)
	table.insert(animators, fn)
end

local function corner(parent: Instance, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.Parent = parent
	return s
end

-- Outline around a box (instead of around its text).
local function border(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	local s = stroke(parent, color, thickness, transparency)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return s
end

local function vertical(parent: Instance, top: Color3, bottom: Color3): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	g.Parent = parent
	return g
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

-- White pixel-font text with a black outline, scaled to fill its box.
local function label(name: string, parent: Instance, text: string, pos: UDim2, size: UDim2, outline: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.Font = FONT
	l.Text = text
	l.TextColor3 = WHITE
	l.TextScaled = true
	l.Parent = parent
	if outline and outline > 0 then
		local s = stroke(l, THEME.TextOutline, outline)
		s.LineJoinMode = Enum.LineJoinMode.Miter
	end
	return l
end

local function isImage(source: string): boolean
	return string.find(source, "rbxasset", 1, true) ~= nil or string.find(source, "http", 1, true) ~= nil
end

-- An icon is either an emoji or an uploaded image.
local function icon(name: string, parent: Instance, source: string, center: Vector2, size: number, transparency: number?): GuiObject
	local obj: GuiObject
	if isImage(source) then
		local img = Instance.new("ImageLabel")
		img.Image = source
		img.ScaleType = Enum.ScaleType.Fit
		img.ImageTransparency = transparency or 0
		obj = img
	else
		local l = Instance.new("TextLabel")
		l.Font = FONT
		l.Text = source
		l.TextScaled = true
		l.TextColor3 = WHITE
		l.TextTransparency = transparency or 0
		obj = l
	end
	obj.Name = name
	obj.BackgroundTransparency = 1
	obj.AnchorPoint = Vector2.new(0.5, 0.5)
	obj.Position = UDim2.fromOffset(center.X, center.Y)
	obj.Size = UDim2.fromOffset(size, size)
	obj.Parent = parent
	return obj
end

-- A rounded box that clips everything inside it (patterns, rays, particles).
-- Also returns the gradient of its fill so callers can recolour it.
local function clipBox(parent: Instance, size: UDim2, radius: number, top: Color3, bottom: Color3): (GuiObject, UIGradient)
	local box: GuiObject = if Config.UseCanvasGroups then Instance.new("CanvasGroup") else Instance.new("Frame")
	box.Name = "Background"
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.ClipsDescendants = true
	box.Size = size
	corner(box, radius)
	box.Parent = parent

	local fill = frame("Fill", box, UDim2.new(), UDim2.fromScale(1, 1), WHITE)
	corner(fill, radius)
	return box, vertical(fill, top, bottom)
end

local function tween(obj: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local t = TweenService:Create(
		obj,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Back, direction or Enum.EasingDirection.Out),
		goal
	)
	t:Play()
	return t
end

local function priceText(price: number): string
	return string.format('%d<font color="#%s">R</font>', price, THEME.RobuxColor:ToHex())
end

--------------------------------------------------------------------------
-- Background patterns
--------------------------------------------------------------------------

-- Diagonal criss-cross lines. Lines sit on x - y = k*spacing and x + y = k*spacing.
local function addLattice(parent: Instance, w: number, h: number, spacing: number, thickness: number, color: Color3, transparency: number, z: number)
	local holder = frame("Lattice", parent, UDim2.new(), UDim2.fromScale(1, 1))
	holder.ZIndex = z
	local length = (h + thickness * 4) * math.sqrt(2)
	local function line(x: number, rotation: number)
		local l = frame("Line", holder, UDim2.fromOffset(x, h / 2), UDim2.fromOffset(length, thickness), color, transparency)
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Rotation = rotation
		l.ZIndex = z
	end
	for k = math.floor(-h / spacing) - 1, math.ceil(w / spacing) + 1 do
		line(k * spacing + h / 2, 45)
	end
	for k = -1, math.ceil((w + h) / spacing) + 1 do
		line(k * spacing - h / 2, -45)
	end
end

-- Round dots in the middle of each diamond of the lattice above.
local function addDots(parent: Instance, w: number, h: number, spacing: number, size: number, color: Color3, transparency: number, z: number)
	local holder = frame("Dots", parent, UDim2.new(), UDim2.fromScale(1, 1))
	holder.ZIndex = z
	local half = spacing / 2
	for i = 0, math.ceil(w / half) do
		for j = 0, math.ceil(h / half) do
			if (i + j) % 2 == 1 then
				local d = frame("Dot", holder, UDim2.fromOffset(i * half, j * half), UDim2.fromOffset(size, size), color, transparency)
				d.AnchorPoint = Vector2.new(0.5, 0.5)
				d.ZIndex = z
				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(0.5, 0)
				c.Parent = d
			end
		end
	end
end

-- _spin: light rays rotating around a point.
local function addRays(parent: Instance, center: Vector2, diameter: number, z: number)
	if not FX.Spin.Enabled then
		return
	end
	local rays = frame("Rays_spin", parent, UDim2.fromOffset(center.X, center.Y), UDim2.fromOffset(diameter, diameter))
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.ZIndex = z
	local fade = FX.Spin.Transparency
	local count = FX.Spin.Rays
	for i = 0, count - 1 do
		-- Each bar crosses the centre, so it draws two opposite rays.
		local ray = frame("Ray", rays, UDim2.fromScale(0.5, 0.5), UDim2.new(1, 0, 0, FX.Spin.RayWidth), WHITE)
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Rotation = i * 180 / count
		ray.ZIndex = z
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.12, fade),
			NumberSequenceKeypoint.new(0.42, fade),
			NumberSequenceKeypoint.new(0.5, 1),
			NumberSequenceKeypoint.new(0.58, fade),
			NumberSequenceKeypoint.new(0.88, fade),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = ray
	end
	local speed = FX.Spin.Speed
	animate(function(t)
		rays.Rotation = (t * speed) % 360
	end)
end

-- _fall: small copies of the card icon drifting down forever.
local function addFallingIcons(parent: Instance, w: number, h: number, source: string, z: number)
	local gapX, gapY, size = 74, 64, 40
	local period = gapY * 2 -- pattern repeats every two rows
	local layer = frame("Particles_fall", parent, UDim2.new(), UDim2.fromOffset(w, h + period))
	layer.ZIndex = z
	for row = 0, math.ceil((h + period) / gapY) + 1 do
		local shift = if row % 2 == 0 then 0 else gapX / 2
		for col = -1, math.ceil(w / gapX) do
			local p = icon("Particle", layer, source, Vector2.new(col * gapX + shift, (row - 1) * gapY), size, FX.Fall.Transparency)
			p.Rotation = ((col * 37 + (row % 2) * 71) % 60) - 30
			p.ZIndex = z
		end
	end
	if FX.Fall.Enabled then
		local speed = FX.Fall.Speed
		animate(function(t)
			layer.Position = UDim2.fromOffset(0, (t * speed) % period - period)
		end)
	end
end

-- _fall: the halftone grid of rounded squares on the VIP banner.
local function addFallingTiles(parent: Instance, w: number, h: number, z: number)
	local gap, size = 30, 16
	local layer = frame("Halftone_fall", parent, UDim2.new(), UDim2.fromOffset(w, h + gap))
	layer.ZIndex = z
	for row = 0, math.ceil(h / gap) + 1 do
		for col = 0, math.ceil(w / gap) do
			local tile = frame("Tile", layer, UDim2.fromOffset(col * gap + gap / 2, (row - 1) * gap + gap / 2), UDim2.fromOffset(size, size), THEME.VipTiles, 0.45)
			tile.AnchorPoint = Vector2.new(0.5, 0.5)
			tile.ZIndex = z
			corner(tile, 4)
		end
	end
	if FX.Fall.Enabled then
		local speed = FX.Fall.Speed * 0.6
		animate(function(t)
			layer.Position = UDim2.fromOffset(0, (t * speed) % gap - gap)
		end)
	end
end

--------------------------------------------------------------------------
-- Text effects
--------------------------------------------------------------------------

-- _gleam: a white copy of the text on top, revealed by a moving gradient band.
local function addGleam(base: TextLabel, delay: number)
	if not FX.Gleam.Enabled then
		return
	end
	local shine = Instance.new("TextLabel")
	shine.Name = "Gleam"
	shine.BackgroundTransparency = 1
	shine.Size = UDim2.fromScale(1, 1)
	shine.Font = base.Font
	shine.Text = base.Text
	shine.RichText = base.RichText
	shine.TextScaled = base.TextScaled
	shine.TextSize = base.TextSize
	shine.TextXAlignment = base.TextXAlignment
	shine.TextYAlignment = base.TextYAlignment
	shine.TextColor3 = WHITE
	shine.ZIndex = base.ZIndex
	shine.Parent = base

	local width = math.clamp(FX.Gleam.WaveWidth, 0.05, 0.95)
	local g = Instance.new("UIGradient")
	g.Rotation = FX.Gleam.Angle
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5 - width / 2, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.5 + width / 2, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Offset = Vector2.new(-1, 0)
	g.Parent = shine

	local sweep = math.max(FX.Gleam.SweepTime, 0.1)
	local cycle = sweep + math.max(FX.Gleam.Pause, 0)
	animate(function(t)
		local progress = math.min(((t + delay) % cycle) / sweep, 1)
		g.Offset = Vector2.new(-1 + 2 * progress, 0)
	end)
end

-- _jelly: each letter is its own label that wobbles and squishes.
local function addJellyWord(parent: Instance, word: string, x: number, y: number, letterW: number, letterH: number, pitch: number)
	local tilts = { -6, 5, -5, 4 }
	local letters: { TextLabel } = {}
	local scales: { UIScale } = {}
	for i = 1, #word do
		local ch = string.sub(word, i, i)
		local l = label(ch .. "_jelly", parent, ch, UDim2.fromOffset(x + (i - 1) * pitch, y), UDim2.fromOffset(letterW, letterH), 6)
		l.ZIndex = 6
		l.Rotation = tilts[(i - 1) % #tilts + 1]
		local s = Instance.new("UIScale")
		s.Parent = l
		table.insert(letters, l)
		table.insert(scales, s)
	end
	if not FX.Jelly.Enabled then
		return
	end
	local wobble, speed, squash = FX.Jelly.Wobble, FX.Jelly.Speed, FX.Jelly.Squash
	animate(function(t)
		for i, l in letters do
			local phase = 2 * math.pi * speed * t + i * 1.3
			l.Rotation = tilts[(i - 1) % #tilts + 1] + wobble * math.sin(phase)
			scales[i].Scale = 1 + squash * math.sin(phase * 2)
		end
	end)
end

--------------------------------------------------------------------------
-- Button effects
--------------------------------------------------------------------------

local soundCache: { [string]: Sound } = {}

local function playSound(id: string)
	if id == "" then
		return
	end
	local sound: Sound? = soundCache[id]
	if not sound then
		local created = Instance.new("Sound")
		created.SoundId = id
		created.Parent = SoundService
		soundCache[id] = created
		sound = created
	end
	SoundService:PlayLocalSound(sound :: Sound)
end

-- _smooth: grow on hover, squish on press. onHover lets _lean and _turn hook in.
local function addSmooth(button: GuiButton, onHover: ((hovered: boolean) -> ())?)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	local hovered, pressed = false, false

	local function refresh()
		local goal = if pressed then FX.Smooth.PressScale elseif hovered then FX.Smooth.HoverScale else 1
		tween(scale, 0.18, { Scale = goal })
	end
	local function setHover(value: boolean)
		if hovered == value then
			return
		end
		hovered = value
		if value then
			playSound(FX.Smooth.HoverSound)
		end
		if onHover then
			onHover(value)
		end
		refresh()
	end

	button.MouseEnter:Connect(function()
		setHover(true)
	end)
	button.MouseLeave:Connect(function()
		pressed = false
		setHover(false)
	end)
	button.MouseButton1Down:Connect(function()
		pressed = true
		refresh()
	end)
	button.MouseButton1Up:Connect(function()
		pressed = false
		refresh()
	end)
	button.Activated:Connect(function(input: InputObject)
		playSound(FX.Smooth.ClickSound)
		pressed = false
		-- Touch screens never send MouseLeave, so drop the hover state here.
		if input.UserInputType == Enum.UserInputType.Touch then
			setHover(false)
		end
		refresh()
	end)
end

-- _lean: tilt an icon while its button is hovered.
local function leanOnHover(target: GuiObject): (boolean) -> ()
	return function(hovered: boolean)
		tween(target, 0.25, { Rotation = if hovered then FX.Lean.Angle else 0 })
	end
end

--------------------------------------------------------------------------
-- Gamepasses
--------------------------------------------------------------------------

local function ownsPass(key: string): boolean
	return player:GetAttribute("Owns_" .. key) == true
end

local function watchOwnership(key: string, onChange: (owned: boolean) -> ())
	player:GetAttributeChangedSignal("Owns_" .. key):Connect(function()
		onChange(ownsPass(key))
	end)
	onChange(ownsPass(key))
end

local function buy(key: string, gamepassId: number)
	if ownsPass(key) then
		return
	end
	if gamepassId == 0 then
		warn(`[Shop] "{key}" has no GamepassId yet. Paste your gamepass ID into ShopConfig.`)
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, gamepassId)
end

-- Show the real Robux price once Roblox tells us what it is.
local function loadPrice(gamepassId: number, onPrice: (price: number) -> ())
	if gamepassId == 0 then
		return
	end
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(gamepassId, Enum.InfoType.GamePass)
		end)
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			onPrice(info.PriceInRobux)
		end
	end)
end

--------------------------------------------------------------------------
-- Screen, panel and title bar
--------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "GamepassShop"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 10
gui:SetAttribute("Open", false)
gui.Parent = playerGui

-- Root holds the scale that fits the design to the screen.
local root = frame("Root", gui, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(PANEL_W, PANEL_H))
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Visible = false
local fitScale = Instance.new("UIScale")
fitScale.Parent = root

-- Panel holds the pop-in scale used when opening and closing.
local panel = frame("Panel", root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1), THEME.Panel, THEME.PanelTransparency)
panel.AnchorPoint = Vector2.new(0.5, 0.5) -- so it pops open from the middle
corner(panel, 26)
border(panel, THEME.Outline, 7)
local popScale = Instance.new("UIScale")
popScale.Parent = panel

-- Rainbow title bar. Its bottom corners are hidden under a strip of panel colour.
local titleBar, rainbow = clipBox(panel, UDim2.fromOffset(PANEL_W, TITLE_H + 30), 26, WHITE, WHITE)
titleBar.Name = "TitleBar"
titleBar.ZIndex = 1
rainbow.Color = THEME.Rainbow
rainbow.Rotation = 0
addLattice(titleBar, PANEL_W, TITLE_H + 30, 46, 3, Color3.new(0, 0, 0), 0.88, 2)
addDots(titleBar, PANEL_W, TITLE_H + 30, 46, 9, WHITE, 0.62, 3)

local strip = frame("TitleEdge", panel, UDim2.fromOffset(0, TITLE_H), UDim2.fromOffset(PANEL_W, 36), THEME.Panel, THEME.PanelTransparency)
strip.ZIndex = 2
local divider = frame("Divider", panel, UDim2.fromOffset(0, TITLE_H - 2), UDim2.fromOffset(PANEL_W, 5), THEME.Outline)
divider.ZIndex = 3

local cart = icon("ShoppingCart", panel, Config.TitleIcon, Vector2.new(68, TITLE_H / 2 + 2), 92)
cart.ZIndex = 6
cart.Rotation = -8

addJellyWord(panel, Config.Title, 150, 11, 90, 84, 110)

-- Close button: _smooth + _turn + close.
local closeButton = Instance.new("TextButton")
closeButton.Name = "XButton_smooth_turn_close"
closeButton.AutoButtonColor = false
closeButton.Text = ""
closeButton.AnchorPoint = Vector2.new(0.5, 0.5)
closeButton.Position = UDim2.fromOffset(PANEL_W - 16 - 44, 8 + 44)
closeButton.Size = UDim2.fromOffset(88, 88)
closeButton.BackgroundColor3 = WHITE
closeButton.ZIndex = 6
closeButton.Parent = panel
corner(closeButton, 14)
vertical(closeButton, THEME.CloseTop, THEME.CloseBottom)
border(closeButton, THEME.Outline, 5)
local closeShine = frame("Shine", closeButton, UDim2.fromOffset(4, 4), UDim2.new(1, -8, 1, -8))
closeShine.ZIndex = 6
corner(closeShine, 11)
border(closeShine, WHITE, 2, 0.55)
local closeX = label("X", closeButton, "X", UDim2.fromOffset(14, 12), UDim2.new(1, -28, 1, -26), 5)
closeX.ZIndex = 7

local sectionLabel = label("Section", panel, Config.SectionLabel, UDim2.fromOffset(PANEL_W / 2 - 200, 121), UDim2.fromOffset(400, 27), 3)
sectionLabel.ZIndex = 6

--------------------------------------------------------------------------
-- VIP banner
--------------------------------------------------------------------------

local function buildFeatured()
	local pass = Config.Featured
	local card = frame("Featured_" .. pass.Key, panel, UDim2.fromOffset(PAD, VIP_Y), UDim2.fromOffset(VIP_W, VIP_H))
	card.ZIndex = 4

	local bg = clipBox(card, UDim2.fromScale(1, 1), 18, THEME.VipTop, THEME.VipBottom)
	bg.ZIndex = 4
	addFallingTiles(bg, VIP_W, VIP_H, 2)
	addRays(bg, Vector2.new(118, 70), 760, 3)
	-- Big faded crowns on the right, like the outlines in the video.
	local marks = { { 690, 70, 170, -14 }, { 845, 120, 150, 12 }, { 560, 150, 110, 8 } }
	for _, m in marks do
		local mark = icon("Watermark", bg, pass.Icon, Vector2.new(m[1], m[2]), m[3], 0.82)
		mark.Rotation = m[4]
		mark.ZIndex = 4
	end

	local edge = frame("Border", card, UDim2.new(), UDim2.fromScale(1, 1))
	edge.ZIndex = 5
	corner(edge, 18)
	border(edge, THEME.Outline, 5)
	local inner = frame("Shine", card, UDim2.fromOffset(4, 4), UDim2.new(1, -8, 1, -8))
	inner.ZIndex = 5
	corner(inner, 14)
	border(inner, WHITE, 2, 0.5)

	local crown = icon("Crown_keep", card, pass.Icon, Vector2.new(118, 52), 96)
	crown.ZIndex = 6

	local title = label("Title_gleam", card, pass.Title, UDim2.fromOffset(18, 98), UDim2.fromOffset(198, 58), 5)
	title.ZIndex = 6
	local gold = Instance.new("UIGradient")
	gold.Color = THEME.VipText
	gold.Rotation = 90
	gold.Parent = title
	addGleam(title, 0)

	local line1 = label("Line1", card, pass.Line1, UDim2.fromOffset(228, 18), UDim2.fromOffset(560, 50), 5)
	line1.TextXAlignment = Enum.TextXAlignment.Left
	line1.ZIndex = 6
	local line2 = label("Line2", card, pass.Line2, UDim2.fromOffset(224, 74), UDim2.fromOffset(400, 32), 4)
	line2.TextXAlignment = Enum.TextXAlignment.Left
	line2.ZIndex = 6

	local price = label("Price", card, priceText(pass.Price), UDim2.fromOffset(VIP_W - 312, 100), UDim2.fromOffset(110, 34), 3)
	price.AnchorPoint = Vector2.new(0.5, 0.5)
	price.RichText = true
	price.Rotation = -16
	price.ZIndex = 7

	-- BUY button: _smooth.
	local buyButton = Instance.new("TextButton")
	buyButton.Name = "Buy_smooth"
	buyButton.AutoButtonColor = false
	buyButton.Text = ""
	buyButton.AnchorPoint = Vector2.new(0.5, 0.5)
	buyButton.Position = UDim2.fromOffset(VIP_W - 12 - 148, VIP_H - 12 - 33)
	buyButton.Size = UDim2.fromOffset(296, 66)
	buyButton.BackgroundColor3 = WHITE
	buyButton.ZIndex = 6
	buyButton.Parent = card
	corner(buyButton, 14)
	local buyFill = vertical(buyButton, THEME.BuyTop, THEME.BuyBottom)
	border(buyButton, THEME.Outline, 5)
	local buyShine = frame("Shine", buyButton, UDim2.fromOffset(4, 4), UDim2.new(1, -8, 1, -8))
	buyShine.ZIndex = 6
	corner(buyShine, 11)
	border(buyShine, WHITE, 2, 0.5)
	local buyText = label("Label", buyButton, Config.BuyText, UDim2.fromOffset(20, 9), UDim2.new(1, -40, 1, -18), 5)
	buyText.ZIndex = 7

	addSmooth(buyButton)
	buyButton.Activated:Connect(function()
		buy(pass.Key, pass.GamepassId)
	end)

	loadPrice(pass.GamepassId, function(robux)
		if not ownsPass(pass.Key) then
			price.Text = priceText(robux)
		end
	end)
	watchOwnership(pass.Key, function(owned)
		buyText.Text = if owned then Config.OwnedText else Config.BuyText
		buyFill.Color = if owned
			then ColorSequence.new(THEME.OwnedTop, THEME.OwnedBottom)
			else ColorSequence.new(THEME.BuyTop, THEME.BuyBottom)
		price.Visible = not owned
	end)
end

--------------------------------------------------------------------------
-- Gamepass cards
--------------------------------------------------------------------------

local function buildCard(pass: Pass, index: number)
	local x = PAD + (index - 1) * (CARD_W + CARD_GAP)

	-- The whole card is the button: _smooth, with _lean on the icon.
	local card = Instance.new("TextButton")
	card.Name = "Card_" .. pass.Key
	card.AutoButtonColor = false
	card.Text = ""
	card.BackgroundTransparency = 1
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromOffset(x + CARD_W / 2, CARDS_Y + CARD_H / 2)
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.ZIndex = 4
	card.Parent = panel

	local bg = clipBox(card, UDim2.fromScale(1, 1), 16, pass.Top, pass.Bottom)
	bg.ZIndex = 4
	addLattice(bg, CARD_W, CARD_H, 46, 2, pass.Lines, 0.55, 2)
	addRays(bg, Vector2.new(CARD_W / 2, 106), 440, 3)
	addFallingIcons(bg, CARD_W, CARD_H, pass.Icon, 4)

	local edge = frame("Border", card, UDim2.new(), UDim2.fromScale(1, 1))
	edge.ZIndex = 5
	corner(edge, 16)
	border(edge, THEME.Outline, 5)
	local inner = frame("Shine", card, UDim2.fromOffset(4, 4), UDim2.new(1, -8, 1, -8))
	inner.ZIndex = 5
	corner(inner, 12)
	border(inner, WHITE, 2, 0.5)

	local title = label("Title_gleam", card, pass.Title, UDim2.fromOffset(14, 8), UDim2.new(1, -28, 0, 40), 4)
	title.ZIndex = 6
	addGleam(title, index * 0.25)

	local art = icon("Icon_lean", card, pass.Icon, Vector2.new(CARD_W / 2, 106), 110)
	art.ZIndex = 6

	local prices: { TextLabel } = {}
	for _, cx in { 46, CARD_W - 46 } do
		local p = label("Price", card, priceText(pass.Price), UDim2.fromOffset(cx, 102), UDim2.fromOffset(92, 30), 3)
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.RichText = true
		p.Rotation = 35
		p.ZIndex = 7
		table.insert(prices, p)
	end

	local perk = label("Perk", card, pass.Perk, UDim2.fromOffset(10, 166), UDim2.new(1, -20, 0, 26), 3)
	perk.ZIndex = 6

	addSmooth(card, leanOnHover(art))
	card.Activated:Connect(function()
		buy(pass.Key, pass.GamepassId)
	end)

	local currentPrice = pass.Price
	local function showPrices()
		local owned = ownsPass(pass.Key)
		for _, p in prices do
			p.Text = if owned then Config.OwnedText else priceText(currentPrice)
		end
	end
	loadPrice(pass.GamepassId, function(robux)
		currentPrice = robux
		showPrices()
	end)
	watchOwnership(pass.Key, function()
		showPrices()
	end)
end

buildFeatured()
for i, pass in Config.Passes do
	if i > 3 then
		warn("[Shop] Only the first three passes fit under the banner.")
		break
	end
	buildCard(pass, i)
end

--------------------------------------------------------------------------
-- Opening, closing and fitting to the screen
--------------------------------------------------------------------------

local function fit()
	local size = gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	fitScale.Scale = math.min(size.X * 0.92 / PANEL_W, size.Y * 0.86 / PANEL_H)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
fit()

local isOpen = false
local closeTween: Tween? = nil

local function setOpen(open: boolean)
	if open == isOpen then
		return
	end
	isOpen = open
	gui:SetAttribute("Open", open)
	if closeTween then
		closeTween:Cancel()
		closeTween = nil
	end
	if open then
		root.Visible = true
		popScale.Scale = 0.6
		tween(popScale, 0.35, { Scale = 1 })
	else
		local t = tween(popScale, 0.18, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		closeTween = t
		t.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and not isOpen then
				root.Visible = false
			end
		end)
	end
end

gui:GetAttributeChangedSignal("Open"):Connect(function()
	setOpen(gui:GetAttribute("Open") == true)
end)

addSmooth(closeButton, function(hovered)
	tween(closeButton, 0.3, { Rotation = if hovered then FX.Turn.Angle else 0 })
end)
closeButton.Activated:Connect(function()
	setOpen(false)
end)

-- Small rainbow SHOP button on the left edge that opens and closes the shop.
if Config.ShowOpenButton then
	local openButton = Instance.new("TextButton")
	openButton.Name = "OpenShop_smooth"
	openButton.AutoButtonColor = false
	openButton.Text = ""
	openButton.BackgroundTransparency = 1
	openButton.AnchorPoint = Vector2.new(0, 0.5)
	openButton.Position = UDim2.new(0, 18, 0.5, 0)
	openButton.Size = UDim2.fromOffset(84, 84)
	openButton.Parent = gui

	local bg, g = clipBox(openButton, UDim2.fromScale(1, 1), 18, WHITE, WHITE)
	g.Color = THEME.Rainbow
	g.Rotation = 35
	addLattice(bg, 84, 84, 28, 2, Color3.new(0, 0, 0), 0.88, 2)
	local edge = frame("Border", openButton, UDim2.new(), UDim2.fromScale(1, 1))
	corner(edge, 18)
	border(edge, THEME.Outline, 4)

	local cartIcon = icon("Icon_lean", openButton, Config.TitleIcon, Vector2.new(42, 36), 52)
	cartIcon.ZIndex = 2
	local text = label("Label", openButton, Config.Title, UDim2.fromOffset(6, 60), UDim2.new(1, -12, 0, 20), 3)
	text.ZIndex = 2

	addSmooth(openButton, leanOnHover(cartIcon))
	openButton.Activated:Connect(function()
		setOpen(not isOpen)
	end)
end

--------------------------------------------------------------------------
-- One loop drives every animation, only while the shop is on screen.
--------------------------------------------------------------------------

local clock = 0
RunService.RenderStepped:Connect(function(dt)
	clock += dt
	if not root.Visible then
		return
	end
	for _, fn in animators do
		fn(clock)
	end
end)

if Config.OpenOnJoin then
	setOpen(true)
end
