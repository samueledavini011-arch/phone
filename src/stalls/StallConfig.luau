--[[
	StallConfig  (ModuleScript, child of PhoneStalls)

	One entry per stall. Change the words and colours here, then run
	require(game.ServerStorage.PhoneStalls).Rebuild() in the Command Bar.

	Colours are { red, green, blue } from 0 to 255.
]]

return {
	{
		Name = "Buy Stall", -- what the new model is called in the Explorer
		Sign = "BUY", -- the big neon letters on the roof
		Kind = "buy", -- "buy" or "sell": changes what sits on the counter and shelves
		Accent = { 40, 220, 255 }, -- neon colour
		Icon = "bag", -- "bag", "cash", "phone" or "none": on the counter and above the floor circle
		Menu = { "FRESH PHONES", "Grown on the farm today", "Step on the circle to buy" },
		OpenSign = true, -- the little neon OPEN sign
		Plants = true, -- potted plants by the front corners
	},
	{
		Name = "Sell Stall",
		Sign = "SELL",
		Kind = "sell",
		Accent = { 255, 45, 60 },
		Icon = "cash",
		Menu = { "WE BUY PHONES", "Instant cash for any phone", "Step on the circle to sell" },
		OpenSign = true,
		Plants = true,
	},
}
