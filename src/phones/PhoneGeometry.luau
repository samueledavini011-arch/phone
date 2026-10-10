--!strict
--[[
	PhoneGeometry  (ModuleScript, child of PhoneBuilder)

	Pure math: describes every phone as a list of simple shapes (boxes,
	cylinders, balls and screens) with positions, rotations, colours and
	materials. PhoneBuilder turns that list into Roblox parts.

	Phones are 4 studs tall, stand upright, and face -Z (the screen side),
	so the model's LookVector points out of the screen.
]]

export type RGB = { number }
export type Vec = { number }
export type Mat = { number } -- 3x3 rotation, row by row

export type Screen = {
	ui: string, -- "lock", "home" or "cover"
	wallpaper: { RGB },
	corner: number, -- corner radius in studs
	span: { number }, -- which slice of one wide UI this screen shows (0..1)
	island: boolean,
}

export type Prim = {
	kind: string, -- "box", "cyl" (axis along its own X), "ball" or "screen"
	name: string,
	size: Vec,
	pos: Vec,
	rot: Mat,
	color: RGB,
	material: string,
	reflectance: number,
	transparency: number,
	screen: Screen?,
}

export type Design = {
	template: string, -- "Slab", "Fold", "TriFold", "Pill" or "Flip"
	finish: string, -- colour name, shown in the preview
	frame: RGB,
	back: RGB,
	backMaterial: string,
	wallpaper: { RGB },
	camera: string, -- "square", "bar", "column" or "circle"
	lenses: number,
	glow: RGB?,
}

local PhoneGeometry = {}

--------------------------------------------------------------------------
-- Tiny 3D math
--------------------------------------------------------------------------

local IDENTITY: Mat = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

local function mul(a: Mat, b: Mat): Mat
	local r = table.create(9, 0)
	for i = 0, 2 do
		for j = 0, 2 do
			r[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
		end
	end
	return r
end

local function apply(m: Mat, v: Vec): Vec
	return {
		m[1] * v[1] + m[2] * v[2] + m[3] * v[3],
		m[4] * v[1] + m[5] * v[2] + m[6] * v[3],
		m[7] * v[1] + m[8] * v[2] + m[9] * v[3],
	}
end

local function rotX(deg: number): Mat
	local c, s = math.cos(math.rad(deg)), math.sin(math.rad(deg))
	return { 1, 0, 0, 0, c, -s, 0, s, c }
end

local function rotY(deg: number): Mat
	local c, s = math.cos(math.rad(deg)), math.sin(math.rad(deg))
	return { c, 0, s, 0, 1, 0, -s, 0, c }
end

local function rotZ(deg: number): Mat
	local c, s = math.cos(math.rad(deg)), math.sin(math.rad(deg))
	return { c, -s, 0, s, c, 0, 0, 0, 1 }
end

type Frame = { pos: Vec, rot: Mat }

local function compose(parent: Frame, child: Frame): Frame
	local p = apply(parent.rot, child.pos)
	return { pos = { parent.pos[1] + p[1], parent.pos[2] + p[2], parent.pos[3] + p[3] }, rot = mul(parent.rot, child.rot) }
end

-- A frame that turns `deg` degrees around an axis through `pivot`.
local function hinge(pivot: Vec, rot: Mat): Frame
	local p = apply(rot, { -pivot[1], -pivot[2], -pivot[3] })
	return { pos = { pivot[1] + p[1], pivot[2] + p[2], pivot[3] + p[3] }, rot = rot }
end

local function mix(a: RGB, b: RGB, t: number): RGB
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

--------------------------------------------------------------------------
-- Shape helpers
--------------------------------------------------------------------------

type Props = { color: RGB, material: string?, reflectance: number?, transparency: number? }

type Ctx = { frame: Frame, prims: { Prim } }

local function add(ctx: Ctx, kind: string, name: string, size: Vec, pos: Vec, rot: Mat, props: Props, screen: Screen?)
	local world = compose(ctx.frame, { pos = pos, rot = rot })
	table.insert(ctx.prims, {
		kind = kind,
		name = name,
		size = size,
		pos = world.pos,
		rot = world.rot,
		color = props.color,
		material = props.material or "SmoothPlastic",
		reflectance = props.reflectance or 0,
		transparency = props.transparency or 0,
		screen = screen,
	})
end

local function box(ctx: Ctx, name: string, size: Vec, pos: Vec, props: Props)
	add(ctx, "box", name, size, pos, IDENTITY, props)
end

-- Cylinder with its round faces pointing along "x", "y" or "z".
local function cyl(ctx: Ctx, name: string, radius: number, length: number, pos: Vec, axis: string, props: Props)
	local rot = if axis == "z" then rotY(90) elseif axis == "y" then rotZ(90) else IDENTITY
	add(ctx, "cyl", name, { length, radius * 2, radius * 2 }, pos, rot, props)
end

type Corners = { tl: boolean, tr: boolean, bl: boolean, br: boolean }
local ALL: Corners = { tl = true, tr = true, bl = true, br = true }

-- A slab with rounded corners, built from boxes and corner cylinders.
local function rounded(ctx: Ctx, name: string, w: number, h: number, d: number, r: number, c: Vec, corners: Corners, props: Props)
	r = math.min(r, w / 2, h / 2)
	if r <= 0.001 then
		box(ctx, name, { w, h, d }, c, props)
		return
	end
	local x, y, z = c[1], c[2], c[3]
	if w - 2 * r > 0.001 then
		box(ctx, name, { w - 2 * r, h, d }, c, props)
	end
	-- The side strips overlap the middle slightly so no seam shows between them.
	local overlap = math.min(0.03, math.max(0, w / 2 - r))
	for _, side in { -1, 1 } do
		local top = if side < 0 then corners.tl else corners.tr
		local bottom = if side < 0 then corners.bl else corners.br
		local y0 = if bottom then -h / 2 + r else -h / 2
		local y1 = if top then h / 2 - r else h / 2
		local stripW = r + overlap
		box(ctx, name, { stripW, y1 - y0, d }, { x + side * (w / 2 - stripW / 2), y + (y0 + y1) / 2, z }, props)
	end
	local seen: { [string]: boolean } = {}
	local cornerList = {
		{ sx = -1, sy = 1, on = corners.tl },
		{ sx = 1, sy = 1, on = corners.tr },
		{ sx = -1, sy = -1, on = corners.bl },
		{ sx = 1, sy = -1, on = corners.br },
	}
	for _, corner in cornerList do
		if corner.on then
			local cx, cy = x + corner.sx * (w / 2 - r), y + corner.sy * (h / 2 - r)
			local key = string.format("%.4f,%.4f", cx, cy)
			if not seen[key] then
				seen[key] = true
				cyl(ctx, name, r, d, { cx, cy, z }, "z", props)
			end
		end
	end
end

-- A screen facing -Z (or +Z when `back` is true).
local function screen(ctx: Ctx, name: string, w: number, h: number, c: Vec, back: boolean, info: Screen)
	add(ctx, "screen", name, { w, h, 0.01 }, c, if back then rotY(180) else IDENTITY, { color = { 0, 0, 0 } }, info)
end

local BLACK_GLASS: Props = { color = { 10, 10, 13 }, material = "Glass", reflectance = 0.18 }
local LENS_BODY: Props = { color = { 14, 14, 16 }, material = "SmoothPlastic" }
local LENS_GLASS: Props = { color = { 22, 30, 56 }, material = "Glass", reflectance = 0.35 }
local LENS_COAT: Props = { color = { 70, 88, 150 }, material = "Glass", reflectance = 0.5 }
local PORT: Props = { color = { 8, 8, 10 }, material = "SmoothPlastic" }

-- One camera lens on a surface facing `dir` (+1 = back, -1 = front).
local function lens(ctx: Ctx, x: number, y: number, z: number, dir: number, radius: number, ring: RGB)
	cyl(ctx, "LensRing", radius, 0.05, { x, y, z + dir * 0.025 }, "z", { color = ring, material = "Metal", reflectance = 0.2 })
	cyl(ctx, "Lens", radius * 0.84, 0.062, { x, y, z + dir * 0.031 }, "z", LENS_BODY)
	cyl(ctx, "LensGlass", radius * 0.55, 0.068, { x, y, z + dir * 0.034 }, "z", LENS_GLASS)
	cyl(ctx, "LensCoating", radius * 0.2, 0.072, { x + radius * 0.12, y + radius * 0.12, z + dir * 0.036 }, "z", LENS_COAT)
end

local function flash(ctx: Ctx, x: number, y: number, z: number, dir: number)
	cyl(ctx, "Flash", 0.055, 0.03, { x, y, z + dir * 0.015 }, "z", { color = { 255, 238, 196 }, material = "SmoothPlastic" })
end

-- Camera module on the back. `z` is the back surface, `w`/`h` the panel size.
local function camera(ctx: Ctx, design: Design, w: number, h: number, z: number, dir: number)
	local ring = design.frame
	local bumpColor = mix(design.back, { 255, 255, 255 }, 0.08)
	local layout = design.camera
	local count = math.clamp(design.lenses, 1, 4)
	if layout == "square" then
		local s = math.min(0.98, w * 0.5)
		local cx, cy = -w / 2 + 0.13 + s / 2, h / 2 - 0.13 - s / 2
		rounded(ctx, "CameraBump", s, s, 0.05, 0.22, { cx, cy, z + dir * 0.025 }, ALL, { color = bumpColor, material = "Glass", reflectance = 0.12 })
		local spots = { { -0.21, 0.21 }, { -0.21, -0.21 }, { 0.21, 0 }, { 0.21, 0.21 } }
		if count == 4 then
			spots = { { -0.21, 0.21 }, { -0.21, -0.21 }, { 0.21, 0.21 }, { 0.21, -0.21 } }
		end
		for i = 1, count do
			lens(ctx, cx + spots[i][1], cy + spots[i][2], z + dir * 0.05, dir, 0.17, ring)
		end
		if count < 4 then
			flash(ctx, cx + 0.23, cy - 0.27, z + dir * 0.05, dir)
		end
	elseif layout == "bar" then
		local bh = 0.5
		local cy = h / 2 - 0.55
		rounded(ctx, "CameraBar", w + 0.004, bh, 0.06, 0.25, { 0, cy, z + dir * 0.03 }, ALL, { color = { 26, 26, 30 }, material = "Glass", reflectance = 0.2 })
		for i = 1, count do
			lens(ctx, -w / 2 + 0.38 + (i - 1) * 0.36, cy, z + dir * 0.06, dir, 0.15, ring)
		end
		flash(ctx, w / 2 - 0.35, cy, z + dir * 0.06, dir)
	elseif layout == "column" then
		local cx = -w / 2 + 0.33
		for i = 1, count do
			lens(ctx, cx, h / 2 - 0.36 - (i - 1) * 0.38, z, dir, 0.15, ring)
		end
		flash(ctx, cx + 0.3, h / 2 - 0.36, z, dir)
	else -- circle
		local cr = math.min(0.58, w * 0.33)
		local cx, cy = 0, h / 2 - 0.25 - cr
		cyl(ctx, "CameraRing", cr, 0.06, { cx, cy, z + dir * 0.03 }, "z", { color = ring, material = "Metal", reflectance = 0.25 })
		cyl(ctx, "CameraIsland", cr * 0.9, 0.07, { cx, cy, z + dir * 0.035 }, "z", { color = { 20, 20, 24 }, material = "Glass", reflectance = 0.2 })
		local spots = { { 0, cr * 0.42 }, { -cr * 0.4, -cr * 0.25 }, { cr * 0.4, -cr * 0.25 }, { 0, -cr * 0.05 } }
		for i = 1, count do
			lens(ctx, cx + spots[i][1], cy + spots[i][2], z + dir * 0.07, dir, cr * 0.28, ring)
		end
		flash(ctx, cx, cy - cr * 0.6, z + dir * 0.07, dir)
		if design.glow then
			-- A light-up ring around the camera, on the Pill.
			cyl(ctx, "GlowRing", cr + 0.11, 0.012, { cx, cy, z + dir * 0.006 }, "z", { color = design.glow, material = "Neon" })
			cyl(ctx, "GlowGap", cr + 0.05, 0.016, { cx, cy, z + dir * 0.008 }, "z", { color = design.back, material = "SmoothPlastic" })
		end
	end
end

-- Buttons on the sides, a port and speaker holes on the bottom.
local function details(ctx: Ctx, design: Design, w: number, h: number, d: number, withPort: boolean)
	local metal: Props = { color = mix(design.frame, { 0, 0, 0 }, 0.08), material = "Metal", reflectance = 0.15 }
	rounded(ctx, "PowerButton", 0.03, 0.42, 0.07, 0.015, { w / 2 + 0.012, h * 0.12, 0 }, ALL, metal)
	rounded(ctx, "VolumeUp", 0.03, 0.3, 0.07, 0.015, { -w / 2 - 0.012, h * 0.2, 0 }, ALL, metal)
	rounded(ctx, "VolumeDown", 0.03, 0.3, 0.07, 0.015, { -w / 2 - 0.012, h * 0.2 - 0.38, 0 }, ALL, metal)
	if withPort then
		rounded(ctx, "Port", 0.24, 0.02, math.min(0.075, d * 0.55), 0.035, { 0, -h / 2 - 0.004, 0 }, ALL, PORT)
		for i = 1, 4 do
			cyl(ctx, "Speaker", 0.017, 0.02, { 0.24 + i * 0.07, -h / 2 - 0.004, 0 }, "y", PORT)
			cyl(ctx, "Mic", 0.017, 0.02, { -0.24 - i * 0.07, -h / 2 - 0.004, 0 }, "y", PORT)
		end
	end
end

-- Frame, black front glass and coloured back of one panel.
local function body(ctx: Ctx, design: Design, w: number, h: number, d: number, r: number, corners: Corners)
	rounded(ctx, "Frame", w, h, d, r, { 0, 0, 0 }, corners, { color = design.frame, material = "Metal", reflectance = 0.12 })
	rounded(ctx, "FrontGlass", w - 0.05, h - 0.05, 0.016, r - 0.025, { 0, 0, -d / 2 - 0.004 }, corners, BLACK_GLASS)
	local backProps: Props = {
		color = design.back,
		material = design.backMaterial,
		reflectance = if design.backMaterial == "Fabric" then 0 else 0.1,
	}
	rounded(ctx, "Back", w - 0.05, h - 0.05, 0.016, r - 0.025, { 0, 0, d / 2 + 0.004 }, corners, backProps)
end

local function screenInfo(design: Design, ui: string, corner: number, span: { number }, island: boolean): Screen
	return { ui = ui, wallpaper = design.wallpaper, corner = corner, span = span, island = island }
end

--------------------------------------------------------------------------
-- Templates
--------------------------------------------------------------------------

local H = 4

local function slab(ctx: Ctx, design: Design)
	local w, d, r = 1.95, 0.24, 0.3
	body(ctx, design, w, H, d, r, ALL)
	screen(ctx, "Screen", w - 0.14, H - 0.14, { 0, 0, -d / 2 - 0.026 }, false, screenInfo(design, "lock", r - 0.07, { 0, 1 }, true))
	camera(ctx, design, w, H, d / 2 + 0.012, 1)
	details(ctx, design, w, H, d, true)
end

local function pill(ctx: Ctx, design: Design)
	local w, h, d = 1.75, 3.7, 0.34
	local r = w / 2
	local base = ctx.frame
	ctx.frame = compose(base, { pos = { 0, (h - H) / 2, 0 }, rot = IDENTITY })
	body(ctx, design, w, h, d, r, ALL)
	screen(ctx, "Screen", w - 0.16, h - 0.16, { 0, 0, -d / 2 - 0.026 }, false, screenInfo(design, "lock", (w - 0.16) / 2, { 0, 1 }, true))
	camera(ctx, design, w, h, d / 2 + 0.012, 1)
	details(ctx, design, w, h, d, true)
	ctx.frame = base
end

-- Book-style foldable, shown open at 150 degrees so both halves of the
-- big inner screen face you.
local function fold(ctx: Ctx, design: Design)
	local w, d, r = 1.8, 0.13, 0.26
	local open = 150
	local a = (180 - open) / 2
	local base = ctx.frame
	for _, side in { -1, 1 } do
		local turn = hinge({ 0, 0, d / 2 }, rotY(-side * a))
		ctx.frame = compose(compose(base, turn), { pos = { side * w / 2, 0, 0 }, rot = IDENTITY })
		local corners = if side < 0 then { tl = true, bl = true, tr = false, br = false } else { tl = false, bl = false, tr = true, br = true }
		body(ctx, design, w, H, d, r, corners)
		local sw = w - 0.07
		local span = if side < 0 then { 0, 0.5 } else { 0.5, 1 }
		screen(ctx, "InnerScreen", sw, H - 0.14, { -side * 0.035, 0, -d / 2 - 0.026 }, false, screenInfo(design, "home", r - 0.07, span, false))
		if side < 0 then
			-- Cover screen on the outside, for when it's closed.
			screen(ctx, "CoverScreen", w - 0.16, H - 0.16, { 0, 0, d / 2 + 0.026 }, true, screenInfo(design, "cover", r - 0.08, { 0, 1 }, true))
		else
			camera(ctx, design, w, H, d / 2 + 0.012, 1)
			details(ctx, design, w, H, d, true)
		end
	end
	ctx.frame = base
	cyl(ctx, "Hinge", 0.075, H - 0.12, { 0, 0, d / 2 + 0.02 }, "y", { color = design.frame, material = "Metal", reflectance = 0.2 })
end

-- Tri-fold, opened into a gentle Z so all three panels show.
local function trifold(ctx: Ctx, design: Design)
	local w, d, r = 1.45, 0.11, 0.24
	local bend = 20
	local base = ctx.frame
	local panels = {
		{ x = -w, turn = hinge({ -w / 2, 0, d / 2 }, rotY(bend)), corners = { tl = true, bl = true, tr = false, br = false }, span = { 0, 1 / 3 } },
		{ x = 0, turn = { pos = { 0, 0, 0 }, rot = IDENTITY }, corners = { tl = false, bl = false, tr = false, br = false }, span = { 1 / 3, 2 / 3 } },
		{ x = w, turn = hinge({ w / 2, 0, -d / 2 }, rotY(bend)), corners = { tl = false, bl = false, tr = true, br = true }, span = { 2 / 3, 1 } },
	}
	for i, panel in panels do
		ctx.frame = compose(compose(base, panel.turn), { pos = { panel.x, 0, 0 }, rot = IDENTITY })
		body(ctx, design, w, H, d, r, panel.corners)
		local inset = if i == 2 then 0 elseif i == 1 then 0.035 else -0.035
		local sw = if i == 2 then w else w - 0.07
		screen(ctx, "InnerScreen", sw, H - 0.14, { inset, 0, -d / 2 - 0.026 }, false, screenInfo(design, "home", r - 0.07, panel.span, false))
		if i == 1 then
			camera(ctx, design, w, H, d / 2 + 0.012, 1)
		elseif i == 3 then
			details(ctx, design, w, H, d, true)
		end
	end
	ctx.frame = base
	local metal: Props = { color = design.frame, material = "Metal", reflectance = 0.25 }
	cyl(ctx, "HingeBack", 0.06, H - 0.12, { -w / 2, 0, d / 2 + 0.015 }, "y", metal)
	cyl(ctx, "HingeFront", 0.06, H - 0.12, { w / 2, 0, -d / 2 - 0.015 }, "y", metal)
end

-- Clamshell flip phone, half open.
local function flip(ctx: Ctx, design: Design)
	local w, hh, d, r = 1.9, 1.98, 0.15, 0.3
	local open = 150
	local base = ctx.frame
	for _, half in { -1, 1 } do
		local turn = if half > 0 then hinge({ 0, 0, d / 2 }, rotX(-(180 - open))) else { pos = { 0, 0, 0 }, rot = IDENTITY }
		ctx.frame = compose(compose(base, { pos = { 0, -H / 4 + 0.5, 0 }, rot = IDENTITY }), compose(turn, { pos = { 0, half * hh / 2, 0 }, rot = IDENTITY }))
		local corners = if half > 0 then { tl = true, tr = true, bl = false, br = false } else { tl = false, tr = false, bl = true, br = true }
		body(ctx, design, w, hh, d, r, corners)
		local span = if half > 0 then { 0, 1 } else { 0, 1 }
		screen(ctx, "InnerScreen", w - 0.14, hh - 0.07, { 0, -half * 0.035, -d / 2 - 0.026 }, false, screenInfo(design, if half > 0 then "lock" else "home", r - 0.07, span, half > 0))
		if half > 0 then
			rounded(ctx, "CoverScreenGlass", w - 0.2, hh * 0.6, 0.01, 0.2, { 0, hh * 0.12, d / 2 + 0.014 }, ALL, BLACK_GLASS)
			screen(ctx, "CoverScreen", w - 0.26, hh * 0.55, { 0, hh * 0.12, d / 2 + 0.03 }, true, screenInfo(design, "cover", 0.17, { 0, 1 }, false))
			lens(ctx, -w / 2 + 0.28, hh / 2 - 0.3, d / 2 + 0.012, 1, 0.13, design.frame)
			lens(ctx, -w / 2 + 0.6, hh / 2 - 0.3, d / 2 + 0.012, 1, 0.13, design.frame)
		end
	end
	ctx.frame = base
	cyl(ctx, "Hinge", 0.085, w - 0.1, { 0, -H / 4 + 0.5, d / 2 + 0.02 }, "x", { color = design.frame, material = "Metal", reflectance = 0.2 })
end

local TEMPLATES: { [string]: (Ctx, Design) -> () } = {
	Slab = slab,
	Pill = pill,
	Fold = fold,
	TriFold = trifold,
	Flip = flip,
}

--------------------------------------------------------------------------
-- Designs
--------------------------------------------------------------------------

-- Real-world style finishes. Phones without their own design get one of
-- these, picked from the phone's name, so every phone still looks unique.
PhoneGeometry.Finishes = {
	{ finish = "Midnight", frame = { 58, 62, 70 }, back = { 30, 34, 44 }, wallpaper = { { 24, 32, 72 }, { 76, 48, 140 }, { 18, 18, 40 } } },
	{ finish = "Starlight", frame = { 226, 220, 208 }, back = { 242, 236, 224 }, wallpaper = { { 255, 214, 170 }, { 250, 160, 120 }, { 120, 110, 190 } } },
	{ finish = "Sierra Blue", frame = { 168, 192, 214 }, back = { 166, 196, 224 }, wallpaper = { { 120, 190, 255 }, { 60, 110, 230 }, { 20, 40, 120 } } },
	{ finish = "Deep Purple", frame = { 92, 80, 110 }, back = { 86, 70, 108 }, wallpaper = { { 180, 120, 255 }, { 110, 60, 200 }, { 40, 20, 90 } } },
	{ finish = "Alpine Green", frame = { 80, 98, 86 }, back = { 70, 92, 78 }, wallpaper = { { 120, 220, 170 }, { 40, 140, 110 }, { 14, 60, 50 } } },
	{ finish = "Coral", frame = { 236, 150, 134 }, back = { 248, 140, 122 }, wallpaper = { { 255, 200, 120 }, { 255, 110, 120 }, { 140, 40, 90 } } },
	{ finish = "Titanium Desert", frame = { 190, 170, 146 }, back = { 196, 180, 160 }, wallpaper = { { 250, 214, 160 }, { 200, 140, 90 }, { 90, 60, 40 } } },
	{ finish = "Sunset Orange", frame = { 230, 120, 50 }, back = { 244, 128, 50 }, wallpaper = { { 255, 190, 80 }, { 255, 90, 60 }, { 120, 30, 70 } } },
	{ finish = "Mint", frame = { 182, 222, 206 }, back = { 172, 226, 204 }, wallpaper = { { 170, 255, 220 }, { 80, 200, 190 }, { 30, 90, 120 } } },
	{ finish = "Graphite", frame = { 84, 84, 88 }, back = { 52, 52, 56 }, wallpaper = { { 120, 130, 150 }, { 50, 60, 80 }, { 10, 12, 20 } } },
}

local CAMERAS = { "square", "bar", "column", "circle" }

-- The phones seen in the game so far. Add more here by name.
PhoneGeometry.Designs = {
	Fold = {
		template = "Fold",
		finish = "Silver Shadow",
		frame = { 200, 204, 212 },
		back = { 236, 234, 230 },
		backMaterial = "Glass",
		wallpaper = { { 150, 200, 255 }, { 120, 120, 240 }, { 40, 30, 110 } },
		camera = "column",
		lenses = 3,
	},
	TriZeta = {
		template = "TriFold",
		finish = "Black Leather & Gold",
		frame = { 212, 176, 108 },
		back = { 34, 31, 31 },
		backMaterial = "Fabric",
		wallpaper = { { 255, 196, 120 }, { 200, 80, 60 }, { 40, 16, 30 } },
		camera = "circle",
		lenses = 3,
	},
	Pill = {
		template = "Pill",
		finish = "Periwinkle",
		frame = { 206, 212, 236 },
		back = { 152, 170, 232 },
		backMaterial = "SmoothPlastic",
		wallpaper = { { 200, 220, 255 }, { 150, 150, 255 }, { 70, 60, 170 } },
		camera = "circle",
		lenses = 1,
		glow = { 190, 230, 255 },
	},
} :: { [string]: Design }

local function hash(text: string): number
	local h = 5381
	for i = 1, #text do
		h = (h * 33 + string.byte(text, i)) % 2147483647
	end
	return h
end

-- The design for a phone name: its own design if it has one, otherwise a
-- realistic design picked from the name (the same name always gets the
-- same look). Names with "flip", "fold" or "pill" in them get that shape.
function PhoneGeometry.DesignFor(name: string): Design
	local own = PhoneGeometry.Designs[name]
	if own then
		return own
	end
	local h = hash(name)
	local f = PhoneGeometry.Finishes[h % #PhoneGeometry.Finishes + 1]
	local lower = string.lower(name)
	local template = "Slab"
	if string.find(lower, "flip", 1, true) then
		template = "Flip"
	elseif string.find(lower, "tri", 1, true) then
		template = "TriFold"
	elseif string.find(lower, "fold", 1, true) then
		template = "Fold"
	elseif string.find(lower, "pill", 1, true) then
		template = "Pill"
	end
	return {
		template = template,
		finish = f.finish,
		frame = f.frame,
		back = f.back,
		backMaterial = "Glass",
		wallpaper = f.wallpaper,
		camera = CAMERAS[(h // 7) % #CAMERAS + 1],
		lenses = 2 + (h // 31) % 3,
	}
end

-- Every shape of one phone. The phone stands with its bottom at y = 0.
function PhoneGeometry.Shapes(design: Design): { Prim }
	local ctx: Ctx = { frame = { pos = { 0, H / 2, 0 }, rot = IDENTITY }, prims = {} }
	local build = TEMPLATES[design.template] or slab
	build(ctx, design)
	return ctx.prims
end

PhoneGeometry.Height = H

return PhoneGeometry
