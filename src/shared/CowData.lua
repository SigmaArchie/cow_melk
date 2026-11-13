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
	HotbarSize = 9, -- Plätze in der Hotbar (Tasten 1-9), für Kühe UND Milch-Eimer
	MaxBuckets = 100, -- so viele Milch-Eimer passen ins Lager (Hotbar + Eimer-Lager), dann erst verkaufen

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
		Name = "CowShop",
		Page = "Shop",
		Title = "KUH-SHOP",
		Label = "Kuh-Shop",
		Icon = "🐄",
		Area = "Süd-Platz",
		Color = Color3.fromRGB(70, 140, 220),
		RoofColor = Color3.fromRGB(45, 90, 160),
		WallColor = Color3.fromRGB(240, 232, 215),
		Position = Vector3.new(-40, 0, -40),
		FacesEast = true,
	},
	{
		Name = "BreedingBarn",
		Page = "Breeding",
		Title = "ZUCHT-STALL",
		Label = "Zucht-Stall",
		Icon = "💕",
		Area = "Süd-Platz",
		Color = Color3.fromRGB(225, 85, 140),
		RoofColor = Color3.fromRGB(160, 45, 45),
		WallColor = Color3.fromRGB(190, 60, 55),
		Position = Vector3.new(40, 0, -40),
		FacesEast = false,
	},
	{
		Name = "CrateShop",
		Page = "Crates",
		Title = "KISTEN",
		Label = "Kisten",
		Icon = "✨",
		Area = "Nord-Markt",
		Color = Color3.fromRGB(230, 150, 45),
		RoofColor = Color3.fromRGB(170, 95, 30),
		WallColor = Color3.fromRGB(245, 230, 200),
		Position = Vector3.new(-40, 0, 405),
		FacesEast = true,
	},
	{
		Name = "AutoMilkerShop",
		Page = "AutoMilker",
		Title = "AUTO-MELKER",
		Label = "Auto-Melker",
		Icon = "🥛",
		Area = "Nord-Markt",
		Color = Color3.fromRGB(60, 185, 160),
		RoofColor = Color3.fromRGB(40, 110, 100),
		WallColor = Color3.fromRGB(215, 222, 228),
		Position = Vector3.new(40, 0, 405),
		FacesEast = false,
	},
}

-- abgeleitete Werte
CowData.Map.WalkwayCycle = CowData.Map.WalkwayTileLength * CowData.Map.WalkwayTileCount -- 300
CowData.Map.WalkwayVisibleStart = CowData.Map.WalkwayStartZ + CowData.Map.WalkwayTileLength -- 40
CowData.Map.WalkwayVisibleEnd = CowData.Map.WalkwayStartZ + CowData.Map.WalkwayCycle -- 290

------------------------------------------------------------------------
-- Kuh-Arten
-- Jede Kuh hat eine Art. Im Speicherstand heißt das Feld aus alten Zeiten noch "Rarity",
-- deshalb heißt auch diese Tabelle weiter CowData.Rarities.
-- DisplayName:  Name der Art (steht auf Namensschild, Karten, Abzeichen)
-- ClassName:    Seltenheitsstufe (Gewöhnlich ... Prismatisch, Spezial)
-- Tier:         Sortierung / Wertigkeit (ab 4 = seltene Meldung, ab 5 = Ansage im ganzen Server)
-- BreedTier:    mit welcher Stufe die Kuh beim Züchten zählt (1-5)
-- MilkPerPull:  Milch pro erfolgreichem Zug im Melk-Minispiel
-- MilkCooldown: Pause in Sekunden, bevor die Kuh wieder gemolken werden kann
-- ShopPrice:    Preis im Kuh-Shop (ob sie gerade im Lager ist: CowData.Shop)
-- BreedTime:    Zuchtdauer in Sekunden
-- MilkBonus:    extra Chance auf Milch-Sorten, z.B. { Choco = 0.25 } (siehe CowData.MilkTypes)
-- Color / SpotColor / Material / Transparency / Reflectance: Aussehen des Modells
-- Effect / EffectColor: welches Licht-/Partikel-Set aus CowModelBuilder (Standard: eigener Name)
------------------------------------------------------------------------
-- RarityOrder: die "Grund-Linie" aus Zucht und Kisten (die Kisten-Animation zeigt die ersten 5)
CowData.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Golden", "Rainbow", "Ghost" }
-- Alle Arten, nach Wert sortiert (für Listen)
CowData.CowTypeOrder = {
	"Common",
	"Uncommon",
	"Jersey",
	"Rare",
	"Chocolate",
	"Epic",
	"Strawberry",
	"Highland",
	"Legendary",
	"Thunder",
	"Moon",
	"Dragon",
	"Crystal",
	"Golden",
	"Rainbow",
	"Ghost",
}

CowData.Rarities = {
	Common = { -- schwarz/weiß
		DisplayName = "Holstein",
		ClassName = "Gewöhnlich",
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
		DisplayName = "Braunvieh",
		ClassName = "Ungewöhnlich",
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
		DisplayName = "Blauschimmel",
		ClassName = "Selten",
		Tier = 3,
		BreedTier = 3,
		MilkPerPull = 12,
		MilkCooldown = 30,
		ShopPrice = 3500,
		BreedTime = 600,
		Color = Color3.fromRGB(185, 210, 245),
		SpotColor = Color3.fromRGB(50, 85, 170),
		UiColor = Color3.fromRGB(70, 150, 255),
		Material = Enum.Material.SmoothPlastic,
	},
	Epic = { -- lila getönt
		DisplayName = "Lavendel-Kuh",
		ClassName = "Episch",
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
		DisplayName = "Goldfell",
		ClassName = "Legendär",
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
		DisplayName = "Goldene Kuh",
		ClassName = "Spezial",
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
		DisplayName = "Regenbogen-Kuh",
		ClassName = "Spezial",
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
		DisplayName = "Geister-Kuh",
		ClassName = "Spezial",
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

	-- Neue Arten aus dem Kuh-Shop (gibt es nur, wenn sie gerade im Lager sind)
	Jersey = { -- hellbraun ohne Flecken, gibt oft Sahnemilch
		DisplayName = "Jersey",
		ClassName = "Ungewöhnlich",
		Tier = 2,
		BreedTier = 2,
		MilkPerPull = 7,
		MilkCooldown = 25,
		ShopPrice = 1500,
		BreedTime = 450,
		MilkBonus = { Creamy = 0.15 },
		Effect = "Uncommon",
		Color = Color3.fromRGB(200, 146, 92),
		UiColor = Color3.fromRGB(90, 210, 90),
		Material = Enum.Material.SmoothPlastic,
	},
	Chocolate = { -- schokobraun mit cremefarbenen Flecken, gibt oft Schokomilch
		DisplayName = "Schoko-Kuh",
		ClassName = "Selten",
		Tier = 3,
		BreedTier = 3,
		MilkPerPull = 18,
		MilkCooldown = 35,
		ShopPrice = 8000,
		BreedTime = 600,
		MilkBonus = { Choco = 0.25 },
		Effect = "Rare",
		EffectColor = Color3.fromRGB(214, 160, 110),
		Color = Color3.fromRGB(96, 60, 40),
		SpotColor = Color3.fromRGB(236, 214, 178),
		UiColor = Color3.fromRGB(70, 150, 255),
		Material = Enum.Material.SmoothPlastic,
	},
	Strawberry = { -- rosa mit roten Flecken, gibt oft Erdbeermilch
		DisplayName = "Erdbeer-Kuh",
		ClassName = "Episch",
		Tier = 4,
		BreedTier = 4,
		MilkPerPull = 40,
		MilkCooldown = 45,
		ShopPrice = 20000,
		BreedTime = 900,
		MilkBonus = { Berry = 0.2 },
		Effect = "Epic",
		EffectColor = Color3.fromRGB(255, 120, 150),
		Color = Color3.fromRGB(250, 196, 206),
		SpotColor = Color3.fromRGB(214, 58, 78),
		UiColor = Color3.fromRGB(180, 90, 255),
		Material = Enum.Material.SmoothPlastic,
	},
	Highland = { -- zotteliges rotbraunes Fell, gibt manchmal Eismilch (auch ohne Schnee)
		DisplayName = "Hochlandrind",
		ClassName = "Episch",
		Tier = 4,
		BreedTier = 4,
		MilkPerPull = 55,
		MilkCooldown = 50,
		ShopPrice = 35000,
		BreedTime = 900,
		MilkBonus = { Creamy = 0.1, Frozen = 0.04 },
		Effect = "Epic",
		EffectColor = Color3.fromRGB(170, 220, 255),
		Color = Color3.fromRGB(196, 112, 58),
		UiColor = Color3.fromRGB(180, 90, 255),
		Material = Enum.Material.Fabric,
	},
	Thunder = { -- sturmgrau mit gelben Flecken, gibt manchmal Blitzmilch (auch ohne Gewitter)
		DisplayName = "Donner-Kuh",
		ClassName = "Legendär",
		Tier = 5,
		BreedTier = 5,
		MilkPerPull = 110,
		MilkCooldown = 60,
		ShopPrice = 80000,
		BreedTime = 1200,
		MilkBonus = { Shocked = 0.01 },
		Effect = "Legendary",
		EffectColor = Color3.fromRGB(255, 232, 110),
		Color = Color3.fromRGB(84, 94, 124),
		SpotColor = Color3.fromRGB(255, 222, 80),
		UiColor = Color3.fromRGB(255, 160, 40),
		Material = Enum.Material.SmoothPlastic,
	},
	Moon = { -- nachtblau mit silbernen Flecken, gibt manchmal Sternenmilch
		DisplayName = "Mondkuh",
		ClassName = "Mythisch",
		Tier = 6,
		BreedTier = 5,
		MilkPerPull = 220,
		MilkCooldown = 75,
		ShopPrice = 200000,
		BreedTime = 1200,
		MilkBonus = { Starry = 0.03 },
		Effect = "Ghost",
		EffectColor = Color3.fromRGB(200, 210, 255),
		Color = Color3.fromRGB(52, 60, 112),
		SpotColor = Color3.fromRGB(226, 230, 255),
		UiColor = Color3.fromRGB(240, 100, 200),
		Material = Enum.Material.SmoothPlastic,
	},
	Dragon = { -- feuerrot und glänzend, gibt öfter Goldmilch
		DisplayName = "Drachenkuh",
		ClassName = "Göttlich",
		Tier = 7,
		BreedTier = 5,
		MilkPerPull = 400,
		MilkCooldown = 90,
		ShopPrice = 500000,
		BreedTime = 1200,
		MilkBonus = { Gold = 0.03 },
		Effect = "Golden",
		EffectColor = Color3.fromRGB(255, 120, 60),
		Color = Color3.fromRGB(178, 44, 40),
		SpotColor = Color3.fromRGB(46, 30, 30),
		UiColor = Color3.fromRGB(255, 214, 60),
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.1,
	},
	Crystal = { -- eisblauer Kristall, durchscheinend, gibt manchmal Regenbogenmilch
		DisplayName = "Kristallkuh",
		ClassName = "Prismatisch",
		Tier = 8,
		BreedTier = 5,
		MilkPerPull = 700,
		MilkCooldown = 90,
		ShopPrice = 1250000,
		BreedTime = 1200,
		MilkBonus = { Prism = 0.01 },
		Effect = "Rainbow",
		Color = Color3.fromRGB(196, 236, 255),
		SpotColor = Color3.fromRGB(140, 196, 255),
		UiColor = Color3.fromRGB(120, 230, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.2,
		Reflectance = 0.25,
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
-- Wachstum: neue Kühe kommen als Kalb und wachsen mit der Zeit (läuft auch, wenn man offline ist).
-- Jede Stufe ist größer und gibt mehr Milch; ausgewachsen gibt die Kuh die volle Milch (MilkPerPull).
-- From:  ab welchem Anteil der Wachstumszeit die Stufe beginnt (0 .. 1)
-- Scale: Größe des Modells (1 = ausgewachsen)
-- Milk:  Anteil der vollen Milch pro Zug
-- TimeByTier: Wachstumszeit in Sekunden je Stufe der Art (Tier 1 .. 8)
-- Ausgewachsen starten nur: Login-Bonus, Robux-Kisten und Kühe aus alten Speicherständen (auch die Gratis-Kuh ist ein Kalb).
------------------------------------------------------------------------
CowData.Growth = {
	Stages = {
		{ Name = "Kalb", Short = "Kalb", From = 0, Scale = 0.5, Milk = 0.25 },
		{ Name = "Jungkuh", Short = "Jung", From = 0.3, Scale = 0.68, Milk = 0.5 },
		{ Name = "Fast ausgewachsen", Short = "Fast groß", From = 0.65, Scale = 0.84, Milk = 0.75 },
		{ Name = "Ausgewachsen", Short = "Groß", From = 1, Scale = 1, Milk = 1 },
	},
	TimeByTier = { 300, 480, 720, 1080, 1500, 1800, 2400, 3000 }, -- 5 Min (Holstein) ... 50 Min (Kristallkuh)
}

------------------------------------------------------------------------
-- Kuh-Shop mit wechselndem Lager (wie der Samen-Shop in Grow a Garden)
-- Alle RestockInterval Sekunden gibt es neues Lager. Das Lager ist in JEDEM Server und auf dem Client
-- gleich (feste Rechnung aus der Nummer des Zeitabschnitts); jeder Spieler darf bis zur Lager-Menge kaufen.
-- Chance: wie oft die Art im Lager ist (1 = immer), Min/Max: wie viele Stück dann
-- Der Preis steht bei der Art (CowData.Rarities[Type].ShopPrice).
------------------------------------------------------------------------
CowData.Shop = {
	RestockInterval = 300, -- 5 Minuten
	AnnounceTier = 5, -- ab dieser Stufe wird ein Treffer im ganzen Server angesagt
	Stock = {
		{ Type = "Common", Chance = 1, Min = 3, Max = 6 },
		{ Type = "Uncommon", Chance = 0.8, Min = 1, Max = 3 },
		{ Type = "Jersey", Chance = 0.6, Min = 1, Max = 3 },
		{ Type = "Rare", Chance = 0.45, Min = 1, Max = 2 },
		{ Type = "Chocolate", Chance = 0.33, Min = 1, Max = 2 },
		{ Type = "Strawberry", Chance = 0.2, Min = 1, Max = 1 },
		{ Type = "Highland", Chance = 0.14, Min = 1, Max = 1 },
		{ Type = "Thunder", Chance = 0.07, Min = 1, Max = 1 },
		{ Type = "Moon", Chance = 0.035, Min = 1, Max = 1 },
		{ Type = "Dragon", Chance = 0.015, Min = 1, Max = 1 },
		{ Type = "Crystal", Chance = 0.006, Min = 1, Max = 1 },
	},
}

------------------------------------------------------------------------
-- Milch-Mutationen
-- Jedes Melken gibt einen Eimer (Gegenstand in Hotbar/Eimer-Lager). Bei einem VOLLEN Eimer wird jede
-- Mutation einzeln gewürfelt – ein Eimer kann also mehrere haben (z.B. Schoko + Gold).
-- Abgebrochenes Melken gibt einen Eimer ohne Mutation.
-- Multiplier:  Wert-Faktor. Mehrere Mutationen zählen zusammen: 1 + Summe(Multiplier - 1)
--              (Schoko x2 + Gold x20 -> x21). Verkaufswert = Liter * MilkSellPrice * Faktor
-- Chance:      Grundchance (0.05 = 5 %), gilt immer
-- Weather:     zusätzliche Chance nur bei diesem Wetter, z.B. { Rain = 0.35 }
-- ShortName:   kurzer Name für die Hotbar
-- Dazu kommt MilkBonus der Kuh-Art; das Wetter-Glück (Luck) multipliziert am Ende alles.
-- "Normal" ist keine Mutation (nur Name/Farbe für Eimer ohne Mutation).
------------------------------------------------------------------------
CowData.MilkTypeOrder =
	{ "Normal", "Creamy", "Fresh", "Choco", "Berry", "Frozen", "Gold", "Starry", "Prism", "Shocked" }

CowData.MilkTypes = {
	Normal = {
		DisplayName = "Milch",
		ShortName = "Milch",
		Multiplier = 1,
		Chance = 0,
		Color = Color3.fromRGB(250, 244, 228),
	},
	Creamy = {
		DisplayName = "Sahnemilch",
		ShortName = "Sahne",
		Multiplier = 1.5,
		Chance = 0.1,
		Color = Color3.fromRGB(255, 232, 170),
	},
	Fresh = {
		DisplayName = "Frischmilch",
		ShortName = "Frisch",
		Multiplier = 2,
		Chance = 0,
		Weather = { Rain = 0.35, Storm = 0.35 },
		Color = Color3.fromRGB(130, 200, 255),
	},
	Choco = {
		DisplayName = "Schokomilch",
		ShortName = "Schoko",
		Multiplier = 2,
		Chance = 0.05,
		Color = Color3.fromRGB(196, 136, 96),
	},
	Berry = {
		DisplayName = "Erdbeermilch",
		ShortName = "Erdbeer",
		Multiplier = 3,
		Chance = 0.03,
		Color = Color3.fromRGB(255, 140, 170),
	},
	Frozen = {
		DisplayName = "Eismilch",
		ShortName = "Eis",
		Multiplier = 8,
		Chance = 0,
		Weather = { Snow = 0.2 },
		Color = Color3.fromRGB(170, 230, 255),
	},
	Gold = {
		DisplayName = "Goldmilch",
		ShortName = "Gold",
		Multiplier = 20,
		Chance = 0.01,
		Color = Color3.fromRGB(255, 205, 70),
	},
	Starry = {
		DisplayName = "Sternenmilch",
		ShortName = "Sterne",
		Multiplier = 40,
		Chance = 0,
		Weather = { StarNight = 0.08 },
		Color = Color3.fromRGB(200, 180, 255),
	},
	Prism = {
		DisplayName = "Regenbogenmilch",
		ShortName = "Regenbogen",
		Multiplier = 50,
		Chance = 0.002,
		Color = Color3.fromRGB(255, 130, 200),
	},
	Shocked = {
		DisplayName = "Blitzmilch",
		ShortName = "Blitz",
		Multiplier = 100,
		Chance = 0,
		Weather = { Storm = 0.03 },
		Color = Color3.fromRGB(255, 240, 90),
	},
}

------------------------------------------------------------------------
-- Wetter-Events (gelten für den ganzen Server, siehe WeatherManager.server.lua)
-- Zwischen zwei Events scheint PauseMin..PauseMax Sekunden die Sonne.
-- Weight: wie oft das Wetter kommt, Luck: alle Milch-Chancen werden damit multipliziert
------------------------------------------------------------------------
CowData.WeatherSettings = {
	PauseMin = 240,
	PauseMax = 420,
	StudioFirstEvent = 30, -- nur in Studio: erstes Event schon nach 30 s (zum Testen)
}

CowData.WeatherOrder = { "Rain", "Storm", "Snow", "StarNight" }

CowData.Weather = {
	Clear = { DisplayName = "Sonne", Icon = "☀", Luck = 1, Hint = "" },
	Rain = {
		DisplayName = "Regen",
		Icon = "🌧",
		Duration = 150,
		Weight = 40,
		Luck = 1,
		Hint = "Frischmilch x2 möglich",
	},
	Storm = {
		DisplayName = "Gewitter",
		Icon = "⛈",
		Duration = 120,
		Weight = 15,
		Luck = 1,
		Hint = "Blitzmilch x100 möglich!",
	},
	Snow = {
		DisplayName = "Schnee",
		Icon = "❄",
		Duration = 150,
		Weight = 25,
		Luck = 1,
		Hint = "Eismilch x8 möglich",
	},
	StarNight = {
		DisplayName = "Sternennacht",
		Icon = "🌠",
		Duration = 150,
		Weight = 10,
		Luck = 2,
		Hint = "Sternenmilch x40 · doppeltes Glück",
	},
}

------------------------------------------------------------------------
-- Kuh-Namen
------------------------------------------------------------------------
CowData.Names = {
	"Berta",
	"Liesl",
	"Rosi",
	"Elsa",
	"Muhriel",
	"Frieda",
	"Klara",
	"Lotte",
	"Heidi",
	"Greta",
	"Paula",
	"Wilma",
	"Bella",
	"Daisy",
	"Milka",
	"Susi",
	"Trudi",
	"Hanni",
	"Kuhnigunde",
	"Muhtilda",
	"Flecki",
	"Sternchen",
	"Butterblume",
	"Gundula",
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

-- Wachstumszeit einer Art in Sekunden
function CowData.GetGrowTime(cowType)
	local info = CowData.Rarities[cowType] or CowData.Rarities.Common
	local times = CowData.Growth.TimeByTier
	return times[math.clamp(info.Tier, 1, #times)]
end

-- Wie weit ist die Kuh gewachsen? cow braucht BornAt + GrowTime (fehlen sie: ausgewachsen).
-- Gibt (Fortschritt 0..1, Stufen-Nummer, Stufe, Sekunden bis zur nächsten Stufe) zurück.
function CowData.GetGrowth(cow, now)
	local stages = CowData.Growth.Stages
	local bornAt, growTime = cow and cow.BornAt, cow and cow.GrowTime
	if type(bornAt) ~= "number" or type(growTime) ~= "number" or growTime <= 0 then
		return 1, #stages, stages[#stages], 0
	end
	local progress = math.clamp((now - bornAt) / growTime, 0, 1)
	local index = 1
	for i, stage in ipairs(stages) do
		if progress >= stage.From then
			index = i
		end
	end
	local nextStage = stages[index + 1]
	local timeToNext = nextStage and math.max(0, bornAt + growTime * nextStage.From - now) or 0
	return progress, index, stages[index], timeToNext
end

-- Sekunden, bis die Kuh ganz ausgewachsen ist (0 = schon groß)
function CowData.GetTimeToGrown(cow, now)
	if type(cow.BornAt) ~= "number" or type(cow.GrowTime) ~= "number" then
		return 0
	end
	return math.max(0, cow.BornAt + cow.GrowTime - now)
end

function CowData.IsGrown(cow, now)
	local progress = CowData.GetGrowth(cow, now)
	return progress >= 1
end

-- Milch pro Zug für diese Kuh jetzt (volle Milch nur ausgewachsen)
function CowData.GetMilkPerPull(cow, now)
	local info = CowData.Rarities[cow.Rarity] or CowData.Rarities.Common
	local _, _, stage = CowData.GetGrowth(cow, now)
	return info.MilkPerPull * stage.Milk
end

-- 0.5 -> "0,5", 12 -> "12", 1234 -> "1.234" (für Milch pro Zug bei Kälbern)
function CowData.FormatAmount(n)
	if n % 1 ~= 0 and n < 100 then
		return (("%.1f"):format(n):gsub("%.", ","))
	end
	return CowData.FormatNumber(n)
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

------------------------------------------------------------------------
-- Kuh-Shop: Lager
------------------------------------------------------------------------
-- Nummer des aktuellen Zeitabschnitts (alle Server rechnen gleich)
function CowData.GetShopCycle(now)
	return math.floor(now / CowData.Shop.RestockInterval)
end

-- Zeitpunkt (os.time), an dem nach diesem Abschnitt neues Lager kommt
function CowData.GetRestockTime(cycle)
	return (cycle + 1) * CowData.Shop.RestockInterval
end

function CowData.GetShopEntry(cowType)
	for _, entry in ipairs(CowData.Shop.Stock) do
		if entry.Type == cowType then
			return entry
		end
	end
	return nil
end

-- 32-Bit-Multiplikation ohne Rundungsfehler (Luau-Zahlen sind doubles)
local function mul32(a, b)
	local aLo, aHi = bit32.band(a, 0xFFFF), bit32.rshift(a, 16)
	local bLo, bHi = bit32.band(b, 0xFFFF), bit32.rshift(b, 16)
	local mid = bit32.band(aHi * bLo + aLo * bHi, 0xFFFF)
	return bit32.band(aLo * bLo + mid * 65536, 0xFFFFFFFF)
end

-- Mischfunktion (murmur3 fmix32): aus einer Zahl wird eine "zufällig" aussehende Zahl
local function mix32(h)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 0xC2B2AE35)
	return bit32.bxor(h, bit32.rshift(h, 16))
end

-- Feste "Zufallszahl" 0..1 für (Abschnitt, Eintrag, Wurf): Server und Client rechnen exakt gleich
local function stockRoll(cycle, index, salt)
	local h = mix32(bit32.bxor(cycle % 4294967296, mul32(index, 0x9E3779B1)))
	h = mix32(bit32.bxor(h, mul32(salt, 0x85EBCA77)))
	return h / 4294967296
end

-- Lager eines Zeitabschnitts: { [Kuh-Art] = Menge } (nur Arten, die da sind)
function CowData.RollShopStock(cycle)
	local stock = {}
	for index, entry in ipairs(CowData.Shop.Stock) do
		if stockRoll(cycle, index, 1) < entry.Chance then
			local spread = entry.Max - entry.Min + 1
			stock[entry.Type] = entry.Min + math.min(math.floor(stockRoll(cycle, index, 2) * spread), spread - 1)
		end
	end
	return stock
end

------------------------------------------------------------------------
-- Milch-Sorten
------------------------------------------------------------------------
function CowData.IsValidMilkType(milkType)
	return type(milkType) == "string" and CowData.MilkTypes[milkType] ~= nil
end

-- Chance (0..0.95) auf eine Milch-Sorte für diese Kuh-Art bei diesem Wetter
function CowData.GetMilkTypeChance(milkType, cowType, weather)
	local info = CowData.MilkTypes[milkType]
	if not info or milkType == "Normal" then
		return 0
	end
	local chance = info.Chance or 0
	if info.Weather and info.Weather[weather] then
		chance += info.Weather[weather]
	end
	local cowInfo = CowData.Rarities[cowType]
	if cowInfo and cowInfo.MilkBonus and cowInfo.MilkBonus[milkType] then
		chance += cowInfo.MilkBonus[milkType]
	end
	local weatherInfo = CowData.Weather[weather] or CowData.Weather.Clear
	return math.min(chance * (weatherInfo.Luck or 1), 0.95)
end

-- Würfelt die Mutationen für einen vollen Eimer. Jede wird einzeln gewürfelt.
-- Gibt eine Liste zurück, wertvollste zuerst, z.B. { "Gold", "Choco" } (leer = normale Milch)
function CowData.RollMilkMutations(cowType, weather, rng)
	rng = rng or Random.new()
	local mutations = {}
	for i = #CowData.MilkTypeOrder, 2, -1 do
		local milkType = CowData.MilkTypeOrder[i]
		local chance = CowData.GetMilkTypeChance(milkType, cowType, weather)
		if chance > 0 and rng:NextNumber() < chance then
			table.insert(mutations, milkType)
		end
	end
	return mutations
end

-- Wert-Faktor einer Mutations-Liste: 1 + Summe(Multiplier - 1)
function CowData.GetMutationMultiplier(mutations)
	local multiplier = 1
	for _, milkType in ipairs(mutations or {}) do
		local info = CowData.MilkTypes[milkType]
		if info then
			multiplier += info.Multiplier - 1
		end
	end
	return multiplier
end

-- Nur bekannte Mutationen, jede einmal, wertvollste zuerst (für Daten vom Speicher / Client)
function CowData.CleanMutations(mutations)
	local has = {}
	if type(mutations) == "table" then
		for _, milkType in ipairs(mutations) do
			if milkType ~= "Normal" and CowData.IsValidMilkType(milkType) then
				has[milkType] = true
			end
		end
	end
	local clean = {}
	for i = #CowData.MilkTypeOrder, 2, -1 do
		if has[CowData.MilkTypeOrder[i]] then
			table.insert(clean, CowData.MilkTypeOrder[i])
		end
	end
	return clean
end

-- "Schoko + Gold" (kurz) bzw. "Schokomilch + Goldmilch" (lang); keine Mutation -> "Milch"
function CowData.FormatMutations(mutations, short)
	if not mutations or #mutations == 0 then
		return "Milch"
	end
	local names = {}
	for _, milkType in ipairs(mutations) do
		local info = CowData.MilkTypes[milkType]
		if info then
			table.insert(names, short and info.ShortName or info.DisplayName)
		end
	end
	return table.concat(names, " + ")
end

-- Größe eines Milch-Eimers nach Litern (1 = normal): 20 L -> 0,8 · 200 L -> 1,15 · 2.000 L -> 1,5 · ab ~20.000 L -> 2,2
function CowData.GetBucketScale(liters)
	local amount = math.max(tonumber(liters) or 0, 1)
	return math.clamp(0.8 + 0.35 * math.log10(amount / 20), 0.8, 2.2)
end

-- Größen-Namen für die Anzeige (bis MaxLiters)
CowData.BucketSizes = {
	{ MaxLiters = 50, Name = "Klein" },
	{ MaxLiters = 300, Name = "Mittel" },
	{ MaxLiters = 1500, Name = "Groß" },
	{ MaxLiters = math.huge, Name = "Riesig" },
}

function CowData.GetBucketSizeName(liters)
	for _, size in ipairs(CowData.BucketSizes) do
		if liters <= size.MaxLiters then
			return size.Name
		end
	end
	return "Riesig"
end

-- Verkaufswert eines Eimers in Coins
function CowData.GetBucketValue(liters, mutations)
	return math.floor(liters * CowData.Config.MilkSellPrice * CowData.GetMutationMultiplier(mutations))
end

-- "x1.5" / "x20"
function CowData.FormatMultiplier(multiplier)
	if multiplier % 1 == 0 then
		return "x" .. multiplier
	end
	return (("x%.1f"):format(multiplier):gsub("%.", ","))
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
