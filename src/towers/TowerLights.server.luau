--!strict
--[[
	TowerLights  (Script in ServerScriptService; PhoneTowers puts it there)

	Brings the towers to life:
	  * office lights come on at dusk and go off at dawn
	  * during the night a few offices switch their lights on and off
	  * the red aircraft warning lights blink
	  * street lamps, floodlights and canopy lights only shine at night
]]

local ServerScriptService = game:GetService("ServerScriptService")
if script.Parent ~= ServerScriptService then
	return -- only the copy in ServerScriptService runs
end

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local DUSK, DAWN = 17.8, 6.3 -- Lighting.ClockTime
local SWITCH_EVERY = 4 -- seconds between offices switching at night
local DARK_SHARE = 0.12 -- at most this share of offices switched off at once
local BLINK = 1 -- seconds on, then seconds off
local BEACON_ON = Color3.fromRGB(255, 28, 18)
local BEACON_OFF = Color3.fromRGB(70, 12, 10)

local function isNight(): boolean
	local t = Lighting.ClockTime
	return t >= DUSK or t < DAWN
end

local function setLights(part: BasePart, on: boolean)
	for _, child in part:GetChildren() do
		if child:IsA("Light") then
			child.Enabled = on
		end
	end
end

local function setLit(part: BasePart, on: boolean)
	local material = part:GetAttribute("NightMaterial")
	local color = part:GetAttribute(if on then "NightColor" else "DayColor")
	if typeof(color) == "Color3" then
		part.Color = color
	end
	if material == "Neon" then
		part.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
	setLights(part, on)
end

local shown: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local switchedOff: { [string]: boolean } = {}
local random = Random.new()

local function refresh(night: boolean)
	for _, tag in { "TowerRoom", "TowerLamp" } do
		for _, inst in CollectionService:GetTagged(tag) do
			if inst:IsA("BasePart") then
				local room = inst:GetAttribute("Room")
				local on = night and not (type(room) == "string" and switchedOff[room])
				if shown[inst] ~= on then
					shown[inst] = on
					setLit(inst, on)
				end
			end
		end
	end
end

local function flipRandomOffice()
	local ids: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, inst in CollectionService:GetTagged("TowerRoom") do
		local id = inst:GetAttribute("Room")
		if type(id) == "string" and not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end
	if #ids == 0 then
		return
	end
	local id = ids[random:NextInteger(1, #ids)]
	if switchedOff[id] then
		switchedOff[id] = nil
	else
		local off = 0
		for _ in switchedOff do
			off += 1
		end
		if off < #ids * DARK_SHARE then
			switchedOff[id] = true
		end
	end
end

-- Red aircraft lights
task.spawn(function()
	local on = true
	while true do
		for _, inst in CollectionService:GetTagged("TowerBeacon") do
			if inst:IsA("BasePart") then
				inst.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
				inst.Color = if on then BEACON_ON else BEACON_OFF
				setLights(inst, on)
			end
		end
		on = not on
		task.wait(BLINK)
	end
end)

-- Offices, lamps and floodlights
local wasNight: boolean? = nil
while true do
	local night = isNight()
	if night ~= wasNight then
		wasNight = night
		table.clear(switchedOff)
	elseif night then
		flipRandomOffice()
	end
	refresh(night)
	task.wait(SWITCH_EVERY)
end
