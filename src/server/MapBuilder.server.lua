-- MapBuilder.server.lua
-- Baut einmalig die gemeinsame Karte (alles unter Workspace.CowFarmLayout):
--   * runder Marktplatz in der Mitte: Brunnen, Dorfbaum, Pavillon, Wegweiser, Bänke, Beete
--   * fünf Shops rund um den Brunnen, Türen zur Mitte (Daten in CowData.Map.Shops;
--     jedes Gebäude bekommt einen Teleport-Punkt)
--   * Landschaft (Folder "Countryside"): Feldwege zu den Farm-Toren, Ringweg, Wiesen mit Bäumen,
--     zwischen den Farmen Windmühle, Teich, Obstgarten, Kürbisse, Blumenfeld, Heu; Waldrand, Hügel
-- Die Bauernhöfe selbst baut CowManager.server.lua (mit FarmBuilder.lua) im Kreis um den Platz.
-- Deko-Bausteine (Bäume, Zäune, Gebäude ...) kommen aus FarmProps.lua.
--
-- Shops: ClickDetector -> Remotes.OpenShop:FireClient(player, page) -> MenuUI öffnet das Fenster.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Palette = require(ReplicatedStorage.Shared:WaitForChild("Palette"))
local FarmProps = require(script.Parent:WaitForChild("FarmProps"))
local GearModels = require(ReplicatedStorage.Shared:WaitForChild("GearModels"))
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
for _, name in ipairs({ "Hub", "Walkways", "Avenue", "NorthMarket", "Countryside", "Hills" }) do
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

local HUB_RADIUS = Map.HubRadius
local STONE = Color3.fromRGB(205, 200, 190)
local STONE_DARK = Color3.fromRGB(150, 145, 138)
local Colors = FarmProps.Colors

-- Punkt auf einem Kreis um den Brunnen (Winkel im Uhrzeigersinn von +Z aus, wie in CowData)
local function polar(angle, radius, y)
	local radians = math.rad(angle)
	return Vector3.new(radius * math.sin(radians), y or 0, radius * math.cos(radians))
end

-- CFrame auf dem Kreis: lokales +Z zeigt nach außen, -Z zur Mitte
local function onRing(angle, radius, y)
	return CFrame.new(polar(angle, radius, y)) * CFrame.Angles(0, math.rad(angle), 0)
end

------------------------------------------------------------------------
-- Marktplatz (Hub) in der Mitte: runder Platz, Brunnen, Shops rundherum
------------------------------------------------------------------------
local hub = Instance.new("Folder")
hub.Name = "Hub"
hub.Parent = layoutFolder

makePart({
	Name = "PlazaRim",
	Shape = Enum.PartType.Cylinder,
	Size = Vector3.new(0.16, HUB_RADIUS * 2 + 3, HUB_RADIUS * 2 + 3),
	CFrame = CFrame.new(0, 0.08, 0) * CFrame.Angles(0, 0, math.rad(90)),
	Color = STONE_DARK,
	Material = Enum.Material.Cobblestone,
	Parent = hub,
})
makePart({
	Name = "Plaza",
	Shape = Enum.PartType.Cylinder,
	Size = Vector3.new(0.2, HUB_RADIUS * 2, HUB_RADIUS * 2),
	CFrame = CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
	Color = STONE,
	Material = Enum.Material.Pavement,
	Parent = hub,
})

-- Brunnen in der Mitte (zwei Becken, Milchkanne als Brunnenfigur, Milch-Fontäne)
do
	local center = Vector3.zero
	local function disc(name, height, diameter, y, color, material, extra)
		local p = makePart({
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, diameter, diameter),
			CFrame = CFrame.new(center + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Material = material,
			Parent = hub,
		})
		if extra then
			for key, value in pairs(extra) do
				p[key] = value
			end
		end
		return p
	end
	disc("FountainBase", 1.4, 18, 0.7, STONE_DARK, Enum.Material.Cobblestone)
	disc("FountainWater", 0.3, 16.4, 1.35, Color3.fromRGB(80, 170, 235), Enum.Material.Glass, {
		Transparency = 0.25,
		CanCollide = false,
	})
	disc("FountainPillar", 3.2, 2.2, 2.6, STONE, Enum.Material.Marble)
	disc("FountainBowl", 0.9, 7, 4.4, STONE_DARK, Enum.Material.Cobblestone)
	disc("FountainBowlWater", 0.2, 6.2, 4.85, Color3.fromRGB(80, 170, 235), Enum.Material.Glass, {
		Transparency = 0.25,
		CanCollide = false,
	})
	disc("FountainNeck", 1.6, 1.4, 5.6, STONE, Enum.Material.Marble)
	-- Milchkanne als Brunnenfigur
	disc("FountainCan", 3, 2.6, 7.8, Color3.fromRGB(205, 210, 218), Enum.Material.Metal)
	disc("FountainCanLid", 0.3, 1.8, 9.45, Pal.Cream, Enum.Material.SmoothPlastic)
	local spout = makePart({
		Name = "FountainSpout",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.2, 1.2, 1.2),
		CFrame = CFrame.new(center + Vector3.new(0, 9.9, 0)),
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
	spawn.CFrame = CFrame.new(polar(270, 21, 0.3)) * CFrame.Angles(0, math.rad(-90), 0)
	spawn.Color = Color3.fromRGB(95, 170, 255)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = hub
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

-- Laterne mit warmem Licht (withLight = false spart die Lichtquelle)
local function buildLantern(parent, position, withLight)
	prop(
		parent,
		"LanternPost",
		Vector3.new(0.4, 6.4, 0.4),
		CFrame.new(position + Vector3.new(0, 3.2, 0)),
		Color3.fromRGB(52, 54, 62),
		Enum.Material.Metal
	)
	prop(
		parent,
		"LanternCap",
		Vector3.new(1.7, 0.25, 1.7),
		CFrame.new(position + Vector3.new(0, 7.45, 0)),
		Color3.fromRGB(52, 54, 62),
		Enum.Material.Metal,
		SOFT
	)
	local lamp = prop(
		parent,
		"LanternLamp",
		Vector3.new(1.2, 1.4, 1.2),
		CFrame.new(position + Vector3.new(0, 6.8, 0)),
		World.Lantern,
		Enum.Material.SmoothPlastic,
		SOFT
	)
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
	prop(
		parent,
		"BenchSeat",
		Vector3.new(4.4, 0.35, 1.5),
		cframe * CFrame.new(0, 1.55, 0),
		World.WoodLight,
		Enum.Material.Wood
	)
	prop(
		parent,
		"BenchBack",
		Vector3.new(4.4, 1.1, 0.25),
		cframe * CFrame.new(0, 2.4, 0.68),
		World.Wood,
		Enum.Material.Wood,
		SOFT
	)
	for _, x in ipairs({ -1.8, 1.8 }) do
		prop(
			parent,
			"BenchLeg",
			Vector3.new(0.35, 1.5, 1.3),
			cframe * CFrame.new(x, 0.75, 0),
			World.WoodDark,
			Enum.Material.Wood
		)
	end
end

local function buildPathRing(parent, center, diameter)
	prop(
		parent,
		"PathRing",
		Vector3.new(0.06, diameter, diameter),
		CFrame.new(center.X, 0.23, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		World.StonePath,
		Enum.Material.Cobblestone,
		{ Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false }
	)
end

------------------------------------------------------------------------
-- Platz-Dekoration: Wege, Dorfbaum, Pavillon, Wegweiser, Beete, Bänke, Laternen
------------------------------------------------------------------------

-- rundes Blumenbeet (passt besser zum runden Platz als eckige)
local function buildRoundBed(parent, center, diameter)
	local function disc(name, height, d, y, color, material)
		prop(
			parent,
			name,
			Vector3.new(height, d, d),
			CFrame.new(center + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			color,
			material,
			{ Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false }
		)
	end
	disc("BedBorder", 0.5, diameter + 0.9, 0.45, World.StoneDark, Enum.Material.Cobblestone)
	disc("BedSoil", 0.6, diameter, 0.5, World.Soil, Enum.Material.Ground)
	disc("BedGreen", 0.8, diameter - 0.6, 0.85, World.Leaf, Enum.Material.Grass)
	for i = 1, math.clamp(math.floor(diameter * 1.6), 5, 12) do
		local angle = i * 2.4
		local distance = (diameter / 2 - 0.7) * math.sqrt(rng:NextNumber(0.1, 1))
		prop(
			parent,
			"Flower",
			Vector3.new(0.7, 0.7, 0.7),
			CFrame.new(center + Vector3.new(math.cos(angle) * distance, 1.45, math.sin(angle) * distance)),
			World.Flowers[rng:NextInteger(1, #World.Flowers)],
			Enum.Material.SmoothPlastic,
			{ Shape = Enum.PartType.Ball, CanCollide = false, CanQuery = false, CastShadow = false }
		)
	end
end

-- gerader Weg von radius r0 bis r1 unter dem Winkel angle
local function radialPath(parent, angle, r0, r1, width, color, material, height, name)
	FarmProps.Strip(
		parent,
		name or "PathStone",
		onRing(angle, (r0 + r1) / 2, 0.2 + (height or 0.06) / 2),
		width,
		r1 - r0,
		color or World.StonePath,
		material or Enum.Material.Cobblestone,
		height or 0.06
	)
end

do
	-- Ring um den Brunnen, Gassen zu den Feldwegen (bei den Farmen) und zu den Shop-Türen
	buildPathRing(hub, Vector3.zero, 32)
	for k = 0, Map.PlotsPerRing - 1 do
		radialPath(hub, k * 360 / Map.PlotsPerRing, 15, HUB_RADIUS + 1, 9)
	end
	for _, shop in ipairs(Map.Shops) do
		radialPath(hub, shop.Angle, 15, Map.ShopRadius - 8, 7)
	end

	-- Dorfbaum hinter dem Werkzeug-Shop (Osten): die Krone ragt über das Dach
	local treeBase = onRing(90, 57)
	FarmProps.Tree(hub, treeBase * CFrame.new(0, 0.2, 0), { Scale = 2.1, Shade = 0.6, Rng = rng })
	FarmProps.Wildflowers(hub, treeBase * CFrame.new(0, 0.2, 0), 5, 10, rng)

	-- Pavillon (Westen, zwischen Auto-Melker und Kuh-Shop), Eingang zum Brunnen
	local pavilion = onRing(270, 40)
	local function pavilionDisc(name, height, diameter, y, color, material)
		prop(
			hub,
			name,
			Vector3.new(height, diameter, diameter),
			pavilion * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
			color,
			material,
			{ Shape = Enum.PartType.Cylinder }
		)
	end
	pavilionDisc("PavilionFloor", 0.8, 14, 0.6, World.WoodLight, Enum.Material.WoodPlanks)
	pavilionDisc("PavilionRoof", 0.8, 16, 8.6, Pal.Red, Enum.Material.Fabric)
	pavilionDisc("PavilionRoof", 0.8, 11.5, 9.4, Pal.Cream, Enum.Material.Fabric)
	pavilionDisc("PavilionRoof", 0.8, 6.5, 10.2, Pal.Red, Enum.Material.Fabric)
	prop(
		hub,
		"PavilionTop",
		Vector3.new(1.4, 1.4, 1.4),
		pavilion * CFrame.new(0, 11.2, 0),
		Pal.Gold,
		Enum.Material.Metal,
		{
			Shape = Enum.PartType.Ball,
		}
	)
	local posts = {}
	for i = 0, 5 do
		local a = math.rad(30 + i * 60)
		local position = Vector3.new(6.2 * math.sin(a), 0, 6.2 * math.cos(a))
		posts[i] = position
		prop(
			hub,
			"PavilionPost",
			Vector3.new(0.6, 7.4, 0.6),
			pavilion * CFrame.new(position + Vector3.new(0, 4.7, 0)),
			Pal.Cream,
			Enum.Material.Wood
		)
	end
	for i = 0, 5 do
		local a, b = posts[i], posts[(i + 1) % 6]
		-- zwischen den Pfosten bei 150° und 210° ist der Eingang (zeigt zum Brunnen, -Z)
		if i ~= 2 then
			local middle = (a + b) / 2
			prop(
				hub,
				"PavilionRail",
				Vector3.new(0.3, 0.35, (b - a).Magnitude),
				pavilion * CFrame.lookAt(middle + Vector3.new(0, 2.4, 0), b + Vector3.new(0, 2.4, 0)),
				World.Wood,
				Enum.Material.Wood
			)
		end
	end
	buildBench(hub, pavilion * CFrame.new(0, 1, 3.6))

	-- Wegweiser zu den Shops (vor dem Pavillon)
	local postPosition = polar(250, 27)
	prop(
		hub,
		"SignPost",
		Vector3.new(0.5, 9, 0.5),
		CFrame.new(postPosition + Vector3.new(0, 4.5, 0)),
		World.WoodDark,
		Enum.Material.Wood
	)
	for i, shop in ipairs(Map.Shops) do
		local y = 8.4 - i * 1.25
		local from = postPosition + Vector3.new(0, y, 0)
		local target = Vector3.new(shop.Position.X, y, shop.Position.Z)
		local board = prop(
			hub,
			"SignBoard",
			Vector3.new(0.25, 1, 4.6),
			CFrame.lookAt(from, target) * CFrame.new(0, 0, -2.4),
			World.WoodLight,
			Enum.Material.WoodPlanks
		)
		addSurfaceText(board, Enum.NormalId.Right, shop.Icon .. " " .. shop.Label, Pal.Cream, World.WoodDark)
		addSurfaceText(board, Enum.NormalId.Left, shop.Icon .. " " .. shop.Label, Pal.Cream, World.WoodDark)
	end

	-- Bänke am Brunnen, Blick zur Mitte
	for _, angle in ipairs({ 245, 295 }) do
		buildBench(hub, onRing(angle, 20))
	end

	-- Laternen an jeder Gasse, runde Beete daneben
	for k = 0, Map.PlotsPerRing - 1 do
		local angle = k * 360 / Map.PlotsPerRing
		buildLantern(hub, polar(angle - 10, 59), true)
		buildLantern(hub, polar(angle + 10, 59), false)
		buildRoundBed(hub, polar(angle - 17, 54), 5)
		buildRoundBed(hub, polar(angle + 17, 54), 5)
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
				ctx.part(
					"Roof",
					Vector3.new(width, 0.6, length),
					CFrame.new(0, center.Y, center.X) * CFrame.Angles(-phi, 0, 0),
					color,
					material
				)
			else
				ctx.part(
					"Roof",
					Vector3.new(width, 0.6, length),
					CFrame.new(0, center.Y, -center.X) * CFrame.Angles(phi, 0, 0),
					color,
					material
				)
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
					ctx.part(
						"GableFill",
						Vector3.new(1, hA, span),
						CFrame.new(x, eaveY + hA / 2, zMid * flip),
						color,
						material
					)
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
		part(
			"WallFront",
			Vector3.new(frontWidth, H, 1),
			CFrame.new(side * (doorW / 2 + frontWidth / 2), H / 2, -D / 2 + 0.5),
			wall,
			material
		)
		part(
			"DoorFrame",
			Vector3.new(0.5, doorH, 1.3),
			CFrame.new(side * (doorW / 2 + 0.25), doorH / 2, -D / 2 + 0.5),
			trim,
			Enum.Material.Wood
		)
	end
	part(
		"WallOverDoor",
		Vector3.new(doorW, H - doorH, 1),
		CFrame.new(0, doorH + (H - doorH) / 2, -D / 2 + 0.5),
		wall,
		material
	)
	part(
		"DoorFrameTop",
		Vector3.new(doorW + 1, 0.5, 1.3),
		CFrame.new(0, doorH + 0.25, -D / 2 + 0.5),
		trim,
		Enum.Material.Wood
	)
	for _, x in ipairs({ -W / 2, W / 2 }) do
		for _, z in ipairs({ -D / 2, D / 2 }) do
			part("Corner", Vector3.new(1.3, H, 1.3), CFrame.new(x, H / 2, z), trim, Enum.Material.Wood)
		end
	end

	-- Theke innen (durch die Tür sichtbar)
	part("Counter", Vector3.new(9, 3.2, 2), CFrame.new(0, 1.8, D / 2 - 4), World.WoodDark, Enum.Material.Wood)
	part(
		"CounterTop",
		Vector3.new(9.4, 0.3, 2.4),
		CFrame.new(0, 3.55, D / 2 - 4),
		ctx.opts.Color,
		Enum.Material.SmoothPlastic
	)
end

-- Fenster mit Rahmen (liegt auf der Außenwand, keine Öffnung)
local function buildWindow(ctx, x, y, w, h, trim)
	ctx.part(
		"WindowFrame",
		Vector3.new(w + 0.6, h + 0.6, 0.15),
		CFrame.new(x, y, -ctx.D / 2 - 0.05),
		trim,
		Enum.Material.Wood,
		SOFT
	)
	ctx.part(
		"Window",
		Vector3.new(w, h, 0.2),
		CFrame.new(x, y, -ctx.D / 2 - 0.15),
		Color3.fromRGB(170, 212, 245),
		Enum.Material.Glass,
		{ Transparency = 0.35, CanCollide = false, CanQuery = false }
	)
	ctx.part(
		"WindowBar",
		Vector3.new(w, 0.18, 0.1),
		CFrame.new(x, y, -ctx.D / 2 - 0.28),
		trim,
		Enum.Material.Wood,
		SOFT
	)
end

-- Holzschild an der Wand: Rückbrett + Brett mit Text (Symbol + Name), gut lesbar aus ~40 Studs
local function buildSign(ctx, x, y, width, height)
	local zFront = -ctx.D / 2 - 0.15
	ctx.part(
		"SignBacker",
		Vector3.new(width + 0.6, height + 0.6, 0.3),
		CFrame.new(x, y, zFront),
		World.Wood,
		Enum.Material.Wood
	)
	local board = ctx.part(
		"Sign",
		Vector3.new(width, height, 0.3),
		CFrame.new(x, y, zFront - 0.25),
		World.WoodDark,
		Enum.Material.Wood
	)

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
	local anchor = ctx.part(
		"SignAnchor",
		Vector3.new(1, 1, 1),
		CFrame.new(-3.6, 5.4, -ctx.D / 2 - 1.8),
		World.WoodDark,
		nil,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false }
	)
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
	npcPart(
		"HatBrim",
		Vector3.new(0.15, 2.6, 2.6),
		CFrame.new(0, 5.25, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(235, 200, 110),
		Enum.PartType.Cylinder
	)
	npcPart(
		"HatCrown",
		Vector3.new(0.8, 1.3, 1.3),
		CFrame.new(0, 5.65, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(235, 200, 110),
		Enum.PartType.Cylinder
	)
	npcPart(
		"HatBand",
		Vector3.new(0.25, 1.36, 1.36),
		CFrame.new(0, 5.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
		ctx.opts.Color,
		Enum.PartType.Cylinder
	)
	npc.PrimaryPart = npcTorso
	npc.Parent = ctx.model
	CollectionService:AddTag(npc, "ShopKeeper")
end

-- warmes Licht innen (ein kleiner Schein statt einer Neon-Kugel)
local function buildInnerLight(ctx, y)
	local lamp = ctx.part(
		"Lamp",
		Vector3.new(1, 1, 1),
		CFrame.new(0, y, 0),
		World.Lantern,
		Enum.Material.SmoothPlastic,
		{ Shape = Enum.PartType.Ball, CanCollide = false, CanQuery = false }
	)
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
		ctx.part(
			"BarnDoor",
			Vector3.new(4.8, 6.6, 0.3),
			CFrame.new(x, 3.5, -D / 2 - 0.1),
			opts.Color,
			Enum.Material.WoodPlanks,
			SOFT
		)
		for _, dir in ipairs({ -1, 1 }) do
			ctx.part(
				"DoorBrace",
				Vector3.new(braceLength, 0.4, 0.2),
				CFrame.new(x, 3.5, -D / 2 - 0.3) * CFrame.Angles(0, 0, dir * braceAngle),
				trim,
				Enum.Material.Wood,
				SOFT
			)
		end
	end

	-- Gambrel-Dach: steile untere, flache obere Fläche
	local profile = { Vector2.new(-D / 2, H), Vector2.new(-4.5, H + 4.2), Vector2.new(0, H + 6.8) }
	buildRoof(ctx, profile, 1.0, opts.RoofColor, Enum.Material.Slate, ctx.W + 2)
	buildGables(ctx, profile, H, opts.WallColor, Enum.Material.WoodPlanks)
	ctx.part("Ridge", Vector3.new(ctx.W + 2.2, 0.6, 0.9), CFrame.new(0, H + 7.15, 0), trim, Enum.Material.Wood, SOFT)
	-- Wetterfahne
	ctx.part(
		"VanePost",
		Vector3.new(0.25, 2.6, 0.25),
		CFrame.new(0, H + 8.4, 0),
		World.WoodDark,
		Enum.Material.Wood,
		SOFT
	)
	ctx.part("VaneArrow", Vector3.new(0.15, 0.5, 1.8), CFrame.new(0, H + 9.5, 0), opts.Color, Enum.Material.Metal, SOFT)

	buildSign(ctx, 0, 8.75, 10.5, 1.9)
	buildInnerLight(ctx, H - 1.5)

	-- davor: Fässer und Heu seitlich (nicht auf dem Weg)
	for _, x in ipairs({ -12.2, -13.6 }) do
		ctx.part(
			"Barrel",
			Vector3.new(2.2, 1.8, 1.8),
			CFrame.new(x, 1.1, -D / 2 + 1.5) * CFrame.Angles(0, 0, math.rad(90)),
			World.Wood,
			Enum.Material.Wood,
			{ Shape = Enum.PartType.Cylinder }
		)
	end
	ctx.part("HayBale", Vector3.new(3.4, 1.8, 2.6), CFrame.new(12.6, 0.9, -D / 2 + 2), World.Hay, Enum.Material.Fabric)
end

-- Stil 2: Kisten = offener Marktstand mit gestreiftem Dach und Kistenstapeln
local function styleStall(ctx)
	local opts, D, W = ctx.opts, ctx.D, ctx.W
	local part = ctx.part

	part("Floor", Vector3.new(W, 0.4, D), CFrame.new(0, 0.2, 0), Color3.fromRGB(165, 124, 86), Enum.Material.WoodPlanks)
	part(
		"WallBack",
		Vector3.new(W, 9.6, 0.8),
		CFrame.new(0, 4.8, D / 2 - 0.4),
		opts.WallColor,
		Enum.Material.WoodPlanks
	)
	for _, side in ipairs({ -1, 1 }) do
		part(
			"WallSide",
			Vector3.new(0.8, 3.6, D),
			CFrame.new(side * (W / 2 - 0.4), 1.8, 0),
			opts.WallColor,
			Enum.Material.WoodPlanks
		)
		part(
			"FrontPost",
			Vector3.new(1.1, 9.6, 1.1),
			CFrame.new(side * (W / 2 - 0.55), 4.8, -D / 2 + 1),
			World.WoodDark,
			Enum.Material.Wood
		)
		part(
			"BackPost",
			Vector3.new(1.1, 11.4, 1.1),
			CFrame.new(side * (W / 2 - 0.55), 5.7, D / 2 - 0.55),
			World.WoodDark,
			Enum.Material.Wood
		)
	end
	part("FrontBeam", Vector3.new(W, 1.8, 1), CFrame.new(0, 8.7, -D / 2 + 1), World.Wood, Enum.Material.Wood)

	-- Verkaufstheke vorne
	part("Counter", Vector3.new(W - 5, 3.2, 1.8), CFrame.new(0, 1.8, -D / 2 + 3), World.WoodDark, Enum.Material.Wood)
	part(
		"CounterTop",
		Vector3.new(W - 4.6, 0.3, 2.3),
		CFrame.new(0, 3.55, -D / 2 + 3),
		opts.Color,
		Enum.Material.SmoothPlastic
	)

	-- gestreiftes Dach (leicht nach hinten ansteigend), Streifen quer zur Länge
	local frontY, backY = 10.0, 11.7
	local frontZ, backZ = -D / 2 - 1.6, D / 2 + 0.4
	local length = math.sqrt((backZ - frontZ) ^ 2 + (backY - frontY) ^ 2)
	local tilt = math.atan2(backY - frontY, backZ - frontZ)
	local stripes = 8
	for i = 0, stripes - 1 do
		local width = (W + 2) / stripes
		part(
			"RoofStripe",
			Vector3.new(width, 0.35, length),
			CFrame.new(-(W + 2) / 2 + (i + 0.5) * width, (frontY + backY) / 2, (frontZ + backZ) / 2)
				* CFrame.Angles(-tilt, 0, 0),
			i % 2 == 0 and opts.Color or Pal.Cream,
			Enum.Material.Fabric
		)
	end

	buildSign(ctx, 0, 8.7, 11, 1.5)

	-- Kisten: auf der Theke und als Stapel dahinter
	local function crate(x, y, z, size, color)
		part(
			"Crate",
			Vector3.new(size, size, size),
			CFrame.new(x, y, z) * CFrame.Angles(0, rng:NextNumber(-0.25, 0.25), 0),
			color,
			Enum.Material.WoodPlanks
		)
		part(
			"CrateBand",
			Vector3.new(size + 0.1, 0.3, size + 0.1),
			CFrame.new(x, y, z),
			World.WoodDark,
			Enum.Material.Wood,
			SOFT
		)
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
		part(
			"ShelfBox",
			Vector3.new(1.4, 1.2, 1.0),
			CFrame.new(-5.6 + (i - 1) * 2.8, 6.95, D / 2 - 1.5),
			Palette.rarityColor(rarity),
			Enum.Material.SmoothPlastic,
			SOFT
		)
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
		ctx.part(
			"FlowerBox",
			Vector3.new(3.8, 0.7, 0.9),
			CFrame.new(x, 2.3, -D / 2 - 0.65),
			World.Wood,
			Enum.Material.Wood,
			SOFT
		)
		for k = -1, 1 do
			ctx.part(
				"Flower",
				Vector3.new(0.7, 0.7, 0.7),
				CFrame.new(x + k * 1.1, 2.9, -D / 2 - 0.65),
				World.Flowers[rng:NextInteger(1, #World.Flowers)],
				Enum.Material.SmoothPlastic,
				{ Shape = Enum.PartType.Ball, CanCollide = false, CanQuery = false, CastShadow = false }
			)
		end
	end

	-- flaches Satteldach mit breitem Überstand
	local ridgeY = H + (D / 2) * math.tan(math.rad(26))
	local profile = { Vector2.new(-D / 2, H), Vector2.new(0, ridgeY) }
	buildRoof(ctx, profile, 1.8, opts.RoofColor, Enum.Material.Slate, ctx.W + 3)
	buildGables(ctx, profile, H, opts.WallColor, Enum.Material.WoodPlanks)
	ctx.part(
		"Ridge",
		Vector3.new(ctx.W + 3.2, 0.6, 0.9),
		CFrame.new(0, ridgeY + 0.4, 0),
		trim,
		Enum.Material.Wood,
		SOFT
	)

	buildSign(ctx, 0, 6.95, 9, 1.7)
	buildInnerLight(ctx, H - 1.5)

	-- Heuballen und Trog neben dem Stall
	ctx.part("HayBale", Vector3.new(3.4, 1.8, 2.6), CFrame.new(-12.4, 0.9, -D / 2 + 2), World.Hay, Enum.Material.Fabric)
	ctx.part(
		"HayBale",
		Vector3.new(3.4, 1.8, 2.6),
		CFrame.new(-12.4, 2.7, -D / 2 + 2.2),
		World.Hay,
		Enum.Material.Fabric
	)
	ctx.part("Trough", Vector3.new(4, 1.1, 1.4), CFrame.new(12.4, 0.55, -D / 2 + 2), World.Wood, Enum.Material.Wood)
	ctx.part(
		"TroughWater",
		Vector3.new(3.5, 0.1, 0.9),
		CFrame.new(12.4, 1.1, -D / 2 + 2),
		Pal.Blue,
		Enum.Material.Glass,
		{ Transparency = 0.3, CanCollide = false, CanQuery = false }
	)
end

-- Stil 4: Auto-Melker = kleine Werkstatt aus Wellblech mit Silo, Schornstein und Milchkannen
local function styleWorkshop(ctx)
	local opts, D = ctx.opts, ctx.D
	local H = 9
	local trim = Color3.fromRGB(64, 70, 82)
	buildShell(ctx, {
		W = 15,
		H = H,
		DoorW = 6,
		DoorH = 6.5,
		WallColor = opts.WallColor,
		Trim = trim,
		WallMaterial = Enum.Material.Metal,
	})
	local W = ctx.W

	-- Pultdach: vorne niedrig, hinten hoch
	local rise = 2.2
	local frontZ, backZ = -D / 2 - 1.2, D / 2 + 0.6
	local slope = rise / D
	local roofLength = (backZ - frontZ) * math.sqrt(1 + slope ^ 2)
	local midZ = (frontZ + backZ) / 2
	ctx.part(
		"Roof",
		Vector3.new(W + 2, 0.6, roofLength),
		CFrame.new(0, H + slope * (midZ + D / 2) + 0.3, midZ) * CFrame.Angles(-math.atan(slope), 0, 0),
		opts.RoofColor,
		Enum.Material.Metal
	)
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
	ctx.part(
		"Chimney",
		Vector3.new(4.5, 1.2, 1.2),
		CFrame.new(-4, H + 3.8, 4) * CFrame.Angles(0, 0, math.rad(90)),
		World.StoneDark,
		Enum.Material.Brick,
		{ Shape = Enum.PartType.Cylinder, CanCollide = false }
	)

	-- Silo daneben (Zylinder + Kuppel + Ringe)
	local siloX, siloH, siloR = W / 2 + 2.4, 14, 2.2
	ctx.part(
		"Silo",
		Vector3.new(siloH, siloR * 2, siloR * 2),
		CFrame.new(siloX, siloH / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(205, 210, 216),
		Enum.Material.Metal,
		{ Shape = Enum.PartType.Cylinder }
	)
	ctx.part(
		"SiloDome",
		Vector3.new(siloR * 2, siloR * 2, siloR * 2),
		CFrame.new(siloX, siloH, 0),
		opts.RoofColor,
		Enum.Material.Metal,
		{ Shape = Enum.PartType.Ball, CanCollide = false }
	)
	for _, y in ipairs({ 4, 9 }) do
		ctx.part(
			"SiloBand",
			Vector3.new(0.35, siloR * 2 + 0.2, siloR * 2 + 0.2),
			CFrame.new(siloX, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
			trim,
			Enum.Material.Metal,
			{ Shape = Enum.PartType.Cylinder, CanCollide = false }
		)
	end
	ctx.part(
		"SiloLadder",
		Vector3.new(0.3, 12, 0.3),
		CFrame.new(siloX, 6.5, -siloR - 0.1),
		World.Metal,
		Enum.Material.Metal,
		SOFT
	)

	buildSign(ctx, 0, 7.9, 8.2, 1.6)
	buildInnerLight(ctx, H - 1.6)

	-- Milchkannen vor der Werkstatt
	for i, x in ipairs({ -10.4, -9.2, -10.9 }) do
		ctx.part(
			"MilkCan",
			Vector3.new(1.5, 1.1, 1.1),
			CFrame.new(x, 0.75, -D / 2 + 1.2 + (i % 2) * 1.4) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(205, 210, 218),
			Enum.Material.Metal,
			{ Shape = Enum.PartType.Cylinder }
		)
	end
end

-- Stil 5: Werkzeug = Geräteschuppen: Steinsockel, Holzwände, steiles Satteldach mit Wetterhahn,
-- Mistgabel/Schaufel/Rechen an der Wand, Werkbank mit Amboss, Werkzeug aus dem Shop als Schaufenster
local function styleToolShed(ctx)
	local opts, D = ctx.opts, ctx.D
	local H = 8.5
	local trim = World.WoodDark
	local doorW = 6
	buildShell(ctx, { W = 18, H = H, DoorW = doorW, DoorH = 6.5, WallColor = opts.WallColor, Trim = trim })
	local W = ctx.W
	local front = -D / 2

	-- Steinsockel rundherum (vorne nur neben der Tür)
	local stone, cobble = World.StoneDark, Enum.Material.Cobblestone
	ctx.part("StoneBase", Vector3.new(W + 0.4, 2.2, 1.3), CFrame.new(0, 1.1, D / 2 - 0.4), stone, cobble)
	local pieceW = (W - doorW) / 2
	for _, side in ipairs({ -1, 1 }) do
		ctx.part("StoneBase", Vector3.new(1.3, 2.2, D + 0.4), CFrame.new(side * (W / 2 - 0.4), 1.1, 0), stone, cobble)
		ctx.part(
			"StoneBase",
			Vector3.new(pieceW, 2.2, 1.3),
			CFrame.new(side * (doorW / 2 + pieceW / 2), 1.1, front + 0.4),
			stone,
			cobble
		)
	end

	-- steiles Satteldach (First parallel zur Vorderseite), Esse mit Rauch
	local ridgeY = H + (D / 2) * math.tan(math.rad(38))
	local profile = { Vector2.new(-D / 2, H), Vector2.new(0, ridgeY) }
	buildRoof(ctx, profile, 1.4, opts.RoofColor, Enum.Material.Slate, W + 2)
	buildGables(ctx, profile, H, opts.WallColor, Enum.Material.WoodPlanks)
	ctx.part("Ridge", Vector3.new(W + 2.2, 0.6, 0.9), CFrame.new(0, ridgeY + 0.4, 0), trim, Enum.Material.Wood, SOFT)
	local chimney = ctx.part(
		"Chimney",
		Vector3.new(1.8, 5, 1.8),
		CFrame.new(W / 2 - 3, ridgeY - 0.6, 3.2),
		Color3.fromRGB(150, 82, 64),
		Enum.Material.Brick,
		SOFT
	)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(200, 200, 200))
	smoke.Transparency = NumberSequence.new(0.4, 1)
	smoke.Size = NumberSequence.new(0.8, 2.4)
	smoke.Lifetime = NumberRange.new(2.5, 4)
	smoke.Speed = NumberRange.new(2, 3)
	smoke.SpreadAngle = Vector2.new(12, 12)
	smoke.Rate = 3
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Parent = chimney
	-- Wetterhahn auf dem First (dreht sich, siehe WorldAnimator)
	local vane = GearModels.Build("WeatherVane", ctx.base * CFrame.new(-W / 2 + 3.2, ridgeY - 0.1, 0))
	if vane then
		vane.Name = "RoofVane"
		vane.Parent = ctx.model
	end

	buildSign(ctx, 0, 7.4, 8.5, 1.5)
	buildInnerLight(ctx, H - 1.5)

	-- Werkzeug an der Wand links neben der Tür (lehnt oben an der Wand)
	local tool = World.WoodLight
	local metal = World.Metal
	local function leaning(x)
		return CFrame.new(x, 0, front - 0.45) * CFrame.Angles(math.rad(9), 0, 0)
	end
	local fork = leaning(-4.3)
	ctx.part("ForkHandle", Vector3.new(0.2, 4.2, 0.2), fork * CFrame.new(0, 2.1, 0), tool, Enum.Material.Wood, SOFT)
	ctx.part("ForkHead", Vector3.new(1.05, 0.14, 0.14), fork * CFrame.new(0, 4.25, 0), metal, Enum.Material.Metal, SOFT)
	for _, x in ipairs({ -0.45, 0, 0.45 }) do
		ctx.part(
			"ForkTine",
			Vector3.new(0.08, 0.9, 0.08),
			fork * CFrame.new(x, 4.75, 0),
			metal,
			Enum.Material.Metal,
			SOFT
		)
	end
	local shovel = leaning(-5.7)
	ctx.part(
		"ShovelBlade",
		Vector3.new(0.95, 1.15, 0.1),
		shovel * CFrame.new(0, 0.62, 0),
		metal,
		Enum.Material.Metal,
		SOFT
	)
	ctx.part("ShovelHandle", Vector3.new(0.2, 3.3, 0.2), shovel * CFrame.new(0, 2.8, 0), tool, Enum.Material.Wood, SOFT)
	ctx.part(
		"ShovelGrip",
		Vector3.new(0.65, 0.16, 0.16),
		shovel * CFrame.new(0, 4.45, 0),
		tool,
		Enum.Material.Wood,
		SOFT
	)
	local rake = leaning(-7.1)
	ctx.part("RakeHandle", Vector3.new(0.18, 4.4, 0.18), rake * CFrame.new(0, 2.2, 0), tool, Enum.Material.Wood, SOFT)
	ctx.part("RakeHead", Vector3.new(1.4, 0.16, 0.2), rake * CFrame.new(0, 4.45, 0), metal, Enum.Material.Metal, SOFT)
	for k = -2, 2 do
		ctx.part(
			"RakeTooth",
			Vector3.new(0.07, 0.35, 0.07),
			rake * CFrame.new(k * 0.3, 4.66, 0),
			metal,
			Enum.Material.Metal,
			SOFT
		)
	end

	-- Werkbank mit Amboss und Hammer rechts neben der Tür
	local bench = CFrame.new(5.8, 0, front - 1.1)
	ctx.part(
		"Workbench",
		Vector3.new(3.4, 0.3, 1.4),
		bench * CFrame.new(0, 2.25, 0),
		World.Wood,
		Enum.Material.WoodPlanks
	)
	for _, x in ipairs({ -1.45, 1.45 }) do
		for _, z in ipairs({ -0.5, 0.5 }) do
			ctx.part(
				"BenchLeg",
				Vector3.new(0.25, 2.1, 0.25),
				bench * CFrame.new(x, 1.05, z),
				World.WoodDark,
				Enum.Material.Wood
			)
		end
	end
	local iron = Color3.fromRGB(70, 74, 82)
	ctx.part("Anvil", Vector3.new(1.1, 0.45, 0.55), bench * CFrame.new(-0.6, 2.85, 0), iron, Enum.Material.Metal, SOFT)
	ctx.part(
		"AnvilFoot",
		Vector3.new(0.6, 0.25, 0.45),
		bench * CFrame.new(-0.6, 2.52, 0),
		iron,
		Enum.Material.Metal,
		SOFT
	)
	ctx.part(
		"HammerHandle",
		Vector3.new(1.2, 0.12, 0.12),
		bench * CFrame.new(0.8, 2.48, 0.1) * CFrame.Angles(0, math.rad(30), 0),
		tool,
		Enum.Material.Wood,
		SOFT
	)
	ctx.part(
		"HammerHead",
		Vector3.new(0.22, 0.25, 0.5),
		bench * CFrame.new(1.3, 2.55, 0.4),
		iron,
		Enum.Material.Metal,
		SOFT
	)

	-- Fass an der Ecke
	ctx.part(
		"Barrel",
		Vector3.new(2, 1.5, 1.5),
		CFrame.new(W / 2 + 1.2, 1, front + 1.4) * CFrame.Angles(0, 0, math.rad(90)),
		World.Wood,
		Enum.Material.Wood,
		{ Shape = Enum.PartType.Cylinder }
	)

	-- Schaufenster: echtes Werkzeug aus dem Shop neben dem Schuppen
	for _, show in ipairs({ { "FeedTrough", -11.6, 20 }, { "CowBell", 11.8, -15 } }) do
		local model = GearModels.Build(
			show[1],
			ctx.base * CFrame.new(show[2], 0, front + 2.4) * CFrame.Angles(0, math.rad(show[3]), 0)
		)
		if model then
			model.Parent = ctx.model
		end
	end
end

local STYLES = {
	CowShop = styleBarn,
	CrateShop = styleStall,
	BreedingBarn = styleStable,
	AutoMilkerShop = styleWorkshop,
	GearShop = styleToolShed,
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
-- Alle Shops bauen (Daten aus CowData.Map.Shops): rund um den Brunnen, Tür zeigt zur Mitte
------------------------------------------------------------------------
for _, shop in ipairs(Map.Shops) do
	local opts = table.clone(shop)
	opts.Parent = hub
	buildShop(opts, CowData.GetShopCFrame(shop))
end

------------------------------------------------------------------------
-- Landschaft rund um den Platz:
--   * Feldwege vom Platz zu jedem Farm-Tor und ein Ringweg vor den Toren
--   * zwischen den Farmen: Windmühle + Weizen, Teich, Obstgarten, Kürbisse, Blumenfeld + Bienen,
--     Traktor + Heu (jeweils links und rechts eines Pfads nach außen)
--   * Waldrand hinter den Farmen, Hügel ganz außen
-- Farmen: innerer Ring bei 0°, 60°, ... (Tor bei Radius 115), Lücken dazwischen bei 30°, 90°, ...
------------------------------------------------------------------------
local country = Instance.new("Folder")
country.Name = "Countryside"
country.Parent = layoutFolder

local countryRng = Random.new(77)
local DIRT = Colors.Dirt
local GATE_RADIUS = Map.PlotRingRadius - Map.PlotDepth / 2 -- 115: Tor der inneren Farmen
local PLOT_STEP = 360 / Map.PlotsPerRing

-- Feldwege: vom Platz zu jedem Tor, Ringweg vor den Toren, Pfade in die Lücken nach außen
do
	for k = 0, Map.PlotsPerRing - 1 do
		local angle = k * PLOT_STEP
		local r0, r1 = HUB_RADIUS - 2, GATE_RADIUS + 1
		FarmProps.Strip(
			country,
			"Road",
			onRing(angle, (r0 + r1) / 2, 0.05),
			9,
			r1 - r0,
			DIRT,
			Enum.Material.Ground,
			0.1
		)
		local g0, g1 = Map.RingRoadRadius + 3, 250
		FarmProps.Strip(
			country,
			"Footpath",
			onRing(angle + PLOT_STEP / 2, (g0 + g1) / 2, 0.04),
			5,
			g1 - g0,
			DIRT:Lerp(Colors.MeadowLight, 0.25),
			Enum.Material.Ground,
			0.08
		)
		-- Laternen am Weg (abwechselnd links/rechts, Ausleger über dem Weg)
		for i, r in ipairs({ 80, 100 }) do
			local side = i % 2 == 0 and 1 or -1
			FarmProps.Lantern(
				country,
				onRing(angle, r) * CFrame.new(side * 6, 0, 0) * CFrame.Angles(0, math.rad(side * 90), 0),
				r == 100
			)
		end
	end
	-- Ringweg aus 36 kurzen Stücken
	local radius, segments = Map.RingRoadRadius, 36
	local half = math.pi / segments
	for i = 0, segments - 1 do
		local angle = (i + 0.5) * 360 / segments
		-- Breite (X) = Stück entlang des Rings, Länge (Z) = Wegbreite quer dazu
		FarmProps.Strip(
			country,
			"RingRoad",
			onRing(angle, radius * math.cos(half), 0.03),
			2 * radius * math.sin(half) + 0.8,
			8,
			DIRT,
			Enum.Material.Ground,
			0.06
		)
	end
end

-- Wiese zwischen Platz und Ringweg: Bäume, Büsche, Blumen, Steine
do
	for k = 0, Map.PlotsPerRing - 1 do
		local c = k * PLOT_STEP + PLOT_STEP / 2
		local function at(angle, radius, yaw)
			return CFrame.new(polar(angle, radius))
				* CFrame.Angles(0, math.rad(yaw or countryRng:NextNumber(0, 360)), 0)
		end
		FarmProps.Tree(country, at(c - 14, 86), { Scale = countryRng:NextNumber(1, 1.3), Rng = countryRng })
		FarmProps.Tree(country, at(c + 12, 78), { Scale = countryRng:NextNumber(0.9, 1.2), Rng = countryRng })
		FarmProps.Bush(country, at(c, 70), 1.1)
		FarmProps.Bush(country, at(c + 21, 95), 0.9)
		FarmProps.Bush(country, at(c - 22, 71), 1)
		FarmProps.Rock(country, at(c - 4, 99), countryRng:NextNumber(0.8, 1.2))
		FarmProps.Wildflowers(country, at(c + 3, 90), 5, 10, countryRng)
		FarmProps.Wildflowers(country, at(c - 18, 100), 3, 6, countryRng)
	end
end

-- Themen zwischen den Farmen. frame: Ursprung = Kartenmitte, +Z zeigt in die Lücke hinaus.
-- place(v, u, yaw): v = seitlich (Pfad bei v = 0), u = Abstand von der Mitte
do
	local themes = {}

	-- 30°: Windmühle und Weizenfeld
	themes[1] = function(place)
		FarmProps.Windmill(country, place(-24, 205, 180))
		FarmProps.WheatField(country, place(26, 210, 0), 20, 26)
		FarmProps.Scarecrow(country, place(26, 206, 180))
		FarmProps.HayBale(country, place(11, 182, 20))
		FarmProps.HayBale(country, place(11.5, 182.3, 15) * CFrame.new(0, 1.8, 0))
		FarmProps.Cart(country, place(-10, 172, 160))
	end
	-- 90°: Teich mit Enten, Bank, Bäume
	themes[2] = function(place)
		FarmProps.Pond(country, place(-22, 206, 0), 11, countryRng)
		FarmProps.Bench(country, place(-6, 196, -90))
		FarmProps.Tree(country, place(20, 190), { Scale = 1.3, Rng = countryRng })
		FarmProps.Tree(country, place(30, 224), { Scale = 1.5, Rng = countryRng })
		FarmProps.Tree(country, place(14, 242), { Scale = 1.1, Rng = countryRng })
		FarmProps.Bush(country, place(-30, 186), 1.2)
		FarmProps.Rock(country, place(10, 176), 1.3)
	end
	-- 150°: Obstgarten mit Apfelbäumen und Apfelkisten
	themes[3] = function(place)
		for _, u in ipairs({ 178, 202, 226 }) do
			for _, v in ipairs({ -24, -12, 12, 24 }) do
				FarmProps.Tree(country, place(v, u), { Scale = 0.95, Fruit = true, Shade = 0.4, Rng = countryRng })
			end
		end
		for i, v in ipairs({ 6, 7.4 }) do
			local crate = place(v, 188 + i * 2.2, countryRng:NextNumber(-20, 20))
			FarmProps.Crate(country, crate, 1.6)
			for j = 1, 3 do
				FarmProps.Ball(
					country,
					"Apple",
					0.6,
					crate * CFrame.new((j - 2) * 0.45, 1.75, 0),
					Colors.Apple,
					Enum.Material.SmoothPlastic,
					{ CanCollide = false, CanQuery = false }
				)
			end
		end
	end
	-- 210°: Kürbisbeet mit Vogelscheuche, Heuballen, Karren
	themes[4] = function(place)
		FarmProps.PumpkinPatch(country, place(-24, 202, 0), 18, 22, countryRng)
		FarmProps.Scarecrow(country, place(-24, 202, 180))
		FarmProps.RoundBale(country, place(16, 185, 70))
		FarmProps.RoundBale(country, place(20.5, 189, 85))
		FarmProps.RoundBale(country, place(28, 214, 10))
		FarmProps.Cart(country, place(14, 228, 200))
	end
	-- 270°: Blumenfeld, Bienenstöcke, Sonnenblumen
	themes[5] = function(place)
		FarmProps.FlowerField(country, place(24, 206, 0), 22, 26)
		for i, offset in ipairs({ -3, 0, 3 }) do
			FarmProps.Beehive(country, place(-13 + offset, 186 + i * 0.6, 180 + offset * 4))
		end
		FarmProps.Sunflowers(country, place(-26, 214, 180), 6, countryRng)
		FarmProps.Sunflowers(country, place(-26, 220, 180), 5, countryRng)
	end
	-- 330°: Traktor, Heu-Stapel, zweites Weizenfeld
	themes[6] = function(place)
		FarmProps.Tractor(country, place(-16, 190, 150))
		for i = 0, 2 do
			FarmProps.HayBale(country, place(-24, 208 + i * 2.6, 90))
		end
		FarmProps.HayBale(country, place(-24, 210.6, 90) * CFrame.new(0, 1.8, 0))
		FarmProps.RoundBale(country, place(16, 180, 0))
		FarmProps.RoundBale(country, place(20, 184, 30))
		FarmProps.WheatField(country, place(28, 220, 0), 18, 24)
	end

	for k = 0, Map.PlotsPerRing - 1 do
		local angle = k * PLOT_STEP + PLOT_STEP / 2
		local frame = CFrame.Angles(0, math.rad(angle), 0) -- +Z zeigt unter "angle" nach außen
		local function place(v, u, yaw)
			-- yaw 0: Vorderseite (-Z) zeigt zum Platz
			return frame * CFrame.new(v, 0, u) * CFrame.Angles(0, math.rad(yaw or countryRng:NextNumber(0, 360)), 0)
		end
		themes[k % #themes + 1](place)

		-- Hecke aus Bäumen und Büschen entlang der Farm-Zäune (trennt die Farmen, rahmt das Thema ein)
		local half = math.rad(PLOT_STEP / 2)
		for i, u in ipairs({ 150, 172, 194, 216, 238, 260 }) do
			-- so viel Platz ist seitlich bis zum Zaun der Nachbar-Farm
			local limit = (u * math.sin(half) - (Map.PlotWidth / 2 + 2)) / math.cos(half)
			for _, side in ipairs({ -1, 1 }) do
				local cf = place(side * (limit - 4), u)
				if (i + (side == 1 and 1 or 0)) % 2 == 0 then
					FarmProps.Tree(country, cf, { Scale = countryRng:NextNumber(1, 1.35), Rng = countryRng })
				else
					FarmProps.Bush(country, cf, countryRng:NextNumber(1.1, 1.5))
				end
			end
		end
		-- Rastplatz am Ende des Pfads, Büsche am Anfang
		FarmProps.Bench(country, place(4.5, 246, 90))
		FarmProps.Lantern(country, place(-4, 248, -90), false)
		FarmProps.Bush(country, place(-5, 122), 0.9)
		FarmProps.Bush(country, place(5.5, 128), 0.8)
		FarmProps.Wildflowers(country, place(-9, 160), 4, 8, countryRng)
		FarmProps.Wildflowers(country, place(10, 236), 4, 8, countryRng)
	end
end

-- Waldrand hinter den inneren Farmen (nicht dort, wo ab Spieler 7 der zweite Ring entsteht)
do
	for k = 0, Map.PlotsPerRing - 1 do
		local center = k * PLOT_STEP
		for i = 1, 10 do
			local angle = center + countryRng:NextNumber(-17, 17)
			local radius = 270 + (i % 4) * 17 + countryRng:NextNumber(-4, 4)
			local cf = CFrame.new(polar(angle, radius)) * CFrame.Angles(0, countryRng:NextNumber(0, math.pi * 2), 0)
			if i % 3 == 0 then
				FarmProps.Tree(country, cf, { Scale = countryRng:NextNumber(1.3, 1.8), Rng = countryRng })
			else
				FarmProps.Pine(country, cf, countryRng:NextNumber(1.4, 2.1))
			end
		end
	end
end

------------------------------------------------------------------------
-- Hügel ganz außen (weit hinter allen Farmen, auch hinter dem zweiten Ring)
------------------------------------------------------------------------
do
	local hills = Instance.new("Folder")
	hills.Name = "Hills"
	hills.Parent = layoutFolder
	for i = 0, 11 do
		local diameter = 240 + (i * 37) % 90
		local radius = (i % 2 == 0 and 610 or 690) + diameter * 0.15
		local position = polar(i * 30 + 15, radius)
		makePart({
			Name = "Hill",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(diameter, diameter, diameter),
			-- große Kugel, zu etwa zwei Dritteln im Boden -> sanfter Hügel
			CFrame = CFrame.new(position.X, -diameter * 0.35, position.Z),
			Color = World.GrassDark:Lerp(World.GrassLight, (i % 3) / 3),
			Material = Enum.Material.Grass,
			Parent = hills,
		})
	end
end
