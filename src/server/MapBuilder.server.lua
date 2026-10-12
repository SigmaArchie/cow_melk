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
local Map = CowData.Map

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

-- Text auf einer Fläche eines Parts (weiß auf dunklem Grund -> gut lesbar)
local function addSurfaceText(part, face, text, textColor, backgroundColor)
	local surface = Instance.new("SurfaceGui")
	surface.Face = face
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.LightInfluence = 0
	surface.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = backgroundColor or Color3.fromRGB(30, 32, 45)
	label.BackgroundTransparency = backgroundColor and 0 or 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = textColor or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
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
			Color = Color3.fromRGB(120, 78, 45),
			Material = Enum.Material.Wood,
			Parent = hub,
		})
	end
	local beam = makePart({
		Name = "ArchSign",
		Size = Vector3.new(AVENUE_HALF * 2 + 6, 4, 1),
		CFrame = CFrame.new(0, 17, WALK_START - 4),
		Color = Color3.fromRGB(120, 78, 45),
		Material = Enum.Material.Wood,
		Parent = hub,
	})
	addSurfaceText(beam, Enum.NormalId.Front, "🐄 COW FARM 🐄", Color3.new(1, 1, 1), Color3.fromRGB(35, 30, 28))
	addSurfaceText(beam, Enum.NormalId.Back, "⬇ Shops & Platz ⬇", Color3.new(1, 1, 1), Color3.fromRGB(35, 30, 28))
end

-- ein paar Bäume am Platzrand
local function buildTree(position, scale)
	makePart({
		Name = "Trunk",
		Size = Vector3.new(1.2, 6, 1.2) * scale,
		CFrame = CFrame.new(position + Vector3.new(0, 3 * scale, 0)),
		Color = Color3.fromRGB(110, 75, 45),
		Material = Enum.Material.Wood,
		Parent = hub,
	})
	for _, offset in ipairs({ Vector3.new(0, 7, 0), Vector3.new(1.5, 6, 0.8), Vector3.new(-1.3, 6.2, -0.9) }) do
		makePart({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(5, 5, 5) * scale,
			CFrame = CFrame.new(position + offset * scale),
			Color = Color3.fromRGB(70, 150, 65),
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = hub,
		})
	end
end
for _, position in ipairs({
	Vector3.new(-55, 0, -5), Vector3.new(55, 0, -5),
	Vector3.new(-55, 0, -95), Vector3.new(55, 0, -95),
	Vector3.new(-20, 0, -95), Vector3.new(20, 0, -95),
}) do
	buildTree(position, 1)
end

------------------------------------------------------------------------
-- Shop-Gebäude
------------------------------------------------------------------------
-- base: Boden-Mitte des Gebäudes, Vorderseite (Tür) zeigt nach -Z
local function buildShop(opts, base)
	local W, D, H = 20, 16, 12
	local DOOR_W, DOOR_H = 6, 8
	local model = Instance.new("Model")
	model.Name = opts.Name

	local function part(name, size, offset, color, material, extra)
		local p = makePart({
			Name = name,
			Size = size,
			CFrame = base * offset,
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			Parent = model,
		})
		if extra then
			for k, v in pairs(extra) do
				p[k] = v
			end
		end
		return p
	end

	local wall = opts.WallColor
	local trim = Color3.fromRGB(70, 50, 38)

	-- Boden
	part("Floor", Vector3.new(W, 0.4, D), CFrame.new(0, 0.2, 0), Color3.fromRGB(165, 120, 80), Enum.Material.WoodPlanks)

	-- Wände (vorne mit Türöffnung)
	part("WallBack", Vector3.new(W, H, 1), CFrame.new(0, H / 2, D / 2 - 0.5), wall, Enum.Material.WoodPlanks)
	for _, side in ipairs({ -1, 1 }) do
		part("WallSide", Vector3.new(1, H, D), CFrame.new(side * (W / 2 - 0.5), H / 2, 0), wall, Enum.Material.WoodPlanks)
		local frontWidth = (W - DOOR_W) / 2
		part("WallFront", Vector3.new(frontWidth, H, 1), CFrame.new(side * (DOOR_W / 2 + frontWidth / 2), H / 2, -D / 2 + 0.5), wall, Enum.Material.WoodPlanks)
		-- Fenster
		part("Window", Vector3.new(3.5, 3, 0.2), CFrame.new(side * (DOOR_W / 2 + frontWidth / 2), 5.5, -D / 2 - 0.05),
			Color3.fromRGB(170, 215, 255), Enum.Material.Glass, { Transparency = 0.35 })
		part("WindowFrame", Vector3.new(4.1, 0.35, 0.3), CFrame.new(side * (DOOR_W / 2 + frontWidth / 2), 3.85, -D / 2 - 0.1), trim)
	end
	part("WallOverDoor", Vector3.new(DOOR_W, H - DOOR_H, 1), CFrame.new(0, DOOR_H + (H - DOOR_H) / 2, -D / 2 + 0.5), wall, Enum.Material.WoodPlanks)

	-- Eckbalken
	for _, x in ipairs({ -W / 2, W / 2 }) do
		for _, z in ipairs({ -D / 2, D / 2 }) do
			part("Corner", Vector3.new(1.3, H, 1.3), CFrame.new(x, H / 2, z), trim, Enum.Material.Wood)
		end
	end
	-- Türrahmen
	for _, side in ipairs({ -1, 1 }) do
		part("DoorFrame", Vector3.new(0.5, DOOR_H, 1.3), CFrame.new(side * (DOOR_W / 2 + 0.25), DOOR_H / 2, -D / 2 + 0.5), trim, Enum.Material.Wood)
	end
	part("DoorFrameTop", Vector3.new(DOOR_W + 1, 0.5, 1.3), CFrame.new(0, DOOR_H + 0.25, -D / 2 + 0.5), trim, Enum.Material.Wood)

	-- Satteldach (First entlang X)
	local slope = math.rad(30)
	local overhang = 1.2
	local halfDepth = D / 2 + overhang
	local ridgeY = H + (D / 2) * math.tan(slope)
	local slabLength = halfDepth / math.cos(slope)
	for _, side in ipairs({ -1, 1 }) do -- -1 = vorne, 1 = hinten
		local centerZ = side * halfDepth / 2
		local centerY = ridgeY - (halfDepth / 2) * math.tan(slope) + 0.3
		part("Roof", Vector3.new(W + 2, 0.6, slabLength),
			CFrame.new(0, centerY, centerZ) * CFrame.Angles(side * slope, 0, 0), opts.RoofColor, Enum.Material.Slate)
	end
	part("Ridge", Vector3.new(W + 2.2, 0.7, 0.9), CFrame.new(0, ridgeY + 0.55, 0), trim, Enum.Material.Wood)

	-- Giebeldreiecke an den Seiten (2 Keile je Seite)
	local rise = (D / 2) * math.tan(slope)
	for _, x in ipairs({ -(W / 2 - 0.5), W / 2 - 0.5 }) do
		-- vordere Hälfte: hoch bei z = 0, niedrig bei z = -D/2 (Keil-Standardrichtung)
		makeWedge({
			Name = "Gable",
			Size = Vector3.new(1, rise, D / 2),
			CFrame = base * CFrame.new(x, H + rise / 2, -D / 4),
			Color = wall,
			Material = Enum.Material.WoodPlanks,
			Parent = model,
		})
		-- hintere Hälfte: um 180° gedreht
		makeWedge({
			Name = "Gable",
			Size = Vector3.new(1, rise, D / 2),
			CFrame = base * CFrame.new(x, H + rise / 2, D / 4) * CFrame.Angles(0, math.pi, 0),
			Color = wall,
			Material = Enum.Material.WoodPlanks,
			Parent = model,
		})
	end

	-- Markise über der Tür
	part("Awning", Vector3.new(DOOR_W + 3, 0.3, 3), CFrame.new(0, DOOR_H + 1.1, -D / 2 - 1.4) * CFrame.Angles(math.rad(-20), 0, 0),
		opts.Color, Enum.Material.Fabric)

	-- großes Schild über der Tür
	local sign = part("Sign", Vector3.new(W - 4, 2.6, 0.4), CFrame.new(0, H - 1.6, -D / 2 - 0.3), trim, Enum.Material.Wood)
	addSurfaceText(sign, Enum.NormalId.Front, opts.Icon .. " " .. opts.Title, Color3.new(1, 1, 1), opts.Color:Lerp(Color3.new(0, 0, 0), 0.35))

	-- Theke innen
	part("Counter", Vector3.new(10, 3.4, 2), CFrame.new(0, 1.9, D / 2 - 4), trim, Enum.Material.Wood)
	part("CounterTop", Vector3.new(10.4, 0.3, 2.4), CFrame.new(0, 3.75, D / 2 - 4), opts.Color, Enum.Material.SmoothPlastic)

	-- warmes gelbes Licht innen + farbiges Licht über der Tür
	local lamp = part("Lamp", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, H - 1.5, 0), Color3.fromRGB(255, 230, 150),
		Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
	local inside = Instance.new("PointLight")
	inside.Color = Color3.fromRGB(255, 200, 110)
	inside.Brightness = 3
	inside.Range = 22
	inside.Parent = lamp
	local doorLight = Instance.new("PointLight")
	doorLight.Color = opts.Color
	doorLight.Brightness = 2
	doorLight.Range = 16
	doorLight.Parent = part("DoorLamp", Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, DOOR_H + 2.6, -D / 2 - 0.6),
		Color3.fromRGB(255, 240, 200), Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })

	-- NPC-Verkäufer vor der Tür (Blockfigur mit Hut, winkt – Animation im Client)
	local npc = Instance.new("Model")
	npc.Name = "ShopKeeper"
	local npcBase = base * CFrame.new(3.6, 0, -D / 2 - 3.2) * CFrame.Angles(0, math.pi, 0) -- schaut zum Platz
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
	local npcTorso = npcPart("Torso", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), opts.Color)
	npcPart("Apron", Vector3.new(1.4, 1.6, 0.1), CFrame.new(0, 2.8, 0.52), Color3.fromRGB(245, 245, 240))
	npcPart("LeftArm", Vector3.new(1, 2, 1), CFrame.new(-1.5, 3, 0), skin)
	local rightArm = npcPart("RightArm", Vector3.new(1, 2, 1), CFrame.new(1.5, 3, 0), skin)
	rightArm:SetAttribute("ShoulderOffset", Vector3.new(1.5, 3.8, 0))
	npcPart("Head", Vector3.new(1.3, 1.3, 1.3), CFrame.new(0, 4.65, 0), skin, Enum.PartType.Ball)
	for _, side in ipairs({ -1, 1 }) do
		npcPart("Eye", Vector3.new(0.18, 0.25, 0.05), CFrame.new(side * 0.25, 4.75, 0.63), Color3.fromRGB(20, 20, 25))
	end
	npcPart("Smile", Vector3.new(0.45, 0.08, 0.05), CFrame.new(0, 4.4, 0.62), Color3.fromRGB(150, 60, 60))
	-- Strohhut: breite Krempe + Hutkrone + farbiges Band
	npcPart("HatBrim", Vector3.new(0.15, 2.6, 2.6), CFrame.new(0, 5.25, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(235, 200, 110), Enum.PartType.Cylinder)
	npcPart("HatCrown", Vector3.new(0.8, 1.3, 1.3), CFrame.new(0, 5.65, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(235, 200, 110), Enum.PartType.Cylinder)
	npcPart("HatBand", Vector3.new(0.25, 1.36, 1.36), CFrame.new(0, 5.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
		opts.Color, Enum.PartType.Cylinder)
	npc.PrimaryPart = npcTorso
	npc.Parent = model
	CollectionService:AddTag(npc, "ShopKeeper")

	-- großes, buntes Schild über dem Dach (hüpft + blinkt -> WorldAnimator.client.lua)
	local billboardAnchor = part("SignAnchor", Vector3.new(1, 1, 1), CFrame.new(0, ridgeY + 6, 0), trim, nil,
		{ Transparency = 1, CanCollide = false, CanQuery = false })
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ShopBillboard"
	-- Größe in Studs (nicht Pixeln): wird mit Abstand kleiner wie ein echtes Schild,
	-- statt aus der Nähe den halben Bildschirm zu verdecken
	billboard.Size = UDim2.fromScale(14, 7)
	billboard.MaxDistance = 250
	billboard.LightInfluence = 0
	billboard.Parent = billboardAnchor

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(0.9, 0.9)
	card.BackgroundColor3 = opts.Color
	card.Parent = billboard
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 18)
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Color3.new(1, 1, 1)
	cardStroke.Thickness = 4
	cardStroke.Parent = card
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150))
	gradient.Rotation = 90
	gradient.Parent = card
	local cardScale = Instance.new("UIScale")
	cardScale.Name = "Bounce"
	cardScale.Parent = card

	local function billboardText(name, text, posY, height, font)
		-- Schatten + Text (fett, weiß)
		local shadow = Instance.new("TextLabel")
		shadow.Name = name .. "Shadow"
		shadow.BackgroundTransparency = 1
		shadow.Position = UDim2.new(0, 3, posY, 3)
		shadow.Size = UDim2.fromScale(1, height)
		shadow.Font = font
		shadow.TextScaled = true
		shadow.TextColor3 = Color3.fromRGB(20, 20, 30)
		shadow.TextTransparency = 0.4
		shadow.Text = text
		shadow.Parent = card
		local label = shadow:Clone()
		label.Name = name
		label.Position = UDim2.fromScale(0, posY)
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextTransparency = 0
		label.TextStrokeTransparency = 0.5
		label.Parent = card
		return label, shadow
	end
	billboardText("Icon", opts.Icon, 0.04, 0.38, Enum.Font.GothamBold)
	billboardText("ShopName", opts.Title, 0.42, 0.3, Enum.Font.FredokaOne)
	local hint, hintShadow = billboardText("ClickHint", "👆 KLICKEN ZUM ÖFFNEN", 0.74, 0.18, Enum.Font.GothamBlack)
	hint.TextColor3 = Color3.fromRGB(255, 240, 120)
	hintShadow.Name = "ClickHintShadow"

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
	local standPosition = (base * CFrame.new(0, 3, -D / 2 - 9)).Position
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
			Color = Color3.fromRGB(120, 78, 45),
			Material = Enum.Material.Wood,
			Parent = north,
		})
	end
	local beam = makePart({
		Name = "ArchSign",
		Size = Vector3.new(AVENUE_HALF * 2 + 6, 4, 1),
		CFrame = CFrame.new(0, 17, archZ),
		Color = Color3.fromRGB(120, 78, 45),
		Material = Enum.Material.Wood,
		Parent = north,
	})
	-- Vorderseite (-Z) sieht man, wenn man vom Förderband kommt
	addSurfaceText(beam, Enum.NormalId.Front, "NORD-MARKT", Color3.new(1, 1, 1), Color3.fromRGB(35, 30, 28))
	addSurfaceText(beam, Enum.NormalId.Back, "⬇ Farmen & Süd-Platz ⬇", Color3.new(1, 1, 1), Color3.fromRGB(35, 30, 28))
end

-- Heuhaufen-Deko und Laternen auf dem Markt
for _, position in ipairs({
	Vector3.new(-50, 0, Map.NorthPlazaZ + 40), Vector3.new(50, 0, Map.NorthPlazaZ + 40),
	Vector3.new(0, 0, Map.NorthPlazaZ + 42),
}) do
	makePart({
		Name = "HayBale",
		Size = Vector3.new(4, 2.4, 3.2),
		CFrame = CFrame.new(position + Vector3.new(0, 1.3, 0)),
		Color = Color3.fromRGB(230, 200, 100),
		Material = Enum.Material.Fabric,
		Parent = north,
	})
end
for _, x in ipairs({ -14, 14 }) do
	local lamp = makePart({
		Name = "Lamp",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.4, 1.4, 1.4),
		CFrame = CFrame.new(x, 9.4, Map.NorthPlazaZ),
		Color = Color3.fromRGB(255, 240, 200),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = north,
	})
	makePart({
		Name = "LampPost",
		Size = Vector3.new(0.5, 9, 0.5),
		CFrame = CFrame.new(x, 4.5, Map.NorthPlazaZ),
		Color = Color3.fromRGB(45, 48, 55),
		Material = Enum.Material.Metal,
		Parent = north,
	})
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(255, 230, 180)
	light.Parent = lamp
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
