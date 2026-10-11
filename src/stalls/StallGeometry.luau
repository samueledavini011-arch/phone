--!strict
--[[
	StallGeometry  (ModuleScript, child of PhoneStalls)

	Pure math: describes one market stall as simple shapes (boxes,
	cylinders and balls) plus the screens, signs and lights on them.
	PhoneStalls turns that list into Roblox parts.

	The stall is built like a hand-made market stall: wooden planks and
	timber posts, each set a fraction of a degree off true, hand-lettered
	signs, hanging bulbs and paper lanterns, with the neon on top.

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
	kind: string, -- "sign", "open", "menu", "icon", "token", "screen", "display", "ticker", "poster", "board" or "card"
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
	tag: string?, -- CollectionService tag for StallFX, e.g. "StallTicker"
	sparkles: RGB?, -- floating sparkles in this colour
}

export type Motion = {
	group: string,
	fx: string, -- "spin" (turns and bobs), "flicker" (neon sign blinks now and then) or "breathe" (glow fades in and out)
	pivot: Vec,
	speed: number, -- spin: radians per second
	bob: number, -- spin: studs up and down
	low: number, -- breathe: transparency range
	high: number,
	radius: number, -- breathe: glows brighter while the player stands inside this radius
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
	Ticker: string?, -- scrolling LED text along the roof edge
	Poster: { string }?, -- headline and line on the lit posters on both sides
	Board: { string }?, -- chalkboard sign out front, one entry per line
	Card: { string }?, -- hand-written cardboard sign on the counter
	StringLights: boolean?, -- warm bulbs hanging from the roof edge
	Shopkeeper: any?, -- "me", a UserId, or false (PhoneStalls dresses the shopkeeper)
	ShopkeeperMoves: boolean?, -- shopkeeper idles and waves (StallFX)
	Bunting: boolean?, -- little flags strung from the sign down to the roof corners
	Props: boolean?, -- cabinet behind the counter, crates and a sack beside the stall
	Cat: any?, -- a cat asleep on the crates: "ginger", "black", "white", or false
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

-- Same numbers every time for the same seed, in Roblox and outside it.
local function rng(seed: number): () -> number
	local s = math.floor(math.abs(seed) * 7919 + 1) % 2147483647
	if s <= 0 then
		s += 2147483646
	end
	return function(): number
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
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
	tag: string?,
	sparkles: RGB?,
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
		tag = p.tag,
		sparkles = p.sparkles,
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

-- Thin cylinder running from point a to point b (cords, chains, wires).
local function rod(ctx: Ctx, name: string, a: Vec, b: Vec, radius: number, p: Props)
	local d = { b[1] - a[1], b[2] - a[2], b[3] - a[3] }
	local len = math.sqrt(d[1] * d[1] + d[2] * d[2] + d[3] * d[3])
	local x = { d[1] / len, d[2] / len, d[3] / len }
	local up: Vec = if math.abs(x[2]) > 0.99 then { 1, 0, 0 } else { 0, 1, 0 }
	local z = { x[2] * up[3] - x[3] * up[2], x[3] * up[1] - x[1] * up[3], x[1] * up[2] - x[2] * up[1] }
	local zl = math.sqrt(z[1] * z[1] + z[2] * z[2] + z[3] * z[3])
	z = { z[1] / zl, z[2] / zl, z[3] / zl }
	local y = { z[2] * x[3] - z[3] * x[2], z[3] * x[1] - z[1] * x[3], z[1] * x[2] - z[2] * x[1] }
	local mid = { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2 }
	add(ctx, "cyl", name, { len, radius * 2, radius * 2 }, mid, { x[1], y[1], z[1], x[2], y[2], z[2], x[3], y[3], z[3] }, p)
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

local BODY: RGB = { 30, 24, 20 }
local WARM: RGB = { 255, 228, 190 }
local BULB: RGB = { 255, 208, 140 }
local TIMBER: RGB = { 92, 62, 40 }
local DARK_WOOD: RGB = { 66, 46, 32 }
local WOODS: { RGB } = { { 134, 94, 60 }, { 148, 106, 68 }, { 120, 84, 54 }, { 158, 116, 74 }, { 108, 74, 48 } }
local HONEY: { RGB } = { { 178, 130, 82 }, { 166, 118, 74 }, { 188, 140, 90 } }
local PAPER: RGB = { 244, 236, 214 }

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
	local function motion(group: string, fx: string, pivot: Vec, speed: number, bob: number, low: number, high: number, radius: number?)
		table.insert(motions, { group = group, fx = fx, pivot = pivot, speed = speed, bob = bob, low = low, high = high, radius = radius or 0 })
	end

	-- Hand-made: every board is a touch off true and its own shade of wood
	local rand = rng(if kind == "sell" then 7 else 3)
	local function jit(amount: number): number
		return (rand() * 2 - 1) * amount
	end
	local function wobble(deg: number): Mat
		return mul(rotZ(jit(deg)), mul(rotX(jit(deg)), rotY(jit(deg))))
	end
	local function wood(): RGB
		return WOODS[math.floor(rand() * #WOODS) + 1]
	end
	local function plank(name: string, size: Vec, pos: Vec, deg: number, color: RGB?, solid: boolean?)
		add(ctx, "box", name, size, pos, wobble(deg), { color = color or wood(), material = "Wood", solid = solid })
	end

	------------------------------------------------------------------ base: a plank deck
	box(ctx, "DeckFrame", { W - 0.3, math.max(0.05, FL - 0.15), D - 0.3 }, { 0, math.max(0.05, FL - 0.15) / 2, 0 }, { color = { 46, 38, 32 }, material = "Wood" })
	local boards = math.max(4, math.floor(D / 0.9))
	local bd = D / boards
	for i = 1, boards do
		plank("Deck", { W + jit(0.12), 0.15, bd - 0.06 }, { jit(0.05), FL - 0.075, -D / 2 + (i - 0.5) * bd }, 0.25)
	end
	plank("DeckEdge", { W + 0.04, math.max(0.1, FL - 0.1), 0.1 }, { 0, math.max(0.1, FL - 0.1) / 2, front - 0.02 }, 0.2, DARK_WOOD)
	box(ctx, "Underglow", { W - 0.6, 0.12, 0.12 }, { 0, 0.12, front - 0.08 }, {
		color = accent,
		material = "Neon",
		solid = false,
		shadow = false,
		light = { kind = "spot", color = accent, brightness = 1.2, range = 10, angle = 120, face = "Front" },
	})
	for _, sx in { -1, 1 } do
		box(ctx, "Underglow", { 0.12, 0.12, D - 0.6 }, { sx * (W / 2 + 0.04), 0.12, 0 }, neon(accent))
	end

	-- Woven rug in front of the counter
	local rug = mix(accent, BLACK, 0.55)
	box(ctx, "Rug", { W - 4, 0.04, 1.5 }, { 0, 0.02, front - 0.95 }, { color = rug, material = "Fabric", solid = false })
	for _, dz in { -0.45, 0.45 } do
		box(ctx, "RugStripe", { W - 4, 0.045, 0.16 }, { 0, 0.023, front - 0.95 + dz }, { color = { 236, 224, 196 }, material = "Fabric", solid = false })
	end

	------------------------------------------------------------------ counter: planks, battens and a butcher-block top
	ctx.group = "Counter"
	local bodyH = CT - 0.3 - FL
	local cw = W - 1.8
	box(ctx, "Counter", { cw, bodyH, CD }, { 0, FL + bodyH / 2, zc + CD / 2 }, { color = BODY })
	local topD = CD + 0.7
	local topZ = zc + CD / 2 - 0.3
	for i = 1, 3 do
		local pd = topD / 3
		plank("CounterTop", { W - 1.5 + jit(0.08), 0.3, pd - 0.02 }, { jit(0.03), CT - 0.15, topZ - topD / 2 + (i - 0.5) * pd }, 0.15, HONEY[i])
	end
	box(ctx, "CounterGlow", { W - 1.7, 0.08, 0.08 }, { 0, CT - 0.36, zc - 0.5 }, neon(accent))
	plank("KickBoard", { cw, 0.22, 0.08 }, { 0, FL + 0.11, zc - 0.05 }, 0.2, DARK_WOOD)

	-- Vertical boards either side of the lit panel, held by two battens and a brace
	local fluteH = bodyH - 0.45
	local fluteY = FL + 0.25 + fluteH / 2
	local panelH = math.min(2, fluteH)
	local function plankRun(x0: number, x1: number)
		local x = x0
		while x < x1 - 0.05 do
			local pw = math.min(0.42 + rand() * 0.3, x1 - x)
			if x1 - (x + pw) < 0.25 then
				pw = x1 - x
			end
			plank("FrontBoard", { pw - 0.05, fluteH + jit(0.06), 0.12 }, { x + pw / 2, fluteY + jit(0.03), zc - 0.07 + jit(0.015) }, 0.5)
			x += pw
		end
		local len = x1 - x0
		local gap = fluteH - 0.8
		for _, dy in { -gap / 2, gap / 2 } do
			plank("Batten", { len - 0.1, 0.2, 0.08 }, { (x0 + x1) / 2, fluteY + dy, zc - 0.17 }, 0.3, DARK_WOOD)
		end
		local diag = math.sqrt((len - 0.4) ^ 2 + gap ^ 2)
		local angle = math.deg(math.atan2(gap, len - 0.4)) * (if x0 < 0 then 1 else -1)
		add(ctx, "box", "Brace", { diag, 0.18, 0.07 }, { (x0 + x1) / 2, fluteY, zc - 0.165 }, rotZ(angle), { color = DARK_WOOD, material = "Wood" })
	end
	plankRun(-cw / 2, -2.05)
	plankRun(2.05, cw / 2)
	box(ctx, "Lightbox", { 3.6, panelH, 0.16 }, { 0, fluteY, zc - 0.08 }, {
		color = { 20, 16, 14 },
		gui = gui("icon", accent, { icon = icon }),
	})
	for _, dy in { -1, 1 } do
		plank("PanelFrame", { 4.1, 0.22, 0.14 }, { 0, fluteY + dy * (panelH / 2 + 0.11), zc - 0.12 }, 0.4, DARK_WOOD)
	end
	for _, dx in { -1, 1 } do
		plank("PanelFrame", { 0.22, panelH + 0.44, 0.14 }, { dx * 1.94, fluteY, zc - 0.12 }, 0.4, DARK_WOOD)
	end

	------------------------------------------------------------------ frame: timber posts, header beam and braces
	ctx.group = "Frame"
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			plank("Post", { 0.7, RH - FL + 0.05, 0.7 }, { sx * (W / 2 - 0.4), FL + (RH - FL) / 2, sz * (D / 2 - 0.4) }, 0.35, TIMBER, true)
		end
		box(ctx, "PillarGlow", { 0.12, RH - FL - 0.6, 0.12 }, { sx * (W / 2 - 0.76), FL + (RH - FL) / 2, front - 0.02 }, neon(accent))
		-- corner brace between the post and the header beam
		add(ctx, "box", "KneeBrace", { 2.1, 0.22, 0.18 }, { sx * (W / 2 - 1.5), RH - 1.1, front + 0.4 }, rotZ(sx * -45), { color = TIMBER, material = "Wood" })

		-- side walls: boards below, a glass window with a wooden cross above
		box(ctx, "SideWall", { 0.25, CT - FL, D - 1.6 }, { sx * (W / 2 - 0.4), FL + (CT - FL) / 2, 0 }, { color = BODY })
		local sideH = (CT - FL) / 4
		for k = 0, 3 do
			plank("SideBoard", { 0.12, sideH - 0.03, D - 1.6 + jit(0.06) }, { sx * (W / 2 - 0.215), FL + (k + 0.5) * sideH, jit(0.03) }, 0.3, nil, true)
		end
		plank("SideRail", { 0.34, 0.16, D - 1.5 }, { sx * (W / 2 - 0.4), CT, 0 }, 0.2, DARK_WOOD)
		box(ctx, "SideGlass", { 0.12, RH - CT - 0.1, D - 1.6 }, { sx * (W / 2 - 0.4), CT + (RH - CT) / 2, 0 }, {
			color = { 200, 214, 222 },
			material = "Glass",
			transparency = 0.62,
			reflectance = 0.1,
		})
		plank("WindowBar", { 0.16, RH - CT - 0.1, 0.12 }, { sx * (W / 2 - 0.4), CT + (RH - CT) / 2, 0 }, 0.2, DARK_WOOD)
		plank("WindowBar", { 0.16, 0.12, D - 1.6 }, { sx * (W / 2 - 0.4), CT + (RH - CT) * 0.55, 0 }, 0.2, DARK_WOOD)
	end
	plank("Header", { W - 0.8, 0.45, 0.5 }, { 0, RH - 0.225, front + 0.4 }, 0.15, TIMBER)

	-- Back wall of boards in mixed widths and shades
	box(ctx, "BackWall", { W - 0.8, RH - FL, 0.3 }, { 0, FL + (RH - FL) / 2, back - 0.4 }, { color = { 34, 26, 22 } })
	local x = -(W / 2 - 0.8)
	while x < W / 2 - 0.85 do
		local sw = math.min(0.24 + rand() * 0.14, W / 2 - 0.8 - x)
		plank("Slat", { sw - 0.05, RH - FL - 0.2 + jit(0.1), 0.1 }, { x + sw / 2, FL + (RH - FL) / 2, back - 0.6 + jit(0.02) }, 0.3, nil, false)
		x += sw + 0.04
	end
	box(ctx, "CoveLight", { W - 1.2, 0.1, 0.1 }, { 0, RH - 0.15, back - 0.75 }, neon(WARM))

	-- Hand-lettered chalk menu in a wooden frame, above the shopkeeper's head
	ctx.group = "Back"
	box(ctx, "MenuBoard", { 5.6, 2.4, 0.12 }, { 0, FL + 7.3, back - 0.8 }, {
		color = { 36, 44, 40 },
		solid = false,
		gui = gui("menu", accent, { lines = s.Menu or { string.upper(text) } }),
	})
	for _, dy in { -1, 1 } do
		plank("MenuFrame", { 6.1, 0.24, 0.16 }, { 0, FL + 7.3 + dy * 1.32, back - 0.82 }, 0.4, DARK_WOOD, false)
	end
	for _, dx in { -1, 1 } do
		plank("MenuFrame", { 0.24, 2.88, 0.16 }, { dx * 2.92, FL + 7.3, back - 0.82 }, 0.4, DARK_WOOD, false)
	end

	-- Rough shelves on brackets, stocked by hand
	local shelfLen = W / 2 - 3.6
	if shelfLen >= 1.4 then
		local seed = if kind == "sell" then 5 else 2
		for _, sx in { -1, 1 } do
			for row, y in { FL + 4.4, FL + 6.0 } do
				local cx = sx * (2.6 + shelfLen / 2)
				plank("Shelf", { shelfLen + jit(0.1), 0.14, 1 }, { cx, y, back - 1.15 }, 0.5, nil, false)
				box(ctx, "ShelfLight", { shelfLen - 0.2, 0.05, 0.05 }, { cx, y - 0.1, back - 0.72 }, neon(WARM))
				for _, dx in { -1, 1 } do
					add(ctx, "box", "Bracket", { 0.07, 0.6, 0.07 }, { cx + dx * (shelfLen / 2 - 0.3), y - 0.27, back - 0.88 }, rotX(-49), { color = DARK_WOOD, material = "Wood", solid = false })
				end
				add(ctx, "box", "PriceTag", { 0.3, 0.2, 0.02 }, { cx + jit(shelfLen / 3), y - 0.2, back - 1.67 }, rotZ(jit(10)), deco(PAPER))
				local n = math.floor(shelfLen / 0.85)
				local step = shelfLen / n
				for i = 1, n do
					local bx = cx - shelfLen / 2 + (i - 0.5) * step + jit(0.05)
					local lean = mul(rotY(jit(7)), rotZ(jit(3)))
					seed = (seed * 7 + 3) % 11
					if kind == "sell" and row == 2 and i % 2 == 1 then
						for k = 0, 1 do
							local by = y + 0.07 + 0.1 + k * 0.2
							add(ctx, "box", "Cash", { 0.62, 0.19, 0.4 }, { bx, by, back - 1.15 }, rotY(jit(10)), deco({ 86, 156, 96 }))
							add(ctx, "box", "CashBand", { 0.14, 0.2, 0.41 }, { bx, by, back - 1.15 }, rotY(jit(10)), deco({ 236, 234, 222 }))
						end
					else
						local c = BOX_COLORS[seed % #BOX_COLORS + 1]
						if (i + row) % 4 == 0 then
							c = mix(accent, BLACK, 0.25)
						end
						add(ctx, "box", "PhoneBox", { 0.6, 1, 0.24 }, { bx, y + 0.57, back - 1.15 }, lean, deco(c))
					end
				end
			end
		end
	end

	-- Low cabinet behind the shopkeeper, with odds and ends on top
	if s.Props ~= false then
		local cabW, cabH, cabZ = W - 2, 2.3, back - 1.15
		box(ctx, "Cabinet", { cabW, cabH, 0.9 }, { 0, FL + cabH / 2, cabZ }, { color = DARK_WOOD, material = "Wood", solid = false })
		plank("CabinetTop", { cabW + 0.2, 0.12, 1.05 }, { 0, FL + cabH + 0.06, cabZ - 0.05 }, 0.3, HONEY[2], false)
		local doors = math.max(3, math.floor(cabW / 1.6))
		local dw = cabW / doors
		for i = 1, doors do
			local dx = -cabW / 2 + (i - 0.5) * dw
			plank("CabinetDoor", { dw - 0.1, cabH - 0.25, 0.06 }, { dx, FL + cabH / 2 - 0.03, cabZ - 0.48 }, 0.6, nil, false)
			ball(ctx, "Knob", 0.06, { dx + (if i % 2 == 0 then -1 else 1) * (dw / 2 - 0.22), FL + cabH * 0.62, cabZ - 0.53 }, deco({ 196, 160, 90 }, "Metal"))
		end
		local topY = FL + cabH + 0.12
		post(ctx, "Mug", 0.17, 0.32, { -cabW / 2 + 0.9, topY + 0.16, cabZ }, deco({ 236, 230, 218 }))
		add(ctx, "box", "Radio", { 0.9, 0.5, 0.35 }, { cabW / 2 - 1.2, topY + 0.25, cabZ }, rotY(jit(10)), deco(mix(accent, BLACK, 0.45)))
		disc(ctx, "RadioSpeaker", 0.15, 0.02, { cabW / 2 - 1.4, topY + 0.25, cabZ - 0.19 }, deco({ 28, 28, 30 }))
		post(ctx, "SmallPot", 0.18, 0.28, { -cabW / 2 + 1.6, topY + 0.14, cabZ }, { color = { 178, 98, 64 }, material = "Sandstone", solid = false })
		ball(ctx, "Succulent", 0.2, { -cabW / 2 + 1.6, topY + 0.38, cabZ }, deco({ 92, 140, 96 }, "LeafyGrass"))
		for k = 0, 2 do
			local c = BOX_COLORS[(k * 2) % #BOX_COLORS + 1]
			add(ctx, "box", "BoxStack", { 0.8, 0.22, 1.2 }, { cabW / 2 - 2.6 + jit(0.06), topY + 0.11 + k * 0.22, cabZ }, rotY(jit(12)), deco(c))
		end
	end

	------------------------------------------------------------------ roof: planks on rafters
	ctx.group = "Roof"
	box(ctx, "Roof", { W + 1.2, 0.5, D + 1.6 }, { 0, RH + 0.25, -0.5 }, { color = { 70, 52, 38 }, material = "WoodPlanks" })
	for i = 0, 4 do
		plank("Rafter", { 0.28, 0.32, D + 1.2 }, { -W / 2 + 1 + i * (W - 2) / 4, RH - 0.16, -0.4 }, 0.2, TIMBER)
	end
	box(ctx, "Fascia", { W + 1.3, 1, 0.25 }, { 0, RH + 0.2, front - 1.42 }, {
		color = DARK_WOOD,
		material = "Wood",
		tag = "StallTicker",
		gui = gui("ticker", accent, { text = s.Ticker or `{string.upper(text)} PHONES  *  OPEN NOW  *` }),
	})

	-- String of warm bulbs swagging under the roof edge
	if s.StringLights ~= false then
		local wire: Props = { color = { 24, 24, 26 }, solid = false, shadow = false }
		local bulb: Props = { color = BULB, material = "Neon", solid = false, shadow = false }
		local yA, zA = RH - 0.42, front - 1.58
		local ends = { -(W / 2 + 0.4), 0, W / 2 + 0.4 }
		for swag = 1, 2 do
			local x0, x1 = ends[swag], ends[swag + 1]
			local n = math.max(4, math.floor((x1 - x0) / 1.1 + 0.5))
			local sag = 0.55 + (x1 - x0) * 0.03 + jit(0.08)
			local last: Vec = { x0, yA, zA }
			for i = 1, n do
				local t = i / n
				local point: Vec = { x0 + (x1 - x0) * t, yA - sag * 4 * t * (1 - t), zA }
				rod(ctx, "Wire", last, point, 0.025, wire)
				if i < n then
					ball(ctx, "Bulb", 0.13, { point[1], point[2] - 0.14, zA }, bulb)
				end
				last = point
			end
		end
	end
	box(ctx, "RoofGlow", { W + 1.3, 0.1, 0.1 }, { 0, RH - 0.32, front - 1.52 }, neon(accent))
	for _, sx in { -1, 1 } do
		box(ctx, "RoofGlow", { 0.1, 0.1, D + 1.6 }, { sx * (W / 2 + 0.62), RH + 0.02, -0.5 }, neon(accent))
	end

	-- Bulbs on cords under little shades, lighting the counter and the shop
	local function pendant(px: number, pz: number, drop: number, light: Light)
		local yb = RH - drop
		rod(ctx, "Cord", { px, RH - 0.3, pz }, { px, yb + 0.22, pz }, 0.025, deco({ 20, 20, 20 }))
		post(ctx, "Shade", 0.3, 0.22, { px, yb + 0.12, pz }, { color = { 44, 38, 32 }, material = "Metal", solid = false })
		ball(ctx, "Bulb", 0.15, { px, yb - 0.05, pz }, { color = BULB, material = "Neon", solid = false, shadow = false, light = light })
	end
	for i, dx in { -W / 4, 0, W / 4 } do
		pendant(dx + jit(0.1), zc + 0.6, 1.1 + jit(0.12), { kind = "spot", color = WARM, brightness = if i == 2 then 1.6 else 1, range = 12, angle = 100, face = "Bottom" })
	end
	pendant(0, back - 2, 1.4, { kind = "point", color = WARM, brightness = 0.8, range = 12, angle = 0, face = "Bottom" })

	-- Paper lanterns at the front corners
	for _, sx in { -1, 1 } do
		local lx, lz = sx * (W / 2 - 0.15), front - 0.7
		rod(ctx, "Cord", { lx, RH, lz }, { lx, RH - 0.62, lz }, 0.025, deco({ 20, 20, 20 }))
		post(ctx, "LanternCap", 0.22, 0.1, { lx, RH - 0.66, lz }, deco({ 40, 30, 24 }))
		ball(ctx, "Lantern", 0.48, { lx, RH - 1.13, lz }, {
			color = { 236, 168, 104 },
			material = "Neon",
			transparency = 0.22,
			solid = false,
			shadow = false,
			light = { kind = "point", color = { 255, 214, 160 }, brightness = 0.7, range = 9, angle = 0, face = "Bottom" },
			sparkles = { 255, 214, 120 }, -- a few fireflies round the lantern
		})
		post(ctx, "LanternCap", 0.22, 0.08, { lx, RH - 1.59, lz }, deco({ 40, 30, 24 }))
		post(ctx, "Tassel", 0.04, 0.42, { lx, RH - 1.84, lz }, neon(accent))
	end

	-- Big neon sign, hung slightly crooked on chains from a timber beam
	local SH = 2.8
	local SL = math.clamp(3.2 + 1.9 * #text, 6, W - 2.4)
	local signY = RH + 0.5 + 0.9 + SH / 2
	local signZ = front + 0.6
	local beamY = signY + SH / 2 + 0.75
	for _, sx in { -1, 1 } do
		plank("SignPost", { 0.32, beamY + 0.16 - (RH + 0.5), 0.32 }, { sx * (SL / 2 + 0.3), (beamY + 0.16 + RH + 0.5) / 2, signZ }, 0.4, TIMBER)
	end
	plank("SignBeam", { SL + 1.1, 0.32, 0.32 }, { 0, beamY, signZ }, 0.3, TIMBER)
	local tilt = rotZ(if kind == "sell" then -1.3 else 1.5)
	local function onSign(offset: Vec): Vec
		local o = apply(tilt, offset)
		return { o[1], signY + o[2], signZ + o[3] }
	end
	for _, sx in { -1, 1 } do
		local hook = onSign({ sx * (SL / 2 - 1.6), SH / 2 + 0.05, 0 })
		rod(ctx, "Chain", { hook[1], beamY - 0.16, signZ }, hook, 0.05, { color = { 70, 70, 74 }, material = "Metal", solid = false })
	end
	ctx.group = "Sign"
	add(ctx, "box", "SignFace", { SL - SH, SH, 0.6 }, onSign({ 0, 0, 0 }), tilt, {
		color = { 34, 26, 22 },
		material = "Wood",
		light = { kind = "spot", color = accent, brightness = 1.6, range = 16, angle = 110, face = "Front" },
		gui = gui("sign", accent, { text = text, twoSided = true }),
	})
	add(ctx, "box", "SignRim", { SL - SH, SH + 0.36, 0.3 }, onSign({ 0, 0, 0.3 }), tilt, neon(accent))
	for _, sx in { -1, 1 } do
		-- a hair thinner than the face, so the round ends never flicker through the letters
		add(ctx, "cyl", "SignEnd", { 0.56, SH, SH }, onSign({ sx * (SL - SH) / 2, 0, 0 }), mul(tilt, rotY(90)), { color = { 34, 26, 22 }, material = "Wood" })
		add(ctx, "cyl", "SignRim", { 0.3, SH + 0.36, SH + 0.36 }, onSign({ sx * (SL - SH) / 2, 0, 0.3 }), mul(tilt, rotY(90)), neon(accent))
	end
	motion("Sign", "flicker", { 0, signY, signZ }, 0, 0, 0, 0)

	-- The neon's transformer box on the beam, with its cable down to the sign
	ctx.group = "Roof"
	local boxX = SL / 2 - 0.9
	box(ctx, "Transformer", { 0.55, 0.38, 0.3 }, { boxX, beamY + 0.35, signZ + 0.05 }, { color = { 52, 54, 58 }, material = "Metal", solid = false })
	rod(ctx, "NeonCable", { boxX, beamY + 0.2, signZ + 0.2 }, onSign({ boxX - 0.2, SH / 2, 0.4 }), 0.03, deco({ 20, 20, 20 }))

	-- Bunting from the beam ends down to the front corners of the roof
	if s.Bunting ~= false then
		local flags: { RGB } = { accent, { 244, 232, 204 }, { 246, 196, 80 }, mix(accent, WHITE, 0.55) }
		for _, sx in { -1, 1 } do
			local a: Vec = { sx * (SL / 2 + 0.3), beamY, signZ }
			local b: Vec = { sx * (W / 2 + 0.55), RH + 0.55, front - 1.25 }
			local n = 6
			local last = a
			for i = 1, n do
				local t = i / n
				local p: Vec = { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t - 1.4 * t * (1 - t), a[3] + (b[3] - a[3]) * t }
				rod(ctx, "Bunting", last, p, 0.02, deco({ 230, 220, 200 }))
				if i < n then
					add(ctx, "box", "Flag", { 0.34, 0.34, 0.02 }, { p[1], p[2] - 0.25, p[3] }, mul(rotY(sx * 35), rotZ(45 + jit(8))), deco(flags[(i - 1) % #flags + 1], "Fabric"))
				end
				last = p
			end
		end
	end

	-- Little neon OPEN sign hanging a bit crooked on the left
	if s.OpenSign ~= false then
		ctx.group = "OpenSign"
		local ox, oy, oz = -(W / 2 - 2.1), FL + 6.5, front + 1.2
		local lean = rotZ(-3)
		add(ctx, "box", "OpenSign", { 2.2, 0.9, 0.12 }, { ox, oy, oz }, lean, {
			color = { 30, 24, 20 },
			material = "Wood",
			solid = false,
			gui = gui("open", { 255, 80, 180 }, { text = "OPEN" }),
		})
		for _, dx in { -0.8, 0.8 } do
			local o = apply(lean, { dx, 0.45, 0 })
			rod(ctx, "Wire", { ox + dx, RH - 0.3, oz }, { ox + o[1], oy + o[2], oz }, 0.02, deco({ 30, 30, 30 }))
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
	-- hand-written cardboard sign leaning on the front
	local card = s.Card or (if kind == "sell" then { "CASH $$", "fair prices!" } else { "FRESH!", "picked today" })
	add(ctx, "box", "CardboardSign", { 1.05, 0.72, 0.03 }, { -1.45, CT + 0.35, zc - 0.25 }, mul(rotX(14), rotZ(jit(5))), {
		color = { 192, 150, 100 },
		material = "Cardboard",
		solid = false,
		gui = gui("card", accent, { lines = card }),
	})
	-- wooden crate of phones at the left end
	local crx, crz, cw2, ch, cd = -(W / 2 - 1.55), zi + 0.3, 1.15, 0.55, 0.8
	plank("Crate", { cw2, 0.06, cd }, { crx, CT + 0.03, crz }, 0.8, nil, false)
	for _, sz in { -1, 1 } do
		for _, k in { 0.25, 0.75 } do
			plank("CrateSlat", { cw2, ch * 0.4, 0.06 }, { crx, CT + ch * k, crz + sz * (cd / 2 - 0.03) }, 1.2, nil, false)
		end
	end
	for _, sx in { -1, 1 } do
		plank("CrateEnd", { 0.06, ch, cd }, { crx + sx * (cw2 / 2 - 0.03), CT + ch / 2, crz }, 1.2, nil, false)
	end
	for k = -1, 1 do
		local c = if kind == "sell" then mix({ 60, 60, 66 }, accent, 0.15 * (k + 1)) else BOX_COLORS[(k + 3) % #BOX_COLORS + 1]
		add(ctx, "box", "CratePhone", { 0.3, 0.62, 0.06 }, { crx + k * 0.3, CT + 0.42, crz + jit(0.1) }, mul(rotZ(jit(9)), rotX(jit(6))), deco(c))
	end

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
			add(ctx, "box", "Cash", { 0.85, 0.19, 0.42 }, { W / 4 + 0.6, by, zi + 0.3 }, rotY(jit(8)), deco({ 86, 156, 96 }))
			add(ctx, "box", "CashBand", { 0.16, 0.2, 0.43 }, { W / 4 + 0.6, by, zi + 0.3 }, rotY(jit(8)), deco({ 236, 234, 222 }))
		end
		box(ctx, "CheckTray", { 1.3, 0.04, 0.9 }, { W / 4 - 1, CT + 0.02, zi + 0.3 }, neon(accent, 0.2))
		add(ctx, "box", "TradeInPhone", { 0.55, 0.06, 1.15 }, { W / 4 - 1, CT + 0.07, zi + 0.3 }, rotY(jit(12)), deco({ 40, 40, 46 }))
	else
		-- turning display phone
		local tx, tz = -W / 4, zi + 0.2
		ctx.group = "Turntable"
		post(ctx, "Turntable", 0.75, 0.1, { tx, CT + 0.05, tz }, { color = { 150, 108, 70 }, material = "Wood", solid = false })
		box(ctx, "DisplayPhone", { 0.62, 1.25, 0.08 }, { tx, CT + 0.73, tz }, {
			color = mix(accent, BLACK, 0.55),
			solid = false,
			gui = gui("screen", accent, { twoSided = false }),
		})
		motion("Turntable", "spin", { tx, CT, tz }, 0.8, 0, 0, 0)
		ctx.group = "Items"
		-- phones on little wooden stands
		for i, dx in { -0.5, 0.5 } do
			local px = W / 4 + dx
			plank("Stand", { 0.62, 0.08, 0.6 }, { px, CT + 0.04, zi + 0.2 }, 0.8, nil, false)
			add(ctx, "box", "DisplayPhone", { 0.58, 1.2, 0.07 }, { px, CT + 0.67, zi + 0.3 }, mul(rotX(15), rotZ(jit(3))), {
				color = if i == 1 then { 236, 236, 232 } else { 28, 28, 32 },
				solid = false,
				gui = gui("screen", accent),
			})
		end
		-- kraft paper bag with string handles at the end of the counter
		local bx = W / 2 - 1.6
		add(ctx, "box", "Bag", { 0.8, 0.95, 0.36 }, { bx, CT + 0.475, zi + 0.45 }, rotY(jit(8)), { color = { 196, 158, 110 }, material = "Cardboard", solid = false })
		for _, dx in { -0.2, 0.2 } do
			box(ctx, "BagHandle", { 0.04, 0.3, 0.04 }, { bx + dx, CT + 1.1, zi + 0.45 }, deco(accent))
		end
		box(ctx, "BagHandle", { 0.44, 0.04, 0.04 }, { bx, CT + 1.25, zi + 0.45 }, deco(accent))
	end

	------------------------------------------------------------------ painted signs and chalkboard
	ctx.group = "Signs"
	local poster = s.Poster or { if kind == "sell" then "CASH FOR PHONES" else "NEW PHONES", if kind == "sell" then "Any phone, paid on the spot" else "Fresh from the farm every day" }
	for _, sx in { -1, 1 } do
		add(ctx, "box", "PaintedSign", { 0.1, 2.4, 3.8 }, { sx * (W / 2 - 0.1), FL + 1.75, 0.6 }, rotX(jit(1.5)), {
			color = { 176, 132, 86 },
			material = "Wood",
			gui = gui("poster", accent, { lines = poster, face = if sx > 0 then "Right" else "Left", icon = icon }),
		})
	end
	local bx, bz = -(W / 2 - 1.3), front - 2.3
	local boardLines = s.Board or { "OPEN", if kind == "sell" then "We buy phones" else "Phones in stock", "Come on in!" }
	local turn = rotY(jit(8))
	add(ctx, "box", "Chalkboard", { 1.7, 2.5, 0.08 }, { bx, 1.22, bz - 0.26 }, mul(turn, rotX(12)), {
		color = { 120, 86, 56 },
		material = "Wood",
		gui = gui("board", accent, { lines = boardLines }),
	})
	add(ctx, "box", "ChalkboardBack", { 1.7, 2.5, 0.08 }, { bx, 1.22, bz + 0.26 }, mul(turn, rotX(-12)), { color = { 120, 86, 56 }, material = "Wood" })

	------------------------------------------------------------------ terracotta pots
	if s.Plants ~= false then
		ctx.group = "Plants"
		local terracotta: Props = { color = { 178, 98, 64 }, material = "Sandstone" }
		for _, sx in { -1, 1 } do
			local px, pz = sx * (W / 2 + 0.95), front + 0.9
			post(ctx, "Pot", 0.48, 1.05, { px, 0.525, pz }, terracotta)
			post(ctx, "PotRim", 0.56, 0.18, { px, 1.05, pz }, terracotta)
			post(ctx, "Soil", 0.46, 0.04, { px, 1.12, pz }, deco({ 58, 42, 30 }, "Ground"))
			for k = 1, 4 do
				ball(ctx, "Leaves", 0.45 + rand() * 0.3, { px + jit(0.35), 1.6 + rand() * 0.6, pz + jit(0.35) }, { color = mix({ 52, 86, 46 }, { 82, 120, 62 }, rand()), material = "LeafyGrass" })
			end
			for k = 1, 3 do
				ball(ctx, "Flower", 0.1, { px + jit(0.5), 2 + rand() * 0.5, pz - 0.3 + jit(0.2) }, deco(if k == 2 then { 255, 214, 90 } else { 246, 140, 170 }))
			end
		end
	end

	------------------------------------------------------------------ hanging rope planter
	if s.Plants ~= false then
		ctx.group = "Plants"
		local hx, hy, hz = W / 2 - 1.4, RH - 2.5, front + 1.5
		for k = 0, 2 do
			local a = math.rad(90 + k * 120)
			rod(ctx, "Rope", { hx, RH - 0.3, hz }, { hx + math.cos(a) * 0.3, hy + 0.17, hz + math.sin(a) * 0.3 }, 0.02, deco({ 226, 210, 180 }, "Fabric"))
		end
		post(ctx, "HangingPot", 0.32, 0.36, { hx, hy, hz }, { color = { 178, 98, 64 }, material = "Sandstone", solid = false })
		ball(ctx, "Leaves", 0.36, { hx, hy + 0.3, hz }, deco({ 66, 112, 60 }, "LeafyGrass"))
		for _, t in { { 0.26, -0.28, 0.16 }, { 0.32, -0.62, 0.13 }, { -0.22, -0.4, 0.14 }, { -0.1, -0.75, 0.11 } } do
			ball(ctx, "Trailing", t[3], { hx + t[1], hy + t[2], hz - 0.15 }, deco({ 74, 124, 64 }, "LeafyGrass"))
		end
	end

	------------------------------------------------------------------ crates, a sack and a sleeping cat beside the stall
	if s.Props ~= false then
		ctx.group = "Props"
		local px, pz = W / 2 + 1.25, back - 1.5
		local function crateBox(cx: number, cy: number, cz: number, w: number, h: number, d: number, turn: number)
			local r = mul(rotY(turn), wobble(0.6))
			add(ctx, "box", "Crate", { w, h, d }, { cx, cy + h / 2, cz }, r, { color = wood(), material = "WoodPlanks" })
			for _, side in { -1, 1 } do
				for _, k in { 0.3, 0.7 } do
					local o = apply(r, { 0, -h / 2 + h * k, side * (d / 2 + 0.03) })
					add(ctx, "box", "CrateSlat", { w + 0.04, h * 0.18, 0.06 }, { cx + o[1], cy + h / 2 + o[2], cz + o[3] }, r, { color = DARK_WOOD, material = "Wood" })
				end
			end
		end
		crateBox(px, 0, pz, 1.5, 1.1, 1.2, jit(6))
		crateBox(px + jit(0.1), 1.1, pz + 0.05, 1.15, 0.85, 0.95, 12 + jit(6))
		ball(ctx, "Sack", 0.55, { px - 0.1, 0.5, pz - 1.05 }, { color = { 196, 168, 120 }, material = "Fabric" })
		ball(ctx, "SackTop", 0.3, { px - 0.1, 1.02, pz - 1.0 }, { color = { 186, 158, 112 }, material = "Fabric", solid = false })

		local cat = s.Cat
		if cat == nil then
			cat = if kind == "sell" then "black" else "ginger"
		end
		if cat then
			ctx.group = "Cat"
			local fur: RGB = if cat == "black" then { 34, 32, 34 } elseif cat == "white" then { 236, 232, 226 } else { 212, 128, 58 }
			local furProps: Props = { color = fur, material = "Fabric", solid = false }
			local cy = 1.1 + 0.85
			ball(ctx, "CatBody", 0.36, { px, cy + 0.26, pz }, furProps)
			ball(ctx, "CatHead", 0.22, { px - 0.12, cy + 0.22, pz - 0.32 }, furProps)
			for _, ex in { -0.22, -0.02 } do
				add(ctx, "box", "CatEar", { 0.12, 0.12, 0.04 }, { px + ex, cy + 0.4, pz - 0.33 }, rotZ(45), furProps)
			end
			local eye: RGB = if cat == "black" then { 120, 110, 90 } else { 40, 30, 26 }
			for _, ex in { -0.2, -0.04 } do
				box(ctx, "CatEye", { 0.08, 0.015, 0.02 }, { px + ex, cy + 0.24, pz - 0.53 }, deco(eye))
			end
			rod(ctx, "CatTail", { px + 0.28, cy + 0.06, pz + 0.05 }, { px + 0.22, cy + 0.04, pz - 0.3 }, 0.06, furProps)
			rod(ctx, "CatTail", { px + 0.22, cy + 0.04, pz - 0.3 }, { px + 0.02, cy + 0.04, pz - 0.48 }, 0.055, furProps)
			motion("Cat", "spin", { px, cy, pz }, 0, 0.02, 0, 0) -- no turning, just breathing
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
	motion("PadGlow", "breathe", { padX, 0, padZ }, 0, 0, 0.82, 0.95, R)

	ctx.group = "Token"
	local ty = 4.4
	disc(ctx, "Token", 0.8, 0.22, { padX, ty, padZ }, {
		color = { 16, 16, 20 },
		solid = false,
		light = { kind = "point", color = accent, brightness = 1.2, range = 10, angle = 0, face = "Front" },
		sparkles = mix(accent, WHITE, 0.4),
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
