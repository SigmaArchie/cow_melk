-- FarmProps.lua
-- Deko-Bausteine für den Bauernhof-Look: Bäume, Zäune, Scheune, Silo, Bauernhaus, Traktor,
-- Brunnen, Heu, Felder, Windmühle, Teich ... Benutzt von FarmBuilder (Farmen) und MapBuilder (Wiesen).
--
-- Jeder Baustein bekommt einen Boden-CFrame "cf": Mitte unten, Vorderseite = -Z.
-- Alle Teile werden relativ dazu gebaut, deshalb passt alles auch auf gedrehten Farmen.
-- Kleine Teile sind CanCollide = false (soft), damit sie niemandem den Weg versperren.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Palette"))
local World = Palette.World

local FarmProps = {}

-- neuere Materialien (seit 2023); gibt es eins nicht, nehmen wir ein ähnliches altes
local function newMaterial(name, fallback)
	local ok, value = pcall(function()
		return Enum.Material[name]
	end)
	return ok and value or fallback
end
local PLASTER = newMaterial("Plaster", Enum.Material.SmoothPlastic)
local ROOF_SHINGLES = newMaterial("RoofShingles", Enum.Material.Slate)
local ROOF_TILES = newMaterial("ClayRoofTiles", Enum.Material.Brick)
local RUBBER = newMaterial("Rubber", Enum.Material.SmoothPlastic)

-- Roblox-Zylinder liegen auf der X-Achse -> so stehen sie aufrecht
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))
-- ... und so zeigen sie nach vorne (Achse entlang Z)
local FORWARD = CFrame.Angles(0, math.rad(90), 0)

local Colors = {
	BarnRed = Color3.fromRGB(178, 60, 48),
	BarnRedDark = Color3.fromRGB(138, 44, 36),
	Trim = Color3.fromRGB(246, 242, 232),
	Roof = Color3.fromRGB(84, 78, 76),
	RoofTile = Color3.fromRGB(168, 84, 58),
	Plaster = Color3.fromRGB(244, 234, 212),
	Shutter = Color3.fromRGB(74, 132, 96),
	Glass = Color3.fromRGB(120, 168, 200),
	Metal = Color3.fromRGB(184, 190, 198),
	MetalDark = Color3.fromRGB(112, 118, 128),
	Concrete = Color3.fromRGB(168, 164, 156),
	Dirt = Color3.fromRGB(172, 142, 102),
	DirtDark = Color3.fromRGB(122, 92, 66),
	Meadow = Color3.fromRGB(98, 166, 72),
	MeadowLight = Color3.fromRGB(122, 184, 84),
	MeadowDark = Color3.fromRGB(84, 150, 64),
	Wheat = Color3.fromRGB(228, 192, 100),
	Pumpkin = Color3.fromRGB(234, 130, 42),
	Water = Color3.fromRGB(86, 168, 222),
	Tractor = Color3.fromRGB(66, 142, 74),
	Rim = Color3.fromRGB(246, 204, 64),
	Tire = Color3.fromRGB(42, 42, 46),
	Apple = Color3.fromRGB(216, 54, 50),
	Leaf = World.Leaf,
	LeafDark = Color3.fromRGB(58, 122, 60),
	LeafLight = Color3.fromRGB(104, 170, 82),
	Pine = Color3.fromRGB(46, 104, 70),
	Rock = Color3.fromRGB(140, 140, 136),
	Duck = Color3.fromRGB(250, 248, 240),
	Beak = Color3.fromRGB(244, 166, 52),
	Burlap = Color3.fromRGB(206, 176, 122),
	Plaid = Color3.fromRGB(176, 64, 58),
}
FarmProps.Colors = Colors

------------------------------------------------------------------------
-- Grundbausteine
------------------------------------------------------------------------
local function part(parent, name, size, cframe, color, material, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if extra and extra.Shape then
		p.Shape = extra.Shape -- vor Size setzen (Kugeln passen ihre Größe sonst an)
	end
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if extra then
		for key, value in pairs(extra) do
			if key ~= "Shape" then
				p[key] = value
			end
		end
	end
	p.Parent = parent
	return p
end
FarmProps.Part = part

-- weiches Teil: man läuft hindurch, Klicks/Raycasts gehen durch
local SOFT = { CanCollide = false, CanQuery = false }
local TINY = { CanCollide = false, CanQuery = false, CastShadow = false }

local function merge(a, b)
	local result = table.clone(a or {})
	for key, value in pairs(b or {}) do
		result[key] = value
	end
	return result
end

local function soft(parent, name, size, cframe, color, material, extra)
	return part(parent, name, size, cframe, color, material, merge(SOFT, extra))
end
FarmProps.Soft = soft

-- stehender Zylinder: cframe = Mitte
local function column(parent, name, height, diameter, cframe, color, material, extra)
	return part(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		cframe * UPRIGHT,
		color,
		material,
		merge(extra, { Shape = Enum.PartType.Cylinder })
	)
end
FarmProps.Column = column

local function ball(parent, name, diameter, cframe, color, material, extra)
	return part(
		parent,
		name,
		Vector3.new(diameter, diameter, diameter),
		cframe,
		color,
		material,
		merge(extra, { Shape = Enum.PartType.Ball })
	)
end
FarmProps.Ball = ball

-- Keil im Giebel: Dreieck in der XY-Ebene, hohe Seite bei x = tallX, flache Spitze bei x = lowX.
-- (Roblox-Keil: hoch am +Z-Ende; um 90° gedreht zeigt +Z nach +X bzw. -X)
local function gableWedge(parent, cf, lowX, tallX, bottomY, topY, z, thickness, color, material)
	local wedge = Instance.new("WedgePart")
	wedge.Name = "Gable"
	wedge.Anchored = true
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	local length = math.abs(tallX - lowX)
	wedge.Size = Vector3.new(thickness, topY - bottomY, length)
	local yaw = tallX > lowX and math.rad(90) or math.rad(-90)
	wedge.CFrame = cf * CFrame.new((lowX + tallX) / 2, (bottomY + topY) / 2, z) * CFrame.Angles(0, yaw, 0)
	wedge.Color = color
	wedge.Material = material or Enum.Material.SmoothPlastic
	wedge.Parent = parent
	return wedge
end

-- Brett zwischen zwei Punkten in der XY-Ebene (Dachflächen), depth entlang Z
local function slab(parent, name, cf, fromXY, toXY, z, thickness, depth, color, material, extra)
	local delta = toXY - fromXY
	local mid = (fromXY + toXY) / 2
	local angle = math.atan2(delta.Y, delta.X)
	return part(
		parent,
		name,
		Vector3.new(delta.Magnitude, thickness, depth),
		cf * CFrame.new(mid.X, mid.Y, z) * CFrame.Angles(0, 0, angle),
		color,
		material,
		extra
	)
end

local function newModel(parent, name, cf)
	local model = Instance.new("Model")
	model.Name = name
	model.WorldPivot = cf
	model.Parent = parent
	return model
end

------------------------------------------------------------------------
-- Natur: Bäume, Büsche, Steine, Blumen
------------------------------------------------------------------------

-- Laubbaum mit runder Krone. options: Scale, Fruit (Äpfel), Shade (0..1 Laubfarbe), Rng
function FarmProps.Tree(parent, cf, options)
	options = options or {}
	local s = options.Scale or 1
	local rng = options.Rng or Random.new(7)
	local model = newModel(parent, options.Fruit and "AppleTree" or "Tree", cf)
	part(
		model,
		"Trunk",
		Vector3.new(1.3, 7, 1.3) * s,
		cf * CFrame.new(0, 3.5 * s, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
		World.WoodDark,
		Enum.Material.Wood
	)
	local shade = options.Shade or rng:NextNumber()
	local leaf = Colors.LeafDark:Lerp(Colors.LeafLight, shade)
	local blobs = {
		{ Vector3.new(0, 8.2, 0), 6.4 },
		{ Vector3.new(1.9, 7.1, 0.9), 4.8 },
		{ Vector3.new(-1.7, 7.3, -1.1), 5 },
		{ Vector3.new(0.4, 6.8, -2.1), 4.2 },
	}
	for i, blob in ipairs(blobs) do
		ball(
			model,
			"Leaves",
			blob[2] * s,
			cf * CFrame.new(blob[1] * s),
			i % 2 == 0 and leaf:Lerp(Colors.LeafDark, 0.25) or leaf,
			Enum.Material.Grass,
			SOFT
		)
	end
	if options.Fruit then
		for _ = 1, 6 do
			local angle = rng:NextNumber(0, math.pi * 2)
			local height = rng:NextNumber(6.2, 9.4)
			local radius = 3.1 - math.abs(height - 8) * 0.25
			ball(
				model,
				"Apple",
				0.65 * s,
				cf * CFrame.new(math.cos(angle) * radius * s, height * s, math.sin(angle) * radius * s),
				Colors.Apple,
				Enum.Material.SmoothPlastic,
				TINY
			)
		end
	end
	return model
end

-- Tanne aus drei Stufen (für den Waldrand)
function FarmProps.Pine(parent, cf, scale)
	local s = scale or 1
	local model = newModel(parent, "Pine", cf)
	part(model, "Trunk", Vector3.new(1, 3, 1) * s, cf * CFrame.new(0, 1.5 * s, 0), World.WoodDark, Enum.Material.Wood)
	local tiers = { { 2.4, 7, 2.6 }, { 4.6, 5.4, 2.4 }, { 6.6, 3.6, 2.2 }, { 8.2, 1.8, 1.6 } }
	for _, tier in ipairs(tiers) do
		column(
			model,
			"Needles",
			tier[3] * s,
			tier[2] * s,
			cf * CFrame.new(0, tier[1] * s, 0),
			Colors.Pine,
			Enum.Material.Grass,
			SOFT
		)
	end
	return model
end

function FarmProps.Bush(parent, cf, scale, color)
	local s = scale or 1
	local tone = color or Colors.Leaf
	local model = newModel(parent, "Bush", cf)
	ball(model, "Bush", 3 * s, cf * CFrame.new(0, 1 * s, 0), tone, Enum.Material.Grass, SOFT)
	ball(
		model,
		"Bush",
		2.4 * s,
		cf * CFrame.new(1.4 * s, 0.8 * s, 0.5 * s),
		tone:Lerp(Colors.LeafDark, 0.3),
		Enum.Material.Grass,
		SOFT
	)
	ball(
		model,
		"Bush",
		2.2 * s,
		cf * CFrame.new(-1.2 * s, 0.7 * s, -0.6 * s),
		tone:Lerp(Colors.LeafLight, 0.3),
		Enum.Material.Grass,
		SOFT
	)
	return model
end

function FarmProps.Rock(parent, cf, scale)
	local s = scale or 1
	local model = newModel(parent, "Rock", cf)
	part(
		model,
		"Rock",
		Vector3.new(2.4, 1.4, 1.9) * s,
		cf * CFrame.new(0, 0.5 * s, 0) * CFrame.Angles(0.2, 0.6, 0.15),
		Colors.Rock,
		Enum.Material.Slate
	)
	part(
		model,
		"Rock",
		Vector3.new(1.3, 0.9, 1.2) * s,
		cf * CFrame.new(1.5 * s, 0.3 * s, 0.7 * s) * CFrame.Angles(-0.2, 1.2, 0.1),
		Colors.Rock:Lerp(Color3.new(1, 1, 1), 0.12),
		Enum.Material.Slate,
		SOFT
	)
	return model
end

-- Wildblumen im Gras: count kleine Blüten in einem Kreis (keine Kollision, kein Schatten)
function FarmProps.Wildflowers(parent, cf, radius, count, rng)
	for _ = 1, count do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = radius * math.sqrt(rng:NextNumber())
		ball(
			parent,
			"Wildflower",
			rng:NextNumber(0.4, 0.65),
			cf * CFrame.new(math.cos(angle) * distance, 0.3, math.sin(angle) * distance),
			World.Flowers[rng:NextInteger(1, #World.Flowers)],
			Enum.Material.SmoothPlastic,
			TINY
		)
	end
end

-- Blumenbeet mit Steinrand (sizeX x sizeZ)
function FarmProps.FlowerBed(parent, cf, sizeX, sizeZ, rng)
	local model = newModel(parent, "FlowerBed", cf)
	soft(
		model,
		"BedBorder",
		Vector3.new(sizeX + 0.8, 0.5, sizeZ + 0.8),
		cf * CFrame.new(0, 0.25, 0),
		World.StoneDark,
		Enum.Material.Cobblestone
	)
	soft(model, "BedSoil", Vector3.new(sizeX, 0.6, sizeZ), cf * CFrame.new(0, 0.3, 0), World.Soil, Enum.Material.Ground)
	soft(
		model,
		"BedGreen",
		Vector3.new(sizeX - 0.6, 0.7, sizeZ - 0.6),
		cf * CFrame.new(0, 0.6, 0),
		World.Leaf,
		Enum.Material.Grass
	)
	local count = math.clamp(math.floor(sizeX * sizeZ / 4), 4, 14)
	for _ = 1, count do
		ball(
			model,
			"Flower",
			0.75,
			cf
				* CFrame.new(
					rng:NextNumber(-sizeX / 2 + 0.6, sizeX / 2 - 0.6),
					1.1,
					rng:NextNumber(-sizeZ / 2 + 0.6, sizeZ / 2 - 0.6)
				),
			World.Flowers[rng:NextInteger(1, #World.Flowers)],
			Enum.Material.SmoothPlastic,
			TINY
		)
	end
	return model
end

------------------------------------------------------------------------
-- Wege, Zäune, Laternen, Bänke
------------------------------------------------------------------------

-- flacher Streifen auf dem Boden (Weg). cf = Mitte, Länge entlang Z
function FarmProps.Strip(parent, name, cf, width, length, color, material, height)
	return soft(parent, name, Vector3.new(width, height or 0.08, length), cf, color, material)
end

-- Holzzaun (Pfosten + Latten) von from nach to, beides in den Koordinaten von cf.
-- options: Rails (Anzahl Latten), Spacing (Pfostenabstand), Height, Color, PostColor
function FarmProps.Fence(parent, cf, from, to, options)
	options = options or {}
	local delta = to - from
	local length = delta.Magnitude
	if length < 0.5 then
		return
	end
	local height = options.Height or 3.8
	local rails = options.Rails or 2
	local postColor = options.PostColor or World.WoodDark
	local railColor = options.Color or World.Wood
	local direction = delta.Unit
	local posts = math.max(1, math.floor(length / (options.Spacing or 8) + 0.5))
	for i = 0, posts do
		local position = from + direction * (length * i / posts)
		part(
			parent,
			"FencePost",
			Vector3.new(0.7, height, 0.7),
			cf * CFrame.new(position + Vector3.new(0, height / 2, 0)),
			postColor,
			Enum.Material.Wood
		)
	end
	local middle = from + delta / 2
	local along = CFrame.lookAt(middle, middle + direction)
	for r = 1, rails do
		local y = height * (r / (rails + 1)) + 0.15
		part(
			parent,
			"FenceRail",
			Vector3.new(0.3, 0.45, length),
			cf * (along + Vector3.new(0, y, 0)),
			railColor,
			Enum.Material.Wood
		)
	end
end

-- Laterne am Holzpfosten mit Ausleger (withLight = echte Lichtquelle, sparsam benutzen)
function FarmProps.Lantern(parent, cf, withLight)
	local model = newModel(parent, "Lantern", cf)
	part(
		model,
		"LanternPost",
		Vector3.new(0.5, 7.4, 0.5),
		cf * CFrame.new(0, 3.7, 0),
		World.WoodDark,
		Enum.Material.Wood
	)
	soft(
		model,
		"LanternArm",
		Vector3.new(0.3, 0.3, 1.8),
		cf * CFrame.new(0, 7.1, -0.8),
		World.WoodDark,
		Enum.Material.Wood
	)
	soft(
		model,
		"LanternCap",
		Vector3.new(1.1, 0.25, 1.1),
		cf * CFrame.new(0, 6.65, -1.45),
		Colors.MetalDark,
		Enum.Material.Metal
	)
	local lamp = soft(
		model,
		"LanternLamp",
		Vector3.new(0.8, 1, 0.8),
		cf * CFrame.new(0, 6, -1.45),
		World.Lantern,
		Enum.Material.Neon
	)
	if withLight then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 222, 165)
		light.Brightness = 1
		light.Range = 16
		light.Shadows = false
		light.Parent = lamp
	end
	return model
end

-- Bank aus Holz, Blick nach -Z
function FarmProps.Bench(parent, cf)
	local model = newModel(parent, "Bench", cf)
	part(
		model,
		"BenchSeat",
		Vector3.new(4.4, 0.35, 1.5),
		cf * CFrame.new(0, 1.55, 0),
		World.WoodLight,
		Enum.Material.Wood
	)
	soft(
		model,
		"BenchBack",
		Vector3.new(4.4, 1.1, 0.25),
		cf * CFrame.new(0, 2.45, 0.7) * CFrame.Angles(math.rad(-8), 0, 0),
		World.Wood,
		Enum.Material.Wood
	)
	for _, x in ipairs({ -1.8, 1.8 }) do
		part(
			model,
			"BenchLeg",
			Vector3.new(0.35, 1.5, 1.3),
			cf * CFrame.new(x, 0.75, 0),
			World.WoodDark,
			Enum.Material.Wood
		)
	end
	return model
end

------------------------------------------------------------------------
-- Kleinkram auf dem Hof
------------------------------------------------------------------------

-- eckiger Heuballen mit zwei Schnüren
function FarmProps.HayBale(parent, cf)
	local model = newModel(parent, "HayBale", cf)
	part(model, "HayBale", Vector3.new(3.4, 1.8, 2.4), cf * CFrame.new(0, 0.9, 0), World.Hay, Enum.Material.Fabric)
	for _, x in ipairs({ -0.8, 0.8 }) do
		soft(
			model,
			"Twine",
			Vector3.new(0.12, 1.84, 2.44),
			cf * CFrame.new(x, 0.9, 0),
			Color3.fromRGB(196, 150, 70),
			Enum.Material.Fabric,
			TINY
		)
	end
	return model
end

-- runder Heuballen (liegt, Achse entlang X)
function FarmProps.RoundBale(parent, cf)
	local model = newModel(parent, "RoundBale", cf)
	part(
		model,
		"RoundBale",
		Vector3.new(3, 3.6, 3.6),
		cf * CFrame.new(0, 1.8, 0),
		World.Hay,
		Enum.Material.Fabric,
		{ Shape = Enum.PartType.Cylinder }
	)
	for _, x in ipairs({ -1.52, 1.52 }) do
		soft(
			model,
			"BaleFace",
			Vector3.new(0.06, 2.6, 2.6),
			cf * CFrame.new(x, 1.8, 0),
			Color3.fromRGB(204, 170, 84),
			Enum.Material.Fabric,
			{ Shape = Enum.PartType.Cylinder, CastShadow = false }
		)
	end
	return model
end

function FarmProps.Crate(parent, cf, size)
	local s = size or 1.8
	return part(
		parent,
		"Crate",
		Vector3.new(s, s, s),
		cf * CFrame.new(0, s / 2, 0),
		World.WoodLight,
		Enum.Material.WoodPlanks
	)
end

-- Milchkannen nebeneinander (entlang X)
function FarmProps.MilkCans(parent, cf, count)
	local model = newModel(parent, "MilkCans", cf)
	for i = 1, count or 3 do
		local x = (i - ((count or 3) + 1) / 2) * 1.25
		local height = i % 2 == 0 and 1.7 or 2
		column(model, "MilkCan", height, 1.05, cf * CFrame.new(x, height / 2, 0), Colors.Metal, Enum.Material.Metal)
		column(
			model,
			"CanNeck",
			0.45,
			0.7,
			cf * CFrame.new(x, height + 0.2, 0),
			Colors.Metal,
			Enum.Material.Metal,
			SOFT
		)
		column(
			model,
			"CanLid",
			0.16,
			0.8,
			cf * CFrame.new(x, height + 0.48, 0),
			Palette.Colors.Cream,
			Enum.Material.SmoothPlastic,
			TINY
		)
	end
	return model
end

-- Wassertrog (Länge entlang X)
function FarmProps.Trough(parent, cf, length)
	local l = length or 6
	local model = newModel(parent, "Trough", cf)
	part(model, "Trough", Vector3.new(l, 1.3, 1.9), cf * CFrame.new(0, 0.95, 0), World.Wood, Enum.Material.WoodPlanks)
	soft(
		model,
		"TroughWater",
		Vector3.new(l - 0.5, 0.1, 1.4),
		cf * CFrame.new(0, 1.62, 0),
		Colors.Water,
		Enum.Material.Glass,
		{ Transparency = 0.2 }
	)
	for _, x in ipairs({ -l / 2 + 0.6, l / 2 - 0.6 }) do
		part(
			model,
			"TroughLeg",
			Vector3.new(0.5, 0.4, 2.2),
			cf * CFrame.new(x, 0.2, 0),
			World.WoodDark,
			Enum.Material.Wood
		)
	end
	return model
end

-- Heuraufe: Holzgestell mit schrägen Latten, Heu darin, kleines Dach (Länge entlang X)
function FarmProps.HayRack(parent, cf, length)
	local l = length or 6
	local model = newModel(parent, "HayRack", cf)
	for _, x in ipairs({ -l / 2, l / 2 }) do
		for _, z in ipairs({ -0.9, 0.9 }) do
			part(
				model,
				"RackPost",
				Vector3.new(0.4, 4.2, 0.4),
				cf * CFrame.new(x, 2.1, z),
				World.WoodDark,
				Enum.Material.Wood
			)
		end
	end
	part(model, "RackBox", Vector3.new(l, 0.9, 1.8), cf * CFrame.new(0, 1.1, 0), World.Wood, Enum.Material.WoodPlanks)
	soft(model, "RackHay", Vector3.new(l - 0.3, 1.4, 1.5), cf * CFrame.new(0, 2.1, 0), World.Hay, Enum.Material.Fabric)
	soft(
		model,
		"RackSlats",
		Vector3.new(l, 1.6, 0.2),
		cf * CFrame.new(0, 2.6, -0.95) * CFrame.Angles(math.rad(12), 0, 0),
		World.WoodLight,
		Enum.Material.WoodPlanks,
		{ Transparency = 0.15 }
	)
	part(
		model,
		"RackRoof",
		Vector3.new(l + 0.8, 0.3, 2.8),
		cf * CFrame.new(0, 4.35, 0) * CFrame.Angles(math.rad(-10), 0, 0),
		Colors.BarnRed,
		Enum.Material.WoodPlanks
	)
	return model
end

function FarmProps.Wheelbarrow(parent, cf)
	local model = newModel(parent, "Wheelbarrow", cf)
	part(
		model,
		"Tray",
		Vector3.new(1.8, 0.9, 2.6),
		cf * CFrame.new(0, 1.4, 0) * CFrame.Angles(math.rad(-6), 0, 0),
		Color3.fromRGB(76, 132, 178),
		Enum.Material.Metal
	)
	soft(model, "Load", Vector3.new(1.5, 0.4, 2.2), cf * CFrame.new(0, 1.85, 0), World.Soil, Enum.Material.Ground)
	part(
		model,
		"Wheel",
		Vector3.new(0.35, 1.2, 1.2),
		cf * CFrame.new(0, 0.6, -1.7),
		Colors.Tire,
		RUBBER,
		{ Shape = Enum.PartType.Cylinder }
	)
	for _, x in ipairs({ -0.75, 0.75 }) do
		soft(
			model,
			"Handle",
			Vector3.new(0.2, 0.2, 3.4),
			cf * CFrame.new(x, 1.2, 0.5) * CFrame.Angles(math.rad(10), 0, 0),
			World.WoodLight,
			Enum.Material.Wood
		)
		soft(
			model,
			"Leg",
			Vector3.new(0.2, 0.9, 0.2),
			cf * CFrame.new(x, 0.45, 0.9),
			World.WoodDark,
			Enum.Material.Wood
		)
	end
	return model
end

function FarmProps.Mailbox(parent, cf)
	local model = newModel(parent, "Mailbox", cf)
	part(model, "MailPost", Vector3.new(0.4, 3.4, 0.4), cf * CFrame.new(0, 1.7, 0), World.WoodDark, Enum.Material.Wood)
	part(
		model,
		"MailBox",
		Vector3.new(1.2, 1.1, 1.9),
		cf * CFrame.new(0, 3.9, 0),
		Color3.fromRGB(70, 120, 200),
		Enum.Material.Metal
	)
	soft(
		model,
		"MailRoof",
		Vector3.new(1.3, 1.9, 1.3),
		cf * CFrame.new(0, 4.45, 0) * FORWARD,
		Color3.fromRGB(70, 120, 200),
		Enum.Material.Metal,
		{ Shape = Enum.PartType.Cylinder }
	)
	soft(
		model,
		"MailFlag",
		Vector3.new(0.12, 0.9, 0.5),
		cf * CFrame.new(0.68, 4.4, 0.3),
		Palette.Colors.Red or Colors.Apple,
		Enum.Material.SmoothPlastic,
		TINY
	)
	return model
end

-- Traktor (Front = -Z)
function FarmProps.Tractor(parent, cf, color)
	local body = color or Colors.Tractor
	local model = newModel(parent, "Tractor", cf)
	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	part(model, "Hood", Vector3.new(2.6, 1.9, 4.6), at(0, 2.45, -1.7), body, Enum.Material.Metal)
	part(
		model,
		"Chassis",
		Vector3.new(2.2, 1.3, 4.2),
		at(0, 2.1, 1.4),
		body:Lerp(Color3.new(0, 0, 0), 0.25),
		Enum.Material.Metal
	)
	soft(model, "Grill", Vector3.new(2.2, 1.4, 0.2), at(0, 2.35, -4.05), Colors.MetalDark, Enum.Material.DiamondPlate)
	for _, x in ipairs({ -0.8, 0.8 }) do
		ball(model, "Headlight", 0.55, at(x, 2.75, -4.1), World.Lantern, Enum.Material.Neon, TINY)
	end
	for _, x in ipairs({ -1.95, 1.95 }) do
		soft(model, "Fender", Vector3.new(1.5, 0.35, 3.6), at(x, 4.35, 1.5), body, Enum.Material.Metal)
	end
	for _, x in ipairs({ -1.3, 1.3 }) do
		for _, z in ipairs({ 0.2, 2.8 }) do
			soft(model, "CabPost", Vector3.new(0.22, 3.5, 0.22), at(x, 5.95, z), Colors.MetalDark, Enum.Material.Metal)
		end
	end
	part(
		model,
		"CabRoof",
		Vector3.new(3.2, 0.3, 3.4),
		at(0, 7.8, 1.5),
		Palette.Colors.Cream,
		Enum.Material.SmoothPlastic
	)
	soft(model, "Seat", Vector3.new(1.4, 0.4, 1.2), at(0, 3.3, 2), Colors.Tire, Enum.Material.Fabric)
	soft(model, "SeatBack", Vector3.new(1.4, 1.2, 0.3), at(0, 4, 2.6), Colors.Tire, Enum.Material.Fabric)
	soft(
		model,
		"Steering",
		Vector3.new(0.15, 1.2, 1.2),
		at(0, 4.3, 0.6) * CFrame.Angles(math.rad(-35), 0, 0) * UPRIGHT,
		Colors.Tire,
		RUBBER,
		{ Shape = Enum.PartType.Cylinder }
	)
	column(model, "Exhaust", 2.6, 0.35, at(0.85, 4.6, -2.7), Colors.MetalDark, Enum.Material.Metal, SOFT)
	for _, x in ipairs({ -2.3, 2.3 }) do
		part(
			model,
			"RearWheel",
			Vector3.new(1.4, 4.2, 4.2),
			at(x, 2.1, 1.5),
			Colors.Tire,
			RUBBER,
			{ Shape = Enum.PartType.Cylinder }
		)
		soft(
			model,
			"RearRim",
			Vector3.new(1.5, 2.2, 2.2),
			at(x, 2.1, 1.5),
			Colors.Rim,
			Enum.Material.Metal,
			{ Shape = Enum.PartType.Cylinder }
		)
	end
	for _, x in ipairs({ -1.6, 1.6 }) do
		part(
			model,
			"FrontWheel",
			Vector3.new(1, 2.6, 2.6),
			at(x, 1.3, -2.8),
			Colors.Tire,
			RUBBER,
			{ Shape = Enum.PartType.Cylinder }
		)
		soft(
			model,
			"FrontRim",
			Vector3.new(1.1, 1.3, 1.3),
			at(x, 1.3, -2.8),
			Colors.Rim,
			Enum.Material.Metal,
			{ Shape = Enum.PartType.Cylinder }
		)
	end
	return model
end

-- Ziehbrunnen aus Stein mit Dach und Eimer
function FarmProps.Well(parent, cf)
	local model = newModel(parent, "Well", cf)
	column(model, "WellWall", 2.4, 5, cf * CFrame.new(0, 1.2, 0), World.StoneDark, Enum.Material.Cobblestone)
	column(
		model,
		"WellWater",
		0.08,
		3.9,
		cf * CFrame.new(0, 2.43, 0),
		Color3.fromRGB(40, 70, 96),
		Enum.Material.Glass,
		TINY
	)
	for _, x in ipairs({ -2.2, 2.2 }) do
		part(
			model,
			"WellPost",
			Vector3.new(0.4, 4.6, 0.4),
			cf * CFrame.new(x, 4.7, 0),
			World.WoodDark,
			Enum.Material.Wood
		)
	end
	for _, side in ipairs({ -1, 1 }) do
		soft(
			model,
			"WellRoof",
			Vector3.new(5.6, 0.3, 2.4),
			cf * CFrame.new(0, 7.45, side * 0.9) * CFrame.Angles(side * math.rad(35), 0, 0),
			Colors.RoofTile,
			ROOF_TILES
		)
	end
	soft(
		model,
		"WellAxle",
		Vector3.new(4.4, 0.3, 0.3),
		cf * CFrame.new(0, 5.7, 0),
		World.WoodLight,
		Enum.Material.Wood,
		{ Shape = Enum.PartType.Cylinder }
	)
	soft(
		model,
		"WellRope",
		Vector3.new(0.08, 1.2, 0.08),
		cf * CFrame.new(0, 5, 0),
		Color3.fromRGB(196, 168, 120),
		Enum.Material.Fabric,
		TINY
	)
	column(model, "WellBucket", 0.8, 0.8, cf * CFrame.new(0, 4.2, 0), World.Wood, Enum.Material.Wood, SOFT)
	return model
end

-- Holzkarren mit Heu (Deichsel nach -Z)
function FarmProps.Cart(parent, cf)
	local model = newModel(parent, "Cart", cf)
	part(model, "CartBed", Vector3.new(3.4, 0.4, 5), cf * CFrame.new(0, 1.9, 0), World.Wood, Enum.Material.WoodPlanks)
	for _, x in ipairs({ -1.6, 1.6 }) do
		part(
			model,
			"CartSide",
			Vector3.new(0.3, 1, 5),
			cf * CFrame.new(x, 2.6, 0),
			World.WoodLight,
			Enum.Material.WoodPlanks
		)
		part(
			model,
			"CartWheel",
			Vector3.new(0.35, 3.2, 3.2),
			cf * CFrame.new(x * 1.22, 1.6, 0.6),
			World.WoodDark,
			Enum.Material.Wood,
			{ Shape = Enum.PartType.Cylinder }
		)
		soft(
			model,
			"CartShaft",
			Vector3.new(0.25, 0.25, 4),
			cf * CFrame.new(x * 0.5, 1.3, -4.3) * CFrame.Angles(math.rad(-8), 0, 0),
			World.WoodLight,
			Enum.Material.Wood
		)
	end
	for _, z in ipairs({ -2.45, 2.45 }) do
		part(
			model,
			"CartBoard",
			Vector3.new(3.4, 1, 0.3),
			cf * CFrame.new(0, 2.6, z),
			World.WoodLight,
			Enum.Material.WoodPlanks
		)
	end
	soft(model, "CartHay", Vector3.new(3, 1.4, 4.6), cf * CFrame.new(0, 3.1, 0), World.Hay, Enum.Material.Fabric)
	ball(model, "CartHayTop", 2.6, cf * CFrame.new(0.2, 3.6, 0.4), World.Hay, Enum.Material.Fabric, SOFT)
	return model
end

-- Vogelscheuche (schaut nach -Z)
function FarmProps.Scarecrow(parent, cf)
	local model = newModel(parent, "Scarecrow", cf)
	part(model, "Pole", Vector3.new(0.4, 7, 0.4), cf * CFrame.new(0, 3.5, 0), World.WoodDark, Enum.Material.Wood)
	soft(model, "Arms", Vector3.new(4.6, 0.8, 0.8), cf * CFrame.new(0, 5, 0), Colors.Plaid, Enum.Material.Fabric)
	soft(model, "Shirt", Vector3.new(2.1, 2.3, 1), cf * CFrame.new(0, 4.5, 0), Colors.Plaid, Enum.Material.Fabric)
	soft(
		model,
		"Pants",
		Vector3.new(1.9, 1.3, 0.9),
		cf * CFrame.new(0, 2.8, 0),
		Color3.fromRGB(70, 96, 150),
		Enum.Material.Fabric
	)
	for _, x in ipairs({ -2.5, 2.5 }) do
		soft(
			model,
			"StrawHand",
			Vector3.new(0.6, 0.6, 0.6),
			cf * CFrame.new(x, 5, 0),
			World.Hay,
			Enum.Material.Fabric,
			TINY
		)
	end
	ball(model, "Head", 1.7, cf * CFrame.new(0, 6.5, 0), Colors.Burlap, Enum.Material.Fabric, SOFT)
	column(
		model,
		"HatBrim",
		0.15,
		2.8,
		cf * CFrame.new(0, 7.25, 0),
		Color3.fromRGB(150, 110, 60),
		Enum.Material.Fabric,
		TINY
	)
	column(
		model,
		"HatTop",
		1.1,
		1.5,
		cf * CFrame.new(0, 7.8, 0),
		Color3.fromRGB(150, 110, 60),
		Enum.Material.Fabric,
		TINY
	)
	return model
end

-- Bienenstock auf Holzbock
function FarmProps.Beehive(parent, cf)
	local model = newModel(parent, "Beehive", cf)
	part(model, "HiveStand", Vector3.new(2, 0.8, 2), cf * CFrame.new(0, 0.4, 0), World.WoodDark, Enum.Material.Wood)
	part(
		model,
		"HiveBox",
		Vector3.new(1.8, 1.1, 1.8),
		cf * CFrame.new(0, 1.35, 0),
		Color3.fromRGB(250, 236, 190),
		Enum.Material.WoodPlanks
	)
	part(
		model,
		"HiveBox",
		Vector3.new(1.8, 1.1, 1.8),
		cf * CFrame.new(0, 2.47, 0),
		Color3.fromRGB(244, 206, 96),
		Enum.Material.WoodPlanks
	)
	part(
		model,
		"HiveRoof",
		Vector3.new(2.2, 0.3, 2.2),
		cf * CFrame.new(0, 3.17, 0),
		World.WoodLight,
		Enum.Material.WoodPlanks
	)
	soft(
		model,
		"HiveHole",
		Vector3.new(0.6, 0.2, 0.06),
		cf * CFrame.new(0, 1.0, -0.92),
		Color3.fromRGB(40, 32, 26),
		Enum.Material.SmoothPlastic,
		TINY
	)
	return model
end

-- Huhn (Blick nach -Z)
function FarmProps.Chicken(parent, cf)
	local model = newModel(parent, "Chicken", cf)
	ball(model, "Body", 1.2, cf * CFrame.new(0, 0.85, 0), Colors.Duck, Enum.Material.SmoothPlastic, SOFT)
	ball(model, "Head", 0.7, cf * CFrame.new(0, 1.55, -0.45), Colors.Duck, Enum.Material.SmoothPlastic, TINY)
	soft(
		model,
		"Comb",
		Vector3.new(0.18, 0.32, 0.42),
		cf * CFrame.new(0, 1.95, -0.45),
		Color3.fromRGB(220, 50, 50),
		Enum.Material.SmoothPlastic,
		TINY
	)
	soft(
		model,
		"Beak",
		Vector3.new(0.22, 0.18, 0.3),
		cf * CFrame.new(0, 1.5, -0.86),
		Colors.Beak,
		Enum.Material.SmoothPlastic,
		TINY
	)
	soft(
		model,
		"Legs",
		Vector3.new(0.4, 0.4, 0.12),
		cf * CFrame.new(0, 0.2, 0),
		Colors.Beak,
		Enum.Material.SmoothPlastic,
		TINY
	)
	return model
end

-- Hühnerstall auf Stelzen mit Rampe (Tür nach -Z)
function FarmProps.ChickenCoop(parent, cf)
	local model = newModel(parent, "ChickenCoop", cf)
	for _, x in ipairs({ -2, 2 }) do
		for _, z in ipairs({ -1.6, 1.6 }) do
			part(
				model,
				"CoopLeg",
				Vector3.new(0.4, 1.3, 0.4),
				cf * CFrame.new(x, 0.65, z),
				World.WoodDark,
				Enum.Material.Wood
			)
		end
	end
	part(
		model,
		"CoopHouse",
		Vector3.new(4.6, 3, 3.8),
		cf * CFrame.new(0, 2.8, 0),
		World.WoodLight,
		Enum.Material.WoodPlanks
	)
	-- Satteldach, First entlang Z (Giebel vorne und hinten)
	for _, side in ipairs({ -1, 1 }) do
		slab(
			model,
			"CoopRoof",
			cf,
			Vector2.new(side * 2.7, 4.05),
			Vector2.new(0, 5.5),
			0,
			0.3,
			4.4,
			Colors.BarnRed,
			Enum.Material.WoodPlanks
		)
		for _, z in ipairs({ -1.75, 1.75 }) do
			gableWedge(model, cf, side * 2.3, 0, 4.3, 5.35, z, 0.3, World.WoodLight, Enum.Material.WoodPlanks)
		end
	end
	soft(
		model,
		"CoopDoor",
		Vector3.new(1, 1.3, 0.1),
		cf * CFrame.new(-0.8, 2.15, -1.92),
		Color3.fromRGB(46, 34, 26),
		Enum.Material.SmoothPlastic,
		TINY
	)
	soft(
		model,
		"CoopWindow",
		Vector3.new(0.9, 0.7, 0.1),
		cf * CFrame.new(1.1, 3.2, -1.92),
		Colors.Trim,
		Enum.Material.SmoothPlastic,
		TINY
	)
	soft(
		model,
		"CoopRamp",
		Vector3.new(1, 0.15, 2.6),
		cf * CFrame.new(-0.8, 0.8, -2.9) * CFrame.Angles(math.rad(-27), 0, 0),
		World.Wood,
		Enum.Material.WoodPlanks
	)
	return model
end

------------------------------------------------------------------------
-- Gebäude
------------------------------------------------------------------------

-- Fenster auf einer Wand: weißer Rahmen, Glas, Fensterkreuz. cf zeigt mit -Z nach außen.
local function windowOn(parent, cf, width, height, options)
	options = options or {}
	soft(
		parent,
		"WindowFrame",
		Vector3.new(width + 0.5, height + 0.5, 0.2),
		cf,
		options.Frame or Colors.Trim,
		Enum.Material.SmoothPlastic
	)
	soft(
		parent,
		"WindowGlass",
		Vector3.new(width, height, 0.24),
		cf,
		Colors.Glass,
		Enum.Material.Glass,
		{ Transparency = 0.1, Reflectance = 0.15 }
	)
	soft(
		parent,
		"WindowBar",
		Vector3.new(0.18, height, 0.28),
		cf,
		options.Frame or Colors.Trim,
		Enum.Material.SmoothPlastic,
		TINY
	)
	soft(
		parent,
		"WindowBar",
		Vector3.new(width, 0.18, 0.28),
		cf,
		options.Frame or Colors.Trim,
		Enum.Material.SmoothPlastic,
		TINY
	)
	if options.Shutters then
		for _, side in ipairs({ -1, 1 }) do
			soft(
				parent,
				"Shutter",
				Vector3.new(width / 2, height + 0.4, 0.15),
				cf * CFrame.new(side * (width * 0.75 + 0.35), 0, -0.05),
				options.Shutters,
				Enum.Material.WoodPlanks
			)
		end
	end
	if options.FlowerBox then
		soft(
			parent,
			"FlowerBox",
			Vector3.new(width + 0.6, 0.5, 0.6),
			cf * CFrame.new(0, -height / 2 - 0.45, -0.3),
			World.Wood,
			Enum.Material.WoodPlanks
		)
		for i = -1, 1 do
			ball(
				parent,
				"BoxFlower",
				0.55,
				cf * CFrame.new(i * width * 0.3, -height / 2 - 0.05, -0.3),
				World.Flowers[(i + 2) % #World.Flowers + 1],
				Enum.Material.SmoothPlastic,
				TINY
			)
		end
	end
end

-- Rote Scheune mit Mansarddach (Gambrel), weißen Kanten und großem Tor vorne (-Z).
-- Grundfläche 16 (X) x 24 (Z), First bei ~16 Studs.
function FarmProps.Barn(parent, cf)
	local model = newModel(parent, "Barn", cf)
	local W, D, H = 16, 24, 9
	local base = 0.6
	local eave = base + H
	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end

	part(
		model,
		"Foundation",
		Vector3.new(W + 0.8, base, D + 0.8),
		at(0, base / 2, 0),
		Colors.Concrete,
		Enum.Material.Concrete
	)
	-- Wände (vorne mit Toröffnung 7 x 7.5)
	local doorW, doorH = 7, 7.5
	part(
		model,
		"WallBack",
		Vector3.new(W, H, 0.8),
		at(0, base + H / 2, D / 2 - 0.4),
		Colors.BarnRed,
		Enum.Material.WoodPlanks
	)
	for _, side in ipairs({ -1, 1 }) do
		part(
			model,
			"WallSide",
			Vector3.new(0.8, H, D),
			at(side * (W / 2 - 0.4), base + H / 2, 0),
			Colors.BarnRed,
			Enum.Material.WoodPlanks
		)
		local pieceW = (W - doorW) / 2
		part(
			model,
			"WallFront",
			Vector3.new(pieceW, H, 0.8),
			at(side * (doorW / 2 + pieceW / 2), base + H / 2, -D / 2 + 0.4),
			Colors.BarnRed,
			Enum.Material.WoodPlanks
		)
	end
	part(
		model,
		"WallFront",
		Vector3.new(doorW, H - doorH, 0.8),
		at(0, base + doorH + (H - doorH) / 2, -D / 2 + 0.4),
		Colors.BarnRed,
		Enum.Material.WoodPlanks
	)

	-- Tor: weißer Rahmen hinter zwei dunkelroten Flügeln mit weißem X
	local doorZ = -D / 2 + 0.55
	soft(
		model,
		"DoorFrame",
		Vector3.new(doorW + 0.4, doorH + 0.2, 0.3),
		at(0, base + doorH / 2, doorZ + 0.1),
		Colors.Trim,
		Enum.Material.WoodPlanks
	)
	local leafW, leafH = doorW / 2 - 0.35, doorH - 0.5
	local diagonal = math.sqrt(leafW * leafW + leafH * leafH)
	local tilt = math.atan2(leafW, leafH)
	for _, side in ipairs({ -1, 1 }) do
		local center = at(side * doorW / 4, base + doorH / 2 - 0.05, doorZ - 0.1)
		part(model, "DoorLeaf", Vector3.new(leafW, leafH, 0.3), center, Colors.BarnRedDark, Enum.Material.WoodPlanks)
		for _, sign in ipairs({ -1, 1 }) do
			soft(
				model,
				"DoorBrace",
				Vector3.new(0.35, diagonal - 0.4, 0.12),
				center * CFrame.new(0, 0, -0.2) * CFrame.Angles(0, 0, sign * tilt),
				Colors.Trim,
				Enum.Material.WoodPlanks,
				TINY
			)
		end
	end

	-- Ecken weiß abgesetzt
	for _, x in ipairs({ -W / 2, W / 2 }) do
		for _, z in ipairs({ -D / 2, D / 2 }) do
			soft(
				model,
				"CornerTrim",
				Vector3.new(0.9, H, 0.9),
				at(x, base + H / 2, z),
				Colors.Trim,
				Enum.Material.WoodPlanks
			)
		end
	end

	-- Mansarddach: steil unten, flach oben (Profil in X-Richtung, First entlang Z)
	local knee = Vector2.new(5.2, eave + 4)
	local ridge = Vector2.new(0, eave + 6.3)
	for _, side in ipairs({ -1, 1 }) do
		slab(
			model,
			"RoofLower",
			cf,
			Vector2.new(side * (W / 2 + 0.7), eave - 0.6),
			Vector2.new(side * knee.X, knee.Y),
			0,
			0.6,
			D + 2,
			Colors.Roof,
			ROOF_SHINGLES
		)
		slab(
			model,
			"RoofUpper",
			cf,
			Vector2.new(side * knee.X, knee.Y),
			ridge,
			0,
			0.6,
			D + 2,
			Colors.Roof,
			ROOF_SHINGLES
		)
	end
	part(
		model,
		"RoofRidge",
		Vector3.new(0.9, 0.5, D + 2.2),
		at(0, ridge.Y + 0.15, 0),
		Colors.Roof:Lerp(Color3.new(0, 0, 0), 0.2),
		ROOF_SHINGLES
	)

	-- Giebel vorne und hinten (Rechteck + Keile)
	for _, z in ipairs({ -D / 2 + 0.4, D / 2 - 0.4 }) do
		part(
			model,
			"GableWall",
			Vector3.new(knee.X * 2, knee.Y - eave, 0.8),
			at(0, (eave + knee.Y) / 2, z),
			Colors.BarnRed,
			Enum.Material.WoodPlanks
		)
		for _, side in ipairs({ -1, 1 }) do
			gableWedge(
				model,
				cf,
				side * W / 2,
				side * knee.X,
				eave,
				knee.Y,
				z,
				0.8,
				Colors.BarnRed,
				Enum.Material.WoodPlanks
			)
			gableWedge(model, cf, side * knee.X, 0, knee.Y, ridge.Y, z, 0.8, Colors.BarnRed, Enum.Material.WoodPlanks)
		end
	end

	-- Heuboden-Luke vorne, Heu schaut heraus
	soft(
		model,
		"LoftFrame",
		Vector3.new(3.4, 3.2, 0.3),
		at(0, eave + 2.4, -D / 2 - 0.05),
		Colors.Trim,
		Enum.Material.WoodPlanks
	)
	soft(
		model,
		"LoftDoor",
		Vector3.new(2.8, 2.6, 0.35),
		at(0, eave + 2.4, -D / 2 - 0.08),
		Color3.fromRGB(60, 40, 30),
		Enum.Material.WoodPlanks
	)
	soft(model, "LoftHay", Vector3.new(2.4, 1, 1), at(0, eave + 1.45, -D / 2 - 0.35), World.Hay, Enum.Material.Fabric)

	-- Fenster an den Seiten, Lampe über dem Tor
	for _, side in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -5, 5 }) do
			windowOn(
				model,
				cf * CFrame.new(side * (W / 2 + 0.05), base + 5.4, z) * CFrame.Angles(0, side * math.rad(-90), 0),
				2,
				2
			)
		end
	end
	soft(
		model,
		"DoorLampArm",
		Vector3.new(0.25, 0.25, 1),
		at(0, base + doorH + 0.9, -D / 2 - 0.4),
		Colors.MetalDark,
		Enum.Material.Metal
	)
	ball(model, "DoorLamp", 0.8, at(0, base + doorH + 0.6, -D / 2 - 0.9), World.Lantern, Enum.Material.Neon, TINY)
	return model
end

-- Silo: Metallzylinder mit Kuppel, Ringen und Leiter (Leiter vorne, -Z)
function FarmProps.Silo(parent, cf, height, diameter)
	local h, d = height or 18, diameter or 7
	local model = newModel(parent, "Silo", cf)
	column(model, "SiloBase", 0.8, d + 0.8, cf * CFrame.new(0, 0.4, 0), Colors.Concrete, Enum.Material.Concrete)
	column(model, "SiloBody", h, d, cf * CFrame.new(0, 0.8 + h / 2, 0), Colors.Metal, Enum.Material.Metal)
	for i = 1, 4 do
		column(
			model,
			"SiloBand",
			0.3,
			d + 0.15,
			cf * CFrame.new(0, 0.8 + h * i / 5, 0),
			Colors.MetalDark,
			Enum.Material.Metal,
			TINY
		)
	end
	ball(model, "SiloDome", d, cf * CFrame.new(0, 0.8 + h, 0), Color3.fromRGB(150, 172, 196), Enum.Material.Metal)
	column(
		model,
		"SiloVent",
		0.8,
		1.1,
		cf * CFrame.new(0, 0.8 + h + d / 2, 0),
		Colors.MetalDark,
		Enum.Material.Metal,
		TINY
	)
	local ladderZ = -(d / 2 + 0.3)
	for _, x in ipairs({ -0.55, 0.55 }) do
		soft(
			model,
			"LadderRail",
			Vector3.new(0.15, h - 1, 0.15),
			cf * CFrame.new(x, 1.3 + (h - 1) / 2, ladderZ),
			Colors.MetalDark,
			Enum.Material.Metal,
			TINY
		)
	end
	for y = 2, h, 2 do
		soft(
			model,
			"LadderRung",
			Vector3.new(1.1, 0.12, 0.12),
			cf * CFrame.new(0, y, ladderZ),
			Colors.MetalDark,
			Enum.Material.Metal,
			TINY
		)
	end
	return model
end

-- Bauernhaus: weiß verputzt, Holzbalken an den Ecken, Ziegeldach (First entlang X), Kamin.
-- Tür vorne (-Z) etwas links, Grundfläche 14 (X) x 12 (Z).
function FarmProps.Farmhouse(parent, cf)
	local model = newModel(parent, "Farmhouse", cf)
	local W, D, H = 14, 12, 7
	local base = 0.8
	local eave = base + H
	local ridgeY = eave + 4.6
	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end

	part(
		model,
		"Foundation",
		Vector3.new(W + 0.6, base, D + 0.6),
		at(0, base / 2, 0),
		World.StoneDark,
		Enum.Material.Cobblestone
	)
	-- Vorderwand mit Türöffnung (2.6 x 5) bei x = -3
	local doorX, doorW, doorH = -3, 2.6, 5
	local leftW = (doorX - doorW / 2) + W / 2
	local rightW = W / 2 - (doorX + doorW / 2)
	part(
		model,
		"WallFront",
		Vector3.new(leftW, H, 0.6),
		at(-W / 2 + leftW / 2, base + H / 2, -D / 2 + 0.3),
		Colors.Plaster,
		PLASTER
	)
	part(
		model,
		"WallFront",
		Vector3.new(rightW, H, 0.6),
		at(W / 2 - rightW / 2, base + H / 2, -D / 2 + 0.3),
		Colors.Plaster,
		PLASTER
	)
	part(
		model,
		"WallFront",
		Vector3.new(doorW, H - doorH, 0.6),
		at(doorX, base + doorH + (H - doorH) / 2, -D / 2 + 0.3),
		Colors.Plaster,
		PLASTER
	)
	part(
		model,
		"Door",
		Vector3.new(doorW, doorH, 0.3),
		at(doorX, base + doorH / 2, -D / 2 + 0.45),
		Color3.fromRGB(110, 70, 44),
		Enum.Material.WoodPlanks
	)
	ball(
		model,
		"DoorKnob",
		0.3,
		at(doorX + 0.85, base + 2.5, -D / 2 + 0.25),
		Palette.Colors.Gold,
		Enum.Material.Metal,
		TINY
	)
	soft(
		model,
		"DoorStep",
		Vector3.new(doorW + 1, 0.4, 1.2),
		at(doorX, base - 0.2 + 0.2, -D / 2 - 0.5),
		World.StoneDark,
		Enum.Material.Cobblestone
	)
	soft(
		model,
		"DoorRoof",
		Vector3.new(doorW + 1.6, 0.25, 1.6),
		at(doorX, base + doorH + 0.9, -D / 2 - 0.6) * CFrame.Angles(math.rad(14), 0, 0),
		Colors.RoofTile,
		ROOF_TILES
	)
	part(model, "WallBack", Vector3.new(W, H, 0.6), at(0, base + H / 2, D / 2 - 0.3), Colors.Plaster, PLASTER)
	for _, side in ipairs({ -1, 1 }) do
		part(
			model,
			"WallSide",
			Vector3.new(0.6, H, D),
			at(side * (W / 2 - 0.3), base + H / 2, 0),
			Colors.Plaster,
			PLASTER
		)
		-- Giebeldreieck über der Seitenwand (in der YZ-Ebene): zwei Keile
		for _, half in ipairs({ -1, 1 }) do
			local wedge = Instance.new("WedgePart")
			wedge.Name = "Gable"
			wedge.Anchored = true
			wedge.Size = Vector3.new(0.6, ridgeY - eave, D / 2)
			-- Keil ist hoch am +Z-Ende: vordere Hälfte (half = -1) so lassen, hintere drehen
			wedge.CFrame = at(side * (W / 2 - 0.3), (eave + ridgeY) / 2, half * D / 4)
				* CFrame.Angles(0, half == 1 and math.pi or 0, 0)
			wedge.Color = Colors.Plaster
			wedge.Material = PLASTER
			wedge.Parent = model
		end
		windowOn(
			model,
			at(side * (W / 2 + 0.05), base + 4, 0) * CFrame.Angles(0, side * math.rad(-90), 0),
			1.8,
			2.2,
			{ Frame = Colors.Trim }
		)
	end
	-- Holzbalken an den Ecken
	for _, x in ipairs({ -W / 2, W / 2 }) do
		for _, z in ipairs({ -D / 2, D / 2 }) do
			soft(model, "Beam", Vector3.new(0.7, H, 0.7), at(x, base + H / 2, z), World.WoodDark, Enum.Material.Wood)
		end
	end
	soft(model, "Beam", Vector3.new(W + 0.4, 0.5, 0.7), at(0, eave - 0.2, -D / 2), World.WoodDark, Enum.Material.Wood)
	soft(model, "Beam", Vector3.new(W + 0.4, 0.5, 0.7), at(0, eave - 0.2, D / 2), World.WoodDark, Enum.Material.Wood)

	-- Fenster vorne und hinten (mit Läden und Blumenkasten)
	windowOn(model, at(3.4, base + 4, -D / 2 - 0.05), 2, 2.2, { Shutters = Colors.Shutter, FlowerBox = true })
	windowOn(
		model,
		at(-3.4, base + 4, D / 2 + 0.05) * CFrame.Angles(0, math.pi, 0),
		2,
		2.2,
		{ Shutters = Colors.Shutter }
	)

	-- Ziegeldach (zwei Flächen, First entlang X)
	local slope = math.atan2(ridgeY - eave + 0.4, D / 2 + 0.8)
	local roofLength = math.sqrt((D / 2 + 0.8) ^ 2 + (ridgeY - eave + 0.4) ^ 2) + 0.3
	for _, side in ipairs({ -1, 1 }) do
		part(
			model,
			"Roof",
			Vector3.new(W + 1.6, 0.6, roofLength),
			at(0, (eave - 0.4 + ridgeY) / 2 + 0.2, side * (D / 2 + 0.8) / 2) * CFrame.Angles(side * slope, 0, 0),
			Colors.RoofTile,
			ROOF_TILES
		)
	end
	-- Kamin
	part(
		model,
		"Chimney",
		Vector3.new(1.6, 4.4, 1.6),
		at(4, ridgeY - 0.2, 2),
		Color3.fromRGB(150, 82, 64),
		Enum.Material.Brick
	)
	soft(model, "ChimneyCap", Vector3.new(2, 0.35, 2), at(4, ridgeY + 2.15, 2), World.StoneDark, Enum.Material.Concrete)
	return model
end

------------------------------------------------------------------------
-- Felder und Gärten (Reihen laufen entlang Z)
------------------------------------------------------------------------

local function fieldSoil(model, cf, sizeX, sizeZ)
	soft(
		model,
		"FieldSoil",
		Vector3.new(sizeX, 0.3, sizeZ),
		cf * CFrame.new(0, 0.15, 0),
		Colors.DirtDark,
		Enum.Material.Ground
	)
end

-- Weizenfeld: goldene Reihen
function FarmProps.WheatField(parent, cf, sizeX, sizeZ)
	local model = newModel(parent, "WheatField", cf)
	fieldSoil(model, cf, sizeX, sizeZ)
	local rows = math.floor(sizeX / 2.2)
	for i = 1, rows do
		local x = (i - (rows + 1) / 2) * 2.2
		soft(
			model,
			"Wheat",
			Vector3.new(1.5, 2.2, sizeZ - 1.2),
			cf * CFrame.new(x, 1.25, 0),
			Colors.Wheat:Lerp(World.Hay, (i % 3) / 4),
			Enum.Material.Grass
		)
	end
	return model
end

-- Blumenfeld: bunte Reihen (wie Tulpenfelder)
function FarmProps.FlowerField(parent, cf, sizeX, sizeZ)
	local model = newModel(parent, "FlowerField", cf)
	fieldSoil(model, cf, sizeX, sizeZ)
	local colors = {
		Color3.fromRGB(236, 96, 120),
		Color3.fromRGB(250, 214, 96),
		Color3.fromRGB(176, 128, 226),
		Color3.fromRGB(246, 150, 70),
		Color3.fromRGB(246, 244, 236),
	}
	local rows = math.floor(sizeX / 2.4)
	for i = 1, rows do
		local x = (i - (rows + 1) / 2) * 2.4
		soft(
			model,
			"FlowerRowGreen",
			Vector3.new(1.5, 0.7, sizeZ - 1),
			cf * CFrame.new(x, 0.6, 0),
			World.Leaf,
			Enum.Material.Grass
		)
		soft(
			model,
			"FlowerRow",
			Vector3.new(1.2, 0.45, sizeZ - 1.6),
			cf * CFrame.new(x, 1.1, 0),
			colors[(i - 1) % #colors + 1],
			Enum.Material.SmoothPlastic,
			{ CastShadow = false }
		)
	end
	return model
end

-- Kürbisbeet
function FarmProps.PumpkinPatch(parent, cf, sizeX, sizeZ, rng)
	local model = newModel(parent, "PumpkinPatch", cf)
	fieldSoil(model, cf, sizeX, sizeZ)
	for i = -1, 1 do
		soft(
			model,
			"Vine",
			Vector3.new(0.5, 0.25, sizeZ - 1),
			cf * CFrame.new(i * sizeX / 3.2, 0.4, 0),
			World.Leaf,
			Enum.Material.Grass,
			TINY
		)
	end
	local count = math.floor(sizeX * sizeZ / 14)
	for _ = 1, count do
		local size = rng:NextNumber(1.6, 2.6)
		local position = CFrame.new(
			rng:NextNumber(-sizeX / 2 + 1.2, sizeX / 2 - 1.2),
			0.3 + size * 0.45,
			rng:NextNumber(-sizeZ / 2 + 1.2, sizeZ / 2 - 1.2)
		)
		ball(model, "Pumpkin", size, cf * position, Colors.Pumpkin, Enum.Material.SmoothPlastic, SOFT)
		soft(
			model,
			"PumpkinStem",
			Vector3.new(0.25, 0.6, 0.25),
			cf * position * CFrame.new(0, size / 2, 0),
			World.Leaf:Lerp(World.WoodDark, 0.4),
			Enum.Material.Wood,
			TINY
		)
	end
	return model
end

-- Reihe Sonnenblumen entlang X (Blüten schauen nach -Z)
function FarmProps.Sunflowers(parent, cf, count, rng)
	local model = newModel(parent, "Sunflowers", cf)
	for i = 1, count do
		local x = (i - (count + 1) / 2) * 2.2
		local height = rng:NextNumber(4.2, 5.6)
		soft(
			model,
			"Stem",
			Vector3.new(0.3, height, 0.3),
			cf * CFrame.new(x, height / 2, 0),
			World.Leaf,
			Enum.Material.Grass,
			TINY
		)
		soft(
			model,
			"Leaf",
			Vector3.new(1.2, 0.15, 0.6),
			cf * CFrame.new(x + 0.5, height * 0.5, 0) * CFrame.Angles(0, 0, math.rad(25)),
			World.Leaf,
			Enum.Material.Grass,
			TINY
		)
		local head = cf * CFrame.new(x, height + 0.4, -0.2) * CFrame.Angles(math.rad(-15), 0, 0) * FORWARD
		soft(
			model,
			"Petals",
			Vector3.new(0.25, 2.3, 2.3),
			head,
			Color3.fromRGB(252, 206, 52),
			Enum.Material.SmoothPlastic,
			{ Shape = Enum.PartType.Cylinder }
		)
		soft(
			model,
			"Seeds",
			Vector3.new(0.32, 1.1, 1.1),
			head * CFrame.new(-0.04, 0, 0),
			Color3.fromRGB(110, 70, 40),
			Enum.Material.Fabric,
			{ Shape = Enum.PartType.Cylinder, CastShadow = false }
		)
	end
	return model
end

------------------------------------------------------------------------
-- Landschaft: Windmühle, Teich
------------------------------------------------------------------------

-- Windmühle. Die Flügel (Model "Sails", Tag "Spinner") dreht WorldAnimator auf dem Client.
function FarmProps.Windmill(parent, cf)
	local model = newModel(parent, "Windmill", cf)
	column(model, "MillBase", 2, 11, cf * CFrame.new(0, 1, 0), World.StoneDark, Enum.Material.Cobblestone)
	local tiers = { { 2, 8, 9.6 }, { 8, 14, 8.3 }, { 14, 19, 7.1 } }
	for i, tier in ipairs(tiers) do
		column(
			model,
			"MillTower",
			tier[2] - tier[1],
			tier[3],
			cf * CFrame.new(0, (tier[1] + tier[2]) / 2, 0),
			i % 2 == 1 and Colors.Plaster or Colors.Plaster:Lerp(World.Stone, 0.4),
			PLASTER
		)
	end
	column(model, "MillGallery", 0.4, 11.5, cf * CFrame.new(0, 8.1, 0), World.Wood, Enum.Material.WoodPlanks, SOFT)
	ball(model, "MillCap", 8.2, cf * CFrame.new(0, 19.2, 0), Colors.RoofTile, ROOF_SHINGLES)
	soft(
		model,
		"MillDoor",
		Vector3.new(2.2, 3.8, 0.4),
		cf * CFrame.new(0, 3.9, -4.75),
		Color3.fromRGB(110, 70, 44),
		Enum.Material.WoodPlanks
	)
	for _, y in ipairs({ 11, 16 }) do
		soft(
			model,
			"MillWindow",
			Vector3.new(1.3, 1.6, 0.4),
			cf * CFrame.new(0, y, -(y < 14 and 4.1 or 3.5)),
			Colors.Glass,
			Enum.Material.Glass
		)
	end

	local hubCFrame = cf * CFrame.new(0, 18, -4.6)
	local sails = newModel(model, "Sails", hubCFrame)
	part(
		sails,
		"SailHub",
		Vector3.new(1.6, 1.4, 1.4),
		hubCFrame * FORWARD,
		World.WoodDark,
		Enum.Material.Wood,
		{ Shape = Enum.PartType.Cylinder }
	)
	for i = 0, 3 do
		local arm = hubCFrame * CFrame.Angles(0, 0, math.rad(90 * i + 20))
		soft(
			sails,
			"SailArm",
			Vector3.new(0.4, 9.5, 0.3),
			arm * CFrame.new(0, 4.9, -0.5),
			World.WoodDark,
			Enum.Material.Wood
		)
		soft(
			sails,
			"SailCloth",
			Vector3.new(1.8, 7.4, 0.12),
			arm * CFrame.new(1.05, 5.6, -0.45),
			Palette.Colors.Cream,
			Enum.Material.Fabric,
			{ Transparency = 0.05 }
		)
	end
	sails:SetAttribute("SpinSpeed", 22) -- Grad pro Sekunde um die eigene Z-Achse
	CollectionService:AddTag(sails, "Spinner")
	return model
end

-- Teich mit Schilf, Seerosen, Steinen, Steg und Enten
function FarmProps.Pond(parent, cf, radius, rng)
	local model = newModel(parent, "Pond", cf)
	column(
		model,
		"PondShore",
		0.14,
		radius * 2 + 4,
		cf * CFrame.new(0, 0.07, 0),
		Color3.fromRGB(196, 178, 130),
		Enum.Material.Sand,
		SOFT
	)
	column(
		model,
		"PondWater",
		0.24,
		radius * 2,
		cf * CFrame.new(0, 0.12, 0),
		Colors.Water,
		Enum.Material.Glass,
		{ Transparency = 0.12, Reflectance = 0.1, CanCollide = false }
	)
	-- Steine am Ufer
	for i = 1, 9 do
		local angle = (i / 9) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local r = radius + 1.2
		local size = rng:NextNumber(0.8, 1.6)
		part(
			model,
			"PondStone",
			Vector3.new(size, size * 0.6, size * 0.9),
			cf * CFrame.new(math.cos(angle) * r, size * 0.25, math.sin(angle) * r) * CFrame.Angles(0, angle, 0.2),
			Colors.Rock,
			Enum.Material.Slate,
			TINY
		)
	end
	-- Schilf in drei Büscheln
	for c = 1, 3 do
		local angle = c * 2.1 + 0.4
		local center = Vector3.new(math.cos(angle) * (radius - 1), 0, math.sin(angle) * (radius - 1))
		for _ = 1, 4 do
			local offset = center + Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
			local height = rng:NextNumber(2.2, 3.4)
			soft(
				model,
				"Reed",
				Vector3.new(0.15, height, 0.15),
				cf * CFrame.new(offset + Vector3.new(0, height / 2, 0)),
				World.Leaf,
				Enum.Material.Grass,
				TINY
			)
			if rng:NextNumber() < 0.6 then
				soft(
					model,
					"Cattail",
					Vector3.new(0.3, 0.8, 0.3),
					cf * CFrame.new(offset + Vector3.new(0, height + 0.2, 0)),
					World.WoodDark,
					Enum.Material.Fabric,
					TINY
				)
			end
		end
	end
	-- Seerosen
	for _ = 1, 5 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(1, radius - 2)
		local pad = cf * CFrame.new(math.cos(angle) * distance, 0.26, math.sin(angle) * distance)
		column(model, "LilyPad", 0.06, rng:NextNumber(1.2, 1.8), pad, World.Leaf, Enum.Material.SmoothPlastic, TINY)
		if rng:NextNumber() < 0.5 then
			ball(
				model,
				"LilyFlower",
				0.45,
				pad * CFrame.new(0, 0.15, 0),
				Color3.fromRGB(246, 180, 200),
				Enum.Material.SmoothPlastic,
				TINY
			)
		end
	end
	-- Steg
	part(
		model,
		"Dock",
		Vector3.new(2.6, 0.3, 6),
		cf * CFrame.new(0, 0.55, radius - 2),
		World.WoodLight,
		Enum.Material.WoodPlanks
	)
	for _, x in ipairs({ -1.1, 1.1 }) do
		soft(
			model,
			"DockPost",
			Vector3.new(0.35, 1.2, 0.35),
			cf * CFrame.new(x, 0.4, radius - 4.8),
			World.WoodDark,
			Enum.Material.Wood
		)
	end
	-- Enten
	for i = 1, 3 do
		local angle = i * 2.2
		local duck = cf
			* CFrame.new(math.cos(angle) * radius * 0.45, 0.24, math.sin(angle) * radius * 0.45)
			* CFrame.Angles(0, angle * 1.7, 0)
		ball(model, "DuckBody", 1, duck * CFrame.new(0, 0.3, 0), Colors.Duck, Enum.Material.SmoothPlastic, TINY)
		ball(model, "DuckHead", 0.6, duck * CFrame.new(0, 0.85, -0.35), Colors.Duck, Enum.Material.SmoothPlastic, TINY)
		soft(
			model,
			"DuckBeak",
			Vector3.new(0.3, 0.12, 0.35),
			duck * CFrame.new(0, 0.8, -0.7),
			Colors.Beak,
			Enum.Material.SmoothPlastic,
			TINY
		)
	end
	return model
end

return FarmProps
