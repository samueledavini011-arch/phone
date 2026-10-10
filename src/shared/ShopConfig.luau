--!strict
--[[
	ShopConfig  (ModuleScript, goes in ReplicatedStorage)

	Everything you might want to change about the shop lives here:
	gamepass IDs, prices, text, icons, colours and effect settings.

	GamepassId: create the gamepass on the Creator Dashboard, copy its ID
	and paste it in. While it is 0 the button only prints a warning.

	Icon: an emoji, or your own image as "rbxassetid://1234567890".
	The pixel-art icons from the video are images, so upload your own
	and paste the IDs here to match it exactly.
]]

export type AttributeValue = boolean | number | string

export type Pass = {
	Key: string, -- unique name; owners get the player attribute "Owns_<Key>"
	GamepassId: number,
	Price: number, -- shown until the real price loads from Roblox
	Title: string,
	Icon: string,
	Perk: string,
	Top: Color3, -- card colour at the top
	Bottom: Color3, -- card colour at the bottom
	Lines: Color3, -- diagonal pattern colour
	Attributes: { [string]: AttributeValue }, -- set on the player when owned
}

export type FeaturedPass = {
	Key: string,
	GamepassId: number,
	Price: number,
	Title: string,
	Icon: string,
	Line1: string,
	Line2: string,
	Attributes: { [string]: AttributeValue },
}

local featured: FeaturedPass = {
	Key = "VIP",
	GamepassId = 0,
	Price = 229,
	Title = "VIP",
	Icon = "👑",
	Line1 = "+500 IDK",
	Line2 = "+2x IDK",
	Attributes = { VIP = true, IdkBonus = 500, IdkMultiplier = 2 },
}

local passes: { Pass } = {
	{
		Key = "Magnet",
		GamepassId = 0,
		Price = 119,
		Title = "MAGNET",
		Icon = "🧲",
		Perk = "+200 RADIUS",
		Top = Color3.fromRGB(244, 66, 88),
		Bottom = Color3.fromRGB(206, 26, 52),
		Lines = Color3.fromRGB(150, 12, 36),
		Attributes = { MagnetRadiusBonus = 200 },
	},
	{
		Key = "DoubleMoney",
		GamepassId = 0,
		Price = 259,
		Title = "x2 MONEY",
		Icon = "💵",
		Perk = "+2x MONEY",
		Top = Color3.fromRGB(118, 224, 74),
		Bottom = Color3.fromRGB(50, 176, 46),
		Lines = Color3.fromRGB(26, 128, 30),
		Attributes = { MoneyMultiplier = 2 },
	},
	{
		Key = "DoubleGems",
		GamepassId = 0,
		Price = 299,
		Title = "x2 GEMS",
		Icon = "💎",
		Perk = "+2x GEMS",
		Top = Color3.fromRGB(96, 176, 252),
		Bottom = Color3.fromRGB(40, 108, 222),
		Lines = Color3.fromRGB(22, 70, 168),
		Attributes = { GemsMultiplier = 2 },
	},
}

local ShopConfig = {
	-- Behaviour
	OpenOnJoin = false, -- pop the shop open when the player joins
	ShowOpenButton = true, -- the small rainbow SHOP button on the left
	UseCanvasGroups = true, -- clean rounded clipping; set false if low-end phones lag

	-- Text
	Font = Enum.Font.Arcade,
	Title = "SHOP",
	TitleIcon = "🛒",
	SectionLabel = "GAMEPASSES",
	BuyText = "BUY",
	OwnedText = "OWNED",

	Featured = featured, -- the wide VIP banner
	Passes = passes, -- the three cards underneath (keep it at three)

	Theme = {
		Panel = Color3.fromRGB(45, 52, 58),
		PanelTransparency = 0.03,
		Outline = Color3.fromRGB(22, 30, 36),
		TextOutline = Color3.fromRGB(16, 16, 20),
		RobuxColor = Color3.fromRGB(110, 255, 90),
		Rainbow = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(168, 92, 246)),
			ColorSequenceKeypoint.new(0.16, Color3.fromRGB(82, 162, 248)),
			ColorSequenceKeypoint.new(0.32, Color3.fromRGB(52, 226, 214)),
			ColorSequenceKeypoint.new(0.47, Color3.fromRGB(70, 228, 92)),
			ColorSequenceKeypoint.new(0.62, Color3.fromRGB(240, 238, 50)),
			ColorSequenceKeypoint.new(0.80, Color3.fromRGB(255, 176, 34)),
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(242, 56, 46)),
		}),
		VipTop = Color3.fromRGB(255, 190, 46),
		VipBottom = Color3.fromRGB(255, 128, 24),
		VipTiles = Color3.fromRGB(255, 214, 110),
		VipText = ColorSequence.new({
			ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 236, 110)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 184, 24)),
			ColorSequenceKeypoint.new(1.0, Color3.fromRGB(226, 112, 10)),
		}),
		BuyTop = Color3.fromRGB(120, 246, 96),
		BuyBottom = Color3.fromRGB(40, 190, 58),
		OwnedTop = Color3.fromRGB(170, 176, 184),
		OwnedBottom = Color3.fromRGB(110, 116, 126),
		CloseTop = Color3.fromRGB(255, 84, 100),
		CloseBottom = Color3.fromRGB(206, 24, 46),
	},

	-- Same effect tags as the video, with its default values.
	Effects = {
		Spin = { Enabled = true, Speed = 55, Rays = 8, RayWidth = 34, Transparency = 0.8 }, -- _spin: rotating rays
		Gleam = { Enabled = true, SweepTime = 3, Pause = 0, WaveWidth = 0.6, Angle = 20 }, -- _gleam: shine across text
		Jelly = { Enabled = true, Wobble = 3, Speed = 1.2, Squash = 0.04 }, -- _jelly: wobbly SHOP letters
		Smooth = { HoverScale = 1.08, PressScale = 0.9, HoverSound = "", ClickSound = "" }, -- _smooth: juicy buttons
		Lean = { Angle = 12 }, -- _lean: icon tilts on hover
		Turn = { Angle = 90 }, -- _turn: close button spins on hover
		Fall = { Enabled = true, Speed = 22, Transparency = 0.6 }, -- _fall: falling background pattern
	},
}

return ShopConfig
