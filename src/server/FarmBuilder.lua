-- FarmBuilder.lua
-- Baut den Bauernhof eines Spielers (nur Deko, ohne Spiel-Logik). Benutzt von CowManager.getFarm.
--
-- Lokale Plot-Koordinaten (Ursprung = Mitte der Farm, siehe CowData.GetPlotOrigin):
--   +Z (z = +70)  Hof-Tor mit Schild "Farm von ..." – zeigt zum Marktplatz
--   z = 32 .. 70  Hof: Weg, Scheune + Silo (links), Milch-Stand, Brunnen, Bauernhaus, Hühner (rechts)
--   z = 32        Holzzaun mit offenem Gatter zur Weide
--   z = -70 .. 32 Weide mit den Kühen (6 x 6 Felder, siehe CowData.GetGridCellLocal)
--
--   x = -54 ... +54, rundherum ein Holzzaun.
-- Der Part "Sign" (Torschild) muss so heißen: das Tutorial zeigt darauf.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local Palette = require(ReplicatedStorage.Shared:WaitForChild("Palette"))
local FarmProps = require(script.Parent:WaitForChild("FarmProps"))

local Map = CowData.Map
local World = Palette.World
local Colors = FarmProps.Colors
local part, soft = FarmProps.Part, FarmProps.Soft

local GROUND = Map.GroundTop
local HALF_W, HALF_D = Map.PlotWidth / 2, Map.PlotDepth / 2 -- 54, 70
local FRONT_Z = Map.PastureFrontZ -- 32
local ENTRANCE = 7.5 -- halbe Breite des Hof-Tors
local GATE = 5 -- halbe Breite des Weide-Gatters
local FENCE = HALF_W - 1 -- Zaun 1 Stud innerhalb der Plot-Kante

local FarmBuilder = {}

-- Schild über dem Hof-Tor (beide Seiten beschriftet)
local function buildSign(parent, cframe, ownerName)
	local sign = part(parent, "Sign", Vector3.new(13, 2.6, 0.4), cframe, World.WoodDark, Enum.Material.Wood)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local surface = Instance.new("SurfaceGui")
		surface.Face = face
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 50
		surface.LightInfluence = 0.2
		surface.Parent = sign
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 0.86)
		text.BackgroundTransparency = 1
		text.Font = Palette.Fonts.Heading
		text.TextScaled = true
		text.TextColor3 = Palette.Colors.Cream
		text.Text = "🐄 Farm von " .. ownerName
		text.Parent = surface
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 80
		limit.Parent = text
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0.05, 0)
		padding.PaddingRight = UDim.new(0.05, 0)
		padding.PaddingTop = UDim.new(0.1, 0)
		padding.Parent = text
		local stripe = Instance.new("Frame")
		stripe.AnchorPoint = Vector2.new(0.5, 1)
		stripe.Position = UDim2.fromScale(0.5, 0.94)
		stripe.Size = UDim2.fromScale(0.8, 0.06)
		stripe.BackgroundColor3 = Palette.Colors.Green
		stripe.BorderSizePixel = 0
		stripe.Parent = surface
	end
	return sign
end

-- Boden: Weide (sattes Wiesengrün mit helleren/dunkleren Flecken), Hof (gemähter Rasen + Hofplatz aus Erde)
local function buildGround(decor, origin, rng)
	local pastureDepth = FRONT_Z + HALF_D
	part(
		decor,
		"Ground",
		Vector3.new(Map.PlotWidth, GROUND, pastureDepth),
		origin * CFrame.new(0, GROUND / 2, (FRONT_Z - HALF_D) / 2),
		Colors.Meadow,
		Enum.Material.Grass
	)
	part(
		decor,
		"Ground",
		Vector3.new(Map.PlotWidth, GROUND, HALF_D - FRONT_Z),
		origin * CFrame.new(0, GROUND / 2, (FRONT_Z + HALF_D) / 2),
		Colors.MeadowLight,
		Enum.Material.Grass
	)
	-- Flecken auf der Weide (flache Scheiben), damit sie nicht wie ein Teppich aussieht
	for i = 1, 6 do
		local diameter = rng:NextNumber(14, 26)
		FarmProps.Column(
			decor,
			"MeadowPatch",
			0.04,
			diameter,
			origin
				* CFrame.new(
					rng:NextNumber(-HALF_W + diameter / 2, HALF_W - diameter / 2),
					GROUND + 0.02,
					rng:NextNumber(-HALF_D + diameter / 2, FRONT_Z - diameter / 2)
				),
			i % 2 == 0 and Colors.MeadowDark or Colors.MeadowLight,
			Enum.Material.Grass,
			{ CanCollide = false, CanQuery = false, CastShadow = false }
		)
	end
	-- Hofplatz aus festgetretener Erde und gepflasterter Weg zum Tor
	FarmProps.Strip(
		decor,
		"Yard",
		origin * CFrame.new(0, GROUND + 0.03, (FRONT_Z + 60) / 2 + 0.5),
		56,
		60 - FRONT_Z - 1,
		Colors.Dirt,
		Enum.Material.Ground,
		0.06
	)
	FarmProps.Strip(
		decor,
		"Path",
		origin * CFrame.new(0, GROUND + 0.05, (60 + HALF_D) / 2),
		8,
		HALF_D - 60,
		World.StonePath,
		Enum.Material.Cobblestone,
		0.08
	)
end

-- Holzzaun rundherum, Zaun zwischen Hof und Weide mit offenem Gatter
local function buildFences(decor, origin)
	local y = GROUND
	local function fence(x1, z1, x2, z2, options)
		FarmProps.Fence(decor, origin, Vector3.new(x1, y, z1), Vector3.new(x2, y, z2), options)
	end
	local back, front = -HALF_D + 1, HALF_D - 1
	fence(-FENCE, back, FENCE, back, { Rails = 3 })
	fence(-FENCE, back, -FENCE, front, { Rails = 3 })
	fence(FENCE, back, FENCE, front, { Rails = 3 })
	fence(-FENCE, front, -ENTRANCE - 1.2, front)
	fence(ENTRANCE + 1.2, front, FENCE, front)
	-- Weide-Zaun mit Gatter in der Mitte
	fence(-FENCE, FRONT_Z, -GATE, FRONT_Z, { Rails = 3 })
	fence(GATE, FRONT_Z, FENCE, FRONT_Z, { Rails = 3 })
	for _, x in ipairs({ -GATE, GATE }) do
		part(
			decor,
			"GatePost",
			Vector3.new(0.9, 5, 0.9),
			origin * CFrame.new(x, y + 2.5, FRONT_Z),
			World.WoodDark,
			Enum.Material.Wood
		)
	end
	-- offener Gatterflügel (an x = +GATE angeschlagen, in die Weide geschwenkt)
	local hinge = origin * CFrame.new(GATE, y, FRONT_Z) * CFrame.Angles(0, math.rad(-70), 0)
	local leaf = GATE * 2 - 0.6
	for _, height in ipairs({ 1.2, 2.4, 3.6 }) do
		soft(
			decor,
			"GateRail",
			Vector3.new(leaf, 0.35, 0.25),
			hinge * CFrame.new(-leaf / 2, height, 0),
			World.WoodLight,
			Enum.Material.Wood
		)
	end
	soft(
		decor,
		"GateBrace",
		Vector3.new(math.sqrt(leaf * leaf + 2.4 * 2.4), 0.3, 0.2),
		hinge * CFrame.new(-leaf / 2, 2.4, 0) * CFrame.Angles(0, 0, math.atan2(2.4, leaf)),
		World.WoodLight,
		Enum.Material.Wood
	)
end

-- Hof-Tor: zwei Steinpfeiler mit Laternen, Holzbalken und Namensschild
local function buildEntrance(decor, origin, ownerName)
	local z = HALF_D - 1
	for _, x in ipairs({ -ENTRANCE, ENTRANCE }) do
		part(
			decor,
			"GatePillar",
			Vector3.new(2.2, 6, 2.2),
			origin * CFrame.new(x, GROUND + 3, z),
			World.StoneDark,
			Enum.Material.Cobblestone
		)
		soft(
			decor,
			"GatePillarCap",
			Vector3.new(2.7, 0.4, 2.7),
			origin * CFrame.new(x, GROUND + 6.2, z),
			World.Stone,
			Enum.Material.Concrete
		)
		local lamp = soft(
			decor,
			"GateLamp",
			Vector3.new(1, 1.3, 1),
			origin * CFrame.new(x, GROUND + 7.05, z),
			World.Lantern,
			Enum.Material.Neon
		)
		if x > 0 then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 222, 165)
			light.Brightness = 1
			light.Range = 18
			light.Shadows = false
			light.Parent = lamp
		end
		part(
			decor,
			"GatePost",
			Vector3.new(0.9, 4, 0.9),
			origin * CFrame.new(x, GROUND + 8.6, z),
			World.WoodDark,
			Enum.Material.Wood
		)
	end
	part(
		decor,
		"GateBeam",
		Vector3.new(ENTRANCE * 2 + 2.4, 0.9, 1),
		origin * CFrame.new(0, GROUND + 10.9, z),
		World.Wood,
		Enum.Material.Wood
	)
	buildSign(decor, origin * CFrame.new(0, GROUND + 12.8, z), ownerName)
end

-- Weide: Wildblumen, Steine in den Ecken (Kühe laufen hindurch, nichts kollidiert)
local function buildPastureDecor(decor, origin, rng)
	for _ = 1, 10 do
		FarmProps.Wildflowers(
			decor,
			origin
				* CFrame.new(rng:NextNumber(-HALF_W + 4, HALF_W - 4), GROUND, rng:NextNumber(-HALF_D + 4, FRONT_Z - 4)),
			2.2,
			4,
			rng
		)
	end
	for _, corner in ipairs({ { -1, -1 }, { 1, -1 } }) do
		FarmProps.Rock(
			decor,
			origin * CFrame.new(corner[1] * (FENCE - 1.6), GROUND, -HALF_D + 2.8),
			rng:NextNumber(0.7, 1)
		)
	end
end

-- Hof: Scheune, Silo, Traktor, Heu, Brunnen, Bauernhaus, Hühner, Beete ...
local function buildYard(decor, origin, rng)
	local function at(x, z, yaw)
		return origin * CFrame.new(x, GROUND, z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
	end

	-- links: Scheune (Tor zeigt zum Hofplatz, +X) und Silo dahinter
	FarmProps.Barn(decor, at(-40, 50, -90))
	FarmProps.Silo(decor, at(-46, 36.5, -90), 18, 7)
	FarmProps.Tractor(decor, at(-15, 52, 0))
	FarmProps.Wheelbarrow(decor, at(-21, 42, 35))
	FarmProps.RoundBale(decor, at(-24, 36, 90))
	FarmProps.RoundBale(decor, at(-30, 37, 80))
	FarmProps.HayBale(decor, at(-24, 62, 0))
	FarmProps.HayBale(decor, at(-24, 64.6, 0))
	FarmProps.HayBale(decor, origin * CFrame.new(-24, GROUND + 1.8, 63.3) * CFrame.Angles(0, math.rad(8), 0))
	FarmProps.Crate(decor, at(-27, 43.4, 15), 1.8)
	FarmProps.Crate(decor, at(-26.4, 41.2, -10), 1.5)
	FarmProps.Tree(decor, at(-45, 64), { Scale = 1.15, Rng = rng })
	FarmProps.Bench(decor, at(-34, 66, 180))

	-- am Weide-Zaun: Wassertrog und Heuraufe (die Kühe "fressen über den Zaun")
	FarmProps.Trough(decor, at(-14, 34.3), 6)
	FarmProps.HayRack(decor, at(14, 34.4), 6)

	-- rechts: Brunnen, Milchkannen, Bauernhaus, Hühnerstall
	FarmProps.Well(decor, at(23, 41))
	FarmProps.MilkCans(decor, at(19.5, 56.5, 90), 3)
	FarmProps.Farmhouse(decor, at(41, 57, 90))
	FarmProps.ChickenCoop(decor, at(45, 40, 90))
	FarmProps.Chicken(decor, at(39, 38, 70))
	FarmProps.Chicken(decor, at(37.5, 42.5, 140))
	FarmProps.Chicken(decor, at(41, 45, -30))
	FarmProps.Cart(decor, at(31, 66.5, 90))
	FarmProps.Bush(decor, at(50, 67), 1.1)
	FarmProps.Lantern(decor, at(6, 40, 90), false)

	-- vorne: Blumenbeete neben dem Tor, Briefkasten
	FarmProps.FlowerBed(decor, at(-17, 66), 12, 3, rng)
	FarmProps.FlowerBed(decor, at(17, 66), 12, 3, rng)
	FarmProps.Mailbox(decor, at(-9.6, 67.8, 180))
end

-- Baut alles in einen neuen Folder "Decor" im Farm-Model.
-- Rückgabe: decor, { StandCFrame = Milch-Stand (Kundenseite -Z), SpawnCFrame = Spawn auf dem Hof }
function FarmBuilder.Build(model, origin, slot, ownerName)
	local rng = Random.new(1000 + slot * 37)
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = model

	buildGround(decor, origin, rng)
	buildFences(decor, origin)
	buildEntrance(decor, origin, ownerName)
	buildPastureDecor(decor, origin, rng)
	buildYard(decor, origin, rng)

	return decor,
		{
			-- Milch-Stand rechts vom Weg, Kunden stehen auf dem Weg (-Z des Stands zeigt nach -X)
			StandCFrame = origin * CFrame.new(13, GROUND, 49) * CFrame.Angles(0, math.rad(90), 0),
			-- auf dem Hof vor dem Weide-Gatter, Blick zu den Kühen (-Z)
			SpawnCFrame = origin * CFrame.new(0, GROUND + 4, 44),
		}
end

return FarmBuilder
