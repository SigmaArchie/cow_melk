-- Palette.lua (ModuleScript, Client UND Server)
-- Gemeinsame Farben und Schriften für alles, was man sieht:
--   * Theme.lua (Client-Oberfläche) liest seine Farben von hier
--   * Server-Scripts (MapBuilder, CowManager) bauen damit Schilder, Namensschilder und Pop-ups
-- Stil: tiefes Marineblau, Creme/Off-White, Grasgrün für Aktionen, Himmelblau als Akzent,
-- Gold NUR für Coins und seltene Belohnungen. Keine Neon-Farben, keine dicken Schrift-Umrisse.

local Palette = {}

Palette.Colors = {
	-- Flächen (Marineblau)
	Deep = Color3.fromRGB(14, 22, 42), -- tiefste Fläche (Kopfzeile, Namensschilder)
	Panel = Color3.fromRGB(24, 36, 64), -- Fenster, Leisten
	PanelLight = Color3.fromRGB(34, 50, 84), -- Zeilen, Eingaben
	Card = Color3.fromRGB(40, 58, 94), -- Karten
	Outline = Color3.fromRGB(10, 16, 32), -- dunkle Tinte (Schrift auf hellen Abzeichen)
	Line = Color3.fromRGB(72, 96, 148), -- dünne Umrandung

	-- Schrift / helle Flächen (Creme)
	Cream = Color3.fromRGB(250, 244, 228),
	Text = Color3.fromRGB(250, 244, 228),
	SubText = Color3.fromRGB(196, 198, 190),

	-- Aktionen & Akzente
	Green = Color3.fromRGB(70, 158, 76), -- Gras: Haupt-Aktionen
	Blue = Color3.fromRGB(78, 164, 232), -- Himmelblau: Akzent
	Steel = Color3.fromRGB(62, 86, 134), -- zweite Aktion
	Red = Color3.fromRGB(208, 78, 78), -- Schließen / Abbrechen
	Gold = Color3.fromRGB(244, 192, 64), -- NUR Coins und seltene Belohnungen
	Orange = Color3.fromRGB(226, 148, 66),
	Pink = Color3.fromRGB(214, 118, 160),
	Teal = Color3.fromRGB(70, 176, 160),
	Grey = Color3.fromRGB(88, 100, 128), -- nicht verfügbar
}

Palette.Fonts = {
	Heading = Enum.Font.FredokaOne, -- Überschriften, Knöpfe, Zahlen
	Body = Enum.Font.GothamBold, -- kleinere Texte
	Text = Enum.Font.GothamMedium, -- Fließtext
}

-- Materialfarben für die Welt (Holz, Stein, Zaun ...)
Palette.World = {
	WoodDark = Color3.fromRGB(88, 62, 42),
	Wood = Color3.fromRGB(140, 98, 62),
	WoodLight = Color3.fromRGB(190, 146, 98),
	Stone = Color3.fromRGB(205, 200, 190),
	StoneDark = Color3.fromRGB(150, 145, 138),
	StonePath = Color3.fromRGB(186, 178, 164),
	Fence = Color3.fromRGB(244, 238, 222),
	Hay = Color3.fromRGB(226, 196, 104),
	GrassLight = Color3.fromRGB(118, 186, 86),
	GrassDark = Color3.fromRGB(104, 170, 76),
	Leaf = Color3.fromRGB(74, 146, 70),
	Soil = Color3.fromRGB(96, 70, 52),
	Metal = Color3.fromRGB(150, 156, 166),
	Lantern = Color3.fromRGB(255, 232, 178),
	-- Blumen (dezent, nicht grell)
	Flowers = {
		Color3.fromRGB(236, 120, 130),
		Color3.fromRGB(250, 226, 120),
		Color3.fromRGB(246, 244, 236),
		Color3.fromRGB(170, 140, 220),
	},
}

-- Namens-/Hinweisfarben je Seltenheit (nur Darstellung; die Spieldaten stehen in CowData.Rarities)
Palette.Rarity = {
	Common = Color3.fromRGB(205, 205, 196), -- schlicht
	Uncommon = Color3.fromRGB(116, 200, 116), -- dezentes Grün
	Rare = Color3.fromRGB(88, 160, 240), -- kühles Blau
	Epic = Color3.fromRGB(172, 112, 232), -- Lila
	Legendary = Color3.fromRGB(250, 170, 70), -- warmes Gold
	Golden = Color3.fromRGB(255, 214, 80), -- Premium-Gold
	Rainbow = Color3.fromRGB(236, 130, 190), -- sanftes Rosa (die Kuh selbst wechselt die Farbe)
	Ghost = Color3.fromRGB(150, 236, 176), -- durchscheinendes Grün
}

-- Farbe für den Namen/Rahmen einer Seltenheit (unbekannt -> Common)
function Palette.rarityColor(rarity)
	return Palette.Rarity[rarity] or Palette.Rarity.Common
end

return Palette
