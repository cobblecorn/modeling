-- Shared colours / materials so the set reads as one family.
local Parts = require("../builder/Parts")
local S = Parts.style

return {
	Steel = S(176, 183, 191, "Metal"),
	SteelBright = S(206, 212, 219, "Metal"),
	SteelDark = S(92, 98, 108, "Metal"),
	Iron = S(70, 72, 78, "Metal"),
	Blackened = S(40, 42, 48, "Metal"),
	Gold = S(206, 164, 72, "Metal"),
	GoldDark = S(150, 112, 44, "Metal"),
	Bronze = S(160, 104, 60, "Metal"),

	Leather = S(78, 50, 32, "Leather"),
	LeatherDark = S(46, 30, 22, "Leather"),
	LeatherRed = S(110, 34, 30, "Leather"),
	Wrap = S(58, 38, 26, "Fabric"),
	Cloth = S(120, 36, 36, "Fabric"),

	Wood = S(122, 82, 48, "Wood"),
	WoodDark = S(84, 54, 32, "Wood"),
	WoodLight = S(160, 118, 72, "Wood"),

	String = S(236, 228, 206, "SmoothPlastic"),
	Feather = S(222, 60, 52, "SmoothPlastic"),
	FeatherWhite = S(238, 236, 230, "SmoothPlastic"),

	GemRed = S(214, 30, 48, "Neon"),
	GemViolet = S(150, 70, 255, "Neon"),
	GemCyan = S(40, 220, 255, "Neon"),
	Energy = S(64, 210, 255, "Neon"),

	Armor = S(82, 90, 104, "Metal"),
	ArmorLight = S(120, 128, 140, "DiamondPlate"),
	Paint = S(214, 118, 42, "SmoothPlastic"),
	Rubber = S(34, 34, 38, "Rubber"),
}
