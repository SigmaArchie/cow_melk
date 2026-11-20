-- Palette.lua (ModuleScript, Client UND Server)
-- Gemeinsame Farben und Schriften für alles, was man sieht:
--   * Theme.lua (Client-Oberfläche) liest seine Farben von hier
--   * Server-Scripts (MapBuilder, CowManager) bauen damit Schilder, Namensschilder und Pop-ups
-- Stil "Holz-Farm": Fenster aus warmem Holz mit dickem dunkelbraunem Rand, Gras-Streifen oben,
-- Titel auf einem Holzschild, weiße Schrift mit dunkelbraunem Umriss, kräftige bunte Knöpfe
-- (Grün = Coins/Kaufen, Gold = Robux/Seltenes, Blau = Geschenk/Info, Orange = Aktion, Rot = Schließen).

local Palette = {}

Palette.Colors = {
	-- Flächen (Holz)
	Deep = Color3.fromRGB(74, 40, 24), -- dunkelstes Holz (eingelassene Felder, Namensschilder)
	Panel = Color3.fromRGB(140, 80, 44), -- Fenster, Leisten
	PanelLight = Color3.fromRGB(112, 60, 34), -- Zeilen, Eingaben (dunkler = eingelassen)
	Card = Color3.fromRGB(104, 56, 32), -- Karten
	Outline = Color3.fromRGB(52, 26, 14), -- dunkelbraune Tinte (Schrift-Umriss, Ränder)
	Line = Color3.fromRGB(66, 34, 18), -- Rand der Flächen
	WoodLight = Color3.fromRGB(184, 112, 60), -- Titelschild, helle Bretter
	Grass = Color3.fromRGB(124, 206, 64), -- Gras-Streifen oben am Fenster
	GrassDark = Color3.fromRGB(74, 150, 40),

	-- Schrift (weiß mit Umriss)
	Cream = Color3.fromRGB(255, 251, 242),
	Text = Color3.fromRGB(255, 251, 242),
	SubText = Color3.fromRGB(244, 214, 176),

	-- Knöpfe & Akzente
	Green = Color3.fromRGB(96, 196, 58), -- Haupt-Aktion, Coins-Preis, AN
	Blue = Color3.fromRGB(44, 170, 240), -- Geschenk, Info
	Steel = Color3.fromRGB(190, 120, 64), -- zweite Aktion: helles Holz (Reiter, Zurück)
	Red = Color3.fromRGB(226, 58, 58), -- Schließen, AUS, Abbrechen
	Gold = Color3.fromRGB(255, 198, 40), -- Robux, Coins, seltene Belohnungen
	Orange = Color3.fromRGB(250, 146, 30), -- besondere Aktion ("Jetzt auffüllen!")
	Pink = Color3.fromRGB(236, 104, 160),
	Teal = Color3.fromRGB(56, 190, 170),
	Grey = Color3.fromRGB(132, 108, 92), -- nicht verfügbar
}

Palette.Fonts = {
	Heading = Enum.Font.FredokaOne, -- Überschriften, Knöpfe, Zahlen
	Body = Enum.Font.FredokaOne, -- kleinere Texte (gleiche runde, dicke Schrift)
	Text = Enum.Font.GothamBold, -- Fließtext
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
	-- Arten aus dem Kuh-Shop (Farbe der Seltenheitsstufe)
	Jersey = Color3.fromRGB(116, 200, 116), -- Ungewöhnlich
	Chocolate = Color3.fromRGB(88, 160, 240), -- Selten
	Strawberry = Color3.fromRGB(172, 112, 232), -- Episch
	Highland = Color3.fromRGB(172, 112, 232), -- Episch
	Thunder = Color3.fromRGB(250, 170, 70), -- Legendär
	Moon = Color3.fromRGB(232, 110, 196), -- Mythisch
	Dragon = Color3.fromRGB(255, 214, 80), -- Göttlich
	Crystal = Color3.fromRGB(130, 224, 255), -- Prismatisch
}

-- Farbe für den Namen/Rahmen einer Seltenheit (unbekannt -> Common)
function Palette.rarityColor(rarity)
	return Palette.Rarity[rarity] or Palette.Rarity.Common
end

return Palette
