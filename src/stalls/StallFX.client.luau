--!strict
--[[
	StallFX  (LocalScript in StarterPlayerScripts; PhoneStalls puts it there)

	Animates the stalls on each player's screen:
	  * the icons above the floor circles spin and float up and down
	  * the display phone on the BUY counter turns on its turntable
	  * the glow round the floor circles fades in and out
	  * the neon signs flicker now and then, like real neon
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

type Spinner = { base: CFrame, speed: number, bob: number, phase: number }

local spinners: { [Model]: Spinner } = {}
local breathers: { [Model]: { low: number, high: number } } = {}
local flickering: { [Model]: number } = {} -- next time each sign flickers

local function number(inst: Instance, name: string, default: number): number
	local v = inst:GetAttribute(name)
	return if type(v) == "number" then v else default
end

local function watch(tag: string, added: (Model) -> (), removed: (Model) -> ())
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsA("Model") then
			added(inst)
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
		if inst:IsA("Model") then
			added(inst)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
		if inst:IsA("Model") then
			removed(inst)
		end
	end)
end

watch("StallSpin", function(m)
	spinners[m] = { base = m:GetPivot(), speed = number(m, "Speed", 1), bob = number(m, "Bob", 0), phase = math.random() * 6 }
end, function(m)
	spinners[m] = nil
end)

watch("StallBreathe", function(m)
	breathers[m] = { low = number(m, "Low", 0.7), high = number(m, "High", 0.9) }
end, function(m)
	breathers[m] = nil
end)

watch("StallFlicker", function(m)
	flickering[m] = os.clock() + 3 + math.random() * 10
end, function(m)
	flickering[m] = nil
end)

-- Switches a sign's neon and screens off or back on.
local saved: { [BasePart]: number } = setmetatable({}, { __mode = "k" }) :: any
local function setSign(m: Model, on: boolean)
	for _, d in m:GetDescendants() do
		if d:IsA("SurfaceGui") then
			d.Enabled = on
		elseif d:IsA("BasePart") and d.Material == Enum.Material.Neon then
			if saved[d] == nil then
				saved[d] = d.Transparency
			end
			d.Transparency = if on then saved[d] else 0.85
		elseif d:IsA("Light") then
			d.Enabled = on
		end
	end
end

local function flicker(m: Model)
	task.spawn(function()
		for _ = 1, math.random(2, 4) do
			setSign(m, false)
			task.wait(0.03 + math.random() * 0.09)
			setSign(m, true)
			task.wait(0.04 + math.random() * 0.2)
		end
	end)
end

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for m, s in spinners do
		if m.Parent then
			local lift = s.bob * math.sin(t * 1.6 + s.phase)
			m:PivotTo(s.base * CFrame.new(0, lift, 0) * CFrame.Angles(0, t * s.speed + s.phase, 0))
		end
	end
	local wave = 0.5 + 0.5 * math.sin(t * 2.2)
	for m, b in breathers do
		local transparency = b.low + (b.high - b.low) * wave
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Transparency = transparency
			end
		end
	end
	for m, nextTime in flickering do
		if t >= nextTime then
			flickering[m] = t + 6 + math.random() * 12
			flicker(m)
		end
	end
end)
