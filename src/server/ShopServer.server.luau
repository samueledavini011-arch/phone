--!strict
--[[
	ShopServer  (Script, goes in ServerScriptService)

	Works out which gamepasses each player owns and marks them with
	attributes. The shop reads "Owns_<Key>" to show OWNED, and your own
	game code can read the perk attributes from ShopConfig, for example:

	  local multiplier = player:GetAttribute("MoneyMultiplier") or 1
	  local radius = 10 + (player:GetAttribute("MagnetRadiusBonus") or 0)
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("ShopConfig"))

type PassInfo = {
	Key: string,
	GamepassId: number,
	Attributes: { [string]: boolean | number | string },
}

-- Every pass in one list: the VIP banner plus the cards.
local allPasses: { PassInfo } = { Config.Featured }
for _, pass in Config.Passes do
	table.insert(allPasses, pass)
end

local passById: { [number]: PassInfo } = {}
for _, pass in allPasses do
	if pass.GamepassId ~= 0 then
		passById[pass.GamepassId] = pass
	end
end

local function grant(player: Player, pass: PassInfo)
	for name, value in pass.Attributes do
		player:SetAttribute(name, value)
	end
	player:SetAttribute("Owns_" .. pass.Key, true)
end

local function checkPass(player: Player, pass: PassInfo)
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.GamepassId)
	end)
	if not ok then
		warn(`[Shop] Could not check "{pass.Key}" for {player.Name}: {owns}`)
	elseif owns and player.Parent then
		grant(player, pass)
	end
end

local function onPlayerAdded(player: Player)
	for _, pass in allPasses do
		if pass.GamepassId ~= 0 then
			task.spawn(checkPass, player, pass)
		end
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- Give the perks straight away when someone buys a pass in game.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamepassId: number, purchased: boolean)
	local pass = passById[gamepassId]
	if purchased and pass then
		grant(player, pass)
	end
end)
