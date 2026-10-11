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
		StringLights = true, -- warm bulbs hanging from the roof edge
		Ticker = "NEW PHONES EVERY DAY  *  BEST PRICES IN TOWN  *  COME ON IN  *", -- scrolling LED text on the roof edge
		Poster = { "NEW PHONES", "Fresh from the farm every day", "HOT" }, -- the painted signs on both sides
		Board = { "OPEN", "Phones in stock", "Come on in!" }, -- the chalkboard out front
		Card = { "FRESH!", "picked today" }, -- the cardboard sign on the counter

		-- Who the shopkeeper looks like: false keeps their own look, "me" is
		-- your Roblox avatar, or a UserId (the number in a profile link).
		Shopkeeper = false,
		ShopkeeperMoves = true, -- idles and waves when someone walks up
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
		StringLights = true,
		Ticker = "WE BUY PHONES  *  INSTANT CASH  *  ANY PHONE, ANY SIZE  *",
		Poster = { "CASH FOR PHONES", "Any phone, paid on the spot", "FAST" },
		Board = { "OPEN", "We buy phones", "Come on in!" },
		Card = { "CASH $$", "fair prices!" },
		Shopkeeper = false,
		ShopkeeperMoves = true,
	},
}
