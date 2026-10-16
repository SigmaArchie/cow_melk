-- MapBuilder.server.lua
-- Baut einmalig die gemeinsame Karte (alles unter Workspace.CowFarmLayout):
--   * Süd-Platz mit Brunnen, Kuh-Shop und Zucht-Stall
--   * Nord-Markt am anderen Ende der Förderbänder mit Kisten und Auto-Melker
--   (Shop-Daten stehen in CowData.Map.Shops; jedes Gebäude bekommt einen Teleport-Punkt)
--   * Allee nach Norden mit ZWEI Laufbändern (eins nach Norden, eins nach Süden)
--   * Begrüßungsbogen und Laternen
-- Die Farm-Plots selbst baut CowManager.server.lua links und rechts der Allee.
--
-- Förderbänder: Das unsichtbare Band ("Belt") schiebt Spieler über AssemblyLinearVelocity.
-- Darauf liegen 6 sichtbare Kacheln (10 x 0.5 x 50, schwarz mit gelben Pfeilen), die der
-- Client mit RunService.Heartbeat bewegt (WorldAnimator) und am Ende sofort zurücksetzt.
-- Shops: ClickDetector -> Remotes.OpenShop:FireClient(player, page) -> MenuUI öffnet das Fenster.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Palette = require(ReplicatedStorage.Shared:WaitForChild("Palette"))
local Map = CowData.Map
local Pal = Palette.Colors
local World = Palette.World

local layoutFolder = workspace:FindFirstChild("CowFarmLayout")
if not layoutFolder then
	layoutFolder = Instance.new("Folder")
	layoutFolder.Name = "CowFarmLayout"
	layoutFolder.Parent = workspace
end

-- alte Version (z.B. nach Neustart im Studio) entfernen
for _, name in ipairs({ "Hub", "Walkways", "Avenue", "NorthMarket" }) do
	local old = layoutFolder:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

local function makePart(props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	return part
end

local function makeWedge(props)
	local part = Instance.new("WedgePart")
	part.Anchored = true
	for key, value in pairs(props) do
		part[key] = value
	end
	return part
end

-- Text auf einer Fläche eines Parts (Creme auf tiefem Marineblau, ohne Schrift-Umriss)
local function addSurfaceText(part, face, text, textColor, backgroundColor)
	local surface = Instance.new("SurfaceGui")
	surface.Face = face
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.LightInfluence = 0
	surface.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = backgroundColor or Pal.Deep
	label.BackgroundTransparency = 0
	label.Font = Palette.Fonts.Heading
	label.TextScaled = true
	label.TextColor3 = textColor or Pal.Cream
	label.Text = text
	label.Parent = surface

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.1, 0)
	padding.PaddingBottom = UDim.new(0.1, 0)
	padding.Parent = label
	return surface
end

local GROUND = Map.GroundTop
local WALK_START = Map.WalkwayStartZ -- Beginn vorderes Gehäuse
local WALK_END = Map.WalkwayStartZ + Map.WalkwayCycle + Map.WalkwayTileLength -- Ende hinteres Gehäuse
local VISIBLE_START = Map.WalkwayVisibleStart
local VISIBLE_END = Map.WalkwayVisibleEnd
local VISIBLE_CENTER_Z = (VISIBLE_START + VISIBLE_END) / 2
local AVENUE_START = 0 -- Allee beginnt an der Platzkante
local AVENUE_END = WALK_END + 10
local AVENUE_CENTER_Z = (AVENUE_START + AVENUE_END) / 2
local AVENUE_LENGTH = AVENUE_END - AVENUE_START

local STONE = Color3.fromRGB(205, 200, 190)
local STONE_DARK = Color3.fromRGB(150, 145, 138)
local AVENUE_HALF = 18

------------------------------------------------------------------------
-- Allee (Gehweg rechts und links der Laufbänder)
------------------------------------------------------------------------
local avenue = Instance.new("Folder")
avenue.Name = "Avenue"
avenue.Parent = layoutFolder

-- beginnt genau an der Platzkante (z = 0), damit sich nichts überlappt
makePart({
	Name = "Sidewalk",
	Size = Vector3.new(AVENUE_HALF * 2, 0.2, AVENUE_LENGTH),
	CFrame = CFrame.new(0, 0.1, AVENUE_CENTER_Z),
	Color = STONE,
	Material = Enum.Material.Pavement,
	Parent = avenue,
})
-- Bordsteine
for _, side in ipairs({ -1, 1 }) do
	makePart({
		Name = "Curb",
		Size = Vector3.new(0.8, 0.5, AVENUE_LENGTH),
		CFrame = CFrame.new(side * (AVENUE_HALF + 0.4), 0.25, AVENUE_CENTER_Z),
		Color = STONE_DARK,
		Material = Enum.Material.Concrete,
		Parent = avenue,
	})
end

-- Laternen entlang der Allee
for z = AVENUE_START + 30, AVENUE_END - 10, 40 do
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (AVENUE_HALF - 2)
		makePart({
			Name = "LampPost",
			Size = Vector3.new(0.5, 9, 0.5),
			CFrame = CFrame.new(x, 4.5, z),
			Color = Color3.fromRGB(45, 48, 55),
			Material = Enum.Material.Metal,
			Parent = avenue,
		})
		local lamp = makePart({
			Name = "Lamp",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.4, 1.4, 1.4),
			CFrame = CFrame.new(x, 9.4, z),
			Color = Color3.fromRGB(255, 240, 200),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = avenue,
		})
		local light = Instance.new("PointLight")
		light.Range = 18
		light.Brightness = 1.2
		light.Color = Color3.fromRGB(255, 230, 180)
		light.Parent = lamp
	end
end

------------------------------------------------------------------------
-- Förderbänder
------------------------------------------------------------------------
local walkways = Instance.new("Folder")
walkways.Name = "Walkways"
walkways.Parent = layoutFolder

local YELLOW = Color3.fromRGB(255, 205, 30)
local BLACK = Color3.fromRGB(28, 28, 32)
local BELT_TOP = GROUND + 0.2 -- etwas höher als der Gehweg

-- Gelb-schwarz gestreifte Leiste (wie Warnband) entlang einer Strecke
local function hazardStrip(parent, center, length, height)
	local stripe = 4
	local count = math.floor(length / stripe)
	for i = 0, count - 1 do
		makePart({
			Name = "Hazard",
			Size = Vector3.new(0.6, height, stripe),
			CFrame = CFrame.new(center + Vector3.new(0, 0, -length / 2 + (i + 0.5) * stripe)),
			Color = i % 2 == 0 and YELLOW or BLACK,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
	end
end

-- Eine Kachel: schwarze Platte mit 8 gelben Pfeilen (Spitze zeigt in Laufrichtung)
local function buildTile(parent, index, x, direction)
	local width = Map.WalkwayWidth
	local length = Map.WalkwayTileLength
	local tile = Instance.new("Model")
	tile.Name = "Tile" .. index

	local facing = direction == 1 and CFrame.identity or CFrame.Angles(0, math.pi, 0)
	-- Startposition wie im Client bei Zeit 0 (WorldAnimator rechnet ab hier weiter)
	local u = (index * length) % Map.WalkwayCycle
	local origin = CFrame.new(x, BELT_TOP - 0.23, Map.WalkwayStartZ + u + length / 2) * facing

	local base = makePart({
		Name = "Plate",
		Size = Vector3.new(width, 0.5, length - 0.3),
		CFrame = origin,
		Color = BLACK,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = tile,
	})
	-- Pfeile "^"
	for i = 0, 7 do
		local z = -length / 2 + (i + 0.5) * (length / 8)
		for _, side in ipairs({ -1, 1 }) do
			makePart({
				Name = "Arrow",
				Size = Vector3.new(0.9, 0.06, 3.6),
				CFrame = origin * CFrame.new(side * 1.2, 0.27, z) * CFrame.Angles(0, math.rad(-40 * side), 0),
				Color = YELLOW,
				Material = Enum.Material.Neon,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Parent = tile,
			})
		end
	end

	tile.PrimaryPart = base
	tile:SetAttribute("Index", index)
	tile:SetAttribute("Direction", direction)
	tile:SetAttribute("X", x)
	tile:SetAttribute("Y", BELT_TOP - 0.23)
	tile:SetAttribute("StartZ", Map.WalkwayStartZ)
	tile:SetAttribute("Cycle", Map.WalkwayCycle)
	tile:SetAttribute("Length", length)
	tile:SetAttribute("Speed", Map.WalkwaySpeed)
	tile.Parent = parent
	CollectionService:AddTag(tile, "ConveyorTile")
	return tile
end

-- Maschinen-Gehäuse an den Enden (verdecken das Zurückspringen der Kacheln)
local function buildHousing(parent, x, zStart, label)
	local length = Map.WalkwayTileLength
	local width = Map.WalkwayWidth + 1.6
	local center = Vector3.new(x, 0, zStart + length / 2)
	makePart({
		Name = "Housing",
		Size = Vector3.new(width, 3.2, length),
		CFrame = CFrame.new(center + Vector3.new(0, 1.6, 0)),
		Color = Color3.fromRGB(70, 75, 88),
		Material = Enum.Material.DiamondPlate,
		Parent = parent,
	})
	makePart({
		Name = "HousingTop",
		Size = Vector3.new(width + 0.4, 0.4, length + 0.4),
		CFrame = CFrame.new(center + Vector3.new(0, 3.4, 0)),
		Color = YELLOW,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	-- gelb-schwarze Streifen an der Öffnung zum Band
	local mouthZ = zStart + (zStart < VISIBLE_START and length or 0)
	for i = 0, 4 do
		makePart({
			Name = "MouthStripe",
			Size = Vector3.new(width / 5, 3.2, 0.3),
			CFrame = CFrame.new(x - width / 2 + (i + 0.5) * width / 5, 1.6, mouthZ),
			Color = i % 2 == 0 and YELLOW or BLACK,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
	end
	if label then
		-- Schild an der Außenseite (vorderes Gehäuse: zum Platz hin, hinteres: nach Norden)
		local isFront = zStart < VISIBLE_START
		local sign = makePart({
			Name = "HousingSign",
			Size = Vector3.new(width - 1, 1.6, 0.2),
			CFrame = CFrame.new(x, 4.6, isFront and zStart - 0.1 or zStart + length + 0.1)
				* (isFront and CFrame.identity or CFrame.Angles(0, math.pi, 0)),
			Color = BLACK,
			Parent = parent,
		})
		addSurfaceText(sign, Enum.NormalId.Front, label, YELLOW, BLACK)
	end
end

local function buildConveyor(name, x, direction)
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("Direction", direction)
	local width = Map.WalkwayWidth
	local visibleLength = VISIBLE_END - VISIBLE_START

	-- unsichtbares Band: schiebt alles, was darauf steht
	local belt = makePart({
		Name = "Belt",
		Size = Vector3.new(width, BELT_TOP, visibleLength),
		CFrame = CFrame.new(x, BELT_TOP / 2, VISIBLE_CENTER_Z),
		Transparency = 1,
		Parent = model,
	})

	-- dunkle Wanne unter den Kacheln (falls zwischen zwei Kacheln eine Fuge ist)
	makePart({
		Name = "Tray",
		Size = Vector3.new(width, BELT_TOP - 0.5, visibleLength),
		CFrame = CFrame.new(x, (BELT_TOP - 0.5) / 2, VISIBLE_CENTER_Z),
		Color = BLACK,
		CanCollide = false,
		Parent = model,
	})

	-- gelb-schwarze Seitenleisten
	for _, side in ipairs({ -1, 1 }) do
		hazardStrip(model, Vector3.new(x + side * (width / 2 + 0.3), (BELT_TOP + 0.3) / 2, VISIBLE_CENTER_Z), visibleLength, BELT_TOP + 0.3)
	end

	-- Kacheln
	local tiles = Instance.new("Folder")
	tiles.Name = "Tiles"
	tiles.Parent = model
	for i = 0, Map.WalkwayTileCount - 1 do
		buildTile(tiles, i, x, direction)
	end

	-- Gehäuse vorne und hinten
	local arrow = direction == 1 and "⬆ NORDEN ⬆" or "⬇ PLATZ ⬇"
	buildHousing(model, x, Map.WalkwayStartZ, direction == 1 and arrow or nil)
	buildHousing(model, x, VISIBLE_END, direction == -1 and arrow or nil)

	model.PrimaryPart = belt
	model.Parent = walkways
	-- Verankertes Teil mit Geschwindigkeit = Förderband
	belt.AssemblyLinearVelocity = Vector3.new(0, 0, direction * Map.WalkwaySpeed)
	return model
end

buildConveyor("ConveyorNorth", -Map.WalkwayX, 1)
buildConveyor("ConveyorSouth", Map.WalkwayX, -1)

------------------------------------------------------------------------
-- Hub-Platz mit Brunnen
------------------------------------------------------------------------
local hub = Instance.new("Folder")
hub.Name = "Hub"
hub.Parent = layoutFolder

local PLAZA_SIZE = Vector3.new(120, 0.2, 100)
local PLAZA_CENTER = Vector3.new(0, 0.1, -50)

makePart({
	Name = "Plaza",
	Size = PLAZA_SIZE,
	CFrame = CFrame.new(PLAZA_CENTER),
	Color = STONE,
	Material = Enum.Material.Pavement,
	Parent = hub,
})

-- Brunnen
do
	local center = Vector3.new(0, 0, -50)
	makePart({
		Name = "FountainBase",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.4, 16, 16),
		CFrame = CFrame.new(center + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = STONE_DARK,
		Material = Enum.Material.Cobblestone,
		Parent = hub,
	})
	makePart({
		Name = "FountainWater",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 14.5, 14.5),
		CFrame = CFrame.new(center + Vector3.new(0, 1.35, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(80, 170, 235),
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		CanCollide = false,
		Parent = hub,
	})
	makePart({
		Name = "FountainPillar",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(5, 1.6, 1.6),
		CFrame = CFrame.new(center + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = STONE,
		Material = Enum.Material.Marble,
		Parent = hub,
	})
	-- Milchkanne als Brunnenfigur
	makePart({
		Name = "FountainCan",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 2.6, 2.6),
		CFrame = CFrame.new(center + Vector3.new(0, 7.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(205, 210, 218),
		Material = Enum.Material.Metal,
		Parent = hub,
	})
	local spout = makePart({
		Name = "FountainSpout",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.2, 1.2, 1.2),
		CFrame = CFrame.new(center + Vector3.new(0, 9.4, 0)),
		Color = Color3.fromRGB(252, 252, 248),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = hub,
	})
	local milkSpray = Instance.new("ParticleEmitter")
	milkSpray.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	milkSpray.Size = NumberSequence.new(0.4, 0.1)
	milkSpray.Lifetime = NumberRange.new(1, 1.4)
	milkSpray.Speed = NumberRange.new(8, 11)
	milkSpray.SpreadAngle = Vector2.new(25, 25)
	milkSpray.Acceleration = Vector3.new(0, -25, 0)
	milkSpray.Rate = 40
	milkSpray.EmissionDirection = Enum.NormalId.Top
	milkSpray.Parent = spout
end

-- Spawn auf dem Platz (danach teleportiert CowManager jeden Spieler auf seine Farm)
do
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = CFrame.new(0, 0.3, -20)
	spawn.Color = Color3.fromRGB(95, 170, 255)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = hub
end

-- Begrüßungsbogen am Anfang der Allee
do
	for _, side in ipairs({ -1, 1 }) do
		makePart({
			Name = "ArchPillar",
			Size = Vector3.new(2, 16, 2),
			CFrame = CFrame.new(side * (AVENUE_HALF + 1), 8, WALK_START - 4),
			Color = World.WoodDark,
			Material = Enum.Material.Wood,
			Parent = hub,
		})
	end
	local beam = makePart({
		Name = "ArchSign",
		Size = Vector3.new(AVENUE_HALF * 2 + 6, 4, 1),
		CFrame = CFrame.new(0, 17, WALK_START - 4),
		Color = World.WoodDark,
		Material = Enum.Material.Wood,
		Parent = hub,
	})
	addSurfaceText(beam, Enum.NormalId.Front, "COW FARM")
	addSurfaceText(beam, Enum.NormalId.Back, "Shops & Platz")
end

------------------------------------------------------------------------
-- Deko-Bausteine (Bäume, Bänke, Laternen, Blumenbeete, Wege)
-- Alles Kleine ist CanCollide = false, damit nichts den Weg versperrt.
------------------------------------------------------------------------
local rng = Random.new(2024) -- feste Zufallszahlen: die Karte sieht bei jedem Start gleich aus
local SOFT = { CanCollide = false, CanQuery = false }

local function prop(parent, name, size, cframe, color, material, extra)
	local p = makePart({
		Name = name,
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	if extra then
		for key, value in pairs(extra) do
			p[key] = value
		end
	end
	return p
end

local function buildTree(parent, position, scale)
	prop(parent, "Trunk", Vector3.new(1.2, 6, 1.2) * scale, CFrame.new(position + Vector3.new(0, 3 * scale, 0)),
		World.WoodDark, Enum.Material.Wood)
	for _, offset in ipairs({ Vector3.new(0, 7, 0), Vector3.new(1.5, 6, 0.8), Vector3.new(-1.3, 6.2, -0.9) }) do
		prop(parent, "Leaves", Vector3.new(5, 5, 5) * scale, CFrame.new(position + offset * scale),
			World.Leaf, Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false })
	end
end

-- Laterne mit warmem Licht (withLight = false spart die Lichtquelle)
local function buildLantern(parent, position, withLight)
	prop(parent, "LanternPost", Vector3.new(0.4, 6.4, 0.4), CFrame.new(position + Vector3.new(0, 3.2, 0)),
		Color3.fromRGB(52, 54, 62), Enum.Material.Metal)
	prop(parent, "LanternCap", Vector3.new(1.7, 0.25, 1.7), CFrame.new(position + Vector3.new(0, 7.45, 0)),
		Color3.fromRGB(52, 54, 62), Enum.Material.Metal, SOFT)
	local lamp = prop(parent, "LanternLamp", Vector3.new(1.2, 1.4, 1.2), CFrame.new(position + Vector3.new(0, 6.8, 0)),
		World.Lantern, Enum.Material.SmoothPlastic, SOFT)
	if withLight then
		local pointLight = Instance.new("PointLight")
		pointLight.Color = Color3.fromRGB(255, 226, 170)
		pointLight.Brightness = 1
		pointLight.Range = 14
		pointLight.Shadows = false
		pointLight.Parent = lamp
	end
end

-- Bank: Sitzfläche, Lehne, zwei Füße. Blick in Richtung -Z des CFrames
local function buildBench(parent, cframe)
	prop(parent, "BenchSeat", Vector3.new(4.4, 0.35, 1.5), cframe * CFrame.new(0, 1.55, 0), World.WoodLight, Enum.Material.Wood)
	prop(parent, "BenchBack", Vector3.new(4.4, 1.1, 0.25), cframe * CFrame.new(0, 2.4, 0.68), World.Wood, Enum.Material.Wood, SOFT)
	for _, x in ipairs({ -1.8, 1.8 }) do
		prop(parent, "BenchLeg", Vector3.new(0.35, 1.5, 1.3), cframe * CFrame.new(x, 0.75, 0), World.WoodDark, Enum.Material.Wood)
	end
end

-- Blumenbeet: Steinrand, Erde, Grünpolster und ein paar bunte Blüten (wenige Teile)
local function buildFlowerBed(parent, center, sizeX, sizeZ)
	prop(parent, "BedBorder", Vector3.new(sizeX + 0.9, 0.5, sizeZ + 0.9), CFrame.new(center + Vector3.new(0, 0.45, 0)),
		World.StoneDark, Enum.Material.Cobblestone, SOFT)
	prop(parent, "BedSoil", Vector3.new(sizeX, 0.6, sizeZ), CFrame.new(center + Vector3.new(0, 0.5, 0)),
		World.Soil, Enum.Material.Ground, SOFT)
	prop(parent, "BedGreen", Vector3.new(sizeX - 0.6, 0.8, sizeZ - 0.6), CFrame.new(center + Vector3.new(0, 0.85, 0)),
		World.Leaf, Enum.Material.Grass, SOFT)
	local count = math.clamp(math.floor(sizeX * sizeZ / 5), 4, 12)
	for _ = 1, count do
		local color = World.Flowers[rng:NextInteger(1, #World.Flowers)]
		local offset = Vector3.new(rng:NextNumber(-sizeX / 2 + 0.6, sizeX / 2 - 0.6), 1.45, rng:NextNumber(-sizeZ / 2 + 0.6, sizeZ / 2 - 0.6))
		prop(parent, "Flower", Vector3.new(0.7, 0.7, 0.7), CFrame.new(center + offset), color, Enum.Material.SmoothPlastic,
			{ Shape = Enum.PartType.Ball, CanCollide = false, CanQuery = false, CastShadow = false })
	end
end

-- Steinweg: flacher Streifen knapp über dem Platz (stört beim Laufen nicht)
local function buildPath(parent, center, sizeX, sizeZ)
	prop(parent, "PathStone", Vector3.new(sizeX, 0.06, sizeZ), CFrame.new(center.X, 0.23, center.Z),
		World.StonePath, Enum.Material.Cobblestone, SOFT)
end

local function buildPathRing(parent, center, diameter)
	prop(parent, "PathRing", Vector3.new(0.06, diameter, diameter), CFrame.new(center.X, 0.23, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		World.StonePath, Enum.Material.Cobblestone, { Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false })
end

------------------------------------------------------------------------
-- Hub-Dekoration (Süd-Platz): Wege, Beete, Bänke, Laternen, Bäume
------------------------------------------------------------------------
do
	-- Wege: Allee-Eingang -> Brunnen, Türen der Shops -> Brunnen, Ring um den Brunnen
	buildPathRing(hub, Vector3.new(0, 0, -50), 26)
	buildPath(hub, Vector3.new(0, 0, -19), 8, 38)
	buildPath(hub, Vector3.new(-22, 0, -40), 24, 6)
	buildPath(hub, Vector3.new(22, 0, -40), 24, 6)

	-- Beete neben dem Eingang und an den Platzecken (nie auf Wegen oder Gebäuden)
	for _, side in ipairs({ -1, 1 }) do
		buildFlowerBed(hub, Vector3.new(side * 16, 0, -10), 10, 4)
		buildFlowerBed(hub, Vector3.new(side * 34, 0, -78), 12, 4)
		buildFlowerBed(hub, Vector3.new(side * 8, 0, -86), 8, 3)
		-- Bänke am Brunnen, Blick zur Mitte
		buildBench(hub, CFrame.new(side * 12, 0, -72) * CFrame.Angles(0, math.pi, 0))
		buildBench(hub, CFrame.new(side * 21, 0, -58) * CFrame.Angles(0, side * math.rad(-90) + math.pi, 0))
		-- Laternen
		buildLantern(hub, Vector3.new(side * 8, 0, -4), true)
		buildLantern(hub, Vector3.new(side * 24, 0, -50), false)
		buildLantern(hub, Vector3.new(side * 50, 0, -60), true)
	end

	-- Bäume am Platzrand
	for _, position in ipairs({
		Vector3.new(-55, 0, -5), Vector3.new(55, 0, -5),
		Vector3.new(-55, 0, -95), Vector3.new(55, 0, -95),
		Vector3.new(-20, 0, -95), Vector3.new(20, 0, -95),
		Vector3.new(-56, 0, -72), Vector3.new(56, 0, -72),
	}) do
		buildTree(hub, position, 1)
	end
end

------------------------------------------------------------------------
-- Shop-Gebäude
-- Jedes Gebäude hat eine eigene Silhouette, aber dieselben Eckdaten:
--   Grundfläche ca. 20 x 16, Tür vorne (-Z), Teleport-Punkt 9 Studs vor der Tür.
-- Hilfen: Dach aus Platten (Profil), Giebelflächen aus Keilen, Schild als Holzbrett.
------------------------------------------------------------------------
local SHOP_W, SHOP_D = 20, 16

-- Dach aus schrägen Platten. profile = Liste von Vector2(z, y) von der vorderen Traufe (z < 0)
-- bis zum First (z = 0); die hintere Hälfte wird gespiegelt.
local function buildRoof(ctx, profile, overhang, color, material, width)
	for half = 1, 2 do
		for i = 1, #profile - 1 do
			local a, b = profile[i], profile[i + 1]
			local dir = (b - a).Unit
			local from = a
			if i == 1 then
				from = a - dir * overhang
			end
			local length = (b - from).Magnitude + (i == #profile - 1 and 0.2 or 0)
			local mid = (from + b) / 2
			local normal = Vector2.new(-dir.Y, dir.X) -- schräg nach oben
			local center = mid + normal * 0.3
			local phi = math.atan2(dir.Y, dir.X)
			if half == 1 then
				ctx.part("Roof", Vector3.new(width, 0.6, length), CFrame.new(0, center.Y, center.X) * CFrame.Angles(-phi, 0, 0),
					color, material)
			else
				ctx.part("Roof", Vector3.new(width, 0.6, length), CFrame.new(0, center.Y, -center.X) * CFrame.Angles(phi, 0, 0),
					color, material)
			end
		end
	end
end

-- Giebelflächen an den beiden Seitenwänden: Rechteck + Keil je Dachabschnitt.
-- Keil-Standardrichtung: hoch am +Z-Ende. Vorne so lassen, hinten um 180° drehen.
local function buildGables(ctx, profile, eaveY, color, material)
	for _, x in ipairs({ -(ctx.W / 2 - 0.5), ctx.W / 2 - 0.5 }) do
		for half = 1, 2 do
			for i = 1, #profile - 1 do
				local a, b = profile[i], profile[i + 1]
				local hA, hB = a.Y - eaveY, b.Y - eaveY
				local span = b.X - a.X
				local zMid = (a.X + b.X) / 2
				local flip = half == 1 and 1 or -1
				if hA > 0.05 then
					ctx.part("GableFill", Vector3.new(1, hA, span), CFrame.new(x, eaveY + hA / 2, zMid * flip), color, material)
				end
				local rise = hB - hA
				if rise > 0.05 then
					local cf = CFrame.new(x, eaveY + hA + rise / 2, zMid * flip)
					if half == 2 then
						cf = cf * CFrame.Angles(0, math.pi, 0)
					end
					makeWedge({
						Name = "Gable",
						Size = Vector3.new(1, rise, span),
						CFrame = ctx.base * cf,
						Color = color,
						Material = material,
						Parent = ctx.model,
					})
				end
			end
		end
	end
end

-- Wände mit Türöffnung, Boden, Eckpfosten, Türrahmen und Theke
local function buildShell(ctx, cfg)
	local W, D, H = cfg.W or ctx.W, ctx.D, cfg.H
	local doorW, doorH = cfg.DoorW, cfg.DoorH
	local part, wall, trim, material = ctx.part, cfg.WallColor, cfg.Trim, cfg.WallMaterial or Enum.Material.WoodPlanks
	ctx.W = W

	part("Floor", Vector3.new(W, 0.4, D), CFrame.new(0, 0.2, 0), Color3.fromRGB(165, 124, 86), Enum.Material.WoodPlanks)
	part("WallBack", Vector3.new(W, H, 1), CFrame.new(0, H / 2, D / 2 - 0.5), wall, material)
	local frontWidth = (W - doorW) / 2
	for _, side in ipairs({ -1, 1 }) do
		part("WallSide", Vector3.new(1, H, D), CFrame.new(side * (W / 2 - 0.5), H / 2, 0), wall, material)
		part("WallFront", Vector3.new(frontWidth, H, 1), CFrame.new(side * (doorW / 2 + frontWidth / 2), H / 2, -D / 2 + 0.5), wall, material)
		part("DoorFrame", Vector3.new(0.5, doorH, 1.3), CFrame.new(side * (doorW / 2 + 0.25), doorH / 2, -D / 2 + 0.5), trim, Enum.Material.Wood)
	end
	part("WallOverDoor", Vector3.new(doorW, H - doorH, 1), CFrame.new(0, doorH + (H - doorH) / 2, -D / 2 + 0.5), wall, material)
	part("DoorFrameTop", Vector3.new(doorW + 1, 0.5, 1.3), CFrame.new(0, doorH + 0.25, -D / 2 + 0.5), trim, Enum.Material.Wood)
	for _, x in ipairs({ -W / 2, W / 2 }) do
		for _, z in ipairs({ -D / 2, D / 2 }) do
			part("Corner", Vector3.new(1.3, H, 1.3), CFrame.new(x, H / 2, z), trim, Enum.Material.Wood)
		end
	end

	-- Theke innen (durch die Tür sichtbar)
	part("Counter", Vector3.new(9, 3.2, 2), CFrame.new(0, 1.8, D / 2 - 4), World.WoodDark, Enum.Material.Wood)
	part("CounterTop", Vector3.new(9.4, 0.3, 2.4), CFrame.new(0, 3.55, D / 2 - 4), ctx.opts.Color, Enum.Material.SmoothPlastic)
end

-- Fenster mit Rahmen (liegt auf der Außenwand, keine Öffnung)
local function buildWindow(ctx, x, y, w, h, trim)
	ctx.part("WindowFrame", Vector3.new(w + 0.6, h + 0.6, 0.15), CFrame.new(x, y, -ctx.D / 2 - 0.05), trim, Enum.Material.Wood, SOFT)
	ctx.part("Window", Vector3.new(w, h, 0.2), CFrame.new(x, y, -ctx.D / 2 - 0.15), Color3.fromRGB(170, 212, 245), Enum.Material.Glass,
		{ Transparency = 0.35, CanCollide = false, CanQuery = false })
	ctx.part("WindowBar", Vector3.new(w, 0.18, 0.1), CFrame.new(x, y, -ctx.D / 2 - 0.28), trim, Enum.Material.Wood, SOFT)
end

-- Holzschild an der Wand: Rückbrett + Brett mit Text (Symbol + Name), gut lesbar aus ~40 Studs
local function buildSign(ctx, x, y, width, height)
	local zFront = -ctx.D / 2 - 0.15
	ctx.part("SignBacker", Vector3.new(width + 0.6, height + 0.6, 0.3), CFrame.new(x, y, zFront), World.Wood, Enum.Material.Wood)
	local board = ctx.part("Sign", Vector3.new(width, height, 0.3), CFrame.new(x, y, zFront - 0.25), World.WoodDark, Enum.Material.Wood)

	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 60
	surface.LightInfluence = 0.2
	surface.Parent = board

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 0.84)
	text.Font = Palette.Fonts.Heading
	text.TextScaled = true
	text.TextColor3 = Pal.Cream
	text.Text = ctx.opts.Icon .. "  " .. ctx.opts.Title
	text.Parent = surface
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 90
	limit.Parent = text
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.Parent = text
	-- farbiger Streifen unten = Erkennungsfarbe des Shops
	local stripe = Instance.new("Frame")
	stripe.AnchorPoint = Vector2.new(0.5, 1)
	stripe.Position = UDim2.fromScale(0.5, 0.92)
	stripe.Size = UDim2.fromScale(0.86, 0.06)
	stripe.BackgroundColor3 = ctx.opts.Color
	stripe.BorderSizePixel = 0
	stripe.Parent = surface
	return board
end

-- kleiner, ruhiger Hinweis "Klicken zum Öffnen" (die Namen bleiben, WorldAnimator findet sie so)
local function buildHint(ctx)
	local anchor = ctx.part("SignAnchor", Vector3.new(1, 1, 1), CFrame.new(-3.6, 5.4, -ctx.D / 2 - 1.8), World.WoodDark, nil,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ShopBillboard"
	billboard.Size = UDim2.fromScale(5.2, 1.1) -- in Studs: wird mit Abstand kleiner wie ein echtes Schild
	billboard.MaxDistance = 45
	billboard.LightInfluence = 0
	billboard.Parent = anchor

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Pal.Deep
	card.BackgroundTransparency = 0.2
	card.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = Pal.Line
	stroke.Thickness = 1.5
	stroke.Parent = card
	local bounce = Instance.new("UIScale")
	bounce.Name = "Bounce"
	bounce.Parent = card

	local hint = Instance.new("TextLabel")
	hint.Name = "ClickHint"
	hint.BackgroundTransparency = 1
	hint.Size = UDim2.fromScale(1, 1)
	hint.Font = Palette.Fonts.Body
	hint.TextScaled = true
	hint.TextColor3 = Pal.Cream
	hint.Text = "Klicken zum Öffnen"
	hint.Parent = card
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.08, 0)
	padding.PaddingRight = UDim.new(0.08, 0)
	padding.PaddingTop = UDim.new(0.18, 0)
	padding.PaddingBottom = UDim.new(0.18, 0)
	padding.Parent = hint
end

-- Verkäufer vor der Tür (Blockfigur mit Strohhut, winkt – Animation im Client)
local function buildShopKeeper(ctx)
	local npc = Instance.new("Model")
	npc.Name = "ShopKeeper"
	local npcBase = ctx.base * CFrame.new(3.6, 0, -ctx.D / 2 - 3.2) * CFrame.Angles(0, math.pi, 0) -- schaut zum Platz
	local skin = Color3.fromRGB(255, 205, 160)
	local function npcPart(name, size, offset, color, shape)
		return makePart({
			Name = name,
			Size = size,
			CFrame = npcBase * offset,
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			Shape = shape or Enum.PartType.Block,
			CanCollide = false,
			Parent = npc,
		})
	end
	npcPart("LeftLeg", Vector3.new(1, 2, 1), CFrame.new(-0.5, 1, 0), Color3.fromRGB(60, 80, 140))
	npcPart("RightLeg", Vector3.new(1, 2, 1), CFrame.new(0.5, 1, 0), Color3.fromRGB(60, 80, 140))
	local npcTorso = npcPart("Torso", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), ctx.opts.Color)
	npcPart("Apron", Vector3.new(1.4, 1.6, 0.1), CFrame.new(0, 2.8, 0.52), Pal.Cream)
	npcPart("LeftArm", Vector3.new(1, 2, 1), CFrame.new(-1.5, 3, 0), skin)
	local rightArm = npcPart("RightArm", Vector3.new(1, 2, 1), CFrame.new(1.5, 3, 0), skin)
	rightArm:SetAttribute("ShoulderOffset", Vector3.new(1.5, 3.8, 0))
	npcPart("Head", Vector3.new(1.3, 1.3, 1.3), CFrame.new(0, 4.65, 0), skin, Enum.PartType.Ball)
	for _, side in ipairs({ -1, 1 }) do
		npcPart("Eye", Vector3.new(0.18, 0.25, 0.05), CFrame.new(side * 0.25, 4.75, 0.63), Color3.fromRGB(20, 20, 25))
	end
	npcPart("Smile", Vector3.new(0.45, 0.08, 0.05), CFrame.new(0, 4.4, 0.62), Color3.fromRGB(150, 60, 60))
	npcPart("HatBrim", Vector3.new(0.15, 2.6, 2.6), CFrame.new(0, 5.25, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(235, 200, 110), Enum.PartType.Cylinder)
	npcPart("HatCrown", Vector3.new(0.8, 1.3, 1.3), CFrame.new(0, 5.65, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(235, 200, 110), Enum.PartType.Cylinder)
	npcPart("HatBand", Vector3.new(0.25, 1.36, 1.36), CFrame.new(0, 5.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
		ctx.opts.Color, Enum.PartType.Cylinder)
	npc.PrimaryPart = npcTorso
	npc.Parent = ctx.model
	CollectionService:AddTag(npc, "ShopKeeper")
end

-- warmes Licht innen (ein kleiner Schein statt einer Neon-Kugel)
local function buildInnerLight(ctx, y)
	local lamp = ctx.part("Lamp", Vector3.new(1, 1, 1), CFrame.new(0, y, 0), World.Lantern, Enum.Material.SmoothPlastic,
		{ Shape = Enum.PartType.Ball, CanCollide = false, CanQuery = false })
	local inside = Instance.new("PointLight")
	inside.Color = Color3.fromRGB(255, 208, 130)
	inside.Brightness = 2
	inside.Range = 20
	inside.Shadows = false
	inside.Parent = lamp
end

-- Stil 1: Kuh-Shop = Scheune mit Gambrel-Dach und offenen Scheunentoren
local function styleBarn(ctx)
	local opts, D = ctx.opts, ctx.D
	local H = 10
	local trim = Pal.Cream
	buildShell(ctx, { H = H, DoorW = 8, DoorH = 7, WallColor = opts.WallColor, Trim = trim })

	-- Scheunentore: geöffnet, neben der Öffnung an die Wand gelegt, mit Kreuzstreben
	local braceLength = math.sqrt(4.8 ^ 2 + 6.6 ^ 2)
	local braceAngle = math.atan2(6.6, 4.8)
	for _, side in ipairs({ -1, 1 }) do
		local x = side * 7
		ctx.part("BarnDoor", Vector3.new(4.8, 6.6, 0.3), CFrame.new(x, 3.5, -D / 2 - 0.1), opts.Color, Enum.Material.WoodPlanks, SOFT)
		for _, dir in ipairs({ -1, 1 }) do
			ctx.part("DoorBrace", Vector3.new(braceLength, 0.4, 0.2), CFrame.new(x, 3.5, -D / 2 - 0.3) * CFrame.Angles(0, 0, dir * braceAngle),
				trim, Enum.Material.Wood, SOFT)
		end
	end

	-- Gambrel-Dach: steile untere, flache obere Fläche
	local profile = { Vector2.new(-D / 2, H), Vector2.new(-4.5, H + 4.2), Vector2.new(0, H + 6.8) }
	buildRoof(ctx, profile, 1.0, opts.RoofColor, Enum.Material.Slate, ctx.W + 2)
	buildGables(ctx, profile, H, opts.WallColor, Enum.Material.WoodPlanks)
	ctx.part("Ridge", Vector3.new(ctx.W + 2.2, 0.6, 0.9), CFrame.new(0, H + 7.15, 0), trim, Enum.Material.Wood, SOFT)
	-- Wetterfahne
	ctx.part("VanePost", Vector3.new(0.25, 2.6, 0.25), CFrame.new(0, H + 8.4, 0), World.WoodDark, Enum.Material.Wood, SOFT)
	ctx.part("VaneArrow", Vector3.new(0.15, 0.5, 1.8), CFrame.new(0, H + 9.5, 0), opts.Color, Enum.Material.Metal, SOFT)

	buildSign(ctx, 0, 8.75, 10.5, 1.9)
	buildInnerLight(ctx, H - 1.5)

	-- davor: Fässer und Heu seitlich (nicht auf dem Weg)
	for _, x in ipairs({ -12.2, -13.6 }) do
		ctx.part("Barrel", Vector3.new(2.2, 1.8, 1.8), CFrame.new(x, 1.1, -D / 2 + 1.5) * CFrame.Angles(0, 0, math.rad(90)),
			World.Wood, Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	end
	ctx.part("HayBale", Vector3.new(3.4, 1.8, 2.6), CFrame.new(12.6, 0.9, -D / 2 + 2), World.Hay, Enum.Material.Fabric)
end

-- Stil 2: Kisten = offener Marktstand mit gestreiftem Dach und Kistenstapeln
local function styleStall(ctx)
	local opts, D, W = ctx.opts, ctx.D, ctx.W
	local part = ctx.part

	part("Floor", Vector3.new(W, 0.4, D), CFrame.new(0, 0.2, 0), Color3.fromRGB(165, 124, 86), Enum.Material.WoodPlanks)
	part("WallBack", Vector3.new(W, 9.6, 0.8), CFrame.new(0, 4.8, D / 2 - 0.4), opts.WallColor, Enum.Material.WoodPlanks)
	for _, side in ipairs({ -1, 1 }) do
		part("WallSide", Vector3.new(0.8, 3.6, D), CFrame.new(side * (W / 2 - 0.4), 1.8, 0), opts.WallColor, Enum.Material.WoodPlanks)
		part("FrontPost", Vector3.new(1.1, 9.6, 1.1), CFrame.new(side * (W / 2 - 0.55), 4.8, -D / 2 + 1), World.WoodDark, Enum.Material.Wood)
		part("BackPost", Vector3.new(1.1, 11.4, 1.1), CFrame.new(side * (W / 2 - 0.55), 5.7, D / 2 - 0.55), World.WoodDark, Enum.Material.Wood)
	end
	part("FrontBeam", Vector3.new(W, 1.8, 1), CFrame.new(0, 8.7, -D / 2 + 1), World.Wood, Enum.Material.Wood)

	-- Verkaufstheke vorne
	part("Counter", Vector3.new(W - 5, 3.2, 1.8), CFrame.new(0, 1.8, -D / 2 + 3), World.WoodDark, Enum.Material.Wood)
	part("CounterTop", Vector3.new(W - 4.6, 0.3, 2.3), CFrame.new(0, 3.55, -D / 2 + 3), opts.Color, Enum.Material.SmoothPlastic)

	-- gestreiftes Dach (leicht nach hinten ansteigend), Streifen quer zur Länge
	local frontY, backY = 10.0, 11.7
	local frontZ, backZ = -D / 2 - 1.6, D / 2 + 0.4
	local length = math.sqrt((backZ - frontZ) ^ 2 + (backY - frontY) ^ 2)
	local tilt = math.atan2(backY - frontY, backZ - frontZ)
	local stripes = 8
	for i = 0, stripes - 1 do
		local width = (W + 2) / stripes
		part("RoofStripe", Vector3.new(width, 0.35, length),
			CFrame.new(-(W + 2) / 2 + (i + 0.5) * width, (frontY + backY) / 2, (frontZ + backZ) / 2) * CFrame.Angles(-tilt, 0, 0),
			i % 2 == 0 and opts.Color or Pal.Cream, Enum.Material.Fabric)
	end

	buildSign(ctx, 0, 8.7, 11, 1.5)

	-- Kisten: auf der Theke und als Stapel dahinter
	local function crate(x, y, z, size, color)
		part("Crate", Vector3.new(size, size, size), CFrame.new(x, y, z) * CFrame.Angles(0, rng:NextNumber(-0.25, 0.25), 0),
			color, Enum.Material.WoodPlanks)
		part("CrateBand", Vector3.new(size + 0.1, 0.3, size + 0.1), CFrame.new(x, y, z), World.WoodDark, Enum.Material.Wood, SOFT)
	end
	crate(-4.5, 4.6, -D / 2 + 3, 2, World.WoodLight)
	crate(-2.1, 4.35, -D / 2 + 3, 1.5, World.Wood)
	crate(5, 4.5, -D / 2 + 3, 1.9, World.WoodLight)
	crate(-8.3, 1.2, 2, 2.4, World.Wood)
	crate(-8.3, 3.6, 2, 2.4, World.WoodLight)
	crate(-5.5, 1.2, 4, 2.4, World.WoodLight)
	crate(8, 1.2, 3, 2.4, World.Wood)

	-- Regal an der Rückwand mit kleinen Kisten in Seltenheitsfarben (Hinweis, was drin sein kann)
	part("Shelf", Vector3.new(W - 6, 0.3, 1.4), CFrame.new(0, 6.2, D / 2 - 1.5), World.WoodDark, Enum.Material.Wood)
	for i, rarity in ipairs({ "Common", "Uncommon", "Rare", "Epic", "Legendary" }) do
		part("ShelfBox", Vector3.new(1.4, 1.2, 1.0), CFrame.new(-5.6 + (i - 1) * 2.8, 6.95, D / 2 - 1.5),
			Palette.rarityColor(rarity), Enum.Material.SmoothPlastic, SOFT)
	end
	buildInnerLight(ctx, 8.4)
end

-- Stil 3: Zucht-Stall = gemütlicher Stall mit Blumenkästen, flachem Dach und Heuballen
local function styleStable(ctx)
	local opts, D = ctx.opts, ctx.D
	local H = 8
	local trim = Pal.Cream
	buildShell(ctx, { H = H, DoorW = 5.5, DoorH = 5.5, WallColor = opts.WallColor, Trim = trim })

	-- Fenster mit Blumenkästen
	for _, side in ipairs({ -1, 1 }) do
		local x = side * 6.4
		buildWindow(ctx, x, 3.9, 3.2, 2.4, trim)
		ctx.part("FlowerBox", Vector3.new(3.8, 0.7, 0.9), CFrame.new(x, 2.3, -D / 2 - 0.65), World.Wood, Enum.Material.Wood, SOFT)
		for k = -1, 1 do
			ctx.part("Flower", Vector3.new(0.7, 0.7, 0.7), CFrame.new(x + k * 1.1, 2.9, -D / 2 - 0.65),
				World.Flowers[rng:NextInteger(1, #World.Flowers)], Enum.Material.SmoothPlastic,
				{ Shape = Enum.PartType.Ball, CanCollide = false, CanQuery = false, CastShadow = false })
		end
	end

	-- flaches Satteldach mit breitem Überstand
	local ridgeY = H + (D / 2) * math.tan(math.rad(26))
	local profile = { Vector2.new(-D / 2, H), Vector2.new(0, ridgeY) }
	buildRoof(ctx, profile, 1.8, opts.RoofColor, Enum.Material.Slate, ctx.W + 3)
	buildGables(ctx, profile, H, opts.WallColor, Enum.Material.WoodPlanks)
	ctx.part("Ridge", Vector3.new(ctx.W + 3.2, 0.6, 0.9), CFrame.new(0, ridgeY + 0.4, 0), trim, Enum.Material.Wood, SOFT)

	buildSign(ctx, 0, 6.95, 9, 1.7)
	buildInnerLight(ctx, H - 1.5)

	-- Heuballen und Trog neben dem Stall
	ctx.part("HayBale", Vector3.new(3.4, 1.8, 2.6), CFrame.new(-12.4, 0.9, -D / 2 + 2), World.Hay, Enum.Material.Fabric)
	ctx.part("HayBale", Vector3.new(3.4, 1.8, 2.6), CFrame.new(-12.4, 2.7, -D / 2 + 2.2), World.Hay, Enum.Material.Fabric)
	ctx.part("Trough", Vector3.new(4, 1.1, 1.4), CFrame.new(12.4, 0.55, -D / 2 + 2), World.Wood, Enum.Material.Wood)
	ctx.part("TroughWater", Vector3.new(3.5, 0.1, 0.9), CFrame.new(12.4, 1.1, -D / 2 + 2), Pal.Blue, Enum.Material.Glass,
		{ Transparency = 0.3, CanCollide = false, CanQuery = false })
end

-- Stil 4: Auto-Melker = kleine Werkstatt aus Wellblech mit Silo, Schornstein und Milchkannen
local function styleWorkshop(ctx)
	local opts, D = ctx.opts, ctx.D
	local H = 9
	local trim = Color3.fromRGB(64, 70, 82)
	buildShell(ctx, {
		W = 15, H = H, DoorW = 6, DoorH = 6.5, WallColor = opts.WallColor, Trim = trim,
		WallMaterial = Enum.Material.Metal,
	})
	local W = ctx.W

	-- Pultdach: vorne niedrig, hinten hoch
	local rise = 2.2
	local frontZ, backZ = -D / 2 - 1.2, D / 2 + 0.6
	local slope = rise / D
	local roofLength = (backZ - frontZ) * math.sqrt(1 + slope ^ 2)
	local midZ = (frontZ + backZ) / 2
	ctx.part("Roof", Vector3.new(W + 2, 0.6, roofLength),
		CFrame.new(0, H + slope * (midZ + D / 2) + 0.3, midZ) * CFrame.Angles(-math.atan(slope), 0, 0),
		opts.RoofColor, Enum.Material.Metal)
	for _, x in ipairs({ -(W / 2 - 0.5), W / 2 - 0.5 }) do
		makeWedge({
			Name = "Gable",
			Size = Vector3.new(1, rise, D),
			CFrame = ctx.base * CFrame.new(x, H + rise / 2, 0), -- hoch am +Z-Ende (Rückseite)
			Color = opts.WallColor,
			Material = Enum.Material.Metal,
			Parent = ctx.model,
		})
	end

	-- Schornstein
	ctx.part("Chimney", Vector3.new(4.5, 1.2, 1.2), CFrame.new(-4, H + 3.8, 4) * CFrame.Angles(0, 0, math.rad(90)),
		World.StoneDark, Enum.Material.Brick, { Shape = Enum.PartType.Cylinder, CanCollide = false })

	-- Silo daneben (Zylinder + Kuppel + Ringe)
	local siloX, siloH, siloR = W / 2 + 2.4, 14, 2.2
	ctx.part("Silo", Vector3.new(siloH, siloR * 2, siloR * 2), CFrame.new(siloX, siloH / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(205, 210, 216), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	ctx.part("SiloDome", Vector3.new(siloR * 2, siloR * 2, siloR * 2), CFrame.new(siloX, siloH, 0), opts.RoofColor, Enum.Material.Metal,
		{ Shape = Enum.PartType.Ball, CanCollide = false })
	for _, y in ipairs({ 4, 9 }) do
		ctx.part("SiloBand", Vector3.new(0.35, siloR * 2 + 0.2, siloR * 2 + 0.2), CFrame.new(siloX, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
			trim, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	end
	ctx.part("SiloLadder", Vector3.new(0.3, 12, 0.3), CFrame.new(siloX, 6.5, -siloR - 0.1), World.Metal, Enum.Material.Metal, SOFT)

	buildSign(ctx, 0, 7.9, 8.2, 1.6)
	buildInnerLight(ctx, H - 1.6)

	-- Milchkannen vor der Werkstatt
	for i, x in ipairs({ -10.4, -9.2, -10.9 }) do
		ctx.part("MilkCan", Vector3.new(1.5, 1.1, 1.1), CFrame.new(x, 0.75, -D / 2 + 1.2 + (i % 2) * 1.4) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(205, 210, 218), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	end
end

local STYLES = {
	CowShop = styleBarn,
	CrateShop = styleStall,
	BreedingBarn = styleStable,
	AutoMilkerShop = styleWorkshop,
}

-- base: Boden-Mitte des Gebäudes, Vorderseite (Tür) zeigt nach -Z
local function buildShop(opts, base)
	local model = Instance.new("Model")
	model.Name = opts.Name

	local ctx = { model = model, base = base, opts = opts, W = SHOP_W, D = SHOP_D }
	function ctx.part(name, size, offset, color, material, extra)
		local p = makePart({
			Name = name,
			Size = size,
			CFrame = base * offset,
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			Parent = model,
		})
		if extra then
			for key, value in pairs(extra) do
				p[key] = value
			end
		end
		return p
	end

	local style = STYLES[opts.Name] or styleBarn
	style(ctx)
	buildHint(ctx)
	buildShopKeeper(ctx)

	-- Klick auf das Gebäude -> Server -> RemoteEvent -> MenuUI öffnet das passende Fenster
	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 80
	clickDetector.Parent = model
	clickDetector.MouseClick:Connect(function(player)
		Remotes.OpenShop:FireClient(player, opts.Page)
	end)

	model:SetAttribute("Page", opts.Page)
	model:SetAttribute("Title", opts.Title)
	model:SetAttribute("Label", opts.Label)
	model:SetAttribute("Area", opts.Area)
	-- hier landet man, wenn man in der Übersicht auf das Haus klickt (vor der Tür, Blick zum Haus)
	local standPosition = (base * CFrame.new(0, 3, -SHOP_D / 2 - 9)).Position
	local doorPosition = (base * CFrame.new(0, 3, 0)).Position
	model:SetAttribute("TeleportCFrame", CFrame.lookAt(standPosition, doorPosition))
	model.PrimaryPart = model:FindFirstChild("Floor")
	CollectionService:AddTag(model, "ShopBuilding")
	model.Parent = opts.Parent or hub
	return model
end

------------------------------------------------------------------------
-- Nord-Markt (am Ende der Förderbänder)
------------------------------------------------------------------------
local north = Instance.new("Folder")
north.Name = "NorthMarket"
north.Parent = layoutFolder

local NORTH_CENTER = Vector3.new(0, 0, Map.NorthPlazaZ)
makePart({
	Name = "Plaza",
	Size = Map.NorthPlazaSize,
	CFrame = CFrame.new(NORTH_CENTER + Vector3.new(0, Map.NorthPlazaSize.Y / 2, 0)),
	Color = STONE,
	Material = Enum.Material.Pavement,
	Parent = north,
})

-- Torbogen am Eingang des Markts
do
	local archZ = Map.NorthPlazaZ - Map.NorthPlazaSize.Z / 2 + 4
	for _, side in ipairs({ -1, 1 }) do
		makePart({
			Name = "ArchPillar",
			Size = Vector3.new(2, 16, 2),
			CFrame = CFrame.new(side * (AVENUE_HALF + 1), 8, archZ),
			Color = World.WoodDark,
			Material = Enum.Material.Wood,
			Parent = north,
		})
	end
	local beam = makePart({
		Name = "ArchSign",
		Size = Vector3.new(AVENUE_HALF * 2 + 6, 4, 1),
		CFrame = CFrame.new(0, 17, archZ),
		Color = World.WoodDark,
		Material = Enum.Material.Wood,
		Parent = north,
	})
	-- Vorderseite (-Z) sieht man, wenn man vom Förderband kommt
	addSurfaceText(beam, Enum.NormalId.Front, "NORD-MARKT")
	addSurfaceText(beam, Enum.NormalId.Back, "Farmen & Süd-Platz")
end

-- Markt-Dekoration: Wege, Beete, Bänke, Laternen, Heu, Bäume
do
	buildPath(north, Vector3.new(0, 0, Map.NorthPlazaZ - 30), 8, 40)
	buildPath(north, Vector3.new(-22, 0, Map.NorthPlazaZ + 5), 24, 6)
	buildPath(north, Vector3.new(22, 0, Map.NorthPlazaZ + 5), 24, 6)
	for _, side in ipairs({ -1, 1 }) do
		buildFlowerBed(north, Vector3.new(side * 16, 0, Map.NorthPlazaZ - 36), 10, 4)
		buildFlowerBed(north, Vector3.new(side * 30, 0, Map.NorthPlazaZ + 32), 12, 4)
		buildBench(north, CFrame.new(side * 12, 0, Map.NorthPlazaZ + 24) * CFrame.Angles(0, math.pi, 0))
		buildLantern(north, Vector3.new(side * 14, 0, Map.NorthPlazaZ - 20), true)
		buildLantern(north, Vector3.new(side * 50, 0, Map.NorthPlazaZ + 20), true)
		buildTree(north, Vector3.new(side * 55, 0, Map.NorthPlazaZ - 40), 1)
		buildTree(north, Vector3.new(side * 55, 0, Map.NorthPlazaZ + 42), 1)
		prop(north, "HayBale", Vector3.new(4, 2.4, 3.2), CFrame.new(side * 50, 1.3, Map.NorthPlazaZ + 40), World.Hay, Enum.Material.Fabric)
	end
	prop(north, "HayBale", Vector3.new(4, 2.4, 3.2), CFrame.new(0, 1.3, Map.NorthPlazaZ + 42), World.Hay, Enum.Material.Fabric)
end

------------------------------------------------------------------------
-- Alle Shops bauen (Daten aus CowData.Map.Shops)
------------------------------------------------------------------------
for _, shop in ipairs(Map.Shops) do
	local opts = table.clone(shop)
	opts.Parent = shop.Area == "Nord-Markt" and north or hub
	-- Tür zeigt zur Platzmitte: -Z des Gebäudes muss nach +X (Westseite) bzw. -X (Ostseite) zeigen
	local yaw = shop.FacesEast and math.rad(-90) or math.rad(90)
	buildShop(opts, CFrame.new(shop.Position) * CFrame.Angles(0, yaw, 0))
end

------------------------------------------------------------------------
-- Hügel nur ganz am Kartenrand (weit weg von Farmen, Wegen, Förderbändern und Spawn)
-- Farm-Plots reichen bis |x| ~ 370 (bei 18 Spielern), die Plätze bis z = -100 bzw. 450.
------------------------------------------------------------------------
do
	local hills = Instance.new("Folder")
	hills.Name = "Hills"
	hills.Parent = layoutFolder
	local function hill(x, z, diameter, shade)
		-- große Kugel, zu etwa zwei Dritteln im Boden -> sanfter Hügel
		makePart({
			Name = "Hill",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(diameter, diameter, diameter),
			CFrame = CFrame.new(x, -diameter * 0.35, z),
			Color = World.GrassDark:Lerp(World.GrassLight, shade),
			Material = Enum.Material.Grass,
			Parent = hills,
		})
	end
	for _, side in ipairs({ -1, 1 }) do
		for i, z in ipairs({ -120, 60, 240, 420, 600 }) do
			hill(side * (560 + (i % 2) * 70), z, 220 + (i * 37) % 80, (i % 3) / 3)
		end
	end
	for i, x in ipairs({ -260, -60, 140, 330 }) do
		hill(x, -300 - (i % 2) * 60, 240, (i % 3) / 3)
		hill(x + 40, 760 + (i % 2) * 60, 240, ((i + 1) % 3) / 3)
	end
end
