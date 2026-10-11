--!strict
--[[
	StallFX  (LocalScript in StarterPlayerScripts; PhoneStalls puts it there)

	Animates the stalls on each player's screen:
	  * the icons above the floor circles spin and float up and down
	  * the display phone on the BUY counter turns on its turntable
	  * the glow round the floor circles fades in and out, and lights up
	    while you stand on the circle
	  * the neon signs flicker now and then, like real neon
	  * the LED ticker on the roof edge scrolls
	  * the shopkeepers stand idle and wave when you walk up
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local WAVE_DISTANCE = 16 -- studs from the shopkeeper
local WAVE_EVERY = 10 -- seconds before the same shopkeeper waves again
local TICKER_SPEED = 90 -- pixels per second
local ANIMATIONS = {
	R15 = { idle = "rbxassetid://507766666", wave = "rbxassetid://507770239" },
	R6 = { idle = "rbxassetid://180435571", wave = "rbxassetid://128777973" },
}

type Spinner = { base: CFrame, speed: number, bob: number, phase: number }

local spinners: { [Model]: Spinner } = {}
local breathers: { [Model]: { low: number, high: number, radius: number, boost: number } } = {}
local flickering: { [Model]: number } = {} -- next time each sign flickers
local tickers: { [BasePart]: boolean } = {}
type Keeper = { root: BasePart, wave: AnimationTrack?, lastWave: number, near: boolean }
local keepers: { [Model]: Keeper } = {}

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
	breathers[m] = { low = number(m, "Low", 0.7), high = number(m, "High", 0.9), radius = number(m, "Radius", 0), boost = 0 }
end, function(m)
	breathers[m] = nil
end)

watch("StallFlicker", function(m)
	flickering[m] = os.clock() + 3 + math.random() * 10
end, function(m)
	flickering[m] = nil
end)

local function playerRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Shopkeepers: a gentle idle, and a wave when someone walks up
local function loadTrack(animator: Animator, id: string, looped: boolean, priority: Enum.AnimationPriority): AnimationTrack?
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return nil
	end
	track.Looped = looped
	track.Priority = priority
	return track
end

watch("StallShopkeeper", function(m)
	if m:GetAttribute("ShopkeeperMoves") == false then
		return
	end
	local humanoid = m:FindFirstChildOfClass("Humanoid")
	local root = if humanoid then humanoid.RootPart or m:FindFirstChild("HumanoidRootPart") else nil
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	local found = humanoid:FindFirstChildOfClass("Animator")
	local animator: Animator
	if found then
		animator = found
	else
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local ids = if humanoid.RigType == Enum.HumanoidRigType.R15 then ANIMATIONS.R15 else ANIMATIONS.R6
	local idle = loadTrack(animator, ids.idle, true, Enum.AnimationPriority.Idle)
	if idle then
		idle:Play()
	end
	keepers[m] = { root = root, wave = loadTrack(animator, ids.wave, false, Enum.AnimationPriority.Action), lastWave = 0, near = false }
end, function(m)
	keepers[m] = nil
end)

-- LED tickers on the roof edge
local function addTicker(inst: Instance)
	if inst:IsA("BasePart") then
		tickers[inst] = true
	end
end
for _, inst in CollectionService:GetTagged("StallTicker") do
	addTicker(inst)
end
CollectionService:GetInstanceAddedSignal("StallTicker"):Connect(addTicker)
CollectionService:GetInstanceRemovedSignal("StallTicker"):Connect(function(inst)
	if inst:IsA("BasePart") then
		tickers[inst] = nil
	end
end)

local function scrollTicker(part: BasePart, t: number)
	local gui = part:FindFirstChild("Screen")
	local track = gui and gui:FindFirstChild("Track")
	local a = track and track:FindFirstChild("A")
	local b = track and track:FindFirstChild("B")
	if not a or not b or not a:IsA("GuiObject") or not b:IsA("GuiObject") then
		return
	end
	local width = a.AbsoluteSize.X
	if width <= 0 then
		return
	end
	local shift = (t * TICKER_SPEED) % width
	a.Position = UDim2.fromOffset(-shift, 0)
	b.Position = UDim2.fromOffset(width - shift, 0)
end

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

RunService.RenderStepped:Connect(function(dt: number)
	local t = os.clock()
	local me = playerRoot()
	for m, s in spinners do
		if m.Parent then
			local lift = s.bob * math.sin(t * 1.6 + s.phase)
			m:PivotTo(s.base * CFrame.new(0, lift, 0) * CFrame.Angles(0, t * s.speed + s.phase, 0))
		end
	end
	for m, b in breathers do
		-- brighter, faster glow while you stand on the circle
		local inside = false
		if me and b.radius > 0 then
			local centre = m:GetPivot().Position
			inside = Vector3.new(me.Position.X - centre.X, 0, me.Position.Z - centre.Z).Magnitude < b.radius
		end
		b.boost += ((if inside then 1 else 0) - b.boost) * math.min(1, dt * 6)
		local wave = 0.5 + 0.5 * math.sin(t * (2.2 + b.boost * 4))
		local transparency = b.low + (b.high - b.low) * wave - b.boost * 0.35
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
	for part in tickers do
		scrollTicker(part, t)
	end
	for _, k in keepers do
		local near = me ~= nil and (me.Position - k.root.Position).Magnitude < WAVE_DISTANCE
		if near and not k.near and t - k.lastWave > WAVE_EVERY and k.wave then
			k.lastWave = t
			k.wave:Play()
		end
		k.near = near
	end
end)
