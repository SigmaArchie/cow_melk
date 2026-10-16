-- CowData.lua
-- Zentrale Spieldaten für "Cow Farm".
-- Wird von Server UND Client benutzt (liegt in ReplicatedStorage.Shared).

local CowData = {}

------------------------------------------------------------------------
-- Allgemeine Einstellungen
------------------------------------------------------------------------
CowData.Config = {
	StartCoins = 100,
	StarterCow = "Common", -- jeder neue Spieler bekommt eine Gratis-Kuh

	MilkSellPrice = 2, -- Coins pro Liter Milch
	UseImportedCowModel = true, -- false = immer die Ersatz-Kuh aus Parts (z.B. wenn das Blender-Modell Probleme macht)
	MaxCows = 40, -- maximale Kühe insgesamt (Farm + Hotbar + Inventar)
	HotbarSize = 6, -- Plätze in der Hotbar (Tasten 1-6)

	-- Melk-Minispiel
	PullsPerMilking = 10, -- so viele richtige Züge, bis der Eimer voll ist
	WrongPullPenalty = 1, -- falsche Seite gezogen -> so viele Züge Fortschritt weg
	MinPullInterval = 0.1, -- schnellste erlaubte Zug-Rate (Anti-Cheat)
	MilkingAnimationId = 0, -- optional: eigene Animation-ID (0 = keine)
	-- Sounds (Roblox-Asset-IDs). Leerer Text = Sound aus.
	-- 5857005819 ist KEIN Sound (Studio: "Asset type does not match") -> aus, bis eine echte ID da ist
	SquirtSoundId = "", -- bei jedem Zug
	MilkDoneSoundId = "", -- Eimer voll (tiefer abgespielt)
	SellSoundId = "rbxassetid://4590662766", -- Coins beim Verkaufen
	CoinSoundId = "rbxassetid://4590662766", -- Coins-Zähler steigt (HUD)
	-- 1843671818 ist KEIN Sound (Studio: "Asset type does not match") -> aus, bis eine echte ID da ist
	AmbientSoundId = "", -- Hintergrund-Musik (Loop)
	MooSoundId = "rbxassetid://535690488", -- Kuh muht (alle 15-30 s pro Kuh)
	NewCowSoundId = "rbxassetid://4590662766", -- neue Kuh auf der Farm
	-- noch keine funktionierenden IDs ("swoosh.wav" ist gesperrt) -> aus, bis eine echte ID da ist
	ShopOpenSoundId = "", -- Shop-Fenster öffnet
	RareCowSoundId = "", -- Fanfare für Episch und besser

	AutoMilkInterval = 3, -- Auto-Melker melkt alle X Sekunden jede Kuh einmal
	AutoMilkerGamePassId = 0, -- >>> HIER die echte Gamepass-ID eintragen <<<

	DailyRewardBase = 25, -- Login-Bonus = 25 * Streak-Tag (Tag 1-7)
	RainbowStreakDays = 7, -- alle 7 Tage am Stück -> Rainbow Cow

	AutosaveInterval = 120, -- Sekunden
}

------------------------------------------------------------------------
-- Karte (wird von MapBuilder, CowManager und WorldAnimator benutzt)
--
--            Norden (+Z)
--   [Plot 1] | ▲ ▼ | [Plot 2]      <- Reihe 0
--   [Plot 3] | ▲ ▼ | [Plot 4]      <- Reihe 1
--   ...      |Laufbänder|  ...
--   [Shop]   Platz (Hub)  [Shop]
--            Süden (-Z)
------------------------------------------------------------------------
CowData.Map = {
	GroundTop = 0.4, -- Oberkante von Plots / Laufbändern

	-- Farm-Plots links (Westen) und rechts (Osten) der Allee.
	-- 3 Reihen pro Seite (6 Spieler); ab Spieler 7 kommt eine zweite Spalte weiter außen.
	PlotWidth = 90, -- entlang der Allee
	PlotDepth = 110, -- von der Allee weg
	PlotCenterX = 75,
	PlotColumnSpacing = 120,
	PlotRowStartZ = 70,
	PlotRowSpacing = 95,
	PlotRowsPerColumn = 3,

	-- Raster auf jeder Farm (Plätze für Kühe), in lokalen Plot-Koordinaten
	GridColumns = 6,
	GridRows = 6,
	GridCellX = 13,
	GridCellZ = 12,
	GridFirstRowZ = -44,

	-- Nord-Markt am anderen Ende der Förderbänder
	NorthPlazaZ = 400, -- Mitte
	NorthPlazaSize = Vector3.new(120, 0.2, 100),

	-- Förderbänder in der Mitte (eins nach Norden, eins nach Süden).
	-- 6 Kacheln à 50 Studs laufen im Kreis (Zyklus = 300 Studs). Die ersten und letzten
	-- 50 Studs stecken in "Maschinen-Gehäusen", dort springen die Kacheln unsichtbar zurück.
	WalkwayStartZ = -10, -- Beginn des vorderen Gehäuses
	WalkwayTileLength = 50,
	WalkwayTileCount = 6,
	WalkwayX = 6, -- Abstand der Bandmitte von der Mittellinie
	WalkwayWidth = 10,
	WalkwaySpeed = 36, -- Studs pro Sekunde
}
-- Shop-Gebäude: zwei am Süd-Platz, zwei am Nord-Markt (Förderbänder verbinden beide)
-- Page = welches Fenster sich öffnet; Label = Name in der Übersicht
CowData.Map.Shops = {
	{
		Name = "CowShop", Page = "Shop", Title = "KUH-SHOP", Label = "Kuh-Shop", Icon = "🐄", Area = "Süd-Platz",
		Color = Color3.fromRGB(70, 140, 220), RoofColor = Color3.fromRGB(45, 90, 160), WallColor = Color3.fromRGB(240, 232, 215),
		Position = Vector3.new(-40, 0, -40), FacesEast = true,
	},
	{
		Name = "BreedingBarn", Page = "Breeding", Title = "ZUCHT-STALL", Label = "Zucht-Stall", Icon = "💕", Area = "Süd-Platz",
		Color = Color3.fromRGB(225, 85, 140), RoofColor = Color3.fromRGB(160, 45, 45), WallColor = Color3.fromRGB(190, 60, 55),
		Position = Vector3.new(40, 0, -40), FacesEast = false,
	},
	{
		Name = "CrateShop", Page = "Crates", Title = "KISTEN", Label = "Kisten", Icon = "✨", Area = "Nord-Markt",
		Color = Color3.fromRGB(230, 150, 45), RoofColor = Color3.fromRGB(170, 95, 30), WallColor = Color3.fromRGB(245, 230, 200),
		Position = Vector3.new(-40, 0, 405), FacesEast = true,
	},
	{
		Name = "AutoMilkerShop", Page = "AutoMilker", Title = "AUTO-MELKER", Label = "Auto-Melker", Icon = "🥛", Area = "Nord-Markt",
		Color = Color3.fromRGB(60, 185, 160), RoofColor = Color3.fromRGB(40, 110, 100), WallColor = Color3.fromRGB(215, 222, 228),
		Position = Vector3.new(40, 0, 405), FacesEast = false,
	},
}

-- abgeleitete Werte
CowData.Map.WalkwayCycle = CowData.Map.WalkwayTileLength * CowData.Map.WalkwayTileCount -- 300
CowData.Map.WalkwayVisibleStart = CowData.Map.WalkwayStartZ + CowData.Map.WalkwayTileLength -- 40
CowData.Map.WalkwayVisibleEnd = CowData.Map.WalkwayStartZ + CowData.Map.WalkwayCycle -- 290

------------------------------------------------------------------------
-- Seltenheiten
-- Tier:         Sortierung / Wertigkeit (1 = Common ... 8 = Ghost)
-- BreedTier:    mit welcher Stufe die Kuh beim Züchten zählt
-- MilkPerPull:  Milch pro erfolgreichem Zug im Melk-Minispiel
-- MilkCooldown: Pause in Sekunden, bevor die Kuh wieder gemolken werden kann
-- ShopPrice:    nur gesetzt, wenn die Kuh direkt im Shop kaufbar ist
-- BreedTime:    Zuchtdauer in Sekunden
-- Color / SpotColor / Material / Transparency: Aussehen des Modells
-- Licht- und Partikel-Effekte je Seltenheit: siehe CowModelBuilder.addRarityEffects
------------------------------------------------------------------------
CowData.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Golden", "Rainbow", "Ghost" }

CowData.Rarities = {
	Common = { -- schwarz/weiß
		DisplayName = "Gewöhnlich",
		Tier = 1,
		BreedTier = 1,
		MilkPerPull = 2,
		MilkCooldown = 20,
		ShopPrice = 100,
		BreedTime = 300, -- 5 Minuten
		Color = Color3.fromRGB(245, 245, 240),
		SpotColor = Color3.fromRGB(25, 25, 25),
		UiColor = Color3.fromRGB(200, 200, 200),
		Material = Enum.Material.SmoothPlastic,
	},
	Uncommon = { -- braun/weiß
		DisplayName = "Ungewöhnlich",
		Tier = 2,
		BreedTier = 2,
		MilkPerPull = 5,
		MilkCooldown = 25,
		ShopPrice = 600,
		BreedTime = 450,
		Color = Color3.fromRGB(140, 85, 50),
		SpotColor = Color3.fromRGB(250, 245, 235),
		UiColor = Color3.fromRGB(90, 210, 90),
		Material = Enum.Material.SmoothPlastic,
	},
	Rare = { -- blau getönt
		DisplayName = "Selten",
		Tier = 3,
		BreedTier = 3,
		MilkPerPull = 12,
		MilkCooldown = 30,
		BreedTime = 600,
		Color = Color3.fromRGB(185, 210, 245),
		SpotColor = Color3.fromRGB(50, 85, 170),
		UiColor = Color3.fromRGB(70, 150, 255),
		Material = Enum.Material.SmoothPlastic,
	},
	Epic = { -- lila getönt
		DisplayName = "Episch",
		Tier = 4,
		BreedTier = 4,
		MilkPerPull = 30,
		MilkCooldown = 45,
		BreedTime = 900,
		Color = Color3.fromRGB(210, 180, 245),
		SpotColor = Color3.fromRGB(105, 45, 165),
		UiColor = Color3.fromRGB(180, 90, 255),
		Material = Enum.Material.SmoothPlastic,
	},
	Legendary = { -- golden mit cremefarbenen Flecken
		DisplayName = "Legendär",
		Tier = 5,
		BreedTier = 5,
		MilkPerPull = 75,
		MilkCooldown = 60,
		BreedTime = 1200,
		Color = Color3.fromRGB(235, 180, 60),
		SpotColor = Color3.fromRGB(255, 240, 200),
		UiColor = Color3.fromRGB(255, 160, 40),
		Material = Enum.Material.SmoothPlastic,
	},

	-- Special-Kühe (zählen beim Züchten wie Legendary)
	Golden = { -- metallisch glänzendes Gold, leuchtet
		DisplayName = "Golden",
		Tier = 6,
		BreedTier = 5,
		MilkPerPull = 200,
		MilkCooldown = 60,
		BreedTime = 1200,
		IsSpecial = true,
		Color = Color3.fromRGB(255, 205, 45),
		UiColor = Color3.fromRGB(255, 215, 0),
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.25,
	},
	Rainbow = { -- Farbe wechselt ständig, weiße Flecken
		DisplayName = "Regenbogen",
		Tier = 7,
		BreedTier = 5,
		MilkPerPull = 160,
		MilkCooldown = 60,
		BreedTime = 1200,
		IsSpecial = true,
		IsRainbow = true,
		Color = Color3.fromRGB(255, 80, 80),
		SpotColor = Color3.fromRGB(255, 255, 255),
		UiColor = Color3.fromRGB(255, 120, 200),
		Material = Enum.Material.SmoothPlastic,
	},
	Ghost = { -- durchsichtig, schimmernd
		DisplayName = "Geister",
		Tier = 8,
		BreedTier = 5,
		MilkPerPull = 130,
		MilkCooldown = 60,
		BreedTime = 1200,
		IsSpecial = true,
		Transparency = 0.5,
		Color = Color3.fromRGB(205, 255, 225),
		UiColor = Color3.fromRGB(150, 255, 180),
		Material = Enum.Material.SmoothPlastic,
	},
}

------------------------------------------------------------------------
-- Zucht-Tabellen (Gewichte in %)
-- Index = BreedTier der Eltern (bei unterschiedlichen Eltern: Durchschnitt, abgerundet)
-- Golden gibt es NUR, wenn beide Eltern echte Legendary-Kühe sind.
------------------------------------------------------------------------
CowData.BreedingTables = {
	[1] = { -- 2x Common
		{ Rarity = "Common", Weight = 90 },
		{ Rarity = "Uncommon", Weight = 10 },
	},
	[2] = { -- 2x Uncommon
		{ Rarity = "Common", Weight = 15 },
		{ Rarity = "Uncommon", Weight = 75 },
		{ Rarity = "Rare", Weight = 10 },
	},
	[3] = { -- 2x Rare
		{ Rarity = "Uncommon", Weight = 20 },
		{ Rarity = "Rare", Weight = 72 },
		{ Rarity = "Epic", Weight = 8 },
	},
	[4] = { -- 2x Epic
		{ Rarity = "Rare", Weight = 25 },
		{ Rarity = "Epic", Weight = 70 },
		{ Rarity = "Legendary", Weight = 5 },
	},
	[5] = { -- 2x Legendary
		{ Rarity = "Epic", Weight = 30 },
		{ Rarity = "Legendary", Weight = 69 },
		{ Rarity = "Golden", Weight = 1 },
	},
}

------------------------------------------------------------------------
-- Kuh-Kisten
-- CoinPrice: Preis in Coins (nil = nicht für Coins kaufbar)
-- ProductId: Developer-Product-ID für Robux (0 = noch nicht eingerichtet)
------------------------------------------------------------------------
CowData.CrateOrder = { "Basic", "Super", "Premium" }

CowData.Crates = {
	Basic = {
		DisplayName = "Holzkiste",
		CoinPrice = 500,
		Loot = {
			{ Rarity = "Common", Weight = 70 },
			{ Rarity = "Uncommon", Weight = 25 },
			{ Rarity = "Rare", Weight = 5 },
		},
	},
	Super = {
		DisplayName = "Silberkiste",
		CoinPrice = 3000,
		ProductId = 0, -- >>> Developer-Product-ID eintragen (Robux-Alternative) <<<
		Loot = {
			{ Rarity = "Uncommon", Weight = 50 },
			{ Rarity = "Rare", Weight = 35 },
			{ Rarity = "Epic", Weight = 13 },
			{ Rarity = "Legendary", Weight = 2 },
		},
	},
	Premium = {
		DisplayName = "Premium-Kiste",
		ProductId = 0, -- >>> Developer-Product-ID eintragen (nur Robux) <<<
		Loot = {
			{ Rarity = "Rare", Weight = 40 },
			{ Rarity = "Epic", Weight = 35 },
			{ Rarity = "Legendary", Weight = 20 },
			{ Rarity = "Ghost", Weight = 5 }, -- Ghost Cow NUR hier
		},
	},
}

------------------------------------------------------------------------
-- Kuh-Namen
------------------------------------------------------------------------
CowData.Names = {
	"Berta", "Liesl", "Rosi", "Elsa", "Muhriel", "Frieda", "Klara", "Lotte",
	"Heidi", "Greta", "Paula", "Wilma", "Bella", "Daisy", "Milka", "Susi",
	"Trudi", "Hanni", "Kuhnigunde", "Muhtilda", "Flecki", "Sternchen", "Butterblume", "Gundula",
}

------------------------------------------------------------------------
-- Hilfsfunktionen
------------------------------------------------------------------------

-- Lage eines Farm-Plots (Server baut ihn, Client zeichnet ihn in der Übersicht).
-- Ungerade Slots links (Westen), gerade rechts (Osten). Lokales +Z (Tor) zeigt zur Allee.
function CowData.GetPlotOrigin(slot)
	local map = CowData.Map
	local index = slot - 1
	local side = index % 2 == 0 and -1 or 1
	local pair = math.floor(index / 2)
	local row = pair % map.PlotRowsPerColumn
	local column = math.floor(pair / map.PlotRowsPerColumn)
	local x = side * (map.PlotCenterX + column * map.PlotColumnSpacing)
	local z = map.PlotRowStartZ + row * map.PlotRowSpacing
	local yaw = side == -1 and math.rad(90) or math.rad(-90)
	return CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0)
end

-- Mitte eines Rasterfelds (1 .. GridColumns*GridRows) in lokalen Plot-Koordinaten
function CowData.GetGridCellLocal(cell)
	local map = CowData.Map
	local index = cell - 1
	local column = index % map.GridColumns
	local row = math.floor(index / map.GridColumns)
	local x = (column - (map.GridColumns - 1) / 2) * map.GridCellX
	local z = map.GridFirstRowZ + row * map.GridCellZ
	return CFrame.new(x, map.GroundTop, z)
end

function CowData.GetGridCellCount()
	return CowData.Map.GridColumns * CowData.Map.GridRows
end

function CowData.IsValidRarity(rarity)
	return type(rarity) == "string" and CowData.Rarities[rarity] ~= nil
end

function CowData.RandomName(rng)
	rng = rng or Random.new()
	return CowData.Names[rng:NextInteger(1, #CowData.Names)]
end

-- Wählt zufällig eine Seltenheit aus einer Liste { {Rarity=..., Weight=...}, ... }
function CowData.RollWeighted(lootTable, rng)
	rng = rng or Random.new()
	local total = 0
	for _, entry in ipairs(lootTable) do
		total += entry.Weight
	end

	local roll = rng:NextNumber() * total
	for _, entry in ipairs(lootTable) do
		roll -= entry.Weight
		if roll <= 0 then
			return entry.Rarity
		end
	end
	return lootTable[#lootTable].Rarity
end

-- Gibt die Zucht-Chancen für zwei Eltern zurück (Liste mit Rarity/Weight)
function CowData.GetBreedingChances(rarityA, rarityB)
	local infoA = CowData.Rarities[rarityA] or CowData.Rarities.Common
	local infoB = CowData.Rarities[rarityB] or CowData.Rarities.Common
	local tier = math.floor((infoA.BreedTier + infoB.BreedTier) / 2)
	local baseTable = CowData.BreedingTables[tier]

	local bothLegendary = rarityA == "Legendary" and rarityB == "Legendary"
	local result = {}
	local movedWeight = 0

	for _, entry in ipairs(baseTable) do
		if entry.Rarity == "Golden" and not bothLegendary then
			-- Golden-Chance wird zu Legendary, wenn nicht 2x echte Legendary
			movedWeight += entry.Weight
		else
			table.insert(result, { Rarity = entry.Rarity, Weight = entry.Weight })
		end
	end

	if movedWeight > 0 then
		for _, entry in ipairs(result) do
			if entry.Rarity == "Legendary" then
				entry.Weight += movedWeight
			end
		end
	end

	return result
end

function CowData.RollBreeding(rarityA, rarityB, rng)
	return CowData.RollWeighted(CowData.GetBreedingChances(rarityA, rarityB), rng)
end

-- Zuchtdauer = die längere Zeit der beiden Eltern
function CowData.GetBreedTime(rarityA, rarityB)
	local infoA = CowData.Rarities[rarityA] or CowData.Rarities.Common
	local infoB = CowData.Rarities[rarityB] or CowData.Rarities.Common
	return math.max(infoA.BreedTime, infoB.BreedTime)
end

-- 1234567 -> "1.234.567"
function CowData.FormatNumber(n)
	n = math.floor(tonumber(n) or 0)
	local negative = n < 0
	local digits = tostring(math.abs(n))
	local formatted = digits:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if formatted:sub(1, 1) == "." then
		formatted = formatted:sub(2)
	end
	return (negative and "-" or "") .. formatted
end

return CowData
