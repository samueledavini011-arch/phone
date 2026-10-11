--!strict
--[[
	PhoneStalls  (ModuleScript)

	Gives your BUY and SELL stalls a new look: a fluted counter with a
	marble top, warm wooden back wall with stocked shelves, a menu board,
	a big flickering neon sign, an OPEN sign, glowing floor circles with a
	spinning icon above them, and real lights.

	Your shopkeepers and your buy/sell scripts are not touched. The old
	stall's parts are only made invisible (players can still step on, touch
	or use its floor circle and prompts), and the new look is built around
	the shopkeeper.

	HOW TO USE (Roblox Studio)
	  1. Put PhoneStalls in ServerStorage.
	  2. Click your old BUY stall in the 3D view so it is selected.
	  3. Open View > Command Bar, paste this line and press Enter:

	       require(game.ServerStorage.PhoneStalls).ReplaceSelected()

	  4. Do the same for the SELL stall.

	The shopkeepers keep their own look. To dress them in your Roblox
	avatar, or take it off again:
	    require(game.ServerStorage.PhoneStalls).DressShopkeepers()
	    require(game.ServerStorage.PhoneStalls).UndressShopkeepers()

	Want the old look back? Select the stall and run:
	    require(game.ServerStorage.PhoneStalls).Restore()
	Changed StallConfig, or got a newer PhoneStalls? Run:
	    require(game.ServerStorage.PhoneStalls).Rebuild()
]]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local StallGeometry = require(script:WaitForChild("StallGeometry"))

type Stall = StallGeometry.Stall
type Fit = StallGeometry.Fit
type Prim = StallGeometry.Prim
type RGB = StallGeometry.RGB

export type BuildOptions = {
	cframe: CFrame?, -- where the bottom centre goes; the counter faces its LookVector
	fit: Fit?,
	parent: Instance?,
}

local PhoneStalls = {}

local VERSION = 3 -- bump when StallFX changes, so old copies get replaced
local SAVED = "PhoneStallsSaved_" -- prefix for the old stall's saved looks
local SIGN_FONT = Enum.Font.FredokaOne
local TEXT_FONT = Enum.Font.GothamMedium

local function rgb(c: RGB): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className) :: any
	for k, v in props do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- A fresh copy every time, so edits to StallConfig count straight away.
local function loadConfig(): { Stall }
	local source = script:FindFirstChild("StallConfig")
	if not source or not source:IsA("ModuleScript") then
		error("[PhoneStalls] StallConfig is missing. It should be inside PhoneStalls.")
	end
	local copy = source:Clone()
	copy.Parent = script
	local ok, result = pcall(require, copy)
	copy:Destroy()
	if not ok or type(result) ~= "table" then
		error("[PhoneStalls] StallConfig has a mistake in it: " .. tostring(result))
	end
	return result :: any
end

local function stallNames(stalls: { Stall }): string
	local names = {}
	for _, s in stalls do
		table.insert(names, `"{s.Name or "?"}"`)
	end
	return table.concat(names, ", ")
end

-- Finds a stall by its name, sign or kind somewhere in `words`.
local function findStall(stalls: { Stall }, words: string): Stall?
	local text = string.lower(words)
	if text == "" then
		return nil
	end
	for _, s in stalls do
		if string.lower(s.Name or "") == text then
			return s
		end
	end
	for _, s in stalls do
		for _, word in { s.Sign, s.Kind } do
			if word and word ~= "" and string.find(text, string.lower(word), 1, true) then
				return s
			end
		end
	end
	return nil
end

--------------------------------------------------------------------------
-- Screens and signs
--------------------------------------------------------------------------

local function surface(part: BasePart, face: Enum.NormalId, pixelsHigh: number, brightness: number): (SurfaceGui, number)
	local size = part.Size
	local w, h = size.X, size.Y
	if face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		h = size.Z
	elseif face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		w = size.Z
	end
	local gui = make("SurfaceGui", {
		Name = "Screen",
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = pixelsHigh / h,
		LightInfluence = 0,
		Brightness = brightness,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, part)
	return gui, w * gui.PixelsPerStud
end

local function label(parent: Instance, text: string, font: Enum.Font, color: Color3, x: number, y: number, w: number, h: number, align: Enum.TextXAlignment?): TextLabel
	return make("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		Font = font,
		Text = text,
		TextScaled = true,
		TextColor3 = color,
		TextXAlignment = align or Enum.TextXAlignment.Center,
	}, parent)
end

local function drawIcon(parent: Instance, icon: string, size: number, color: Color3)
	local holder = make("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
	}, parent)
	local function piece(x: number, y: number, w: number, h: number, round: number, z: number): Frame
		local f = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromScale(w, h),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = z,
		}, holder)
		make("UICorner", { CornerRadius = UDim.new(round, 0) }, f)
		return f
	end
	local function outline(f: Frame, thickness: number)
		f.BackgroundTransparency = 1
		make("UIStroke", { Color = color, Thickness = thickness }, f)
	end

	if string.find(icon, "://", 1, true) then
		make("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Image = icon, ImageColor3 = color }, holder)
	elseif icon == "bag" then
		piece(0.5, 0.63, 0.68, 0.56, 0.14, 2)
		outline(piece(0.5, 0.36, 0.34, 0.36, 0.5, 1), size * 0.075)
	elseif icon == "cash" then
		outline(piece(0.5, 0.5, 0.86, 0.86, 0.5, 1), size * 0.07)
		local dollar = label(holder, "$", SIGN_FONT, color, 0.2, 0.14, 0.6, 0.72)
		dollar.ZIndex = 2
	elseif icon == "phone" then
		outline(piece(0.5, 0.5, 0.5, 0.86, 0.18, 1), size * 0.065)
		piece(0.5, 0.17, 0.14, 0.035, 0.5, 2)
		piece(0.5, 0.82, 0.1, 0.06, 0.5, 2)
	end
end

local function neonText(parent: Instance, text: string, accent: Color3)
	local core = accent:Lerp(Color3.new(1, 1, 1), 0.62)
	for _, layer in { { color = accent, text = 0.45, stroke = 16, strokeT = 0.82 }, { color = core, text = 0, stroke = 6, strokeT = 0.05 } } do
		local l = label(parent, text, SIGN_FONT, layer.color, 0.07, 0.13, 0.86, 0.74)
		l.TextTransparency = layer.text
		make("UIStroke", { Color = accent, Thickness = layer.stroke, Transparency = layer.strokeT, LineJoinMode = Enum.LineJoinMode.Round }, l)
	end
end

local function drawGui(part: BasePart, g: StallGeometry.Gui, face: Enum.NormalId)
	local accent = rgb(g.color)
	local white = Color3.new(1, 1, 1)
	if g.kind == "sign" then
		local gui = surface(part, face, 300, 2.5)
		neonText(gui, g.text, accent)
	elseif g.kind == "open" then
		local gui = surface(part, face, 120, 2.5)
		local pill = make("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.92, 0.8),
		}, gui)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pill)
		make("UIStroke", { Color = accent, Thickness = 6 }, pill)
		local l = label(gui, g.text, SIGN_FONT, accent:Lerp(white, 0.55), 0.18, 0.2, 0.64, 0.6)
		make("UIStroke", { Color = accent, Thickness = 3, Transparency = 0.3 }, l)
	elseif g.kind == "menu" then
		-- chalk lettering on the slate board
		local gui = surface(part, face, 240, 1)
		local chalk = Color3.fromRGB(240, 238, 228)
		local tint = accent:Lerp(white, 0.45)
		local lines = g.lines
		local head = label(gui, lines[1] or "", Enum.Font.PermanentMarker, tint, 0.06, 0.05, 0.88, 0.32)
		head.Rotation = -1.5
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.42),
			Size = UDim2.new(0.62, 0, 0, 4),
			BackgroundColor3 = tint,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			Rotation = 1,
		}, gui)
		for i = 2, math.min(#lines, 3) do
			local l = label(gui, lines[i], Enum.Font.PatrickHand, chalk, 0.08, 0.5 + (i - 2) * 0.23, 0.84, 0.19)
			l.Rotation = if i % 2 == 0 then 0.8 else -0.6
		end
		for _, at in { 0.005, 0.925 } do
			label(gui, "*", Enum.Font.PermanentMarker, tint, at, 0.52, 0.07, 0.16)
		end
	elseif g.kind == "icon" then
		local gui = surface(part, face, 200, 1.8)
		local panel = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.94, 0.9),
			BackgroundColor3 = accent:Lerp(Color3.new(0, 0, 0), 0.82),
		}, gui)
		make("UICorner", { CornerRadius = UDim.new(0.18, 0) }, panel)
		make("UIStroke", { Color = accent, Thickness = 5 }, panel)
		drawIcon(panel, g.icon, 120, accent)
	elseif g.kind == "token" then
		local gui = surface(part, face, 200, 2.2)
		drawIcon(gui, g.icon, 120, accent:Lerp(white, 0.3))
	elseif g.kind == "screen" then
		local gui = surface(part, face, 250, 1.6)
		local bg = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = white, BorderSizePixel = 0 }, gui)
		make("UICorner", { CornerRadius = UDim.new(0.1, 0) }, bg)
		make("UIGradient", {
			Color = ColorSequence.new(accent, Color3.fromRGB(110, 60, 220)),
			Rotation = 120,
		}, bg)
		label(gui, "9:41", TEXT_FONT, white, 0.3, 0.1, 0.4, 0.12)
		for row = 0, 1 do
			for col = 0, 2 do
				local app = make("Frame", {
					Position = UDim2.fromScale(0.14 + col * 0.26, 0.5 + row * 0.18),
					Size = UDim2.fromScale(0.2, 0.11),
					BackgroundColor3 = white,
					BackgroundTransparency = 0.45,
					BorderSizePixel = 0,
				}, gui)
				make("UICorner", { CornerRadius = UDim.new(0.3, 0) }, app)
			end
		end
	elseif g.kind == "display" then
		local gui = surface(part, face, 120, 1.6)
		label(gui, g.text, Enum.Font.GothamBold, accent, 0.1, 0.2, 0.8, 0.6)
	elseif g.kind == "ticker" then
		-- LED strip; StallFX scrolls the two copies of the text along
		local gui = surface(part, face, 100, 1.8)
		make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(6, 6, 8), BorderSizePixel = 0 }, gui)
		local track = make("Frame", {
			Name = "Track",
			Position = UDim2.fromScale(0.01, 0.12),
			Size = UDim2.fromScale(0.98, 0.76),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
		}, gui)
		for _, name in { "A", "B" } do
			local l = make("TextLabel", {
				Name = name,
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 1, 0),
				Position = UDim2.fromOffset(if name == "A" then 0 else 4000, 0),
				Font = Enum.Font.Arcade,
				Text = g.text .. "    ",
				TextSize = 60,
				TextColor3 = accent:Lerp(white, 0.25),
				TextXAlignment = Enum.TextXAlignment.Left,
			}, track)
			make("UIStroke", { Color = accent, Thickness = 2, Transparency = 0.6 }, l)
		end
	elseif g.kind == "poster" then
		-- painted straight onto the wooden board, so the wood shows through
		local gui = surface(part, face, 240, 1)
		gui.LightInfluence = 0.5
		local paint = accent:Lerp(white, 0.15)
		local phone = make("Frame", {
			Position = UDim2.fromScale(0.07, 0.14),
			Size = UDim2.fromScale(0.24, 0.72),
			BackgroundTransparency = 1,
			Rotation = -4,
		}, gui)
		make("UICorner", { CornerRadius = UDim.new(0.14, 0) }, phone)
		make("UIStroke", { Color = paint, Thickness = 7 }, phone)
		drawIcon(phone, g.icon, 60, paint)
		local lines = g.lines
		local head = label(gui, lines[1] or "", Enum.Font.PermanentMarker, paint, 0.36, 0.12, 0.6, 0.38, Enum.TextXAlignment.Left)
		head.Rotation = -2
		local sub = label(gui, lines[2] or "", Enum.Font.PatrickHand, Color3.fromRGB(252, 248, 238), 0.37, 0.54, 0.58, 0.17, Enum.TextXAlignment.Left)
		sub.Rotation = -1
		if lines[3] then
			local blob = make("Frame", {
				Position = UDim2.fromScale(0.68, 0.7),
				Size = UDim2.fromScale(0.25, 0.25),
				SizeConstraint = Enum.SizeConstraint.RelativeYY,
				BackgroundColor3 = paint,
				Rotation = 8,
			}, gui)
			make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, blob)
			label(blob, lines[3], Enum.Font.PermanentMarker, Color3.fromRGB(30, 22, 18), 0.1, 0.22, 0.8, 0.56)
		end
	elseif g.kind == "board" then
		local gui = surface(part, face, 250, 1)
		local slate = make("Frame", {
			Position = UDim2.fromScale(0.08, 0.06),
			Size = UDim2.fromScale(0.84, 0.88),
			BackgroundColor3 = Color3.fromRGB(32, 40, 37),
		}, gui)
		make("UICorner", { CornerRadius = UDim.new(0.04, 0) }, slate)
		local chalk = Color3.fromRGB(236, 236, 228)
		for i, line in g.lines do
			local first = i == 1
			local l = label(slate, line, if first then Enum.Font.PermanentMarker else Enum.Font.PatrickHand, if first then accent:Lerp(white, 0.4) else chalk, 0.06, if first then 0.06 else 0.2 + i * 0.13, 0.88, if first then 0.24 else 0.13)
			l.Rotation = if first then -3 else (if i % 2 == 0 then 1.5 else -1)
		end
	elseif g.kind == "card" then
		-- marker on cardboard
		local gui = surface(part, face, 180, 1)
		gui.LightInfluence = 0.5
		local ink = accent:Lerp(Color3.new(0, 0, 0), 0.35)
		local head = label(gui, g.lines[1] or "", Enum.Font.PermanentMarker, ink, 0.06, 0.08, 0.88, 0.5)
		head.Rotation = -4
		local sub = label(gui, g.lines[2] or "", Enum.Font.PatrickHand, Color3.fromRGB(46, 34, 26), 0.08, 0.6, 0.84, 0.3)
		sub.Rotation = -2
	end
end

local OPPOSITE: { [string]: Enum.NormalId } = {
	Front = Enum.NormalId.Back,
	Back = Enum.NormalId.Front,
	Top = Enum.NormalId.Bottom,
	Bottom = Enum.NormalId.Top,
	Left = Enum.NormalId.Right,
	Right = Enum.NormalId.Left,
}

--------------------------------------------------------------------------
-- Parts
--------------------------------------------------------------------------

local function addLight(part: BasePart, l: StallGeometry.Light)
	if l.kind == "spot" then
		make("SpotLight", {
			Face = (Enum.NormalId :: any)[l.face] or Enum.NormalId.Front,
			Angle = l.angle,
			Range = math.min(60, l.range),
			Brightness = l.brightness,
			Color = rgb(l.color),
		}, part)
	else
		make("PointLight", { Range = math.min(60, l.range), Brightness = l.brightness, Color = rgb(l.color) }, part)
	end
end

local function makePart(p: Prim): BasePart
	local part: Part = Instance.new("Part")
	if p.kind == "cyl" then
		part.Shape = Enum.PartType.Cylinder
	elseif p.kind == "ball" then
		part.Shape = Enum.PartType.Ball
	end
	part.Name = p.name
	part.Anchored = true
	part.CanCollide = p.solid
	part.CanQuery = p.solid
	part.CanTouch = false
	part.CastShadow = p.shadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
	local r = p.rot
	part.CFrame = CFrame.new(p.pos[1], p.pos[2], p.pos[3], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
	part.Material = (Enum.Material :: any)[p.material] or Enum.Material.SmoothPlastic
	part.Color = rgb(p.color)
	part.Reflectance = p.reflectance
	part.Transparency = p.transparency
	if p.light then
		addLight(part, p.light)
	end
	if p.tag then
		CollectionService:AddTag(part, p.tag)
	end
	if p.sparkles then
		make("ParticleEmitter", {
			Color = ColorSequence.new(rgb(p.sparkles)),
			LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(1, 1.8),
			Rate = 6,
			Speed = NumberRange.new(0.3, 0.8),
			SpreadAngle = Vector2.new(180, 180),
			RotSpeed = NumberRange.new(-90, 90),
		}, part)
	end
	local g = p.gui
	if g then
		drawGui(part, g, (Enum.NormalId :: any)[g.face] or Enum.NormalId.Front)
		if g.twoSided then
			drawGui(part, g, OPPOSITE[g.face] or Enum.NormalId.Back)
		end
	end
	return part
end

-- Copies StallFX into StarterPlayerScripts. It spins the floating icons
-- and the turntable, and makes the neon flicker, on each player's screen.
local function installEffects()
	local scripts = StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
	local source = script:FindFirstChild("StallFX")
	if not scripts or not source then
		return
	end
	local existing = scripts:FindFirstChild("StallFX")
	if existing and existing:GetAttribute("PhoneStallsVersion") == VERSION then
		return
	end
	if existing then
		existing:Destroy()
	end
	local copy = source:Clone()
	copy:SetAttribute("PhoneStallsVersion", VERSION)
	copy.Parent = scripts
	print("[PhoneStalls] Put StallFX in StarterPlayerScripts. It animates the signs and floating icons.")
end

local function buildStall(s: Stall, options: BuildOptions?): Model
	local o: BuildOptions = options or {}
	local fit: Fit = o.fit or {}
	local shapes = StallGeometry.Shapes(s, fit)
	local name = s.Name or "Stall"

	local model = Instance.new("Model")
	model.Name = name
	local groups: { [string]: Instance } = {}
	for _, m in shapes.motions do
		local g = Instance.new("Model")
		g.Name = m.group
		g.WorldPivot = CFrame.new(m.pivot[1], m.pivot[2], m.pivot[3])
		if m.fx == "spin" then
			g:SetAttribute("Speed", m.speed)
			g:SetAttribute("Bob", m.bob)
			CollectionService:AddTag(g, "StallSpin")
		elseif m.fx == "flicker" then
			CollectionService:AddTag(g, "StallFlicker")
		elseif m.fx == "breathe" then
			g:SetAttribute("Low", m.low)
			g:SetAttribute("High", m.high)
			g:SetAttribute("Radius", m.radius)
			CollectionService:AddTag(g, "StallBreathe")
		end
		g.Parent = model
		groups[m.group] = g
	end
	local function groupFor(group: string): Instance
		local existing = groups[group]
		if existing then
			return existing
		end
		local folder = Instance.new("Folder")
		folder.Name = group
		folder.Parent = model
		groups[group] = folder
		return folder
	end
	for _, p in shapes.prims do
		makePart(p).Parent = groupFor(p.group)
	end

	model.WorldPivot = CFrame.new()
	model:SetAttribute("PhoneStall", name)
	model:SetAttribute("FitWidth", shapes.width)
	model:SetAttribute("FitDepth", shapes.depth)
	model:SetAttribute("FitFloor", fit.floor)
	model:SetAttribute("PadX", fit.padX)
	model:SetAttribute("PadZ", fit.padZ)
	model:SetAttribute("PadR", fit.padR)
	if o.cframe then
		model:PivotTo(o.cframe)
	end
	model.Parent = o.parent or workspace
	installEffects()
	return model
end

--------------------------------------------------------------------------
-- Working out where the old stall is
--------------------------------------------------------------------------

local CORNERS = {
	Vector3.new(-1, -1, -1),
	Vector3.new(-1, -1, 1),
	Vector3.new(-1, 1, -1),
	Vector3.new(-1, 1, 1),
	Vector3.new(1, -1, -1),
	Vector3.new(1, -1, 1),
	Vector3.new(1, 1, -1),
	Vector3.new(1, 1, 1),
}

local function corners(part: BasePart): { Vector3 }
	local half = part.Size / 2
	local out = table.create(8)
	for i, c in CORNERS do
		out[i] = part.CFrame:PointToWorldSpace(c * half)
	end
	return out
end

local function flat(v: Vector3): Vector3?
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 0.01 then
		return nil
	end
	return f.Unit
end

local function isInside(inst: Instance, roots: { Instance }): boolean
	for _, root in roots do
		if inst == root or inst:IsDescendantOf(root) then
			return true
		end
	end
	return false
end

local function topModel(inst: Instance): Instance
	local current = inst
	while true do
		local parent = current.Parent
		if parent and parent ~= workspace and parent:IsA("Model") then
			current = parent
		else
			return current
		end
	end
end

local function descendantsAndSelf(root: Instance): { Instance }
	local all = root:GetDescendants()
	table.insert(all, root)
	return all
end

local function npcRoot(npc: Model): BasePart?
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RootPart then
		return humanoid.RootPart
	end
	for _, name in { "HumanoidRootPart", "Torso", "UpperTorso", "Head" } do
		local p = npc:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return npc.PrimaryPart
end

type Analysis = { cframe: CFrame, fit: Fit, npcs: { Instance }, words: string, padFound: boolean }

local PAD_WORDS = { "pad", "circle", "ring", "zone", "touch", "prompt", "button", "buy", "sell", "trigger" }

local function analyse(old: Instance): Analysis?
	-- Shopkeepers: inside the stall, or standing in it
	local npcs: { Instance } = {}
	local all = descendantsAndSelf(old)
	for _, d in all do
		if d:IsA("Humanoid") and d.Parent and d.Parent:IsA("Model") and d.Parent ~= old then
			table.insert(npcs, d.Parent)
		end
	end

	local parts: { BasePart } = {}
	local words = { old.Name }
	for _, d in all do
		if not isInside(d, npcs) then
			if d:IsA("BasePart") and d.Transparency < 1 then
				table.insert(parts, d)
			elseif d:IsA("TextLabel") or d:IsA("TextButton") then
				table.insert(words, d.Text)
			end
		end
	end
	if #parts == 0 then
		return nil
	end

	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, part in parts do
		for _, c in corners(part) do
			lo = Vector3.new(math.min(lo.X, c.X), math.min(lo.Y, c.Y), math.min(lo.Z, c.Z))
			hi = Vector3.new(math.max(hi.X, c.X), math.max(hi.Y, c.Y), math.max(hi.Z, c.Z))
		end
	end
	local c0 = (lo + hi) / 2

	if #npcs == 0 then
		for _, d in workspace:GetDescendants() do
			if d:IsA("Humanoid") and d.Parent and d.Parent:IsA("Model") then
				local root = npcRoot(d.Parent)
				if root then
					local p = root.Position
					if p.X > lo.X - 1 and p.X < hi.X + 1 and p.Z > lo.Z - 1 and p.Z < hi.Z + 1 and p.Y > lo.Y - 2 and p.Y < hi.Y then
						table.insert(npcs, d.Parent)
					end
				end
			end
		end
	end

	-- Which way the stall faces: the way the shopkeeper looks
	local front: Vector3? = nil
	local npc = npcs[1]
	if npc and npc:IsA("Model") then
		local root = npcRoot(npc)
		if root then
			front = flat(root.CFrame.LookVector)
		end
	end

	-- The floor circle: flat, on the ground, in front, and looks like a trigger
	local function padScore(part: BasePart): number
		local ys = corners(part)
		local bottom, top = math.huge, -math.huge
		for _, c in ys do
			bottom = math.min(bottom, c.Y)
			top = math.max(top, c.Y)
		end
		if top - bottom > 1.2 or bottom > lo.Y + 1.5 then
			return 0
		end
		if front and (part.Position - c0):Dot(front) < 0.5 then
			return 0
		end
		local score = 0
		local holder = part.Parent
		for _, d in descendantsAndSelf(part) do
			if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") or d:IsA("Script") or d:IsA("LocalScript") then
				score += 3
				break
			end
		end
		if holder and holder ~= old and holder:FindFirstChildWhichIsA("ProximityPrompt", true) then
			score += 1
		end
		local name = string.lower(part.Name)
		for _, word in PAD_WORDS do
			if string.find(name, word, 1, true) then
				score += 2
				break
			end
		end
		if part:IsA("Part") and part.Shape == Enum.PartType.Cylinder then
			score += 1
		end
		if part:FindFirstChildWhichIsA("SurfaceGui") or part:FindFirstChildWhichIsA("Decal") then
			score += 1
		end
		return score
	end
	local pad: BasePart? = nil
	local best = 0
	for _, part in parts do
		local score = padScore(part)
		if score > best then
			pad, best = part, score
		end
	end
	if not front and pad then
		front = flat(pad.Position - c0)
	end
	if not front and old:IsA("PVInstance") then
		front = flat(old:GetPivot().LookVector)
	end
	local look = front or Vector3.new(0, 0, -1)
	local right = look:Cross(Vector3.yAxis)

	-- Size of the stall itself, leaving out anything flat on the ground in front
	local rMin, rMax, fMin, fMax = math.huge, -math.huge, math.huge, -math.huge
	for _, part in parts do
		local skip = part == pad
		if not skip and pad then
			local size = part.Size
			skip = math.min(size.X, size.Y, size.Z) < 0.6 and (part.Position - pad.Position).Magnitude < 6
		end
		if not skip then
			for _, c in corners(part) do
				local r, f = (c - c0):Dot(right), (c - c0):Dot(look)
				rMin, rMax = math.min(rMin, r), math.max(rMax, r)
				fMin, fMax = math.min(fMin, f), math.max(fMax, f)
			end
		end
	end
	local centre = c0 + right * ((rMin + rMax) / 2) + look * ((fMin + fMax) / 2)
	centre = Vector3.new(centre.X, lo.Y, centre.Z)
	local where = CFrame.lookAt(centre, centre + look)

	local fit: Fit = { width = rMax - rMin, depth = fMax - fMin }

	-- Put the new floor right under the shopkeeper's feet
	if npc then
		local feet = math.huge
		for _, d in npc:GetDescendants() do
			if d:IsA("BasePart") then
				for _, c in corners(d) do
					feet = math.min(feet, c.Y)
				end
			end
		end
		if feet < math.huge then
			fit.floor = math.clamp(feet - lo.Y, 0.2, 3)
		end
	end

	if pad then
		local local_ = where:PointToObjectSpace(pad.Position)
		fit.padX, fit.padZ = local_.X, local_.Z
		local reach = 0
		for _, c in corners(pad) do
			reach = math.max(reach, Vector3.new(c.X - pad.Position.X, 0, c.Z - pad.Position.Z).Magnitude)
		end
		fit.padR = math.clamp(reach / math.sqrt(2), 1.5, 4.5)
	end

	return { cframe = where, fit = fit, npcs = npcs, words = table.concat(words, " "), padFound = pad ~= nil }
end

--------------------------------------------------------------------------
-- Hiding and restoring the old stall
--------------------------------------------------------------------------

local SWITCHABLE = { "SurfaceGui", "BillboardGui", "Light", "Beam", "ParticleEmitter", "Trail", "Highlight", "Fire", "Smoke", "Sparkles" }

local function saveAndSet(inst: Instance, prop: string, value: any)
	if inst:GetAttribute(SAVED .. prop) == nil then
		inst:SetAttribute(SAVED .. prop, (inst :: any)[prop])
	end
	(inst :: any)[prop] = value
end

-- Makes the old stall invisible but keeps it working: its parts can still
-- be touched and its prompts still show. Shopkeepers stay as they are.
local function hideOld(old: Instance, keep: { Instance })
	for _, d in descendantsAndSelf(old) do
		if isInside(d, keep) then
			continue
		end
		if d:IsA("BasePart") then
			saveAndSet(d, "Transparency", 1)
			saveAndSet(d, "CanCollide", false)
		elseif d:IsA("Decal") then
			saveAndSet(d, "Transparency", 1)
		else
			for _, class in SWITCHABLE do
				if d:IsA(class) then
					saveAndSet(d, "Enabled", false)
					break
				end
			end
		end
	end
	old:SetAttribute("PhoneStallsHidden", true)
end

local function restoreOld(old: Instance)
	for _, d in descendantsAndSelf(old) do
		for name, value in d:GetAttributes() do
			if string.sub(name, 1, #SAVED) == SAVED then
				local prop = string.sub(name, #SAVED + 1)
				pcall(function()
					(d :: any)[prop] = value
				end)
				d:SetAttribute(name, nil)
			end
		end
	end
	old:SetAttribute("PhoneStallsHidden", nil)
end

local function linkedOld(model: Instance): Instance?
	local link = model:FindFirstChild("OldStall")
	if link and link:IsA("ObjectValue") then
		return link.Value
	end
	return nil
end

local function newFor(old: Instance): Model?
	for _, d in workspace:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("PhoneStall") and linkedOld(d) == old then
			return d
		end
	end
	return nil
end

local function waypoint(name: string)
	pcall(function()
		(game:GetService("ChangeHistoryService") :: any):SetWaypoint(name)
	end)
end

local function fitOf(model: Model): Fit
	local function num(name: string): number?
		local v = model:GetAttribute(name)
		return if type(v) == "number" then v else nil
	end
	return {
		width = num("FitWidth"),
		depth = num("FitDepth"),
		floor = num("FitFloor"),
		padX = num("PadX"),
		padZ = num("PadZ"),
		padR = num("PadR"),
	}
end

-- One of ours: build it again in exactly the same place.
local function rebuildOurs(current: Model, stall: Stall): Model
	local model = buildStall(stall, { cframe = current:GetPivot(), fit = fitOf(current), parent = current.Parent })
	local old = linkedOld(current)
	if old then
		make("ObjectValue", { Name = "OldStall", Value = old }, model)
	end
	current:Destroy()
	return model
end

--------------------------------------------------------------------------
-- Shopkeepers
--------------------------------------------------------------------------

-- "me" means whoever is logged in to Studio (or the game's owner).
local function resolveUser(who: any): number?
	if type(who) == "number" and who > 0 then
		return who
	end
	if type(who) == "string" and tonumber(who) then
		return tonumber(who)
	end
	if who == nil or who == true or who == "me" then
		local ok, id = pcall(function()
			return (game:GetService("StudioService") :: any):GetUserId()
		end)
		if ok and type(id) == "number" and id > 0 then
			return id
		end
		if game.CreatorType == Enum.CreatorType.User and game.CreatorId > 0 then
			return game.CreatorId
		end
	end
	return nil
end

local looks: { [string]: Model } = {}

local function avatarLook(userId: number, rig: Enum.HumanoidRigType): (Model?, string?)
	local key = `{userId}:{rig.Name}`
	local cached = looks[key]
	if cached then
		return cached, nil
	end
	local ok, result = pcall(function()
		local description = Players:GetHumanoidDescriptionFromUserId(userId)
		return Players:CreateHumanoidModelFromDescription(description, rig)
	end)
	if not ok then
		return nil, tostring(result)
	end
	looks[key] = result
	return result, nil
end

local function bodyPart(model: Model, name: string): BasePart?
	local p = model:FindFirstChild(name)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

-- The body part an accessory hangs off.
local function wornOn(handle: BasePart): BasePart?
	for _, j in handle:GetChildren() do
		if j:IsA("JointInstance") or j:IsA("WeldConstraint") then
			local joint = j :: any
			local other = if joint.Part0 == handle then joint.Part1 else joint.Part0
			if other and other:IsA("BasePart") then
				return other
			end
		end
	end
	return nil
end

local function isOutfit(c: Instance): boolean
	return c:IsA("Accessory") or c:IsA("Clothing") or c:IsA("ShirtGraphic") or c:IsA("BodyColors") or c:IsA("CharacterMesh")
end

local function colorKey(partName: string): string
	return "Color_" .. string.gsub(partName, "%W", "_")
end

local function faceOf(head: BasePart?): Decal?
	if not head then
		return nil
	end
	for _, d in head:GetChildren() do
		if d:IsA("Decal") and d.Name == "face" then
			return d
		end
	end
	return nil
end

-- The shopkeeper's own outfit, kept in ServerStorage > PhoneStallsLooks
-- while they wear an avatar, so it can be put back.
local function savedLook(npc: Model, create: boolean): Folder?
	local root = ServerStorage:FindFirstChild("PhoneStallsLooks")
	local id = npc:GetAttribute("PhoneStallsLook")
	if type(id) == "string" and root then
		local existing = root:FindFirstChild(id)
		if existing and existing:IsA("Folder") then
			return existing
		end
	end
	if not create then
		return nil
	end
	if not root then
		root = make("Folder", { Name = "PhoneStallsLooks" }, ServerStorage)
	end
	local newId = HttpService:GenerateGUID(false)
	npc:SetAttribute("PhoneStallsLook", newId)
	local store: Folder = make("Folder", { Name = newId }, root)
	store:SetAttribute("Shopkeeper", npc:GetFullName())
	for _, c in npc:GetChildren() do
		if isOutfit(c) then
			c.Parent = store
		elseif c:IsA("BasePart") then
			store:SetAttribute(colorKey(c.Name), c.Color)
		end
	end
	local face = faceOf(bodyPart(npc, "Head"))
	if face then
		face.Parent = make("Folder", { Name = "Face" }, store)
	end
	return store
end

local function markAvatar(inst: Instance): Instance
	inst:SetAttribute("PhoneStallsAvatar", true)
	return inst
end

-- Puts the avatar's clothes, hair and hats, face and skin colour on the
-- shopkeeper. Its body, position and any scripts stay as they are, and its
-- own outfit is kept so UndressShopkeepers can put it back.
local function dress(npc: Model, look: Model)
	local store = savedLook(npc, true)
	for _, c in npc:GetChildren() do
		if isOutfit(c) then
			c:Destroy()
		end
	end
	for _, c in look:GetChildren() do
		if c:IsA("Clothing") or c:IsA("ShirtGraphic") or c:IsA("BodyColors") then
			markAvatar(c:Clone()).Parent = npc
		elseif c:IsA("BasePart") and c.Name ~= "HumanoidRootPart" then
			local mine = bodyPart(npc, c.Name)
			if mine then
				mine.Color = c.Color
			end
		end
	end

	local head, lookHead = bodyPart(npc, "Head"), bodyPart(look, "Head")
	if head then
		local old = faceOf(head)
		if old then
			old:Destroy()
		end
		local face = faceOf(lookHead)
		local ownFace = store and store:FindFirstChild("Face")
		local fallback = if ownFace then ownFace:FindFirstChildOfClass("Decal") else nil
		local use = face or fallback
		if use then
			markAvatar(use:Clone()).Parent = head
		end
	end
	for _, accessory in look:GetChildren() do
		local handle = if accessory:IsA("Accessory") then accessory:FindFirstChild("Handle") else nil
		if handle and handle:IsA("BasePart") then
			local theirs = wornOn(handle) or lookHead
			local mine = if theirs then bodyPart(npc, theirs.Name) or head else head
			if theirs and mine then
				local copy = accessory:Clone()
				local h = copy:FindFirstChild("Handle") :: BasePart
				for _, j in h:GetChildren() do
					if j:IsA("JointInstance") or j:IsA("WeldConstraint") then
						j:Destroy()
					end
				end
				h.CFrame = mine.CFrame * theirs.CFrame:ToObjectSpace(handle.CFrame)
				h.Anchored = false
				h.CanCollide = false
				h.CanTouch = false
				h.CanQuery = false
				h.Massless = true
				make("WeldConstraint", { Name = "AccessoryWeld", Part0 = mine, Part1 = h }, h)
				markAvatar(copy).Parent = npc
			end
		end
	end
end

local partialUndress = false

-- Takes the avatar off and gives the shopkeeper their own outfit back.
-- Returns true if there was an avatar to take off. The first PhoneStalls
-- didn't keep the old outfit; its avatar hats are only recognised on
-- shopkeepers it already tagged.
local function undress(npc: Model): boolean
	local store = savedLook(npc, false)
	local fromFirstVersion = false
	local tagged = CollectionService:HasTag(npc, "StallShopkeeper")
	local worn: { Instance } = if tagged then npc:GetChildren() else {}
	for _, c in worn do
		local handle = if c:IsA("Accessory") then c:FindFirstChild("Handle") else nil
		local weld = if handle then handle:FindFirstChild("AccessoryWeld") else nil
		if weld and weld:IsA("WeldConstraint") then
			fromFirstVersion = true
		end
	end
	if not store and not fromFirstVersion and not npc:GetAttribute("PhoneStallsDressed") then
		return false
	end

	for _, c in npc:GetChildren() do
		if isOutfit(c) then
			c:Destroy()
		end
	end
	local head = bodyPart(npc, "Head")
	local face = faceOf(head)
	if face then
		face:Destroy()
	end

	if store then
		for _, c in store:GetChildren() do
			if c.Name == "Face" and c:IsA("Folder") then
				local own = c:FindFirstChildOfClass("Decal")
				if own and head then
					own.Parent = head
				end
			else
				c.Parent = npc
			end
		end
		for _, part in npc:GetChildren() do
			if part:IsA("BasePart") then
				local color = store:GetAttribute(colorKey(part.Name))
				if typeof(color) == "Color3" then
					part.Color = color
				end
			end
		end
		store:Destroy()
	else
		partialUndress = true
		if head then
			make("Decal", { Name = "face", Face = Enum.NormalId.Front, Texture = "rbxasset://textures/face.png" }, head)
		end
	end
	npc:SetAttribute("PhoneStallsLook", nil)
	npc:SetAttribute("PhoneStallsDressed", nil)
	return true
end

-- Shopkeepers standing inside one of our stalls.
local function shopkeepersIn(stall: Model): { Instance }
	local fit = fitOf(stall)
	local hw, hd = (fit.width or 14) / 2 + 0.5, (fit.depth or 9) / 2 + 0.5
	local pivot = stall:GetPivot()
	local found: { Instance } = {}
	for _, h in workspace:GetDescendants() do
		local npc = h.Parent
		if h:IsA("Humanoid") and npc and npc:IsA("Model") and not npc:IsDescendantOf(stall) then
			local root = npcRoot(npc)
			if root then
				local p = pivot:PointToObjectSpace(root.Position)
				if math.abs(p.X) < hw and math.abs(p.Z) < hd and p.Y > -2 and p.Y < 12 then
					table.insert(found, npc)
				end
			end
		end
	end
	return found
end

local warnedNoUser = false

-- Tags the shopkeepers for StallFX and dresses them. Returns how many were dressed.
local function prepareShopkeepers(npcs: { Instance }, s: Stall): number
	local dressed = 0
	for _, npc in npcs do
		if not npc:IsA("Model") then
			continue
		end
		if s.Shopkeeper == nil or s.Shopkeeper == false then
			undress(npc)
		end
		npc:SetAttribute("ShopkeeperMoves", s.ShopkeeperMoves ~= false)
		CollectionService:AddTag(npc, "StallShopkeeper")
		if s.Shopkeeper == nil or s.Shopkeeper == false then
			continue
		end
		local userId = resolveUser(s.Shopkeeper)
		local humanoid = npc:FindFirstChildOfClass("Humanoid")
		if not userId then
			if not warnedNoUser then
				warnedNoUser = true
				warn("[PhoneStalls] I couldn't tell whose avatar to use. In StallConfig, set Shopkeeper to your UserId (the number in your Roblox profile link).")
			end
		elseif humanoid then
			local look, problem = avatarLook(userId, humanoid.RigType)
			if look then
				dress(npc, look)
				npc:SetAttribute("PhoneStallsDressed", true)
				dressed += 1
			else
				warn(`[PhoneStalls] Couldn't load the avatar for user {userId}: {problem}`)
			end
		end
	end
	return dressed
end

--------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------

-- Builds one stall. With no options it stands at the world centre.
function PhoneStalls.Build(name: string, options: BuildOptions?): Model
	local stalls = loadConfig()
	local s = findStall(stalls, name)
	if not s then
		error(`[PhoneStalls] No stall called "{name}" in StallConfig. Try one of: {stallNames(stalls)}`)
	end
	return buildStall(s, options)
end

-- Gives the selected stall its new look. `width` (studs) is optional.
function PhoneStalls.ReplaceSelected(name: string?, width: number?): Model?
	local Selection = game:GetService("Selection") :: any
	local picked: Instance? = Selection:Get()[1]
	if not picked then
		warn("[PhoneStalls] Click your old stall first so it is selected, then run the line again.")
		return nil
	end
	local old = topModel(picked)
	local stalls = loadConfig()

	local ours = old:GetAttribute("PhoneStall")
	if type(ours) == "string" and old:IsA("Model") then
		local s = findStall(stalls, name or ours)
		if not s then
			warn(`[PhoneStalls] No stall called "{name or ours}" in StallConfig. Try one of: {stallNames(stalls)}`)
			return nil
		end
		waypoint("Before PhoneStalls")
		table.clear(looks)
		local model = rebuildOurs(old, s)
		prepareShopkeepers(shopkeepersIn(model), s)
		waypoint("PhoneStalls")
		Selection:Set({ model })
		return model
	end
	if old:GetAttribute("PhoneStallsHidden") then
		warn(`[PhoneStalls] "{old.Name}" already has its new look. Select the new stall instead, or run Restore() to undo it.`)
		return nil
	end

	local a = analyse(old)
	if not a then
		warn(`[PhoneStalls] "{old.Name}" has no visible parts to measure. Select the whole stall.`)
		return nil
	end
	local s = if name then findStall(stalls, name) else findStall(stalls, a.words)
	if not s then
		warn(`[PhoneStalls] Is "{old.Name}" the buy or the sell stall? Run it again with the name, one of: {stallNames(stalls)}`)
		return nil
	end
	if width then
		a.fit.width = width
	end

	waypoint("Before PhoneStalls")
	local model = buildStall(s, { cframe = a.cframe, fit = a.fit, parent = old.Parent })
	make("ObjectValue", { Name = "OldStall", Value = old }, model)
	hideOld(old, a.npcs)
	table.clear(looks)
	local dressed = prepareShopkeepers(a.npcs, s)
	waypoint("PhoneStalls")
	Selection:Set({ model })

	local note = if a.padFound then "The floor circle is on top of your old one." else "I couldn't find your old floor circle, so the new one is in front of the counter."
	local keeper = if dressed > 0 then " The shopkeeper is wearing your avatar." elseif #a.npcs == 0 then " I didn't find a shopkeeper in this stall." else ""
	print(`[PhoneStalls] Built "{model.Name}". The old stall is hidden but still works. {note}{keeper}`)
	return model
end

-- Puts the selected stall back the way it was.
function PhoneStalls.Restore(): boolean
	local Selection = game:GetService("Selection") :: any
	local picked: Instance? = Selection:Get()[1]
	if not picked then
		warn("[PhoneStalls] Click the stall first so it is selected, then run the line again.")
		return false
	end
	local top = topModel(picked)
	local ours: Model? = if top:IsA("Model") and top:GetAttribute("PhoneStall") then top else newFor(top)
	local old = if ours then linkedOld(ours) else top
	waypoint("Before PhoneStalls restore")
	if old then
		restoreOld(old)
	end
	if ours then
		ours:Destroy()
	end
	waypoint("PhoneStalls restore")
	if old then
		Selection:Set({ old })
	end
	print("[PhoneStalls] Put the old stall back.")
	return true
end

-- Rebuilds every stall this module made, where it stands. Use it after
-- changing StallConfig or putting in a newer PhoneStalls.
function PhoneStalls.Rebuild(): { Model }
	local stalls = loadConfig()
	local found: { Model } = {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("Model") and type(d:GetAttribute("PhoneStall")) == "string" then
			table.insert(found, d)
		end
	end
	waypoint("Before PhoneStalls rebuild")
	table.clear(looks)
	local models = {}
	for _, current in found do
		local name = current:GetAttribute("PhoneStall") :: string
		local s = findStall(stalls, name)
		if s then
			local model = rebuildOurs(current, s)
			prepareShopkeepers(shopkeepersIn(model), s)
			table.insert(models, model)
		else
			warn(`[PhoneStalls] Skipped "{name}": it is not in StallConfig any more.`)
		end
	end
	waypoint("PhoneStalls rebuild")
	print(`[PhoneStalls] Rebuilt {#models} stall(s).`)
	return models
end

-- Dresses the shopkeepers in every stall. `who` is "me" (default) or a UserId.
function PhoneStalls.DressShopkeepers(who: any?): number
	local stalls = loadConfig()
	table.clear(looks)
	warnedNoUser = false
	local count = 0
	waypoint("Before PhoneStalls dress")
	for _, d in workspace:GetDescendants() do
		local name = d:GetAttribute("PhoneStall")
		if d:IsA("Model") and type(name) == "string" then
			local s: Stall = table.clone(findStall(stalls, name) or {})
			s.Shopkeeper = if who ~= nil then who elseif s.Shopkeeper == false or s.Shopkeeper == nil then "me" else s.Shopkeeper
			count += prepareShopkeepers(shopkeepersIn(d), s)
		end
	end
	waypoint("PhoneStalls dress")
	print(`[PhoneStalls] Dressed {count} shopkeeper(s).`)
	return count
end

-- Takes the avatar off every shopkeeper and gives them their own look back.
function PhoneStalls.UndressShopkeepers(): number
	partialUndress = false
	local npcs: { Instance } = CollectionService:GetTagged("StallShopkeeper")
	for _, d in workspace:GetDescendants() do
		if d:IsA("Model") and type(d:GetAttribute("PhoneStall")) == "string" then
			for _, npc in shopkeepersIn(d) do
				table.insert(npcs, npc)
			end
		end
	end
	waypoint("Before PhoneStalls undress")
	local seen: { [Instance]: boolean } = {}
	local count = 0
	for _, npc in npcs do
		if npc:IsA("Model") and not seen[npc] then
			seen[npc] = true
			if undress(npc) then
				count += 1
			end
		end
	end
	waypoint("PhoneStalls undress")
	print(`[PhoneStalls] Took the avatar off {count} shopkeeper(s).`)
	if partialUndress then
		warn("[PhoneStalls] The first version of PhoneStalls didn't keep the shopkeepers' own clothes, so they now have a plain look. If you dressed them in this Studio session, Ctrl+Z gets their old clothes back instead.")
	end
	return count
end

return PhoneStalls
