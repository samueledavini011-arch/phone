--!strict
--[[
	PhoneTowers  (ModuleScript)

	Rebuilds your phone-company towers so they look like real skyscrapers:
	glass curtain walls with lit offices behind them, a stone podium with a
	lobby you can walk into, an entrance canopy, a louvred crown with the
	brand name, and a lattice antenna with blinking aircraft lights.

	HOW TO USE (Roblox Studio)
	  1. Put PhoneTowers in ServerStorage.
	  2. Click your old tower in the 3D view so it is selected.
	  3. Open View > Command Bar, paste this line and press Enter:

	       require(game.ServerStorage.PhoneTowers).ReplaceSelected()

	     The new tower appears in the same spot, at the same height.
	     The old one is moved to ServerStorage > OldTowers, not deleted.
	  4. Do the same for your other tower.

	It works out which tower it is from the old sign. To pick it yourself:
	    require(game.ServerStorage.PhoneTowers).ReplaceSelected("Pearl Phones")
	Facing the wrong way? Add how many degrees to turn it:
	    require(game.ServerStorage.PhoneTowers).ReplaceSelected("Pearl Phones", 180)

	Changed TowerConfig, or got a newer PhoneTowers? Rebuild every tower
	in place with:
	    require(game.ServerStorage.PhoneTowers).Rebuild()

	Change names, colours and floor counts in TowerConfig.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local TextService = game:GetService("TextService")

local TowerGeometry = require(script:WaitForChild("TowerGeometry"))

type Tower = TowerGeometry.Tower
type Prim = TowerGeometry.Prim
type RGB = TowerGeometry.RGB

export type BuildOptions = {
	scale: number?, -- 1 = about 340 studs tall
	cframe: CFrame?, -- where the bottom centre goes; the entrance faces its LookVector
	parent: Instance?,
}

local PhoneTowers = {}

local VERSION = 2 -- bump when TowerLights changes, so old copies get replaced
local SIGN_FONT = Enum.Font.Michroma
local SIGN_PIXELS = 200 -- sign height in pixels

local function rgb(c: RGB): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function isNight(): boolean
	local t = Lighting.ClockTime
	return t >= 17.8 or t < 6.3
end

-- A fresh copy every time, so edits to TowerConfig count straight away.
local function loadConfig(): { Tower }
	local source = script:FindFirstChild("TowerConfig")
	if not source or not source:IsA("ModuleScript") then
		error("[PhoneTowers] TowerConfig is missing. It should be inside PhoneTowers.")
	end
	local copy = source:Clone()
	copy.Parent = script
	local ok, result = pcall(require, copy)
	copy:Destroy()
	if not ok or type(result) ~= "table" then
		error("[PhoneTowers] TowerConfig has a mistake in it: " .. tostring(result))
	end
	return result :: any
end

local function findTower(towers: { Tower }, name: string): Tower?
	local want = string.lower(name)
	if want == "" then
		return nil
	end
	for _, t in towers do
		if string.lower(t.Name or "") == want or string.lower(t.Sign or "") == want then
			return t
		end
	end
	-- "PEARL PHONES HQ" still finds "Pearl Phones"
	for _, t in towers do
		local first = string.match(string.lower(t.Name or ""), "%w+")
		if first and string.find(want, first, 1, true) then
			return t
		end
	end
	return nil
end

local function towerNames(towers: { Tower }): string
	local names = {}
	for _, t in towers do
		table.insert(names, `"{t.Name or "?"}"`)
	end
	return table.concat(names, ", ")
end

--------------------------------------------------------------------------
-- Signs
--------------------------------------------------------------------------

local function drawLogo(parent: Instance, logo: string, size: number, color: Color3, glow: Color3): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Logo"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size, size)
	holder.Parent = parent

	local function shape(w: number, h: number, x: number, y: number, rotation: number, round: number, z: number): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(x, y)
		f.Size = UDim2.fromScale(w, h)
		f.Rotation = rotation
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.ZIndex = z
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(round, 0)
		corner.Parent = f
		f.Parent = holder
		return f
	end

	if string.find(logo, "://", 1, true) then
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.Image = logo
		image.Parent = holder
	elseif logo == "pearl" then
		local pearl = shape(0.86, 0.86, 0.5, 0.5, 0, 0.5, 1)
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(176, 190, 210))
		gradient.Rotation = 45
		gradient.Parent = pearl
		local ring = Instance.new("UIStroke")
		ring.Color = glow
		ring.Thickness = math.max(2, size * 0.035)
		ring.Transparency = 0.35
		ring.Parent = pearl
		local shine = shape(0.24, 0.24, 0.36, 0.34, 0, 0.5, 2)
		shine.BackgroundColor3 = Color3.new(1, 1, 1)
	elseif logo == "star" then
		shape(0.16, 1, 0.5, 0.5, 0, 0.5, 1)
		shape(1, 0.16, 0.5, 0.5, 0, 0.5, 1)
		shape(0.4, 0.4, 0.5, 0.5, 45, 0.12, 2)
	elseif logo == "ring" then
		local ring = shape(0.78, 0.78, 0.5, 0.5, 0, 0.5, 1)
		ring.BackgroundTransparency = 1
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = size * 0.12
		stroke.Parent = ring
	end
	return holder
end

local function addSign(part: BasePart, sign: TowerGeometry.Sign)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = if sign.face == "Back" then Enum.NormalId.Back else Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = SIGN_PIXELS / part.Size.Y
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = part

	local W, H = part.Size.X * gui.PixelsPerStud, SIGN_PIXELS
	local textSize = 84
	local hasLogo = sign.logo ~= "none" and sign.logo ~= ""
	local logoSize = if hasLogo then 128 else 0
	local gap = if hasLogo then 34 else 0
	local textW = TextService:GetTextSize(sign.text, textSize, SIGN_FONT, Vector2.new(100000, 1000)).X
	local total = logoSize + gap + textW
	if total > W * 0.88 then
		local k = W * 0.88 / total
		textSize = math.floor(textSize * k)
		logoSize *= k
		gap *= k
		textW *= k
		total = W * 0.88
	end

	local x = (W - total) / 2
	if hasLogo then
		local logo = drawLogo(gui, sign.logo, logoSize, rgb(sign.color), rgb(sign.glow))
		logo.Position = UDim2.fromOffset(x, (H - logoSize) / 2)
	end

	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.BackgroundTransparency = 1
	label.Font = SIGN_FONT
	label.Text = sign.text
	label.TextSize = textSize
	label.TextColor3 = rgb(sign.color)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.fromOffset(textW + 12, H)
	label.Position = UDim2.fromOffset(x + logoSize + gap, 0)
	local halo = Instance.new("UIStroke")
	halo.Color = rgb(sign.glow)
	halo.Thickness = 3
	halo.Transparency = 0.55
	halo.Parent = label
	label.Parent = gui
end

--------------------------------------------------------------------------
-- Parts
--------------------------------------------------------------------------

local function addLight(part: BasePart, l: TowerGeometry.Light, scale: number, on: boolean)
	local range = math.min(60, l.range * scale)
	if l.kind == "spot" then
		local spot = Instance.new("SpotLight")
		spot.Face = (Enum.NormalId :: any)[l.face] or Enum.NormalId.Top
		spot.Angle = l.angle
		spot.Range = range
		spot.Brightness = l.brightness
		spot.Color = rgb(l.color)
		spot.Enabled = on
		spot.Parent = part
	else
		local point = Instance.new("PointLight")
		point.Range = range
		point.Brightness = l.brightness
		point.Color = rgb(l.color)
		point.Enabled = on
		point.Parent = part
	end
end

local function makePart(p: Prim, scale: number, night: boolean, towerName: string): BasePart
	local part: BasePart
	if p.kind == "wedge" then
		part = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		if p.kind == "cyl" then
			block.Shape = Enum.PartType.Cylinder
		elseif p.kind == "ball" then
			block.Shape = Enum.PartType.Ball
		end
		part = block
	end

	part.Name = p.name
	part.Anchored = true
	part.CanCollide = p.solid
	part.CanQuery = p.solid
	part.CanTouch = false
	part.CastShadow = p.shadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = Vector3.new(p.size[1] * scale, p.size[2] * scale, p.size[3] * scale)
	local r = p.rot
	part.CFrame = CFrame.new(p.pos[1] * scale, p.pos[2] * scale, p.pos[3] * scale, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
	part.Reflectance = p.reflectance
	part.Transparency = p.transparency

	local material: Enum.Material = (Enum.Material :: any)[p.material] or Enum.Material.SmoothPlastic
	local color = p.color
	local lightOn = true
	if p.tag == "Room" or p.tag == "Lamp" then
		-- TowerLights switches these on at dusk and off at dawn
		part:SetAttribute("NightColor", rgb(p.color))
		part:SetAttribute("NightMaterial", p.material)
		part:SetAttribute("DayColor", rgb(p.dayColor or p.color))
		if p.room then
			part:SetAttribute("Room", `{towerName}:{p.room}`)
		end
		CollectionService:AddTag(part, if p.tag == "Room" then "TowerRoom" else "TowerLamp")
		if not night then
			color = p.dayColor or color
			if p.material == "Neon" then
				material = Enum.Material.SmoothPlastic
			end
			lightOn = false
		end
	elseif p.tag == "Beacon" then
		CollectionService:AddTag(part, "TowerBeacon")
	end
	part.Material = material
	part.Color = rgb(color)

	if p.light then
		addLight(part, p.light, scale, lightOn)
	end
	if p.sign then
		addSign(part, p.sign)
	end
	return part
end

-- Copies TowerLights into ServerScriptService the first time a tower is built.
local function installLights()
	local existing = ServerScriptService:FindFirstChild("TowerLights")
	if existing and existing:GetAttribute("PhoneTowersVersion") == VERSION then
		return
	end
	local source = script:FindFirstChild("TowerLights")
	if not source then
		return
	end
	if existing then
		existing:Destroy()
	end
	local copy = source:Clone()
	copy:SetAttribute("PhoneTowersVersion", VERSION)
	copy.Parent = ServerScriptService
	print("[PhoneTowers] Put TowerLights in ServerScriptService. It switches the office lights at dusk and blinks the red lights.")
end

type Spinner = { base: BasePart?, hub: BasePart?, parts: { BasePart }, speed: number }

-- Parts that turn, like the revolving door: they are welded to their hub,
-- and a motor turns the hub on the still base part. Roblox physics runs the
-- motor during the game, so no script is needed.
local function makeSpinner(s: Spinner)
	local base, hub = s.base, s.hub
	if not base or not hub then
		return
	end
	for _, part in s.parts do
		part.Anchored = false
		part.Massless = true
		part.CanCollide = false
		part.CanQuery = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hub
		weld.Part1 = part
		weld.Parent = part
	end
	hub.Anchored = false
	hub.CanCollide = false
	hub.CanQuery = false

	local onBase = Instance.new("Attachment")
	onBase.Name = "SpinBase"
	onBase.CFrame = base.CFrame:ToObjectSpace(hub.CFrame)
	onBase.Parent = base
	local onHub = Instance.new("Attachment")
	onHub.Name = "SpinHub"
	onHub.Parent = hub

	local motor = Instance.new("HingeConstraint")
	motor.Name = "Motor"
	motor.Attachment0 = onBase
	motor.Attachment1 = onHub
	motor.ActuatorType = Enum.ActuatorType.Motor
	motor.AngularVelocity = s.speed
	motor.MotorMaxTorque = 1e7
	motor.Parent = hub
	CollectionService:AddTag(hub, "TowerSpinner")
end

local function buildTower(t: Tower, options: BuildOptions?): Model
	local o: BuildOptions = options or {}
	local scale = o.scale or 1
	local night = isNight()
	local shapes = TowerGeometry.Shapes(t)
	local name = t.Name or "Phone Tower"

	local model = Instance.new("Model")
	model.Name = name
	local folders: { [string]: Folder } = {}
	local function folderFor(group: string): Folder
		local existing = folders[group]
		if existing then
			return existing
		end
		local folder = Instance.new("Folder")
		folder.Name = group
		folder.Parent = model
		folders[group] = folder
		return folder
	end
	local spinners: { [string]: Spinner } = {}
	for _, p in shapes.prims do
		local part = makePart(p, scale, night, name)
		part.Parent = folderFor(p.group)
		local spin = p.spin
		if spin then
			local spinner: Spinner = spinners[spin.id] or { parts = {}, speed = spin.speed }
			spinners[spin.id] = spinner
			if spin.role == "base" then
				spinner.base = part
			elseif spin.role == "hub" then
				spinner.hub = part
			else
				table.insert(spinner.parts, part)
			end
		end
	end
	for _, spinner in spinners do
		makeSpinner(spinner)
	end
	model.WorldPivot = CFrame.new()
	model:SetAttribute("PhoneTower", name)
	model:SetAttribute("Scale", scale)
	if o.cframe then
		model:PivotTo(o.cframe)
	end
	model.Parent = o.parent or workspace
	installLights()
	return model
end

--------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------

-- Builds one tower. With no options it stands at the world centre.
function PhoneTowers.Build(name: string, options: BuildOptions?): Model
	local towers = loadConfig()
	local t = findTower(towers, name)
	if not t then
		error(`[PhoneTowers] No tower called "{name}" in TowerConfig. Try one of: {towerNames(towers)}`)
	end
	return buildTower(t, options)
end

-- Builds every tower in TowerConfig in a row, for a quick look.
function PhoneTowers.BuildAll(): { Model }
	local models = {}
	for i, t in loadConfig() do
		table.insert(models, buildTower(t, { cframe = CFrame.new((i - 1) * 180, 0, 0) }))
	end
	return models
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

local function worldBounds(root: Instance): (Vector3?, Vector3?)
	local parts: { BasePart } = {}
	if root:IsA("BasePart") then
		table.insert(parts, root)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			table.insert(parts, d)
		end
	end
	if #parts == 0 then
		return nil, nil
	end
	local inf = math.huge
	local x0, y0, z0, x1, y1, z1 = inf, inf, inf, -inf, -inf, -inf
	for _, part in parts do
		local half = part.Size / 2
		for _, c in { Vector3.new(-1, -1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, 1, -1), Vector3.new(-1, 1, 1), Vector3.new(1, -1, -1), Vector3.new(1, -1, 1), Vector3.new(1, 1, -1), Vector3.new(1, 1, 1) } do
			local p = part.CFrame:PointToWorldSpace(c * half)
			x0, y0, z0 = math.min(x0, p.X), math.min(y0, p.Y), math.min(z0, p.Z)
			x1, y1, z1 = math.max(x1, p.X), math.max(y1, p.Y), math.max(z1, p.Z)
		end
	end
	return Vector3.new(x0, y0, z0), Vector3.new(x1, y1, z1)
end

-- The old sign tells us which tower this is and which way its front faces.
local function readOldSign(root: Instance): (string?, Vector3?)
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") and string.find(string.upper(d.Text), "PHONE", 1, true) then
			local gui = d:FindFirstAncestorWhichIsA("SurfaceGui")
			local part = if gui then gui.Adornee or gui.Parent else nil
			if gui and part and part:IsA("BasePart") then
				return d.Text, part.CFrame:VectorToWorldSpace(Vector3.FromNormalId(gui.Face))
			end
			return d.Text, nil
		end
	end
	return nil, nil
end

local function swap(old: Instance, tower: Tower, scale: number, where: CFrame): Model
	local history = game:GetService("ChangeHistoryService") :: any
	pcall(function()
		history:SetWaypoint("Before PhoneTowers")
	end)
	local model = buildTower(tower, { scale = scale, cframe = where, parent = old.Parent })
	local backup = ServerStorage:FindFirstChild("OldTowers")
	if not backup then
		backup = Instance.new("Folder")
		backup.Name = "OldTowers"
		backup.Parent = ServerStorage
	end
	old.Parent = backup
	pcall(function()
		history:SetWaypoint("PhoneTowers")
	end)
	return model
end

-- A tower this module built: same spot, same size, same way round.
local function rebuildOurs(old: Model, tower: Tower, turn: number?): Model
	local scale = old:GetAttribute("Scale")
	if type(scale) ~= "number" then
		local lo, hi = worldBounds(old)
		scale = if lo and hi then (hi.Y - lo.Y) / TowerGeometry.Shapes(tower).height else 1
	end
	return swap(old, tower, scale :: number, old:GetPivot() * CFrame.Angles(0, math.rad(turn or 0), 0))
end

-- Swaps the selected old building for a realistic one of the same height.
function PhoneTowers.ReplaceSelected(name: string?, turn: number?): Model?
	local Selection = game:GetService("Selection") :: any
	local picked: Instance? = Selection:Get()[1]
	if not picked then
		warn("[PhoneTowers] Click your old tower first so it is selected, then run the line again.")
		return nil
	end
	local old = topModel(picked)
	local towers = loadConfig()

	local ours = old:GetAttribute("PhoneTower")
	if type(ours) == "string" and old:IsA("Model") then
		local tower = findTower(towers, name or ours)
		if not tower then
			warn(`[PhoneTowers] No tower called "{name or ours}" in TowerConfig. Try one of: {towerNames(towers)}`)
			return nil
		end
		local model = rebuildOurs(old, tower, turn)
		Selection:Set({ model })
		print(`[PhoneTowers] Rebuilt "{model.Name}". The previous one is in ServerStorage > OldTowers.`)
		return model
	end

	local lo, hi = worldBounds(old)
	if not lo or not hi then
		warn(`[PhoneTowers] "{old.Name}" has no visible parts to measure. Select the whole building.`)
		return nil
	end
	local signText, facing = readOldSign(old)
	local tower: Tower?
	if name then
		tower = findTower(towers, name)
	else
		tower = findTower(towers, signText or "") or findTower(towers, old.Name)
		if not tower and #towers == 1 then
			tower = towers[1]
		end
	end
	if not tower then
		warn(`[PhoneTowers] Which tower is "{old.Name}"? Run it again with its name, one of: {towerNames(towers)}`)
		return nil
	end

	local height = hi.Y - lo.Y
	local scale = math.clamp(height / TowerGeometry.Shapes(tower).height, 0.2, 10)
	local base = Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
	local look = facing or (if old:IsA("PVInstance") then old:GetPivot().LookVector else Vector3.new(0, 0, -1))
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	local where = CFrame.lookAt(base, base + look.Unit) * CFrame.Angles(0, math.rad(turn or 0), 0)

	local model = swap(old, tower, scale, where)
	Selection:Set({ model })
	print(`[PhoneTowers] Built "{model.Name}" ({math.floor(height + 0.5)} studs tall). The old one is in ServerStorage > OldTowers.`)
	return model
end

-- Rebuilds every tower this module made, where it stands. Use it after
-- changing TowerConfig or putting in a newer PhoneTowers.
function PhoneTowers.Rebuild(): { Model }
	local towers = loadConfig()
	local found: { Model } = {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("Model") and type(d:GetAttribute("PhoneTower")) == "string" then
			table.insert(found, d)
		end
	end
	local models = {}
	for _, old in found do
		local name = old:GetAttribute("PhoneTower") :: string
		local tower = findTower(towers, name)
		if tower then
			table.insert(models, rebuildOurs(old, tower))
		else
			warn(`[PhoneTowers] Skipped "{name}": it is not in TowerConfig any more.`)
		end
	end
	print(`[PhoneTowers] Rebuilt {#models} tower(s). The previous ones are in ServerStorage > OldTowers.`)
	return models
end

return PhoneTowers
