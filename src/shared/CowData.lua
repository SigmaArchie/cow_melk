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
	MaxCows = 40, -- maximale Kühe pro Farm (für Coin-Käufe & Zucht)

	-- Melk-Minispiel
	PullsPerMilking = 10, -- so viele richtige Züge, bis der Eimer voll ist
	WrongPullPenalty = 1, -- falsche Seite gezogen -> so viele Züge Fortschritt weg
	MinPullInterval = 0.1, -- schnellste erlaubte Zug-Rate (Anti-Cheat)
	MilkingAnimationId = 0, -- optional: eigene Animation-ID (0 = keine)
	-- Sounds (Roblox-Asset-IDs). Leerer Text = Sound aus.
	SquirtSoundId = "rbxassetid://5857005819", -- bei jedem Zug
	MilkDoneSoundId = "rbxassetid://5857005819", -- Eimer voll (tiefer abgespielt)
	SellSoundId = "rbxassetid://4590662766", -- Coins beim Verkaufen
	CoinSoundId = "rbxassetid://4590662766", -- Coins-Zähler steigt (HUD)
	AmbientSoundId = "rbxassetid://1843671818", -- Hintergrund-Musik (Loop)
	MooSoundId = "rbxassetid://535690488", -- Kuh muht (alle 15-30 s pro Kuh)
	NewCowSoundId = "rbxassetid://4590662766", -- neue Kuh auf der Farm
	-- eingebaute Roblox-Sounds; falls sie stumm bleiben, eigene IDs eintragen:
	ShopOpenSoundId = "rbxasset://sounds/swoosh.wav", -- Shop-Fenster öffnet
	RareCowSoundId = "rbxasset://sounds/victory.wav", -- Fanfare für Episch und besser

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

	-- Farm-Plots links (Westen) und rechts (Osten) der Allee
	PlotWidth = 90, -- entlang der Allee
	PlotDepth = 110, -- von der Allee weg
	PlotCenterX = 75,
	PlotRowStartZ = 70,
	PlotRowSpacing = 95,

	-- Förderbänder in der Mitte (eins nach Norden, eins nach Süden).
	-- 6 Kacheln à 50 Studs laufen im Kreis (Zyklus = 300 Studs). Die ersten und letzten
	-- 50 Studs stecken in "Maschinen-Gehäusen", dort springen die Kacheln unsichtbar zurück.
	WalkwayStartZ = -10, -- Beginn des vorderen Gehäuses
	WalkwayTileLength = 50,
	WalkwayTileCount = 6,
	WalkwayX = 6, -- Abstand der Bandmitte von der Mittellinie
	WalkwayWidth = 10,
	WalkwaySpeed = 22, -- Studs pro Sekunde
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
