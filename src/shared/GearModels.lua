-- GearModels.lua
-- 3D-Modelle für das Werkzeug (CowData.Gears). Server UND Client benutzen sie:
--   * Server: aufgestelltes Werkzeug auf den Farmen (GearManager), Deko am Werkzeug-Shop (MapBuilder)
--   * Client: Bilder in Shop und Werkzeug-Fenster (ViewportFrame), Vorschau beim Aufstellen
-- GearModels.Build(gearType, cf, options) baut das Modell auf dem Boden-CFrame cf (Vorderseite -Z).
--   options.Ghost = true: halb durchsichtig, ohne Licht/Partikel (Vorschau beim Aufstellen)
-- Drehende/schwingende Teile (Wetterhahn, Glocke) haben den Tag "Spinner" (WorldAnimator).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Palette"))
local World = Palette.World

local GearModels = {}

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- Zylinder aufrecht stellen

local WOOD, WOOD_DARK, WOOD_LIGHT = World.Wood, World.WoodDark, World.WoodLight
local HAY = World.Hay
local GOLD = Color3.fromRGB(246, 196, 64)
local BRASS = Color3.fromRGB(214, 166, 62)
local IRON = Color3.fromRGB(70, 74, 82)
local CARROT = Color3.fromRGB(240, 128, 40)
local LEAF = Color3.fromRGB(86, 168, 70)
local RED = Color3.fromRGB(214, 58, 54)

local function newPart(model, name, size, cframe, color, material, extra)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if extra and extra.Shape then
		part.Shape = extra.Shape
	end
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	if extra then
		for key, value in pairs(extra) do
			if key ~= "Shape" then
				part[key] = value
			end
		end
	end
	part.Parent = model
	return part
end

-- Baukasten für ein Modell: alle Maße relativ zum Boden-CFrame
local function kit(model, cf)
	local k = {}
	function k.box(name, size, offset, color, material, extra)
		return newPart(model, name, size, cf * offset, color, material, extra)
	end
	function k.column(name, height, diameter, offset, color, material, extra)
		extra = extra and table.clone(extra) or {}
		extra.Shape = Enum.PartType.Cylinder
		return newPart(
			model,
			name,
			Vector3.new(height, diameter, diameter),
			cf * offset * UPRIGHT,
			color,
			material,
			extra
		)
	end
	function k.rod(name, length, diameter, offset, color, material, extra)
		-- liegender Zylinder entlang der lokalen X-Achse von offset
		extra = extra and table.clone(extra) or {}
		extra.Shape = Enum.PartType.Cylinder
		return newPart(model, name, Vector3.new(length, diameter, diameter), cf * offset, color, material, extra)
	end
	function k.ball(name, diameter, offset, color, material, extra)
		extra = extra and table.clone(extra) or {}
		extra.Shape = Enum.PartType.Ball
		return newPart(model, name, Vector3.new(diameter, diameter, diameter), cf * offset, color, material, extra)
	end
	return k
end

local function sparkles(parent, color, rate, size)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkles"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size or 0.25),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(1, 1.8)
	emitter.Speed = NumberRange.new(0.5, 1.4)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Acceleration = Vector3.new(0, 1.2, 0)
	emitter.Rate = rate or 3
	emitter.Parent = parent
	return emitter
end

local function glow(parent, color, range)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 0.9
	light.Range = range or 9
	light.Shadows = false
	light.Parent = parent
	return light
end

------------------------------------------------------------------------
-- Die Modelle
------------------------------------------------------------------------
local builders = {}

-- Heubündel: zusammengebundene Garbe mit zwei Schnüren und abstehenden Halmen
builders.Hay = function(k, _, rng)
	local main = k.column("Bundle", 2.2, 1.5, CFrame.new(0, 1.2, 0), HAY, Enum.Material.Fabric)
	k.column("BundleFoot", 0.5, 1.95, CFrame.new(0, 0.25, 0), HAY:Lerp(WOOD, 0.15), Enum.Material.Fabric)
	k.ball("BundleTop", 1.95, CFrame.new(0, 2.35, 0), HAY:Lerp(Color3.new(1, 1, 1), 0.12), Enum.Material.Fabric)
	for _, y in ipairs({ 0.85, 1.6 }) do
		k.column("Twine", 0.18, 1.56, CFrame.new(0, y, 0), Color3.fromRGB(150, 98, 52), Enum.Material.Fabric)
	end
	for i = 1, 7 do
		local angle = i / 7 * math.pi * 2
		local tilt = math.rad(rng:NextNumber(18, 34))
		k.box(
			"Straw",
			Vector3.new(0.08, 1.1, 0.08),
			CFrame.new(math.cos(angle) * 0.45, 3.0, math.sin(angle) * 0.45)
				* CFrame.Angles(math.sin(angle) * tilt, 0, -math.cos(angle) * tilt),
			HAY:Lerp(Color3.new(1, 1, 1), 0.2),
			Enum.Material.Fabric
		)
	end
	return main
end

-- Striegel: Holzbürste mit dunklen Borsten und Lederschlaufe
builders.Brush = function(k)
	local main = k.box("BrushBody", Vector3.new(2.2, 0.55, 1), CFrame.new(0, 0.78, 0), WOOD_LIGHT, Enum.Material.Wood)
	for _, x in ipairs({ -1.1, 1.1 }) do
		k.rod("BrushEnd", 0.12, 0.98, CFrame.new(x, 0.78, 0) * CFrame.Angles(0, 0, 0), WOOD, Enum.Material.Wood)
	end
	k.box(
		"Bristles",
		Vector3.new(2, 0.52, 0.86),
		CFrame.new(0, 0.27, 0),
		Color3.fromRGB(58, 46, 40),
		Enum.Material.Fabric
	)
	local leather = Color3.fromRGB(124, 72, 42)
	k.box("Strap", Vector3.new(1.5, 0.12, 0.7), CFrame.new(0, 1.42, 0), leather, Enum.Material.Fabric)
	for _, x in ipairs({ -0.72, 0.72 }) do
		k.box("StrapSide", Vector3.new(0.12, 0.42, 0.7), CFrame.new(x, 1.2, 0), leather, Enum.Material.Fabric)
	end
	k.box("BrushPlate", Vector3.new(0.6, 0.06, 0.45), CFrame.new(0, 1.07, -0.2), GOLD, Enum.Material.Metal)
	return main
end

-- Futtertrog (auch golden): Holztrog auf Beinen, voll Körner mit Karotten und Äpfeln
local function trough(k, golden, rng)
	local plank = golden and GOLD or WOOD
	local material = golden and Enum.Material.Metal or Enum.Material.WoodPlanks
	local extra = golden and { Reflectance = 0.2 } or nil
	for _, x in ipairs({ -1.6, 1.6 }) do
		for _, z in ipairs({ -0.5, 0.5 }) do
			k.box("Leg", Vector3.new(0.3, 1.1, 0.3), CFrame.new(x, 0.55, z), golden and BRASS or WOOD_DARK, material)
		end
	end
	local main = k.box("TroughBottom", Vector3.new(3.7, 0.25, 0.8), CFrame.new(0, 1.1, 0), plank, material, extra)
	for _, side in ipairs({ -1, 1 }) do
		k.box(
			"TroughSide",
			Vector3.new(3.7, 1.15, 0.2),
			CFrame.new(0, 1.62, side * 0.62) * CFrame.Angles(side * math.rad(25), 0, 0),
			plank,
			material,
			extra
		)
	end
	for _, x in ipairs({ -1.9, 1.9 }) do
		k.box("TroughEnd", Vector3.new(0.2, 1.2, 1.6), CFrame.new(x, 1.65, 0), golden and BRASS or WOOD_DARK, material)
	end
	k.box(
		"Feed",
		Vector3.new(3.5, 0.45, 1.25),
		CFrame.new(0, 1.85, 0),
		golden and Color3.fromRGB(255, 232, 140) or Color3.fromRGB(206, 164, 96),
		Enum.Material.Sand
	)
	for i = 1, 5 do
		local x = -1.35 + (i - 1) * 0.68
		local yaw = math.rad(rng:NextNumber(-50, 50))
		local carrot = CFrame.new(x, 2.18, rng:NextNumber(-0.25, 0.25))
			* CFrame.Angles(0, yaw, math.rad(rng:NextNumber(-14, 14)))
		k.box(
			"Carrot",
			Vector3.new(0.95, 0.3, 0.3),
			carrot,
			golden and GOLD or CARROT,
			golden and Enum.Material.Metal or Enum.Material.SmoothPlastic,
			{ Shape = Enum.PartType.Cylinder }
		)
		k.box("CarrotLeaf", Vector3.new(0.3, 0.32, 0.22), carrot * CFrame.new(0.55, 0.08, 0), LEAF, Enum.Material.Grass)
	end
	for _, x in ipairs({ -0.7, 0.9 }) do
		k.ball("Apple", 0.48, CFrame.new(x, 2.25, 0.32), golden and GOLD or RED, Enum.Material.SmoothPlastic)
	end
	return main
end

builders.FeedTrough = function(k, _, rng)
	return trough(k, false, rng)
end

builders.GoldenTrough = function(k, options, rng)
	local main = trough(k, true, rng)
	if not options.Ghost then
		sparkles(main, Color3.fromRGB(255, 230, 120), 5, 0.3)
		glow(main, Color3.fromRGB(255, 214, 120), 10)
	end
	return main
end

-- Kuhglocke: Holzgalgen auf einem Stein, Messingglocke an rotem Band (schwingt leicht)
builders.CowBell = function(k, options, _, model, cf)
	local main =
		k.box("BellBase", Vector3.new(1.8, 0.3, 1.8), CFrame.new(0, 0.15, 0), World.StoneDark, Enum.Material.Slate)
	k.box("BellPost", Vector3.new(0.4, 4.3, 0.4), CFrame.new(-0.9, 2.45, 0), WOOD_DARK, Enum.Material.Wood)
	k.box("BellArm", Vector3.new(1.9, 0.32, 0.32), CFrame.new(-0.15, 4.45, 0), WOOD_DARK, Enum.Material.Wood)
	k.box(
		"BellBrace",
		Vector3.new(0.2, 1.1, 0.2),
		CFrame.new(-0.55, 3.95, 0) * CFrame.Angles(0, 0, math.rad(-45)),
		WOOD,
		Enum.Material.Wood
	)
	k.ball("PostCap", 0.5, CFrame.new(-0.9, 4.7, 0), GOLD, Enum.Material.Metal)

	-- schwingender Teil: Band, Glocke, Klöppel
	local pivot = cf * CFrame.new(0.4, 4.3, 0)
	local bell = Instance.new("Model")
	bell.Name = "Bell"
	bell.WorldPivot = pivot
	bell.Parent = model
	local function bellPart(name, size, offset, color, material, extra)
		return newPart(bell, name, size, cf * offset, color, material, extra)
	end
	bellPart("Ribbon", Vector3.new(0.12, 0.75, 0.4), CFrame.new(0.4, 3.95, 0), RED, Enum.Material.Fabric)
	local layers = { { 3.48, 0.3, 0.5 }, { 3.16, 0.4, 0.95 }, { 2.78, 0.42, 1.25 }, { 2.5, 0.18, 1.5 } }
	for _, layer in ipairs(layers) do
		bellPart(
			"Bell",
			Vector3.new(layer[2], layer[3], layer[3]),
			CFrame.new(0.4, layer[1], 0) * UPRIGHT,
			BRASS,
			Enum.Material.Metal,
			{ Shape = Enum.PartType.Cylinder, Reflectance = 0.15 }
		)
	end
	bellPart("Clapper", Vector3.new(0.38, 0.38, 0.38), CFrame.new(0.4, 2.3, 0), IRON, Enum.Material.Metal, {
		Shape = Enum.PartType.Ball,
	})
	bell:SetAttribute("SwingAngle", 14) -- Grad nach jeder Seite
	bell:SetAttribute("SpinSpeed", 2.4) -- Tempo der Schwingung
	CollectionService:AddTag(bell, "Spinner")

	for i, x in ipairs({ -0.55, 0.6 }) do
		k.ball("Flower", 0.4, CFrame.new(x, 0.42, -0.65), World.Flowers[i], Enum.Material.SmoothPlastic)
	end
	if not options.Ghost then
		sparkles(main, Color3.fromRGB(220, 170, 255), 2, 0.22)
	end
	return main
end

-- Wetterhahn: Steinsockel, Mast, Himmelsrichtungen, oben dreht sich der Hahn mit dem Pfeil
builders.WeatherVane = function(k, options, _, model, cf)
	local main = k.column("VaneBase", 0.5, 1.7, CFrame.new(0, 0.25, 0), World.StoneDark, Enum.Material.Cobblestone)
	k.column("VanePole", 5.7, 0.25, CFrame.new(0, 3.35, 0), IRON, Enum.Material.Metal)
	k.box("VaneCross", Vector3.new(2.4, 0.12, 0.12), CFrame.new(0, 4.7, 0), IRON, Enum.Material.Metal)
	k.box("VaneCross", Vector3.new(0.12, 0.12, 2.4), CFrame.new(0, 4.7, 0), IRON, Enum.Material.Metal)
	for _, offset in ipairs({
		Vector3.new(1.2, 0, 0),
		Vector3.new(-1.2, 0, 0),
		Vector3.new(0, 0, 1.2),
		Vector3.new(0, 0, -1.2),
	}) do
		k.ball("VaneDot", 0.3, CFrame.new(offset + Vector3.new(0, 4.7, 0)), GOLD, Enum.Material.Metal)
	end
	k.ball("VaneTop", 0.36, CFrame.new(0, 6.25, 0), GOLD, Enum.Material.Metal)

	-- drehender Teil (Pivot so gedreht, dass seine Z-Achse nach oben zeigt)
	local vane = Instance.new("Model")
	vane.Name = "Vane"
	vane.WorldPivot = cf * CFrame.new(0, 6.3, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	vane.Parent = model
	local function vanePart(name, size, offset, color, material, extra)
		return newPart(vane, name, size, cf * offset, color, material, extra)
	end
	local copper = Color3.fromRGB(206, 112, 52)
	vanePart("Arrow", Vector3.new(2.8, 0.1, 0.1), CFrame.new(0, 6.42, 0), IRON, Enum.Material.Metal)
	vanePart(
		"ArrowTip",
		Vector3.new(0.45, 0.1, 0.45),
		CFrame.new(1.45, 6.42, 0) * CFrame.Angles(0, math.rad(45), 0),
		GOLD,
		Enum.Material.Metal
	)
	vanePart("ArrowFin", Vector3.new(0.6, 0.5, 0.06), CFrame.new(-1.2, 6.5, 0), GOLD, Enum.Material.Metal)
	vanePart("RoosterLegs", Vector3.new(0.08, 0.35, 0.08), CFrame.new(0, 6.6, 0), IRON, Enum.Material.Metal)
	vanePart("RoosterBody", Vector3.new(1, 0.6, 0.14), CFrame.new(0, 7.05, 0), copper, Enum.Material.Metal)
	vanePart("RoosterNeck", Vector3.new(0.36, 0.5, 0.14), CFrame.new(0.42, 7.45, 0), copper, Enum.Material.Metal)
	vanePart("RoosterComb", Vector3.new(0.28, 0.16, 0.15), CFrame.new(0.44, 7.76, 0), RED, Enum.Material.SmoothPlastic)
	vanePart(
		"RoosterBeak",
		Vector3.new(0.18, 0.09, 0.14),
		CFrame.new(0.68, 7.5, 0),
		Color3.fromRGB(244, 176, 52),
		Enum.Material.SmoothPlastic
	)
	for i, angle in ipairs({ 25, 45, 65 }) do
		vanePart(
			"RoosterTail",
			Vector3.new(0.14, 0.75, 0.13),
			CFrame.new(-0.5, 7.25, 0) * CFrame.Angles(0, 0, math.rad(angle)),
			i == 2 and Color3.fromRGB(60, 120, 80) or Color3.fromRGB(40, 90, 70),
			Enum.Material.SmoothPlastic
		)
	end
	vane:SetAttribute("SpinSpeed", 18) -- Grad pro Sekunde
	CollectionService:AddTag(vane, "Spinner")
	if not options.Ghost then
		sparkles(main, Color3.fromRGB(180, 236, 255), 2, 0.22)
	end
	return main
end

-- Wunder-Spray: Glasflasche mit lila Flüssigkeit, Sprühkopf, funkelt
builders.MutationSpray = function(k, options)
	local liquid = Color3.fromRGB(176, 96, 255)
	local main = k.column("Liquid", 1.3, 0.86, CFrame.new(0, 0.72, 0), liquid, Enum.Material.SmoothPlastic)
	k.column("Bottle", 1.6, 1.02, CFrame.new(0, 0.86, 0), Color3.fromRGB(226, 210, 255), Enum.Material.Glass, {
		Transparency = 0.45,
	})
	k.column("Label", 0.55, 1.05, CFrame.new(0, 0.85, 0), Palette.Colors.Cream, Enum.Material.SmoothPlastic)
	k.ball("LabelStar", 0.3, CFrame.new(0, 0.85, -0.5), GOLD, Enum.Material.Neon)
	k.ball("Shoulder", 1.02, CFrame.new(0, 1.65, 0), Color3.fromRGB(226, 210, 255), Enum.Material.Glass, {
		Transparency = 0.45,
	})
	k.column("Neck", 0.4, 0.46, CFrame.new(0, 2.15, 0), Color3.fromRGB(245, 245, 250), Enum.Material.SmoothPlastic)
	k.box(
		"SprayHead",
		Vector3.new(0.5, 0.45, 0.95),
		CFrame.new(0, 2.55, -0.12),
		liquid:Lerp(Color3.new(1, 1, 1), 0.3),
		Enum.Material.SmoothPlastic
	)
	k.box("Nozzle", Vector3.new(0.22, 0.22, 0.3), CFrame.new(0, 2.6, -0.72), IRON, Enum.Material.Metal)
	k.box(
		"Trigger",
		Vector3.new(0.18, 0.55, 0.16),
		CFrame.new(0, 2.2, -0.45) * CFrame.Angles(math.rad(18), 0, 0),
		liquid,
		Enum.Material.SmoothPlastic
	)
	if not options.Ghost then
		sparkles(main, Color3.fromRGB(220, 170, 255), 3, 0.2)
	end
	return main
end

------------------------------------------------------------------------
-- öffentlich
------------------------------------------------------------------------

-- Baut das Modell. Gibt das Model zurück (PrimaryPart = Hauptteil, Pivot = cf).
function GearModels.Build(gearType, cf, options)
	options = options or {}
	local builder = builders[gearType]
	if not builder then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = gearType
	local rng = Random.new(options.Seed or 7)
	local main = builder(kit(model, cf), options, rng, model, cf)
	-- Pivot des Modells = cf (Boden-Mitte). Achtung: Hat ein Model einen PrimaryPart, ignoriert Roblox
	-- WorldPivot und nimmt den Pivot des PrimaryPart. Ohne PivotOffset würde PivotTo (Vorschau im
	-- Aufstell-Modus) das Modell um die Lage des Hauptteils versetzen: Tröge sanken samt Wirkungsbereich
	-- in den Boden, Wetterhahn/Heu lagen auf der Seite (Hauptteil ist ein gedrehter Zylinder).
	main.PivotOffset = main.CFrame:ToObjectSpace(cf)
	model.PrimaryPart = main
	model.WorldPivot = cf
	model:SetAttribute("GearType", gearType)
	if options.Ghost then
		for _, item in ipairs(model:GetDescendants()) do
			if item:IsA("Model") then
				-- Vorschau wird verschoben: nicht von WorldAnimator drehen lassen
				CollectionService:RemoveTag(item, "Spinner")
			elseif item:IsA("BasePart") then
				item.Transparency = math.max(item.Transparency, 0.45)
				item.CastShadow = false
				item.CanQuery = false
			end
		end
	end
	return model
end

-- Wirkungsbereich als flache, durchsichtige Scheibe auf dem Boden
function GearModels.AddRangeRing(model, cf, radius, color)
	return newPart(
		model,
		"Range",
		Vector3.new(0.06, radius * 2, radius * 2),
		cf * CFrame.new(0, 0.07, 0) * UPRIGHT,
		color,
		Enum.Material.SmoothPlastic,
		{
			Shape = Enum.PartType.Cylinder,
			Transparency = 0.82,
			CastShadow = false,
			CanQuery = false,
		}
	)
end

-- Größe des Modells (für die Kamera im ViewportFrame): Mitte und Radius
function GearModels.GetBounds(model)
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = -minV
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "Range" then
			local half = part.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local corner = part.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
						minV = Vector3.new(
							math.min(minV.X, corner.X),
							math.min(minV.Y, corner.Y),
							math.min(minV.Z, corner.Z)
						)
						maxV = Vector3.new(
							math.max(maxV.X, corner.X),
							math.max(maxV.Y, corner.Y),
							math.max(maxV.Z, corner.Z)
						)
					end
				end
			end
		end
	end
	return (minV + maxV) / 2, (maxV - minV).Magnitude / 2
end

return GearModels
