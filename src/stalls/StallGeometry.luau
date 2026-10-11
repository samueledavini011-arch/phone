--!strict
--[[
	StallGeometry  (ModuleScript, child of PhoneStalls)

	Pure math: describes one market stall as simple shapes (boxes,
	cylinders and balls) plus the screens, signs and lights on them.
	PhoneStalls turns that list into Roblox parts.

	The stall stands on y = 0, is centred on x = 0, z = 0 and its counter
	faces -Z, so the model's LookVector points at the customers. Heights
	are fixed for a normal-sized character; width and depth stretch to fit.
]]

export type RGB = { number }
export type Vec = { number }
export type Mat = { number } -- 3x3 rotation, row by row

export type Light = {
	kind: string, -- "spot" or "point"
	color: RGB,
	brightness: number,
	range: number,
	angle: number, -- spot lights only, in degrees
	face: string, -- spot lights shine out of this face of their part
}

export type Gui = {
	kind: string, -- "sign", "open", "menu", "icon", "token", "screen" or "display"
	face: string, -- "Front" or "Top"
	twoSided: boolean, -- also draw it on the opposite face
	text: string,
	lines: { string },
	icon: string,
	color: RGB, -- the stall's neon colour
}

export type Prim = {
	kind: string, -- "box", "cyl" (round ends on its own X axis) or "ball"
	name: string,
	group: string, -- folder inside the model, or a moving group (see Motion)
	size: Vec,
	pos: Vec,
	rot: Mat,
	color: RGB,
	material: string,
	reflectance: number,
	transparency: number,
	solid: boolean, -- players bump into it
	shadow: boolean,
	light: Light?,
	gui: Gui?,
}

export type Motion = {
	group: string,
	fx: string, -- "spin" (turns and bobs), "flicker" (neon sign blinks now and then) or "breathe" (glow fades in and out)
	pivot: Vec,
	speed: number, -- spin: radians per second
	bob: number, -- spin: studs up and down
	low: number, -- breathe: transparency range
	high: number,
}

export type Stall = { -- one entry in StallConfig
	Name: string?,
	Sign: string?,
	Kind: string?,
	Accent: RGB?,
	Icon: string?,
	Menu: { string }?,
	OpenSign: boolean?,
	Plants: boolean?,
}

export type Fit = {
	width: number?, -- along the counter
	depth: number?,
	floor: number?, -- height of the floor the shopkeeper stands on
	padX: number?, -- where the floor circle goes (stall space)
	padZ: number?,
	padR: number?,
}

export type Result = { prims: { Prim }, motions: { Motion }, width: number, depth: number }

local StallGeometry = {}

--------------------------------------------------------------------------
-- Tiny 3D math
--------------------------------------------------------------------------

local IDENTITY: Mat = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

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

local function mix(a: RGB, b: RGB, t: number): RGB
	return {
		math.floor(a[1] + (b[1] - a[1]) * t + 0.5),
		math.floor(a[2] + (b[2] - a[2]) * t + 0.5),
		math.floor(a[3] + (b[3] - a[3]) * t + 0.5),
	}
end

local WHITE: RGB = { 255, 255, 255 }
local BLACK: RGB = { 0, 0, 0 }

--------------------------------------------------------------------------
-- Shape helpers
--------------------------------------------------------------------------

type Props = {
	color: RGB,
	material: string?,
	reflectance: number?,
	transparency: number?,
	solid: boolean?,
	shadow: boolean?,
	light: Light?,
	gui: Gui?,
}

type Ctx = { prims: { Prim }, group: string }

local function add(ctx: Ctx, kind: string, name: string, size: Vec, pos: Vec, rot: Mat, p: Props)
	table.insert(ctx.prims, {
		kind = kind,
		name = name,
		group = ctx.group,
		size = size,
		pos = pos,
		rot = rot,
		color = p.color,
		material = p.material or "SmoothPlastic",
		reflectance = p.reflectance or 0,
		transparency = p.transparency or 0,
		solid = if p.solid == nil then true else p.solid,
		shadow = if p.shadow == nil then true else p.shadow,
		light = p.light,
		gui = p.gui,
	})
end

local function box(ctx: Ctx, name: string, size: Vec, pos: Vec, p: Props)
	add(ctx, "box", name, size, pos, IDENTITY, p)
end

-- Upright cylinder (round ends facing up and down).
local function post(ctx: Ctx, name: string, radius: number, height: number, pos: Vec, p: Props)
	add(ctx, "cyl", name, { height, radius * 2, radius * 2 }, pos, rotZ(90), p)
end

-- Cylinder with its round ends facing front and back.
local function disc(ctx: Ctx, name: string, radius: number, thick: number, pos: Vec, p: Props)
	add(ctx, "cyl", name, { thick, radius * 2, radius * 2 }, pos, rotY(90), p)
end

local function ball(ctx: Ctx, name: string, radius: number, pos: Vec, p: Props)
	add(ctx, "ball", name, { radius * 2, radius * 2, radius * 2 }, pos, IDENTITY, p)
end

local function neon(color: RGB, transparency: number?): Props
	return { color = color, material = "Neon", solid = false, shadow = false, transparency = transparency }
end

local function deco(color: RGB, material: string?): Props
	return { color = color, material = material, solid = false }
end

type GuiExtra = { text: string?, lines: { string }?, icon: string?, face: string?, twoSided: boolean? }

local function gui(kind: string, accent: RGB, extra: GuiExtra?): Gui
	local e: GuiExtra = extra or {}
	return {
		kind = kind,
		face = e.face or "Front",
		twoSided = e.twoSided or false,
		text = e.text or "",
		lines = e.lines or {},
		icon = e.icon or "none",
		color = accent,
	}
end

--------------------------------------------------------------------------
-- Palette
--------------------------------------------------------------------------

local BODY: RGB = { 22, 23, 27 }
local FRAME: Props = { color = { 42, 44, 50 }, material = "Metal" }
local STONE: Props = { color = { 36, 36, 40 }, material = "Slate" }
local MARBLE: Props = { color = { 234, 233, 230 }, material = "Marble", reflectance = 0.05 }
local WOOD: RGB = { 128, 92, 62 }
local WARM: RGB = { 255, 228, 190 }

local BOX_COLORS: { RGB } = {
	{ 240, 240, 236 },
	{ 30, 30, 34 },
	{ 214, 186, 140 },
	{ 190, 200, 214 },
	{ 236, 170, 190 },
	{ 170, 214, 196 },
}

--------------------------------------------------------------------------
-- The stall
--------------------------------------------------------------------------

function StallGeometry.Shapes(s: Stall, fit: Fit?): Result
	local f: Fit = fit or {}
	local W = math.clamp(f.width or 14, 9, 30)
	local D = math.clamp(f.depth or 9, 6, 16)
	local FL = math.clamp(f.floor or 0.6, 0.2, 3)
	local accent = s.Accent or { 40, 220, 255 }
	local kind = string.lower(s.Kind or "buy")
	local icon = s.Icon or (if kind == "sell" then "cash" else "bag")
	local text = s.Sign or string.upper(kind)

	local CT = FL + 3.4 -- counter top
	local RH = FL + 9.4 -- underside of the roof
	local front, back = -D / 2, D / 2
	local zc = front + 0.7 -- front face of the counter
	local CD = 1.5 -- counter depth

	local ctx: Ctx = { prims = {}, group = "Base" }
	local motions: { Motion } = {}
	local function motion(group: string, fx: string, pivot: Vec, speed: number, bob: number, low: number, high: number)
		table.insert(motions, { group = group, fx = fx, pivot = pivot, speed = speed, bob = bob, low = low, high = high })
	end

	------------------------------------------------------------------ base
	box(ctx, "Base", { W, FL, D }, { 0, FL / 2, 0 }, STONE)
	box(ctx, "BaseTrim", { W + 0.02, 0.14, 0.06 }, { 0, FL - 0.07, front - 0.02 }, { color = { 130, 132, 138 }, material = "Metal" })
	box(ctx, "Underglow", { W - 0.6, 0.12, 0.12 }, { 0, 0.12, front - 0.04 }, {
		color = accent,
		material = "Neon",
		solid = false,
		shadow = false,
		light = { kind = "spot", color = accent, brightness = 1.2, range = 10, angle = 120, face = "Front" },
	})
	for _, sx in { -1, 1 } do
		box(ctx, "Underglow", { 0.12, 0.12, D - 0.6 }, { sx * (W / 2 + 0.04), 0.12, 0 }, neon(accent))
	end
	box(ctx, "Floor", { W - 1, 0.08, D - 1 }, { 0, FL + 0.04, 0 }, { color = { 78, 58, 44 }, material = "WoodPlanks" })

	------------------------------------------------------------------ counter
	ctx.group = "Counter"
	local bodyH = CT - 0.3 - FL
	local cw = W - 1.8
	box(ctx, "Counter", { cw, bodyH, CD }, { 0, FL + bodyH / 2, zc + CD / 2 }, { color = BODY })
	box(ctx, "CounterTop", { W - 1.5, 0.3, CD + 0.7 }, { 0, CT - 0.15, zc + CD / 2 - 0.3 }, MARBLE)
	box(ctx, "CounterGlow", { W - 1.7, 0.08, 0.08 }, { 0, CT - 0.36, zc - 0.5 }, neon(accent))
	box(ctx, "KickPlate", { cw, 0.2, 0.08 }, { 0, FL + 0.1, zc - 0.04 }, { color = { 90, 92, 98 }, material = "Metal" })

	-- Fluted metal front, with a lit panel in the middle
	local fluteH = bodyH - 0.45
	local fluteY = FL + 0.25 + fluteH / 2
	local x = -cw / 2 + 0.3
	while x <= cw / 2 - 0.29 do
		if math.abs(x) > 2.05 then
			post(ctx, "Flute", 0.16, fluteH, { x, fluteY, zc - 0.06 }, { color = { 48, 50, 56 }, material = "Metal" })
		end
		x += 0.42
	end
	box(ctx, "Lightbox", { 3.6, math.min(2, fluteH), 0.16 }, { 0, fluteY, zc - 0.08 }, {
		color = { 14, 15, 18 },
		gui = gui("icon", accent, { icon = icon }),
	})

	------------------------------------------------------------------ frame and walls
	ctx.group = "Frame"
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(ctx, "Pillar", { 0.8, RH - FL, 0.8 }, { sx * (W / 2 - 0.4), FL + (RH - FL) / 2, sz * (D / 2 - 0.4) }, FRAME)
		end
		box(ctx, "PillarGlow", { 0.12, RH - FL - 0.6, 0.12 }, { sx * (W / 2 - 0.76), FL + (RH - FL) / 2, front - 0.02 }, neon(accent))
		box(ctx, "SideWall", { 0.25, CT - FL, D - 1.6 }, { sx * (W / 2 - 0.4), FL + (CT - FL) / 2, 0 }, { color = BODY })
		box(ctx, "SideRail", { 0.3, 0.15, D - 1.6 }, { sx * (W / 2 - 0.4), CT, 0 }, FRAME)
		box(ctx, "SideGlass", { 0.12, RH - CT - 0.1, D - 1.6 }, { sx * (W / 2 - 0.4), CT + (RH - CT) / 2, 0 }, {
			color = { 190, 210, 222 },
			material = "Glass",
			transparency = 0.62,
			reflectance = 0.1,
		})
	end

	-- Back wall with warm wooden slats
	box(ctx, "BackWall", { W - 0.8, RH - FL, 0.3 }, { 0, FL + (RH - FL) / 2, back - 0.4 }, { color = { 26, 26, 30 } })
	x = -(W / 2 - 1.05)
	while x <= W / 2 - 1.05 do
		box(ctx, "Slat", { 0.28, RH - FL - 0.2, 0.1 }, { x, FL + (RH - FL) / 2, back - 0.6 }, deco(WOOD, "Wood"))
		x += 0.55
	end
	box(ctx, "CoveLight", { W - 1.2, 0.1, 0.1 }, { 0, RH - 0.15, back - 0.75 }, neon(WARM))

	-- Menu board above the shopkeeper's head
	ctx.group = "Back"
	box(ctx, "MenuFrame", { 5.8, 2.6, 0.1 }, { 0, FL + 7.3, back - 0.7 }, deco({ 60, 62, 68 }, "Metal"))
	box(ctx, "MenuBoard", { 5.6, 2.4, 0.12 }, { 0, FL + 7.3, back - 0.8 }, {
		color = { 12, 12, 14 },
		solid = false,
		gui = gui("menu", accent, { lines = s.Menu or { string.upper(text) } }),
	})

	-- Shelves either side, with phone boxes (and cash on the sell stall)
	local shelfLen = W / 2 - 3.6
	if shelfLen >= 1.4 then
		local seed = if kind == "sell" then 5 else 2
		for _, sx in { -1, 1 } do
			for row, y in { FL + 4.4, FL + 6.0 } do
				local cx = sx * (2.6 + shelfLen / 2)
				box(ctx, "Shelf", { shelfLen, 0.12, 1 }, { cx, y, back - 1.15 }, deco({ 186, 146, 104 }, "Wood"))
				box(ctx, "ShelfLight", { shelfLen - 0.2, 0.05, 0.05 }, { cx, y - 0.09, back - 0.72 }, neon(WARM))
				local n = math.floor(shelfLen / 0.85)
				local step = shelfLen / n
				for i = 1, n do
					local bx = cx - shelfLen / 2 + (i - 0.5) * step
					seed = (seed * 7 + 3) % 11
					if kind == "sell" and row == 2 and i % 2 == 1 then
						-- bundles of cash
						for k = 0, 1 do
							local by = y + 0.06 + 0.1 + k * 0.2
							box(ctx, "Cash", { 0.62, 0.19, 0.4 }, { bx, by, back - 1.15 }, deco({ 86, 156, 96 }))
							box(ctx, "CashBand", { 0.14, 0.2, 0.41 }, { bx, by, back - 1.15 }, deco({ 236, 234, 222 }))
						end
					else
						local c = BOX_COLORS[seed % #BOX_COLORS + 1]
						if (i + row) % 4 == 0 then
							c = mix(accent, BLACK, 0.25)
						end
						box(ctx, "PhoneBox", { 0.6, 1, 0.24 }, { bx, y + 0.56, back - 1.15 }, deco(c))
						box(ctx, "PhoneBoxLid", { 0.62, 0.08, 0.26 }, { bx, y + 1.02, back - 1.15 }, deco(mix(c, WHITE, 0.35)))
					end
				end
			end
		end
	end

	------------------------------------------------------------------ roof
	ctx.group = "Roof"
	box(ctx, "Roof", { W + 1.2, 0.5, D + 1.6 }, { 0, RH + 0.25, -0.5 }, { color = { 26, 27, 31 } })
	box(ctx, "Fascia", { W + 1.3, 1, 0.25 }, { 0, RH + 0.2, front - 1.42 }, { color = { 34, 36, 40 }, material = "Metal" })
	box(ctx, "RoofGlow", { W + 1.3, 0.1, 0.1 }, { 0, RH - 0.32, front - 1.52 }, neon(accent))
	for _, sx in { -1, 1 } do
		box(ctx, "RoofGlow", { 0.1, 0.1, D + 1.6 }, { sx * (W / 2 + 0.62), RH + 0.02, -0.5 }, neon(accent))
	end
	for i, dx in { -W / 4, 0, W / 4 } do
		box(ctx, "Downlight", { 0.7, 0.05, 0.7 }, { dx, RH - 0.03, zc + 0.6 }, {
			color = WARM,
			material = "Neon",
			solid = false,
			shadow = false,
			light = { kind = "spot", color = WARM, brightness = if i == 2 then 1.6 else 1, range = 12, angle = 100, face = "Bottom" },
		})
	end
	box(ctx, "Downlight", { 0.7, 0.05, 0.7 }, { 0, RH - 0.03, back - 2 }, {
		color = WARM,
		material = "Neon",
		solid = false,
		shadow = false,
		light = { kind = "point", color = WARM, brightness = 0.8, range = 12, angle = 0, face = "Bottom" },
	})

	-- Big neon sign on the roof
	local SH = 2.8
	local SL = math.clamp(3.2 + 1.9 * #text, 6, W - 2.4)
	local signY = RH + 0.5 + 0.7 + SH / 2
	local signZ = front + 0.6
	for _, sx in { -1, 1 } do
		box(ctx, "SignPost", { 0.3, 0.8, 0.3 }, { sx * (SL / 2 - 1.6), RH + 0.85, signZ }, FRAME)
	end
	ctx.group = "Sign"
	box(ctx, "SignFace", { SL - SH, SH, 0.6 }, { 0, signY, signZ }, {
		color = { 12, 12, 15 },
		light = { kind = "spot", color = accent, brightness = 1.6, range = 16, angle = 110, face = "Front" },
		gui = gui("sign", accent, { text = text, twoSided = true }),
	})
	box(ctx, "SignRim", { SL - SH, SH + 0.36, 0.3 }, { 0, signY, signZ + 0.3 }, neon(accent))
	for _, sx in { -1, 1 } do
		-- a hair thinner than the face, so the round ends never flicker through the letters
		disc(ctx, "SignEnd", SH / 2, 0.56, { sx * (SL - SH) / 2, signY, signZ }, { color = { 12, 12, 15 } })
		disc(ctx, "SignRim", SH / 2 + 0.18, 0.3, { sx * (SL - SH) / 2, signY, signZ + 0.3 }, neon(accent))
	end
	motion("Sign", "flicker", { 0, signY, signZ }, 0, 0, 0, 0)

	-- Little neon OPEN sign hanging on the left
	if s.OpenSign ~= false then
		ctx.group = "OpenSign"
		local ox, oy, oz = -(W / 2 - 2.1), FL + 6.5, front + 1.2
		box(ctx, "OpenSign", { 2.2, 0.9, 0.12 }, { ox, oy, oz }, {
			color = { 14, 14, 16 },
			solid = false,
			gui = gui("open", { 255, 80, 180 }, { text = "OPEN" }),
		})
		for _, dx in { -0.8, 0.8 } do
			post(ctx, "Wire", 0.02, RH - oy - 0.45, { ox + dx, (oy + 0.45 + RH) / 2, oz }, deco({ 30, 30, 30 }))
		end
		motion("OpenSign", "flicker", { ox, oy, oz }, 0, 0, 0, 0)
	end

	------------------------------------------------------------------ on the counter
	ctx.group = "Items"
	local zi = zc + 0.5
	-- service bell
	post(ctx, "BellBase", 0.22, 0.06, { 0.9, CT + 0.03, zc - 0.05 }, deco({ 40, 40, 44 }, "Metal"))
	ball(ctx, "Bell", 0.18, { 0.9, CT + 0.1, zc - 0.05 }, { color = { 222, 182, 92 }, material = "Metal", reflectance = 0.2, solid = false })
	-- card reader
	box(ctx, "CardReader", { 0.45, 0.12, 0.75 }, { 1.7, CT + 0.06, zi + 0.2 }, deco({ 30, 30, 34 }))
	box(ctx, "CardReaderScreen", { 0.34, 0.02, 0.3 }, { 1.7, CT + 0.13, zi + 0.4 }, neon(mix(accent, WHITE, 0.4)))

	if kind == "sell" then
		-- cash register
		local rx = -W / 4
		box(ctx, "Register", { 1.7, 0.55, 1.1 }, { rx, CT + 0.275, zi + 0.35 }, { color = { 30, 31, 35 } })
		box(ctx, "Drawer", { 1.5, 0.1, 0.02 }, { rx, CT + 0.2, zi - 0.21 }, deco({ 70, 72, 78 }, "Metal"))
		box(ctx, "Keypad", { 0.8, 0.05, 0.45 }, { rx + 0.35, CT + 0.575, zi + 0.2 }, deco({ 54, 56, 62 }))
		add(ctx, "box", "RegisterScreen", { 0.9, 0.5, 0.07 }, { rx - 0.25, CT + 0.95, zi + 0.6 }, rotX(20), {
			color = { 10, 10, 12 },
			solid = false,
			gui = gui("display", accent, { text = "$$$" }),
		})
		-- cash and a phone being checked on a glowing tray
		for k = 0, 2 do
			local by = CT + 0.1 + k * 0.2
			box(ctx, "Cash", { 0.85, 0.19, 0.42 }, { W / 4 + 0.6, by, zi + 0.3 }, deco({ 86, 156, 96 }))
			box(ctx, "CashBand", { 0.16, 0.2, 0.43 }, { W / 4 + 0.6, by, zi + 0.3 }, deco({ 236, 234, 222 }))
		end
		box(ctx, "CheckTray", { 1.3, 0.04, 0.9 }, { W / 4 - 1, CT + 0.02, zi + 0.3 }, neon(accent, 0.2))
		box(ctx, "TradeInPhone", { 0.55, 0.06, 1.15 }, { W / 4 - 1, CT + 0.07, zi + 0.3 }, deco({ 40, 40, 46 }))
	else
		-- turning display phone
		local tx, tz = -W / 4, zi + 0.2
		ctx.group = "Turntable"
		post(ctx, "Turntable", 0.75, 0.1, { tx, CT + 0.05, tz }, { color = { 200, 200, 206 }, material = "Metal", solid = false })
		box(ctx, "DisplayPhone", { 0.62, 1.25, 0.08 }, { tx, CT + 0.73, tz }, {
			color = mix(accent, BLACK, 0.55),
			solid = false,
			gui = gui("screen", accent, { twoSided = false }),
		})
		motion("Turntable", "spin", { tx, CT, tz }, 0.8, 0, 0, 0)
		ctx.group = "Items"
		-- phones on clear stands
		for i, dx in { -0.5, 0.5 } do
			local px = W / 4 + dx
			box(ctx, "Stand", { 0.62, 0.06, 0.6 }, { px, CT + 0.03, zi + 0.2 }, { color = { 220, 235, 240 }, material = "Glass", transparency = 0.5, solid = false })
			add(ctx, "box", "DisplayPhone", { 0.58, 1.2, 0.07 }, { px, CT + 0.66, zi + 0.3 }, rotX(15), {
				color = if i == 1 then { 236, 236, 232 } else { 28, 28, 32 },
				solid = false,
				gui = gui("screen", accent),
			})
		end
		-- shopping bag at the end of the counter
		local bx = W / 2 - 1.6
		box(ctx, "Bag", { 0.8, 0.95, 0.36 }, { bx, CT + 0.475, zi + 0.45 }, deco(mix(accent, BLACK, 0.2)))
		for _, dx in { -0.2, 0.2 } do
			box(ctx, "BagHandle", { 0.04, 0.3, 0.04 }, { bx + dx, CT + 1.1, zi + 0.45 }, deco(WHITE))
		end
		box(ctx, "BagHandle", { 0.44, 0.04, 0.04 }, { bx, CT + 1.25, zi + 0.45 }, deco(WHITE))
	end

	------------------------------------------------------------------ plants
	if s.Plants ~= false then
		ctx.group = "Plants"
		for _, sx in { -1, 1 } do
			local px = sx * (W / 2 + 0.95)
			post(ctx, "Pot", 0.5, 1.2, { px, 0.6, front + 0.9 }, { color = { 68, 68, 74 }, material = "Concrete" })
			ball(ctx, "Leaves", 0.78, { px, 1.75, front + 0.9 }, { color = { 58, 92, 52 }, material = "LeafyGrass" })
			ball(ctx, "Leaves", 0.55, { px + sx * 0.3, 2.3, front + 1.1 }, { color = { 66, 104, 58 }, material = "LeafyGrass" })
		end
	end

	------------------------------------------------------------------ floor circle and floating icon
	local padX, padZ = f.padX or 0, f.padZ or (front - 4.2)
	local R = math.clamp(f.padR or 2.3, 1.5, 4.5)
	ctx.group = "Pad"
	post(ctx, "PadRing", R, 0.06, { padX, 0.03, padZ }, neon(accent))
	post(ctx, "PadDisc", R - 0.22, 0.08, { padX, 0.04, padZ }, { color = { 18, 18, 22 }, solid = false })
	post(ctx, "PadInnerRing", R * 0.62, 0.09, { padX, 0.045, padZ }, neon(accent))
	post(ctx, "PadCentre", R * 0.62 - 0.12, 0.1, { padX, 0.05, padZ }, { color = { 24, 24, 30 }, solid = false })
	ctx.group = "PadGlow"
	post(ctx, "PadGlow", R + 0.7, 0.03, { padX, 0.015, padZ }, neon(accent, 0.88))
	motion("PadGlow", "breathe", { padX, 0, padZ }, 0, 0, 0.82, 0.95)

	ctx.group = "Token"
	local ty = 4.4
	disc(ctx, "Token", 0.8, 0.22, { padX, ty, padZ }, {
		color = { 16, 16, 20 },
		solid = false,
		light = { kind = "point", color = accent, brightness = 1.2, range = 10, angle = 0, face = "Front" },
	})
	disc(ctx, "TokenRim", 0.88, 0.16, { padX, ty, padZ }, neon(accent))
	box(ctx, "TokenIcon", { 1.2, 1.2, 0.24 }, { padX, ty, padZ }, {
		color = accent,
		transparency = 1,
		solid = false,
		shadow = false,
		gui = gui("token", accent, { icon = icon, twoSided = true }),
	})
	motion("Token", "spin", { padX, ty, padZ }, 1.4, 0.22, 0, 0)

	return { prims = ctx.prims, motions = motions, width = W, depth = D }
end

return StallGeometry
