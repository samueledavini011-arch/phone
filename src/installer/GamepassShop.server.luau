--!strict
--[[
	GamepassShop  (one-file install)

	Drop GamepassShop.rbxmx into Roblox Studio, or right-click
	ServerScriptService and pick "Insert from File...". This script then
	moves the shop's parts to where they need to live:

	  ShopConfig -> ReplicatedStorage (settings, shared with players)
	  ShopClient -> StarterPlayer > StarterPlayerScripts (the shop UI)
	  ShopServer stays here and runs the gamepass checks.

	To change prices, names or gamepass IDs, open the ShopConfig inside
	this script before pressing Play.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local config = script:WaitForChild("ShopConfig")
local client = script:WaitForChild("ShopClient")

if ReplicatedStorage:FindFirstChild("ShopConfig") then
	warn("[Shop] ReplicatedStorage already has a ShopConfig, so that one is used. Delete it to use the one in this script.")
else
	config.Parent = ReplicatedStorage
end

client.Parent = StarterPlayer:WaitForChild("StarterPlayerScripts")
