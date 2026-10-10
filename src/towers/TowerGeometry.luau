--!strict
--[[
	TowerGeometry  (ModuleScript, child of PhoneTowers)

	Pure math: turns one entry from TowerConfig into a list of simple
	shapes (boxes, wedges, cylinders and balls) plus the lights and signs
	that go on them. PhoneTowers turns that list into Roblox parts.

	Native size is about 340 studs tall. The tower stands on y = 0, is
	centred on x = 0, z = 0 and its entrance faces -Z, so the model's
	LookVector points out of the front door.
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

export type Sign = {
	text: string,
	logo: string,
	color: RGB, -- letters
	glow: RGB, -- halo around the letters
	face: string, -- "Front" or "Back"
}

export type Prim = {
	kind: string, -- "box", "wedge", "cyl" (round ends on its own X axis) or "ball"
	name: string,
	group: string, -- folder inside the model
	size: Vec,
	pos: Vec,
	rot: Mat,
	color: RGB,
	material: string,
	reflectance: number,
	transparency: number,
	solid: boolean, -- players bump into it
	shadow: boolean,
	tag: string?, -- "Room" (office light), "Lamp" (only on at night) or "Beacon" (blinks red)
	room: string?, -- Room parts that switch on and off together share this id
	dayColor: RGB?, -- Room and Lamp parts: colour while the lights are off
	light: Light?,
	sign: Sign?,
}

export type Tower = { -- one entry in TowerConfig
	Name: string?,
	Sign: string?,
	Logo: string?,
	Seed: number?,
	Glass: RGB?,
	Accent: RGB?,
	TopAccent: RGB?,
	TopRooms: RGB?,
	LowerFloors: number?,
	UpperFloors: number?,
	Plaza: boolean?,
}

export type Result = { prims: { Prim }, height: number }

local TowerGeometry = {}

--------------------------------------------------------------------------
-- Tiny 3D math
--------------------------------------------------------------------------

local IDENTITY: Mat = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

local function rotY(deg: number): Mat
	local c, s = math.cos(math.rad(deg)), math.sin(math.rad(deg))
	return { c, 0, s, 0, 1, 0, -s, 0, c }
end

local function rotZ(deg: number): Mat
	local c, s = math.cos(math.rad(deg)), math.sin(math.rad(deg))
	return { c, -s, 0, s, c, 0, 0, 0, 1 }
end

local function sub(a: Vec, b: Vec): Vec
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end

local function cross(a: Vec, b: Vec): Vec
	return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end

local function unit(a: Vec): Vec
	local l = math.sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3])
	return { a[1] / l, a[2] / l, a[3] / l }
end

local function mix(a: RGB, b: RGB, t: number): RGB
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
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
	tag: string?,
	room: string?,
	dayColor: RGB?,
	light: Light?,
	sign: Sign?,
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
		tag = p.tag,
		room = p.room,
		dayColor = p.dayColor,
		light = p.light,
		sign = p.sign,
	})
end

local function box(ctx: Ctx, name: string, size: Vec, pos: Vec, p: Props)
	add(ctx, "box", name, size, pos, IDENTITY, p)
end

-- Upright cylinder (round ends facing up and down).
local function post(ctx: Ctx, name: string, radius: number, height: number, pos: Vec, p: Props)
	add(ctx, "cyl", name, { height, radius * 2, radius * 2 }, pos, rotZ(90), p)
end

local function ball(ctx: Ctx, name: string, radius: number, pos: Vec, p: Props)
	add(ctx, "ball", name, { radius * 2, radius * 2, radius * 2 }, pos, IDENTITY, p)
end

-- Cylinder running from point a to point b.
local function rod(ctx: Ctx, name: string, a: Vec, b: Vec, radius: number, p: Props)
	local d = sub(b, a)
	local len = math.sqrt(d[1] * d[1] + d[2] * d[2] + d[3] * d[3])
	local x = unit(d)
	local up: Vec = if math.abs(x[2]) > 0.99 then { 1, 0, 0 } else { 0, 1, 0 }
	local z = unit(cross(x, up))
	local y = cross(z, x)
	local mid = { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2 }
	add(ctx, "cyl", name, { len, radius * 2, radius * 2 }, mid, { x[1], y[1], z[1], x[2], y[2], z[2], x[3], y[3], z[3] }, p)
end

--------------------------------------------------------------------------
-- Palette
--------------------------------------------------------------------------

local MULLION: Props = { color = { 172, 166, 154 }, material = "Metal" }
local SLAB_BAND: Props = { color = { 52, 56, 63 }, material = "Metal" }
local DARK_METAL: Props = { color = { 46, 50, 56 }, material = "Metal" }
local CORE: Props = { color = { 15, 16, 19 }, solid = false, shadow = false }
local STONE: Props = { color = { 132, 127, 120 }, material = "Granite" }
local STONE_BAND: Props = { color = { 88, 86, 82 }, material = "Slate" }
local RAIL_GLASS: Props = { color = { 190, 210, 220 }, material = "Glass", transparency = 0.7, reflectance = 0.1 }

local ROOM_DAY: RGB = { 38, 39, 42 }
local STRIP_DAY: RGB = { 64, 65, 68 }
local LAMP_DAY: RGB = { 175, 175, 170 }
local WARM: RGB = { 255, 214, 165 }
local BEACON: Props = { color = { 255, 28, 18 }, material = "Neon", tag = "Beacon", solid = false, shadow = false }

local function neon(color: RGB): Props
	return { color = color, material = "Neon", solid = false, shadow = false }
end

local function lamp(color: RGB, light: Light?): Props
	return { color = color, material = "Neon", tag = "Lamp", dayColor = LAMP_DAY, solid = false, shadow = false, light = light }
end

local function spot(color: RGB, brightness: number, range: number, angle: number, face: string): Light
	return { kind = "spot", color = color, brightness = brightness, range = range, angle = angle, face = face }
end

--------------------------------------------------------------------------
-- Curtain walls: glass, mullions, floor slabs and lit offices behind
--------------------------------------------------------------------------

local FLOOR = 12
local SLAB = 1.4

type Face = { name: string, n: number, side: boolean }

-- n is which way the face points along its axis (-1 or 1).
local FACES: { Face } = {
	{ name = "Front", n = -1, side = false },
	{ name = "Back", n = 1, side = false },
	{ name = "Left", n = -1, side = true },
	{ name = "Right", n = 1, side = true },
}

-- A point on a face of a w x d box: u runs along the face, depth runs
-- inwards from the glass (negative depth sticks out).
local function onFace(f: Face, w: number, d: number, u: number, y: number, depth: number): Vec
	if f.side then
		return { f.n * (w / 2 - depth), y, u }
	end
	return { u, y, f.n * (d / 2 - depth) }
end

local function faceSize(f: Face, along: number, h: number, thick: number): Vec
	if f.side then
		return { thick, h, along }
	end
	return { along, h, thick }
end

local function halfLength(f: Face, w: number, d: number): number
	return if f.side then d / 2 else w / 2
end

type Rooms = {
	walls: { RGB }, -- back-wall glow colours, one picked per floor
	strips: { RGB }, -- the matching ceiling lights
	busy: number, -- 0..1, how many offices are lit on a normal floor
}

type Section = {
	id: string,
	w: number,
	d: number,
	y0: number,
	floors: number,
	bay: number, -- target window width
	inset: number, -- distance from the glass to the dark core
	glass: RGB,
	accent: RGB?,
	rooms: Rooms,
	faces: { Face }?,
}

local function office(ctx: Ctx, s: Section, f: Face, u0: number, u1: number, floorY: number, ceilY: number, wall: RGB, strip: RGB, id: string, rand: () -> number)
	local len = u1 - u0
	local u = (u0 + u1) / 2
	local h = ceilY - floorY
	box(ctx, "Office", faceSize(f, len - 0.3, h - 0.1, 0.2), onFace(f, s.w, s.d, u, floorY + h / 2, s.inset - 0.1), {
		color = wall,
		material = "Neon",
		tag = "Room",
		room = id,
		dayColor = ROOM_DAY,
		solid = false,
		shadow = false,
	})
	box(ctx, "CeilingLight", faceSize(f, len - 0.8, 0.16, 0.8), onFace(f, s.w, s.d, u, ceilY - 0.08, 2.4), {
		color = strip,
		material = "Neon",
		tag = "Room",
		room = id,
		dayColor = STRIP_DAY,
		solid = false,
		shadow = false,
	})
	if rand() < 0.7 then
		box(ctx, "Desks", faceSize(f, len - 0.6, 2.4, 1), onFace(f, s.w, s.d, u, floorY + 1.2, 3.6), { color = { 14, 14, 16 }, solid = false, shadow = false })
	end
	if rand() < 0.3 then
		local bh = 2 + rand() * 5
		box(ctx, "Blinds", faceSize(f, len - 0.3, bh, 0.08), onFace(f, s.w, s.d, u, ceilY - bh / 2, 0.5), { color = { 196, 192, 184 }, solid = false, shadow = false })
	end
end

local function offices(ctx: Ctx, s: Section, fl: number, floorY: number, ceilY: number, rand: () -> number)
	local pick = math.floor(rand() * #s.rooms.walls) + 1
	local wall, strip = s.rooms.walls[pick], s.rooms.strips[pick]
	local mood = rand()
	local chance = if mood < 0.2 then 0.95 elseif mood < 0.65 then s.rooms.busy else 0.08
	for _, f in s.faces or FACES do
		local half = halfLength(f, s.w, s.d)
		local n = math.max(2, math.floor(2 * half / s.bay + 0.5))
		local bw = 2 * half / n
		local lit = table.create(n, false)
		local on = rand() < chance
		for k = 1, n do
			if rand() < 0.35 then
				on = rand() < chance
			end
			lit[k] = on
		end
		local k = 1
		while k <= n do
			if lit[k] then
				local j = k
				while j < n and lit[j + 1] do
					j += 1
				end
				office(ctx, s, f, -half + (k - 1) * bw, -half + j * bw, floorY, ceilY, wall, strip, `{s.id}{fl}{f.name}{k}`, rand)
				k = j + 1
			else
				k += 1
			end
		end
	end
end

local function curtainWall(ctx: Ctx, s: Section, rand: () -> number)
	local H = s.floors * FLOOR
	local mid = s.y0 + H / 2

	box(ctx, "Core", { s.w - 2 * s.inset, H - 0.2, s.d - 2 * s.inset }, { 0, mid, 0 }, CORE)

	for _, f in FACES do
		local half = halfLength(f, s.w, s.d)
		box(ctx, f.name .. "Glass", faceSize(f, 2 * half, H, 0.3), onFace(f, s.w, s.d, 0, mid, 0), {
			color = s.glass,
			material = "Glass",
			transparency = 0.42,
			reflectance = 0.18,
		})
		local n = math.max(2, math.floor(2 * half / s.bay + 0.5))
		for k = 1, n - 1 do
			local u = -half + k * (2 * half / n)
			box(ctx, "Mullion", faceSize(f, 0.35, H, 0.9), onFace(f, s.w, s.d, u, mid, -0.3), MULLION)
		end
	end

	for i = 0, s.floors do
		box(ctx, "FloorEdge", { s.w + 0.6, SLAB, s.d + 0.6 }, { 0, s.y0 + i * FLOOR, 0 }, SLAB_BAND)
	end

	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(ctx, "CornerColumn", { 1.6, H, 1.6 }, { sx * s.w / 2, mid, sz * s.d / 2 }, DARK_METAL)
			if s.accent then
				box(ctx, "CornerLight", { 0.5, H, 0.5 }, { sx * (s.w / 2 + 0.85), mid, sz * (s.d / 2 + 0.85) }, neon(s.accent))
			end
		end
	end

	for fl = 0, s.floors - 1 do
		offices(ctx, s, fl, s.y0 + fl * FLOOR + SLAB / 2, s.y0 + (fl + 1) * FLOOR - SLAB / 2, rand)
	end
end

--------------------------------------------------------------------------
-- The pieces of a tower, bottom to top
--------------------------------------------------------------------------

local PODIUM_H = 42 -- podium roof
local TOP_W = 62 -- podium width at the roof
local BASE_W = 112 -- podium width at the ground
local PODIUM_D = 64
local LOBBY = 1.6 -- lobby floor height
local MEZZ = 24 -- second floor height
local DOOR_TOP = 11

local W1, D1 = 52, 44 -- lower tower
local W2, D2 = 40, 34 -- upper tower
local MECH = 10 -- plant floor between them
local CROWN = 16
local OVER = 1.4 -- how far the crown sticks out

local OFFICE_ROOMS: Rooms = {
	walls = { { 200, 156, 104 }, { 176, 168, 148 }, { 132, 150, 172 }, { 196, 160, 116 } },
	strips = { { 255, 232, 196 }, { 245, 244, 232 }, { 222, 236, 255 }, { 255, 236, 205 } },
	busy = 0.45,
}

local function plaza(ctx: Ctx, t: Tower)
	ctx.group = "Plaza"
	local paving: Props = { color = { 150, 148, 142 }, material = "Pavement" }
	box(ctx, "Paving", { 150, 0.4, 124 }, { 0, 0.2, -8 }, paving)
	box(ctx, "Walkway", { 22, 0.06, 30 }, { 0, 0.43, -55 }, { color = { 82, 82, 84 }, material = "Slate" })

	for i = 1, 3 do
		local depth = (4 - i) * 2.2
		box(ctx, "Step", { 32, i * 0.4, depth }, { 0, 0.4 + i * 0.2, -PODIUM_D / 2 - depth / 2 }, { color = { 160, 156, 150 }, material = "Granite" })
	end

	-- Trees in stone planters
	local leaves = { { 52, 82, 46 }, { 60, 90, 50 }, { 46, 74, 42 } }
	for i, x in { -62, -20, 20, 62 } do
		local z = -50
		box(ctx, "Planter", { 8, 2, 8 }, { x, 1.4, z }, { color = { 128, 126, 120 }, material = "Concrete" })
		box(ctx, "Soil", { 7.2, 0.1, 7.2 }, { x, 2.45, z }, { color = { 52, 40, 30 }, material = "Ground" })
		post(ctx, "Trunk", 0.5, 10, { x, 7.4, z }, { color = { 78, 58, 42 }, material = "Wood" })
		local leaf = leaves[(i - 1) % #leaves + 1]
		local p: Props = { color = leaf, material = "LeafyGrass" }
		ball(ctx, "Leaves", 4.5, { x, 13, z }, p)
		ball(ctx, "Leaves", 3.6, { x + 2.2, 11.4, z + 1 }, p)
		ball(ctx, "Leaves", 3.2, { x - 2.2, 12, z - 1.5 }, p)
	end

	-- Monument sign on the left, low hedge on the right
	box(ctx, "MonumentSign", { 16, 4.6, 2 }, { -41, 2.7, -60 }, {
		color = { 34, 35, 38 },
		material = "Slate",
		sign = { text = t.Sign or "PHONES", logo = t.Logo or "none", color = { 255, 255, 255 }, glow = t.Accent or { 40, 220, 255 }, face = "Front" },
	})
	box(ctx, "HedgePlanter", { 16, 1.8, 4 }, { 41, 1.3, -60 }, { color = { 128, 126, 120 }, material = "Concrete" })
	box(ctx, "Hedge", { 15.2, 1.8, 3.2 }, { 41, 3.1, -60 }, { color = { 50, 80, 44 }, material = "LeafyGrass" })

	-- Street lamps
	for _, x in { -52, -32, 32, 52 } do
		local z = -66
		post(ctx, "LampPost", 0.35, 18, { x, 9.4, z }, DARK_METAL)
		box(ctx, "LampArm", { 0.35, 0.35, 3.6 }, { x, 18.2, z + 1.6 }, DARK_METAL)
		box(ctx, "LampHead", { 1.4, 0.5, 2.6 }, { x, 18, z + 3.2 }, DARK_METAL)
		box(ctx, "LampGlow", { 1.1, 0.1, 2.2 }, { x, 17.72, z + 3.2 }, lamp(WARM, spot(WARM, 2.2, 34, 80, "Bottom")))
	end

	-- Bollards along the front
	for i = 0, 5 do
		local x = -9 + i * 3.6
		post(ctx, "Bollard", 0.4, 2.4, { x, 1.6, -68 }, DARK_METAL)
		post(ctx, "BollardLight", 0.32, 0.25, { x, 2.9, -68 }, lamp({ 240, 240, 230 }))
	end
end

local function podium(ctx: Ctx, t: Tower, accent: RGB, rand: () -> number)
	ctx.group = "Podium"
	local front = -PODIUM_D / 2
	local side = (BASE_W - TOP_W) / 2

	box(ctx, "LobbyFloor", { TOP_W - 0.5, 1.2, PODIUM_D - 0.5 }, { 0, LOBBY - 0.6, 0 }, { color = { 226, 222, 214 }, material = "Marble", reflectance = 0.08 })

	-- Sloped stone sides
	for _, sx in { -1, 1 } do
		add(ctx, "wedge", "StoneSide", { PODIUM_D, PODIUM_H, side }, { sx * (TOP_W / 2 + side / 2), PODIUM_H / 2, 0 }, rotY(sx * -90), STONE)
		for y = 7, 35, 7 do
			local x = BASE_W / 2 - side * (y / PODIUM_H)
			box(ctx, "StoneLine", { 0.6, 0.6, PODIUM_D + 0.4 }, { sx * x, y, 0 }, STONE_BAND)
		end
		-- Uplight washing the stone
		box(ctx, "Uplight", { 1.6, 0.6, 1.6 }, { sx * 43, 0.7, front - 3 }, {
			color = { 40, 42, 46 },
			material = "Metal",
			tag = "Lamp",
			dayColor = { 40, 42, 46 },
			light = spot({ 255, 236, 210 }, 2.5, 50, 50, "Top"),
		})
	end

	local glass: Props = { color = t.Glass or { 34, 46, 62 }, material = "Glass", transparency = 0.38, reflectance = 0.15 }
	local zf, zb = front + 0.4, -front - 0.4
	local glassH = PODIUM_H - 1.2 - LOBBY

	-- Front: glass either side of the entrance and above it
	local doorHalf = TOP_W / 10
	local sideW = TOP_W / 2 - doorHalf
	for _, sx in { -1, 1 } do
		box(ctx, "FrontGlass", { sideW, glassH, 0.3 }, { sx * (doorHalf + sideW / 2), LOBBY + glassH / 2, zf }, glass)
		box(ctx, "DoorGlass", { doorHalf - 4.2, DOOR_TOP - LOBBY, 0.3 }, { sx * (4.2 + (doorHalf - 4.2) / 2), (LOBBY + DOOR_TOP) / 2, zf }, glass)
	end
	box(ctx, "FrontGlass", { doorHalf * 2, PODIUM_H - 1.2 - DOOR_TOP, 0.3 }, { 0, (DOOR_TOP + PODIUM_H - 1.2) / 2, zf }, glass)
	box(ctx, "BackGlass", { TOP_W, glassH, 0.3 }, { 0, LOBBY + glassH / 2, zb }, glass)

	-- Mullions, transoms and bands on both glass faces
	for _, z in { zf, zb } do
		local out = if z < 0 then -0.4 else 0.4
		for k = 1, 9 do
			local x = -TOP_W / 2 + k * TOP_W / 10
			if k == 5 and z < 0 then
				box(ctx, "Mullion", { 0.45, PODIUM_H - 1.2 - DOOR_TOP, 0.8 }, { x, (DOOR_TOP + PODIUM_H - 1.2) / 2, z + out }, MULLION)
			else
				box(ctx, "Mullion", { 0.45, glassH, 0.8 }, { x, LOBBY + glassH / 2, z + out }, MULLION)
			end
		end
		for _, sx in { -1, 1 } do
			box(ctx, "Jamb", { 1, glassH, 1 }, { sx * (TOP_W / 2 - 0.3), LOBBY + glassH / 2, z + out }, DARK_METAL)
		end
		box(ctx, "Transom", { TOP_W, 0.6, 0.9 }, { 0, DOOR_TOP, z + out }, MULLION)
		box(ctx, "Transom", { TOP_W, 0.35, 0.7 }, { 0, 32.5, z + out }, MULLION)
		box(ctx, "FloorEdge", { TOP_W, 1.6, 1 }, { 0, MEZZ - 0.7, z + out }, SLAB_BAND)
		box(ctx, "Fascia", { TOP_W + 0.4, 2.4, 1 }, { 0, PODIUM_H - 1.4, z + out * 1.2 }, DARK_METAL)
	end

	-- Revolving door and side doors
	local door = { 0, (LOBBY + DOOR_TOP) / 2, zf }
	post(ctx, "RevolvingDoor", 4.2, DOOR_TOP - LOBBY, door, { color = { 200, 220, 230 }, material = "Glass", transparency = 0.7, solid = false })
	post(ctx, "DoorDrum", 4.5, 0.8, { 0, DOOR_TOP + 0.3, zf }, DARK_METAL)
	for _, a in { 45, -45 } do
		add(ctx, "box", "DoorWing", { 8.2, DOOR_TOP - LOBBY - 0.4, 0.12 }, door, rotY(a), { color = { 200, 220, 230 }, material = "Glass", transparency = 0.5, solid = false })
	end
	for _, sx in { -1, 1 } do
		local x = sx * (doorHalf + TOP_W / 20)
		box(ctx, "DoorFrame", { 0.25, DOOR_TOP - LOBBY, 0.6 }, { x, (LOBBY + DOOR_TOP) / 2, zf - 0.2 }, DARK_METAL)
		for _, dx in { -0.45, 0.45 } do
			box(ctx, "DoorHandle", { 0.2, 3.2, 0.3 }, { x + dx, LOBBY + 4, zf - 0.35 }, MULLION)
		end
	end

	-- Entrance canopy with tension rods, downlights and the main sign
	local canopyZ = front - 5.6
	box(ctx, "Canopy", { 28, 0.9, 11 }, { 0, 13.6, canopyZ }, {
		color = { 52, 55, 60 },
		material = "Metal",
		light = spot(WARM, 3, 22, 100, "Bottom"),
	})
	for _, x in { -9, -3, 3, 9 } do
		for _, dz in { -2.5, 2.5 } do
			post(ctx, "Downlight", 0.45, 0.1, { x, 13.12, canopyZ + dz }, lamp(WARM))
		end
	end
	for _, x in { -13.5, 13.5 } do
		rod(ctx, "CanopyRod", { x, 14, front - 10.8 }, { x, 22, front - 0.6 }, 0.14, MULLION)
	end
	box(ctx, "Sign", { 26, 4.6, 0.6 }, { 0, 18.2, front - 0.6 }, {
		color = { 24, 25, 28 },
		material = "Metal",
		sign = { text = t.Sign or "PHONES", logo = t.Logo or "none", color = { 255, 255, 255 }, glow = accent, face = "Front" },
	})

	-- Lobby inside
	box(ctx, "SecondFloor", { TOP_W - 0.5, SLAB, PODIUM_D - 0.6 }, { 0, MEZZ - 0.7, 0 }, { color = { 70, 70, 72 }, material = "Concrete" })
	box(ctx, "Roof", { TOP_W, 1.2, PODIUM_D }, { 0, PODIUM_H - 0.6, 0 }, { color = { 92, 92, 90 }, material = "Concrete" })
	box(ctx, "FeatureWall", { 24, MEZZ - LOBBY - 1.4, 14 }, { 0, (LOBBY + MEZZ - 1.4) / 2, 12 }, { color = { 92, 64, 44 }, material = "Wood" })
	box(ctx, "LobbySign", { 14, 3.6, 0.2 }, { 0, 14, 4.9 }, {
		color = { 30, 30, 32 },
		material = "Metal",
		solid = false,
		sign = { text = t.Sign or "PHONES", logo = t.Logo or "none", color = { 255, 240, 220 }, glow = accent, face = "Front" },
	})
	box(ctx, "Reception", { 14, 3.4, 3 }, { 0, LOBBY + 1.7, -2 }, { color = { 236, 232, 226 }, material = "Marble" })
	box(ctx, "ReceptionTop", { 14.6, 0.3, 3.4 }, { 0, LOBBY + 3.55, -2 }, { color = { 92, 64, 44 }, material = "Wood" })
	box(ctx, "ReceptionGlow", { 13, 0.2, 0.1 }, { 0, LOBBY + 0.5, -3.55 }, neon(WARM))
	for i, z in { -26, -18, -10, -2 } do
		local light: Light? = if i % 2 == 1 then { kind = "point", color = WARM, brightness = 1.2, range = 40, angle = 0, face = "Bottom" } else nil
		box(ctx, "LobbyLight", { TOP_W - 8, 0.2, 0.9 }, { 0, MEZZ - 1.5, z }, { color = { 255, 240, 220 }, material = "Neon", solid = false, shadow = false, light = light })
	end
	for _, sx in { -1, 1 } do
		post(ctx, "Pot", 1.5, 2.4, { sx * 24, LOBBY + 1.2, -24 }, { color = { 40, 40, 42 }, material = "Slate" })
		ball(ctx, "Plant", 3, { sx * 24, LOBBY + 5.2, -24 }, { color = { 56, 88, 48 }, material = "LeafyGrass" })
	end

	-- Offices on the second floor, front and back
	local back: Props = { color = CORE.color, solid = false, shadow = false }
	for _, sz in { -1, 1 } do
		box(ctx, "OfficeWall", { TOP_W - 2, PODIUM_H - 1.2 - MEZZ, 0.4 }, { 0, (MEZZ + PODIUM_H - 1.2) / 2, sz * (PODIUM_D / 2 - 8) }, back)
	end
	local s: Section = {
		id = "P",
		w = TOP_W,
		d = PODIUM_D - 0.8,
		y0 = MEZZ,
		floors = 1,
		bay = TOP_W / 10,
		inset = 8,
		glass = glass.color,
		rooms = OFFICE_ROOMS,
		faces = { FACES[1], FACES[2] },
	}
	offices(ctx, s, 0, MEZZ, PODIUM_H - 1.2, rand)

	-- Glass railing round the podium roof
	local railY = PODIUM_H + 1.4
	for _, sz in { -1, 1 } do
		box(ctx, "Railing", { TOP_W, 2.6, 0.2 }, { 0, railY, sz * (PODIUM_D / 2 - 0.3) }, RAIL_GLASS)
		box(ctx, "Handrail", { TOP_W + 0.2, 0.25, 0.4 }, { 0, railY + 1.4, sz * (PODIUM_D / 2 - 0.3) }, MULLION)
	end
	for _, sx in { -1, 1 } do
		box(ctx, "Railing", { 0.2, 2.6, PODIUM_D }, { sx * (TOP_W / 2 - 0.3), railY, 0 }, RAIL_GLASS)
		box(ctx, "Handrail", { 0.4, 0.25, PODIUM_D + 0.2 }, { sx * (TOP_W / 2 - 0.3), railY + 1.4, 0 }, MULLION)
		-- Floodlights on the roof that light up the tower's front
		box(ctx, "Floodlight", { 1.6, 0.6, 1.6 }, { sx * 14, PODIUM_H + 0.3, -D1 / 2 - 5 }, {
			color = { 40, 42, 46 },
			material = "Metal",
			tag = "Lamp",
			dayColor = { 40, 42, 46 },
			light = spot({ 214, 230, 255 }, 3, 60, 32, "Top"),
		})
	end
end

local function plantFloor(ctx: Ctx, y: number, accent: RGB)
	ctx.group = "Tower"
	local w, d = W1, D1
	box(ctx, "PlantRoom", { w - 1, MECH, d - 1 }, { 0, y + MECH / 2, 0 }, { color = { 30, 32, 36 }, material = "Metal" })
	for _, f in FACES do
		local half = halfLength(f, w, d)
		for k = 0, 4 do
			box(ctx, "Louver", faceSize(f, 2 * half - 1.6, 0.3, 1.2), onFace(f, w, d, 0, y + 1.6 + k * 1.75, 0.1), { color = { 120, 124, 130 }, material = "Metal" })
		end
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(ctx, "CornerColumn", { 1.6, MECH, 1.6 }, { sx * w / 2, y + MECH / 2, sz * d / 2 }, DARK_METAL)
		end
	end

	local top = y + MECH + 1.2
	box(ctx, "Setback", { w + 2, 1.2, d + 2 }, { 0, y + MECH + 0.6, 0 }, { color = { 64, 68, 76 }, material = "Metal" })
	local led = neon(accent)
	for _, sz in { -1, 1 } do
		box(ctx, "SetbackLight", { w + 2, 0.22, 0.22 }, { 0, y + MECH - 0.11, sz * (d / 2 + 0.89) }, led)
		box(ctx, "Railing", { w + 1.6, 2.6, 0.2 }, { 0, top + 1.3, sz * (d / 2 + 0.7) }, RAIL_GLASS)
		box(ctx, "Handrail", { w + 1.8, 0.25, 0.4 }, { 0, top + 2.7, sz * (d / 2 + 0.7) }, MULLION)
	end
	for _, sx in { -1, 1 } do
		box(ctx, "SetbackLight", { 0.22, 0.22, d + 2 }, { sx * (w / 2 + 0.89), y + MECH - 0.11, 0 }, led)
		box(ctx, "Railing", { 0.2, 2.6, d + 1.6 }, { sx * (w / 2 + 0.7), top + 1.3, 0 }, RAIL_GLASS)
		box(ctx, "Handrail", { 0.4, 0.25, d + 1.8 }, { sx * (w / 2 + 0.7), top + 2.7, 0 }, MULLION)
	end
end

local function crown(ctx: Ctx, t: Tower, y: number, accent: RGB): number
	ctx.group = "Crown"
	local wc, dc = W2 + 2 * OVER, D2 + 2 * OVER

	box(ctx, "CrownBase", { wc, 1.4, dc }, { 0, y + 0.7, 0 }, SLAB_BAND)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(ctx, "CrownPost", { 2, CROWN - 1.4, 2 }, { sx * (wc / 2 - 1), y + 1.4 + (CROWN - 1.4) / 2, sz * (dc / 2 - 1) }, DARK_METAL)
			ball(ctx, "RoofBeacon", 0.5, { sx * (wc / 2 - 0.5), y + CROWN + 0.5, sz * (dc / 2 - 0.5) }, BEACON)
		end
	end
	local led = neon(accent)
	for _, f in FACES do
		local half = halfLength(f, wc, dc)
		for k = 0, 6 do
			box(ctx, "CrownLouver", faceSize(f, 2 * half - 2, 0.35, 1.1), onFace(f, wc, dc, 0, y + 2.6 + k * 1.85, 0.55), { color = { 150, 152, 158 }, material = "Metal" })
		end
		box(ctx, "Coping", faceSize(f, 2 * half + 0.4, 1, 1.4), onFace(f, wc, dc, 0, y + CROWN - 0.5, 0.5), { color = { 70, 74, 82 }, material = "Metal" })
		box(ctx, "CrownLight", faceSize(f, 2 * half, 0.22, 0.22), onFace(f, wc, dc, 0, y + CROWN - 1.11, -0.05), led)
	end

	-- Name near the top, front and back
	for _, sz in { -1, 1 } do
		box(ctx, "CrownSign", { wc - 8, 5.6, 0.3 }, { 0, y + 8, sz * (dc / 2 + 0.35) }, {
			color = { 18, 19, 22 },
			material = "Metal",
			sign = { text = t.Sign or "PHONES", logo = t.Logo or "none", color = { 255, 255, 255 }, glow = accent, face = if sz < 0 then "Front" else "Back" },
		})
	end

	-- Roof machinery behind the louvers
	for _, sx in { -1, 1 } do
		box(ctx, "AirCon", { 9, 4.5, 6 }, { sx * 9.5, y + 1.4 + 2.25, 9 }, { color = { 120, 124, 128 }, material = "Metal" })
		post(ctx, "Fan", 1.8, 0.3, { sx * 9.5, y + 1.4 + 4.6, 9 }, { color = { 40, 42, 46 }, material = "DiamondPlate" })
	end
	local penthouseTop = y + 1.4 + 22
	box(ctx, "Penthouse", { 18, 22, 14 }, { 0, y + 1.4 + 11, 3 }, DARK_METAL)
	box(ctx, "PenthouseCap", { 19, 0.8, 15 }, { 0, penthouseTop + 0.4, 3 }, { color = { 70, 74, 82 }, material = "Metal" })
	return penthouseTop + 0.8
end

local function antenna(ctx: Ctx, y: number): number
	ctx.group = "Antenna"
	local cz = 3
	local paint: Props = { color = { 205, 205, 210 }, material = "Metal" }
	box(ctx, "AntennaBase", { 9, 1.2, 9 }, { 0, y + 0.6, cz }, DARK_METAL)
	local y0 = y + 1.2
	local height, segments, rb, rt = 56, 9, 3.4, 0.9

	local function at(k: number, j: number, push: number?): Vec
		local r = rb + (rt - rb) * (k / segments) + (push or 0)
		local a = math.rad(-90 + 120 * (j % 3))
		return { r * math.cos(a), y0 + height * (k / segments), cz + r * math.sin(a) }
	end

	for j = 0, 2 do
		rod(ctx, "Leg", at(0, j), at(segments, j), 0.32, paint)
		for k = 1, segments do
			rod(ctx, "Brace", at(k, j), at(k, j + 1), 0.14, paint)
		end
		for k = 0, segments - 1 do
			if k % 2 == 0 then
				rod(ctx, "Brace", at(k, j), at(k + 1, j + 1), 0.12, paint)
			else
				rod(ctx, "Brace", at(k, j + 1), at(k + 1, j), 0.12, paint)
			end
		end
		ball(ctx, "Beacon", 0.45, at(5, j, 0.4), BEACON)
	end

	-- Two microwave dishes
	for _, j in { 0, 1 } do
		local inner, outer = at(2, j, 0.6), at(2, j, 1.4)
		rod(ctx, "Dish", inner, outer, 1.3, { color = { 232, 232, 234 } })
	end

	local top = y0 + height
	post(ctx, "Mast", 0.32, 18, { 0, top + 9, cz }, paint)
	post(ctx, "Whip", 0.15, 6, { 0, top + 21, cz }, paint)
	local tip = top + 24
	ball(ctx, "TopBeacon", 0.7, { 0, tip + 0.5, cz }, {
		color = BEACON.color,
		material = "Neon",
		tag = "Beacon",
		solid = false,
		shadow = false,
		light = { kind = "point", color = { 255, 40, 30 }, brightness = 3, range = 24, angle = 0, face = "Top" },
	})
	return tip + 1.2
end

--------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------

function TowerGeometry.Shapes(t: Tower): Result
	local rand = rng(t.Seed or 1)
	local ctx: Ctx = { prims = {}, group = "Plaza" }
	local accent = t.Accent or { 40, 220, 255 }
	local topAccent = t.TopAccent or { 255, 70, 230 }
	local topRooms = t.TopRooms or { 150, 80, 255 }
	local glass = t.Glass or { 34, 46, 62 }
	local lower = math.clamp(math.floor(t.LowerFloors or 10), 2, 40)
	local upper = math.clamp(math.floor(t.UpperFloors or 6), 1, 30)

	if t.Plaza ~= false then
		plaza(ctx, t)
	end
	podium(ctx, t, accent, rand)

	ctx.group = "Tower"
	curtainWall(ctx, {
		id = "L",
		w = W1,
		d = D1,
		y0 = PODIUM_H,
		floors = lower,
		bay = 5.2,
		inset = 6,
		glass = glass,
		accent = accent,
		rooms = OFFICE_ROOMS,
	}, rand)

	local plantY = PODIUM_H + lower * FLOOR
	plantFloor(ctx, plantY, accent)

	local upperY = plantY + MECH + 1.2
	curtainWall(ctx, {
		id = "U",
		w = W2,
		d = D2,
		y0 = upperY,
		floors = upper,
		bay = 5,
		inset = 5,
		glass = mix(glass, { 10, 12, 18 }, 0.25),
		accent = topAccent,
		rooms = {
			walls = { mix(topRooms, { 0, 0, 0 }, 0.25), mix(topRooms, { 255, 200, 255 }, 0.2) },
			strips = { mix(topRooms, { 255, 255, 255 }, 0.6), mix(topRooms, { 255, 255, 255 }, 0.7) },
			busy = 0.75,
		},
	}, rand)

	local roof = crown(ctx, t, upperY + upper * FLOOR, topAccent)
	local height = antenna(ctx, roof)
	return { prims = ctx.prims, height = height }
end

return TowerGeometry
