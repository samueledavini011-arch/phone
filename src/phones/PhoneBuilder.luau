--!strict
--[[
	PhoneBuilder  (ModuleScript, goes in ReplicatedStorage, with
	PhoneGeometry inside it as a child ModuleScript)

	Builds realistic phone models: metal frames, black glass fronts, glossy
	or leather backs, camera bumps with real-looking lenses, buttons, ports,
	hinges for the foldables, and screens that show a lock screen or a home
	screen.

	From a script:
	  local PhoneBuilder = require(game.ReplicatedStorage.PhoneBuilder)
	  local phone = PhoneBuilder.Build("Fold")     -- any phone name works
	  phone:PivotTo(CFrame.new(0, 0, 0))           -- pivot is the bottom centre
	  phone.Parent = workspace

	From the Studio command bar, to make every designed phone in Workspace:
	  require(game.ReplicatedStorage.PhoneBuilder).BuildAll()

	Phones with their own design: Fold, TriZeta, Pill. Any other name gets a
	realistic design picked from its name. Add or change designs in
	PhoneGeometry.Designs.
]]

local Geo = require(script:WaitForChild("PhoneGeometry"))

export type Options = {
	Height: number?, -- studs, default 4
	Screens: string?, -- "detailed" (default), "simple" or "off"
}

local PhoneBuilder = {}
PhoneBuilder.Designs = Geo.Designs

local PIXELS_PER_STUD = 160
local APP_COLORS = {
	Color3.fromRGB(255, 94, 87), Color3.fromRGB(255, 176, 46), Color3.fromRGB(255, 214, 10),
	Color3.fromRGB(52, 199, 89), Color3.fromRGB(48, 176, 199), Color3.fromRGB(10, 132, 255),
	Color3.fromRGB(94, 92, 230), Color3.fromRGB(191, 90, 242), Color3.fromRGB(255, 55, 95),
	Color3.fromRGB(162, 132, 94), Color3.fromRGB(99, 99, 102), Color3.fromRGB(255, 255, 255),
}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(math.floor(c[1] + 0.5), math.floor(c[2] + 0.5), math.floor(c[3] + 0.5))
end

local function newFrame(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.Parent = parent
	return f
end

local function round(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function text(parent: Instance, value: string, x: number, y: number, w: number, h: number, font: Enum.Font, alignment: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(x, y)
	l.Size = UDim2.fromOffset(w, h)
	l.Font = font
	l.Text = value
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextXAlignment = alignment or Enum.TextXAlignment.Center
	l.Parent = parent
	return l
end

-- Draws the whole screen picture at fullW x fullH pixels.
local function drawUI(ui: Frame, info: Geo.Screen, fullW: number, fullH: number, detail: string)
	local wp = info.wallpaper
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(wp[1])),
		ColorSequenceKeypoint.new(0.55, rgb(wp[2])),
		ColorSequenceKeypoint.new(1, rgb(wp[3])),
	})
	g.Rotation = 120
	g.Parent = ui
	if detail == "simple" then
		text(ui, "9:41", fullW * 0.1, fullH * 0.12, fullW * 0.8, fullH * 0.12, Enum.Font.BuilderSansBold)
		return
	end

	-- Soft light blobs in the wallpaper
	local blobs = {
		{ x = 0.3, y = 0.3, size = 0.5, color = wp[1], transparency = 0.55 },
		{ x = 0.68, y = 0.7, size = 0.55, color = wp[3], transparency = 0.6 },
	}
	for _, blob in blobs do
		local d = fullW * blob.size
		local f = newFrame(ui, fullW * blob.x - d / 2, fullH * blob.y - d / 2, d, d, rgb(blob.color), blob.transparency)
		round(f, UDim.new(0.5, 0))
	end

	if info.island then
		local iw, ih = fullW * 0.3, math.max(8, fullH * 0.032)
		round(newFrame(ui, fullW / 2 - iw / 2, fullH * 0.022, iw, ih, Color3.new(0, 0, 0)), UDim.new(0.5, 0))
	end

	if info.ui == "home" then
		text(ui, "9:41", fullW * 0.05, fullH * 0.018, fullW * 0.12, fullH * 0.03, Enum.Font.BuilderSansBold, Enum.TextXAlignment.Left)
		local battery = newFrame(ui, fullW * 0.9, fullH * 0.024, fullW * 0.045, fullH * 0.018, Color3.new(1, 1, 1), 0.1)
		round(battery, UDim.new(0.3, 0))
		local icon = fullH * 0.085
		local gap = icon * 0.55
		local cols = math.max(3, math.floor((fullW - gap) / (icon + gap)))
		local startX = (fullW - (cols * icon + (cols - 1) * gap)) / 2
		local n = 0
		for row = 0, 4 do
			for col = 0, cols - 1 do
				n += 1
				local f = newFrame(ui, startX + col * (icon + gap), fullH * 0.1 + row * (icon + gap * 1.3), icon, icon, APP_COLORS[(n * 7) % #APP_COLORS + 1])
				round(f, UDim.new(0.24, 0))
				local glyph = newFrame(f, icon * 0.3, icon * 0.3, icon * 0.4, icon * 0.4, Color3.new(1, 1, 1), 0.25)
				round(glyph, UDim.new(if n % 3 == 0 then 0.5 else 0.2, 0))
			end
		end
		local dock = newFrame(ui, fullW * 0.04, fullH * 0.855, fullW * 0.92, fullH * 0.115, Color3.new(1, 1, 1), 0.72)
		round(dock, UDim.new(0, fullH * 0.04))
		local dockCount = math.min(cols, 6)
		local dockStart = (fullW - (dockCount * icon + (dockCount - 1) * gap)) / 2
		for i = 0, dockCount - 1 do
			local f = newFrame(ui, dockStart + i * (icon + gap), fullH * 0.855 + (fullH * 0.115 - icon) / 2, icon, icon, APP_COLORS[(i * 5 + 2) % #APP_COLORS + 1])
			round(f, UDim.new(0.24, 0))
		end
	else
		local small = info.ui == "cover"
		text(ui, "Monday, June 9", fullW * 0.2, fullH * (if small then 0.12 else 0.085), fullW * 0.6, fullH * 0.035, Enum.Font.BuilderSansMedium)
		text(ui, "9:41", fullW * 0.08, fullH * (if small then 0.16 else 0.12), fullW * 0.84, fullH * (if small then 0.16 else 0.14), Enum.Font.BuilderSansBold)
		if not small then
			for _, x in { 0.17, 0.83 } do
				local d = fullW * 0.14
				local b = newFrame(ui, fullW * x - d / 2, fullH * 0.885 - d / 2, d, d, Color3.new(0, 0, 0), 0.6)
				round(b, UDim.new(0.5, 0))
				local dot = newFrame(b, d * 0.36, d * 0.36, d * 0.28, d * 0.28, Color3.new(1, 1, 1), 0.1)
				round(dot, UDim.new(0.5, 0))
			end
		end
	end
	local bar = newFrame(ui, fullW * 0.33, fullH * 0.972, fullW * 0.34, math.max(3, fullH * 0.008), Color3.new(1, 1, 1), 0.1)
	round(bar, UDim.new(0.5, 0))
end

local function addScreen(part: BasePart, info: Geo.Screen, scale: number, detail: string)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Display"
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = PIXELS_PER_STUD / scale
	sg.LightInfluence = 0
	sg.Brightness = 1.4
	sg.Parent = part

	local partW = part.Size.X / scale * PIXELS_PER_STUD
	local partH = part.Size.Y / scale * PIXELS_PER_STUD
	local spanWidth = info.span[2] - info.span[1]
	local fullW = partW / spanWidth

	local clip = Instance.new("Frame")
	clip.Name = "Clip"
	clip.BackgroundTransparency = 1
	clip.Size = UDim2.fromScale(1, 1)
	clip.ClipsDescendants = true
	clip.Parent = sg

	local ui = newFrame(clip, -info.span[1] * fullW, 0, fullW, partH, Color3.new(1, 1, 1))
	ui.Name = "Screen"
	round(ui, UDim.new(0, info.corner * PIXELS_PER_STUD))
	drawUI(ui, info, fullW, partH, detail)
end

local function boundsOf(shapes: { Geo.Prim }): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, p in shapes do
		local half = math.max(p.size[1], p.size[2], p.size[3]) / 2
		local c = Vector3.new(p.pos[1], p.pos[2], p.pos[3])
		lo = lo:Min(c - Vector3.one * half)
		hi = hi:Max(c + Vector3.one * half)
	end
	return lo, hi
end

-- Builds one phone. The model's pivot is the bottom centre of the phone,
-- and its front (the screen) faces the pivot's LookVector.
function PhoneBuilder.Build(name: string, options: Options?): Model
	local height = (options and options.Height) or Geo.Height
	local detail = (options and options.Screens) or "detailed"
	local scale = height / Geo.Height
	local design = Geo.DesignFor(name)
	local shapes = Geo.Shapes(design)

	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("Finish", design.finish)

	local lo, hi = boundsOf(shapes)
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.CanCollide = false
	root.Transparency = 1
	root.Size = (hi - lo) * scale
	root.CFrame = CFrame.new((lo + hi) / 2 * scale)
	root.Parent = model

	for _, p in shapes do
		if p.kind == "screen" and detail == "off" then
			continue
		end
		local part = Instance.new("Part")
		part.Name = p.name
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Size = Vector3.new(p.size[1], p.size[2], p.size[3]) * scale
		local r = p.rot
		part.CFrame = CFrame.new(p.pos[1] * scale, p.pos[2] * scale, p.pos[3] * scale, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
		if p.kind == "cyl" then
			part.Shape = Enum.PartType.Cylinder
		elseif p.kind == "ball" then
			part.Shape = Enum.PartType.Ball
		end
		part.Color = rgb(p.color)
		part.Material = (Enum.Material :: any)[p.material] or Enum.Material.SmoothPlastic
		part.Reflectance = p.reflectance
		part.Transparency = p.transparency
		local info = p.screen
		if p.kind == "screen" and info then
			part.Transparency = 1
			part.CastShadow = false
			addScreen(part, info, scale, detail)
		end
		part.Parent = model
	end

	model.PrimaryPart = root
	model.WorldPivot = CFrame.new()
	return model
end

-- Builds every phone that has its own design, in a row in Workspace.
function PhoneBuilder.BuildAll(parent: Instance?, options: Options?): Folder
	local folder = Instance.new("Folder")
	folder.Name = "RealisticPhones"
	local names = {}
	for name in Geo.Designs do
		table.insert(names, name)
	end
	table.sort(names)
	local height = (options and options.Height) or Geo.Height
	for i, name in names do
		local phone = PhoneBuilder.Build(name, options)
		phone:PivotTo(CFrame.new((i - (#names + 1) / 2) * height * 1.6, 0, 0))
		phone.Parent = folder
	end
	folder.Parent = parent or workspace
	return folder
end

return PhoneBuilder
