--[[
	TowerConfig  (ModuleScript, child of PhoneTowers)

	One entry per phone-company tower. Change the words and colours here,
	then run the Command Bar line again (see PhoneTowers).

	Colours are { red, green, blue } from 0 to 255.
]]

return {
	{
		Name = "Pearl Phones", -- what the model is called in the Explorer
		Sign = "PEARL PHONES", -- the letters on the building
		Logo = "pearl", -- "pearl", "star", "ring", "none", or an image like "rbxassetid://123456"
		Seed = 11, -- any number: changes which offices have their lights on

		Glass = { 34, 46, 62 }, -- window tint
		Accent = { 40, 220, 255 }, -- LED lines on the lower tower and the sign glow
		TopAccent = { 255, 70, 230 }, -- LED lines on the top floors and crown
		TopRooms = { 150, 80, 255 }, -- the colour the top-floor offices glow at night

		LowerFloors = 10, -- floors below the setback
		UpperFloors = 6, -- floors above the setback
		Plaza = true, -- paving, steps, trees and street lamps around the base
	},
	{
		Name = "Starsung Phones",
		Sign = "STARSUNG PHONES", -- I couldn't read this sign well in your screenshot; fix the spelling here
		Logo = "star",
		Seed = 23,

		Glass = { 30, 44, 58 },
		Accent = { 40, 220, 255 },
		TopAccent = { 255, 70, 230 },
		TopRooms = { 165, 90, 255 },

		LowerFloors = 10,
		UpperFloors = 6,
		Plaza = true,
	},
}
