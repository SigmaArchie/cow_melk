-- CowModelBuilder.lua (ModuleScript)
-- Baut Kühe, Melkschemel und Melkeimer komplett aus BaseParts – keine externen Assets.
-- Runde Formen entstehen mit SpecialMesh (MeshType Sphere).
--
-- Stil: niedlich & knubbelig wie Pets in Simulator-Spielen (großer runder Kopf,
-- dicker Bauch, kurze dicke Beine, große Augen).
--
-- Koordinaten (lokal zur Kuh): Ursprung = Boden unter der Kuhmitte,
-- die Kuh schaut in Richtung -Z, +Y ist oben, +X ist die rechte Seite der Kuh.
--
-- Aufbau des Modells "Cow" (Tag "Cow", wird von WorldAnimator.client.lua animiert):
--   Torso (PrimaryPart) + restliche Körperteile   -> schwebt leicht, dreht sich manchmal
--   HeadGroup  (Model, Pivot = Hals)              -> Kopf dreht links/rechts
--   EarLeft / EarRight (Model, Pivot = Ohransatz) -> Ohren flattern
--   TailGroup  (Model, Pivot = Schwanzansatz)     -> Schwanz wedelt
--   TeatLeftA/B, TeatRightA/B                     -> Zitzen (Left = vorne, Right = hinten)

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CowData = require(script.Parent:WaitForChild("CowData"))
local Palette = require(script.Parent:WaitForChild("Palette"))

local Builder = {}

local PINK = Color3.fromRGB(255, 170, 185)
local DARK_PINK = Color3.fromRGB(200, 90, 115)
local CHEEK = Color3.fromRGB(255, 130, 160)
local HOOF = Color3.fromRGB(60, 48, 42)
local HORN = Color3.fromRGB(245, 235, 205)
local EYE_WHITE = Color3.fromRGB(255, 255, 255)
local EYE_BLACK = Color3.fromRGB(20, 20, 25)
local WOOD = Color3.fromRGB(150, 100, 60)
local DARK_WOOD = Color3.fromRGB(105, 68, 40)
local METAL = Color3.fromRGB(165, 170, 178)
local MILK = Color3.fromRGB(252, 252, 248)

local RAD90 = math.rad(90)

-- Rumpf (Ellipsoid 5 x 3 x 7) – wird auch für die Flecken gebraucht
local BODY_CENTER = Vector3.new(0, 3.7, 0)
local BODY_SIZE = Vector3.new(5, 3, 7)

------------------------------------------------------------------------
-- Hilfsfunktionen
------------------------------------------------------------------------

-- Aus der Kuh-ID eine feste Zahl machen -> jede Kuh hat immer dieselben Flecken
local function seedFromString(text)
	local hash = 7
	for i = 1, #text do
		hash = (hash * 31 + string.byte(text, i)) % 2147483647
	end
	return hash
end

local function newPart(parent, base, name, shape, size, localCFrame, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.CFrame = base * localCFrame
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Senkrechter Zylinder (Roblox-Zylinder liegen standardmäßig entlang X)
local function upright(cframe)
	return cframe * CFrame.Angles(0, 0, RAD90)
end

local function particles(parent, props)
	local emitter = Instance.new("ParticleEmitter")
	emitter.LightEmission = props.LightEmission or 0.3 -- sanft, nicht strahlend
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, props.Size or 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, props.Transparency or 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = props.Color
	emitter.Rate = props.Rate or 3
	emitter.Lifetime = props.Lifetime or NumberRange.new(1, 2)
	emitter.Speed = props.Speed or NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = props.Spread or Vector2.new(180, 180)
	emitter.Acceleration = props.Acceleration or Vector3.zero
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = props.RotSpeed or NumberRange.new(-60, 60)
	emitter.Drag = props.Drag or 0
	emitter.Parent = parent
	return emitter
end

local function light(parent, color, brightness, range)
	local pointLight = Instance.new("PointLight")
	pointLight.Color = color
	pointLight.Brightness = brightness
	pointLight.Range = range
	pointLight.Shadows = false
	pointLight.Parent = parent
	return pointLight
end

local RAINBOW_SEQUENCE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(246, 128, 128)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(246, 178, 104)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(240, 224, 124)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(132, 208, 144)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(124, 182, 244)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(186, 144, 240)),
})

-- Licht & Partikel je Seltenheit – bewusst zurückhaltend (viele Kühe auf mehreren Farmen):
--   Common    schlicht, nichts
--   Uncommon  ganz wenige grünliche Funken
--   Rare      kühles blaues Leuchten (kleines Licht)
--   Epic      lila Schein + wenige Partikel
--   Legendary warmer Gold-Schein + wenige Funken
--   Golden    Premium-Gold: Schein, wenige Münz-Partikel, dünner Lichtstrahl
--   Rainbow   sanfter Schein, zarte Farbpartikel (die Kuh wechselt langsam die Farbe)
--   Ghost     grünlicher, durchscheinender Dunst
local function addRarityEffects(rarity, torso, model)
	-- neue Arten borgen sich ein Set (info.Effect) und färben es selbst (info.EffectColor)
	local info = CowData.Rarities[rarity]
	local preset = info and info.Effect or rarity
	local color = info and info.EffectColor or Palette.rarityColor(rarity)
	if preset == "Uncommon" then
		particles(torso, { Color = ColorSequence.new(color), Rate = 1.5, Size = 0.2, Transparency = 0.4 })
	elseif preset == "Rare" then
		light(torso, color, 0.8, 9)
	elseif preset == "Epic" then
		light(torso, color, 1.0, 10)
		particles(torso, {
			Color = ColorSequence.new(color),
			Rate = 3,
			Size = 0.3,
			Lifetime = NumberRange.new(1.5, 2.5),
			Speed = NumberRange.new(0.2, 0.5),
			Drag = 2,
		})
	elseif preset == "Legendary" then
		light(torso, color, 1.4, 11)
		particles(torso, {
			Color = ColorSequence.new(color),
			Rate = 4,
			Size = 0.3,
			Speed = NumberRange.new(0.8, 2),
			Acceleration = Vector3.new(0, 1.5, 0),
		})
	elseif preset == "Golden" then
		light(torso, color, 1.8, 13)
		-- wenige Goldmünzen-Partikel
		particles(torso, {
			Color = ColorSequence.new(color),
			Rate = 3,
			Size = 0.45,
			Lifetime = NumberRange.new(1.2, 1.8),
			Speed = NumberRange.new(3, 5),
			Spread = Vector2.new(35, 35),
			Acceleration = Vector3.new(0, -10, 0),
			RotSpeed = NumberRange.new(-200, 200),
		})
		-- dünner goldener Lichtstrahl nach oben (kurz und durchsichtig)
		local bottom = Instance.new("Attachment")
		bottom.Name = "BeamBottom"
		bottom.Position = Vector3.new(0, 1, 0)
		bottom.Parent = torso
		local top = Instance.new("Attachment")
		top.Name = "BeamTop"
		top.Position = Vector3.new(0, 11, 0)
		top.Parent = torso
		local beam = Instance.new("Beam")
		beam.Attachment0 = bottom
		beam.Attachment1 = top
		beam.Color = ColorSequence.new(color)
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.Width0 = 1.8
		beam.Width1 = 0.3
		beam.LightEmission = 0.5
		beam.FaceCamera = true
		beam.Parent = torso
	elseif preset == "Rainbow" then
		light(torso, color, 1.0, 10)
		particles(torso, {
			Color = RAINBOW_SEQUENCE,
			Rate = 3,
			Size = 0.3,
			Lifetime = NumberRange.new(1.5, 2.5),
			Speed = NumberRange.new(0.3, 0.6),
			Drag = 1.5,
		})
	elseif preset == "Ghost" then
		light(torso, color, 0.8, 10)
		-- Geister-Dunst, der langsam nach oben steigt
		particles(torso, {
			Color = ColorSequence.new(color),
			Rate = 2,
			Size = 0.9,
			Transparency = 0.6,
			Lifetime = NumberRange.new(2, 3),
			Speed = NumberRange.new(0.4, 0.8),
			Spread = Vector2.new(30, 30),
			Acceleration = Vector3.new(0, 1, 0),
			LightEmission = 0.1,
		})
	end
	model:SetAttribute("HasEffects", preset ~= "Common")
end

------------------------------------------------------------------------
-- Kuh (Ersatz-Version aus Parts, falls das Blender-Modell noch fehlt)
------------------------------------------------------------------------
-- Gibt (model, refs) zurück. refs = { Torso, Head, Udder, Teats = { LeftA, LeftB, RightA, RightB } }
local function buildProceduralCow(rarity, seedId, base)
	local info = CowData.Rarities[rarity] or CowData.Rarities.Common
	local rng = Random.new(seedFromString(tostring(seedId)))
	local transparency = info.Transparency or 0

	local model = Instance.new("Model")
	model.Name = "Cow"
	model:SetAttribute("Rarity", rarity)

	local function group(name, pivotOffset)
		local g = Instance.new("Model")
		g.Name = name
		g.Parent = model
		g:SetAttribute("PivotOffset", pivotOffset) -- lokale Position des Gelenks
		return g
	end
	local headGroup = group("HeadGroup", Vector3.new(0, 4.6, -3.0))
	local earLeft = group("EarLeft", Vector3.new(-0.95, 5.55, -3.75))
	local earRight = group("EarRight", Vector3.new(0.95, 5.55, -3.75))
	local tailGroup = group("TailGroup", Vector3.new(0, 4.6, 3.4))

	local refs = { Teats = {} }

	-- kind: "Ellipsoid" | "Cylinder" | "Ball" | "Block"
	-- tint = true -> Fellfarbe (wird bei der Regenbogen-Kuh eingefärbt)
	local function make(parent, name, kind, size, localCFrame, color, tint)
		local shape = Enum.PartType.Block
		if kind == "Cylinder" then
			shape = Enum.PartType.Cylinder
		elseif kind == "Ball" then
			shape = Enum.PartType.Ball
		end
		local material = tint and info.Material or Enum.Material.SmoothPlastic
		local part = newPart(parent, base, name, shape, size, localCFrame, color or info.Color, material)
		part.Transparency = transparency
		if tint and info.Reflectance then
			part.Reflectance = info.Reflectance
		end
		if kind == "Ellipsoid" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
		end
		if tint then
			part:SetAttribute("Tint", true)
		end
		return part
	end

	local function fur(parent, name, kind, size, localCFrame)
		return make(parent, name, kind, size, localCFrame, info.Color, true)
	end

	--------------------------------------------------------------------
	-- Körper: dicker runder Rumpf + Bauch
	--------------------------------------------------------------------
	local torso = fur(model, "Torso", "Ellipsoid", BODY_SIZE, CFrame.new(BODY_CENTER))
	torso.CanCollide = true
	refs.Torso = torso
	fur(model, "Belly", "Ellipsoid", Vector3.new(4.4, 2.6, 6), CFrame.new(0, 3.3, 0))
	fur(model, "Chest", "Ellipsoid", Vector3.new(3.6, 3, 2.6), CFrame.new(0, 3.9, -2.6))

	-- kurze, dicke Beine mit Hufen
	for _, x in ipairs({ -1.4, 1.4 }) do
		for _, z in ipairs({ -2.2, 2.2 }) do
			fur(model, "Leg", "Cylinder", Vector3.new(2.5, 1.05, 1.05), upright(CFrame.new(x, 1.25, z)))
			make(model, "Hoof", "Cylinder", Vector3.new(0.5, 1.2, 1.2), upright(CFrame.new(x, 0.25, z)), HOOF)
		end
	end

	-- großes rosa Euter mit gut sichtbaren Zitzen
	refs.Udder = make(model, "Udder", "Ellipsoid", Vector3.new(2.2, 1.3, 1.9), CFrame.new(0, 2.35, 1.0), PINK)
	local teatPositions = {
		LeftA = Vector3.new(-0.45, 1.55, 0.55),
		LeftB = Vector3.new(0.45, 1.55, 0.55),
		RightA = Vector3.new(-0.45, 1.55, 1.45),
		RightB = Vector3.new(0.45, 1.55, 1.45),
	}
	for name, position in pairs(teatPositions) do
		refs.Teats[name] =
			make(model, "Teat" .. name, "Cylinder", Vector3.new(0.6, 0.3, 0.3), upright(CFrame.new(position)), PINK)
	end

	--------------------------------------------------------------------
	-- Kopf: große Kugel, rosa Schnauze, große Augen, Bäckchen, Hörnchen
	--------------------------------------------------------------------
	local head = fur(headGroup, "Head", "Ellipsoid", Vector3.new(2.5, 2.5, 2.5), CFrame.new(0, 5.0, -3.9))
	refs.Head = head

	make(headGroup, "Snout", "Ellipsoid", Vector3.new(1.9, 1.2, 1.0), CFrame.new(0, 4.5, -5.0), PINK)
	for _, side in ipairs({ -1, 1 }) do
		make(
			headGroup,
			"Nostril",
			"Ellipsoid",
			Vector3.new(0.28, 0.34, 0.12),
			CFrame.new(side * 0.38, 4.6, -5.47),
			DARK_PINK
		)
		-- große Augen: weiß + schwarze Pupille + Glanzpunkt
		make(headGroup, "EyeWhite", "Ball", Vector3.new(0.9, 0.9, 0.9), CFrame.new(side * 0.55, 5.35, -4.85), EYE_WHITE)
		make(headGroup, "Pupil", "Ball", Vector3.new(0.48, 0.48, 0.48), CFrame.new(side * 0.55, 5.36, -5.22), EYE_BLACK)
		make(
			headGroup,
			"EyeShine",
			"Ball",
			Vector3.new(0.16, 0.16, 0.16),
			CFrame.new(side * 0.47, 5.5, -5.43),
			EYE_WHITE
		)
		-- Bäckchen
		make(
			headGroup,
			"Cheek",
			"Ellipsoid",
			Vector3.new(0.55, 0.35, 0.12),
			CFrame.new(side * 0.98, 4.85, -4.6) * CFrame.Angles(0, side * math.rad(-50), 0),
			CHEEK
		)
		-- Hörnchen
		make(
			headGroup,
			"Horn",
			"Cylinder",
			Vector3.new(0.6, 0.3, 0.3),
			CFrame.new(side * 0.62, 6.2, -3.75) * CFrame.Angles(0, 0, math.rad(side == 1 and 65 or 115)),
			HORN
		)
	end
	make(headGroup, "Mouth", "Ellipsoid", Vector3.new(0.7, 0.12, 0.1), CFrame.new(0, 4.12, -5.42), DARK_PINK)

	-- Ohren (eigene Gruppen, damit sie flattern können) mit rosa Innenseite
	for _, entry in ipairs({ { earLeft, -1 }, { earRight, 1 } }) do
		local earGroup, side = entry[1], entry[2]
		local earCFrame = CFrame.new(side * 1.5, 5.45, -3.75) * CFrame.Angles(0, 0, math.rad(-20 * side))
		fur(earGroup, "Ear", "Ellipsoid", Vector3.new(1.25, 0.35, 0.75), earCFrame)
		make(
			earGroup,
			"EarInner",
			"Ellipsoid",
			Vector3.new(0.85, 0.37, 0.42),
			earCFrame * CFrame.new(side * 0.05, 0, -0.14),
			PINK
		)
	end

	--------------------------------------------------------------------
	-- Schwanz mit Quaste
	--------------------------------------------------------------------
	fur(
		tailGroup,
		"Tail",
		"Cylinder",
		Vector3.new(2.0, 0.26, 0.26),
		upright(CFrame.new(0, 3.65, 3.65)) * CFrame.Angles(0, 0, 0)
	)
	make(
		tailGroup,
		"TailTuft",
		"Ellipsoid",
		Vector3.new(0.6, 0.85, 0.6),
		CFrame.new(0, 2.6, 3.7),
		info.SpotColor or HOOF
	)

	--------------------------------------------------------------------
	-- Flecken: 3-5 unregelmäßige Kleckse auf der Rumpf-Oberfläche
	-- (jeder Klecks = 2 überlappende, flache Ellipsoide, leicht eingesunken)
	--------------------------------------------------------------------
	if info.SpotColor then
		local a, b, c = BODY_SIZE.X / 2, BODY_SIZE.Y / 2, BODY_SIZE.Z / 2
		local function surfaceCFrame(theta, t, sink)
			local ring = math.sqrt(1 - t * t)
			local point = Vector3.new(a * ring * math.cos(theta), b * ring * math.sin(theta), c * t)
			local normal = Vector3.new(point.X / (a * a), point.Y / (b * b), point.Z / (c * c)).Unit
			local position = BODY_CENTER + point - normal * sink
			return CFrame.lookAt(position, position + normal, Vector3.zAxis)
		end
		for i = 1, rng:NextInteger(3, 5) do
			-- Seiten und Rücken, nicht der Bauch (dort ist das Euter)
			local theta = math.rad(rng:NextNumber(-35, 215))
			local t = rng:NextNumber(-0.6, 0.6)
			local w, h = rng:NextNumber(1.4, 2.4), rng:NextNumber(1.2, 2.2)
			make(model, "Spot" .. i, "Ellipsoid", Vector3.new(w, h, 0.4), surfaceCFrame(theta, t, 0.1), info.SpotColor)
			-- zweiter, versetzter Klecks -> unregelmäßige Form
			local theta2 = theta + math.rad(rng:NextNumber(-14, 14))
			local t2 = math.clamp(t + rng:NextNumber(-0.15, 0.15), -0.7, 0.7)
			make(
				model,
				"Spot" .. i .. "b",
				"Ellipsoid",
				Vector3.new(w * 0.7, h * 0.75, 0.4),
				surfaceCFrame(theta2, t2, 0.1),
				info.SpotColor
			)
		end
		-- Fleck um ein Auge (sehr typisch für Cartoon-Kühe)
		if rng:NextNumber() < 0.5 then
			local side = rng:NextNumber() < 0.5 and -1 or 1
			make(
				headGroup,
				"EyePatch",
				"Ellipsoid",
				Vector3.new(1.3, 1.2, 0.3),
				CFrame.new(side * 0.62, 5.4, -4.72) * CFrame.Angles(0, side * math.rad(-25), 0),
				info.SpotColor
			)
		end
	end

	--------------------------------------------------------------------
	-- Gelenke setzen, Effekte, Tag
	--------------------------------------------------------------------
	for _, g in ipairs({ headGroup, earLeft, earRight, tailGroup }) do
		g.WorldPivot = base * CFrame.new(g:GetAttribute("PivotOffset"))
	end

	addRarityEffects(rarity, torso, model)

	-- Maße für Schemel/Eimer (CowManager)
	model:SetAttribute("BodyHalfWidth", BODY_SIZE.X / 2)
	model:SetAttribute("UdderZ", 1.0)

	model.PrimaryPart = torso
	model.WorldPivot = base -- Drehpunkt = Boden unter der Kuhmitte
	CollectionService:AddTag(model, "Cow")
	return model, refs
end

------------------------------------------------------------------------
-- Kuh aus dem Blender-Modell (ReplicatedStorage.Assets.CowModel)
--
-- Das Modell kommt aus CowModell.blend (Export: tools/export_cow.py, Import: Roblox-3D-Importer).
-- Die Teile werden an ihren Blender-Namen erkannt. Das Script dreht die Kuh so, dass sie
-- nach -Z schaut, skaliert sie auf TARGET_HEIGHT und stellt sie auf den Boden – egal wie
-- sie exportiert wurde.
------------------------------------------------------------------------
local TARGET_HEIGHT = 6.4 -- Studs (ungefähr so groß wie die Ersatz-Kuh)

local MESH_CHECK_TIMEOUT = 15 -- Sekunden, bis die Mesh-Prüfung als gescheitert gilt

-- Prüft EINMAL, ob die Meshes des importierten Modells wirklich laden. Sonst wären die Kühe unsichtbar.
-- Gibt true zurück, wenn das Modell benutzt werden darf.
local function verifyMeshes(template)
	local meshIds, meshParts = {}, {}
	for _, descendant in ipairs(template:GetDescendants()) do
		if descendant:IsA("MeshPart") and descendant.MeshId ~= "" then
			meshIds[descendant.MeshId] = true
			table.insert(meshParts, descendant)
		end
	end
	if #meshParts == 0 then
		return true -- keine Meshes, nichts zu laden
	end

	local succeeded, failed, finished = 0, 0, false
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(meshParts, function(contentId, status)
				if not meshIds[contentId] then
					return -- nur die Meshes zählen, nicht Texturen
				end
				if status == Enum.AssetFetchStatus.Success then
					succeeded += 1
				elseif status == Enum.AssetFetchStatus.Failure or status == Enum.AssetFetchStatus.TimedOut then
					failed += 1
				end
			end)
		end)
		finished = true
	end)

	local start = os.clock()
	while not finished and os.clock() - start < MESH_CHECK_TIMEOUT do
		task.wait(0.1)
	end
	if not finished or failed > 0 then
		return false
	end
	if succeeded > 0 then
		return true
	end

	-- PreloadAsync war nicht eindeutig (z.B. auf dem Server): ein Mesh direkt laden
	local anyId = next(meshIds)
	local ok = pcall(function()
		return AssetService:CreateMeshPartAsync(anyId)
	end)
	return ok
end

local meshCheckResult = nil -- nil = noch nicht fertig, true/false = Ergebnis (wird gemerkt)
local meshCheckStarted = false

local function importedModelAllowed(template)
	if meshCheckResult == nil and not meshCheckStarted then
		meshCheckStarted = true
		task.spawn(function()
			local ok, result = pcall(verifyMeshes, template)
			meshCheckResult = ok and result == true
			if not meshCheckResult then
				warn(
					"[CowModelBuilder] Die Meshes von CowModel.rbxm konnten nicht geladen werden. "
						.. "Es wird die Ersatz-Kuh aus Parts benutzt (sonst wären die Kühe unsichtbar). "
						.. "Mögliche Ursache: Mesh-Asset gehört einem anderen Konto oder ist nicht freigegeben."
				)
			end
		end)
	end
	-- andere Kühe, die gleichzeitig gebaut werden, warten auf dasselbe Ergebnis
	local start = os.clock()
	while meshCheckResult == nil and os.clock() - start < MESH_CHECK_TIMEOUT + 10 do
		task.wait(0.1)
	end
	return meshCheckResult == true
end

local function getTemplate()
	if not CowData.Config.UseImportedCowModel then
		return nil
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("CowModel")
	if template and template:FindFirstChild("Koerper", true) and template:FindFirstChild("Kopf", true) then
		if importedModelAllowed(template) then
			return template
		end
	end
	return nil
end

-- Rolle eines Teils anhand des Blender-Namens
local function roleOf(name)
	if name:match("^Fleck_Kopf") then
		return "spot", "head"
	elseif name:match("^Fleck") then
		return "spot", "body"
	elseif name:match("^Zitze") then
		return "teat", "body"
	elseif name:match("^Euter") then
		return "pink", "body"
	elseif name:match("Huf") then
		return "hoof", "body"
	elseif name:match("^Bein") or name:match("^Koerper") then
		return "fur", "body"
	elseif name:match("^Schwanz_Quaste") then
		return "tuft", "tail"
	elseif name:match("^Schwanz") then
		return "fur", "tail"
	elseif name:match("^Ohr") then
		return "fur", "ear"
	elseif name:match("^Schnauze") then
		return "pink", "head"
	elseif name:match("^Nase") then
		return "nostril", "head"
	elseif name:match("^Horn") then
		return "horn", "head"
	elseif name:match("^Auge") then
		return "eye", "head"
	elseif name:match("^Kopf") then
		return "fur", "head"
	end
	return "keep", "body"
end

-- Achsen-ausgerichtete Box um mehrere Parts (in Weltkoordinaten)
local function boundsOf(parts)
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = -minV
	for _, part in ipairs(parts) do
		local half = part.Size / 2
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local corner = part.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
					minV = minV:Min(corner)
					maxV = maxV:Max(corner)
				end
			end
		end
	end
	return minV, maxV
end

local function buildTemplateCow(template, rarity, base)
	local info = CowData.Rarities[rarity] or CowData.Rarities.Common
	local transparency = info.Transparency or 0
	local clone = template:Clone()

	-- alle Mesh-Teile einsammeln (Unterordner aus dem Importer auflösen)
	local parts = {}
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	local function find(prefix)
		for _, part in ipairs(parts) do
			if part.Name:sub(1, #prefix) == prefix then
				return part
			end
		end
		return nil
	end
	local body, head = find("Koerper"), find("Kopf")

	-- 1) drehen: Kopf zeigt nach -Z, Mitte auf den Ursprung
	local minV, maxV = boundsOf(parts)
	local center = (minV + maxV) / 2
	local forward = (head.Position - body.Position) * Vector3.new(1, 0, 1)
	if forward.Magnitude < 0.01 then
		forward = Vector3.new(0, 0, -1)
	end
	local toLocal = CFrame.lookAt(center, center + forward.Unit):Inverse()
	for _, part in ipairs(parts) do
		part.CFrame = toLocal * part.CFrame
	end

	-- 2) skalieren auf Zielhöhe, 3) auf den Boden stellen
	minV, maxV = boundsOf(parts)
	local scale = TARGET_HEIGHT / math.max(maxV.Y - minV.Y, 0.01)
	for _, part in ipairs(parts) do
		local rotation = part.CFrame.Rotation
		part.Size *= scale
		part.CFrame = CFrame.new(part.Position * scale) * rotation
	end
	minV, maxV = boundsOf(parts)
	local lift = Vector3.new(-(minV.X + maxV.X) / 2, -minV.Y, -(minV.Z + maxV.Z) / 2)
	for _, part in ipairs(parts) do
		part.CFrame = part.CFrame + lift
	end

	-- neues Modell mit den Gruppen, die WorldAnimator erwartet
	local model = Instance.new("Model")
	model.Name = "Cow"
	model:SetAttribute("Rarity", rarity)
	local groups = {}
	for _, name in ipairs({ "HeadGroup", "EarLeft", "EarRight", "TailGroup" }) do
		local g = Instance.new("Model")
		g.Name = name
		g.Parent = model
		groups[name] = g
	end

	local refs = { Teats = {} }
	local teats = {}
	local headParts, earParts, tailParts = {}, {}, {}

	for _, part in ipairs(parts) do
		local role, group = roleOf(part.Name)
		part.Anchored = true
		part.CanCollide = false
		part.CastShadow = true
		part.Transparency = math.max(part.Transparency, transparency)
		-- Importer-Texturen entfernen, damit die Seltenheits-Farbe sichtbar ist
		if role ~= "eye" and role ~= "keep" then
			for _, child in ipairs(part:GetChildren()) do
				if child:IsA("SurfaceAppearance") then
					child:Destroy()
				end
			end
			pcall(function()
				part.TextureID = ""
			end)
		end

		if role == "fur" then
			part.Color = info.Color
			part.Material = info.Material
			part.Reflectance = info.Reflectance or 0
			part:SetAttribute("Tint", true)
		elseif role == "spot" then
			part.Color = info.SpotColor or info.Color
		elseif role == "tuft" then
			part.Color = info.SpotColor or HOOF
		elseif role == "pink" or role == "teat" then
			part.Color = PINK
		elseif role == "nostril" then
			part.Color = DARK_PINK
		elseif role == "hoof" then
			part.Color = HOOF
		elseif role == "horn" then
			part.Color = HORN
		end

		if role == "teat" then
			table.insert(teats, part)
		end
		if group == "head" then
			table.insert(headParts, part)
			part.Parent = groups.HeadGroup
		elseif group == "ear" then
			table.insert(earParts, part)
		elseif group == "tail" then
			table.insert(tailParts, part)
			part.Parent = groups.TailGroup
		else
			part.Parent = model
		end
	end

	-- Ohren: das linke ist das mit kleinerem X
	table.sort(earParts, function(a, b)
		return a.Position.X < b.Position.X
	end)
	if earParts[1] then
		earParts[1].Parent = groups.EarLeft
	end
	if earParts[2] then
		earParts[2].Parent = groups.EarRight
	end

	-- Zitzen: vordere zwei (kleineres Z) = Left, hintere = Right
	table.sort(teats, function(a, b)
		return a.Position.Z < b.Position.Z
	end)
	local front = { teats[1], teats[2] }
	local back = { teats[3], teats[4] }
	for _, pair in ipairs({ { front, "Left" }, { back, "Right" } }) do
		local list, side = pair[1], pair[2]
		table.sort(list, function(a, b)
			return a.Position.X < b.Position.X
		end)
		for i, teat in ipairs(list) do
			local key = side .. (i == 1 and "A" or "B")
			teat.Name = "Teat" .. key
			refs.Teats[key] = teat
		end
	end

	body.Name = "Torso"
	body.CanCollide = true
	head.Name = "Head"
	refs.Torso = body
	refs.Head = head
	refs.Udder = find("Euter")

	-- Gelenke: Kopf dreht hinten unten am Kopf, Ohren am inneren Ende, Schwanz oben
	if #headParts > 0 then
		local hMin, hMax = boundsOf({ head })
		groups.HeadGroup.WorldPivot = CFrame.new((hMin.X + hMax.X) / 2, hMin.Y + (hMax.Y - hMin.Y) * 0.3, hMax.Z)
	end
	for _, entry in ipairs({ { groups.EarLeft, 1 }, { groups.EarRight, -1 } }) do
		local g, innerSign = entry[1], entry[2]
		local list = g:GetChildren()
		if #list > 0 then
			local eMin, eMax = boundsOf(list)
			local innerX = innerSign == 1 and eMax.X or eMin.X
			g.WorldPivot = CFrame.new(innerX, (eMin.Y + eMax.Y) / 2, (eMin.Z + eMax.Z) / 2)
		end
	end
	if #tailParts > 0 then
		local tMin, tMax = boundsOf(tailParts)
		groups.TailGroup.WorldPivot = CFrame.new((tMin.X + tMax.X) / 2, tMax.Y, (tMin.Z + tMax.Z) / 2)
	end

	-- Maße für Schemel/Eimer (CowManager)
	local bMin, bMax = boundsOf({ body })
	model:SetAttribute("BodyHalfWidth", (bMax.X - bMin.X) / 2)
	model:SetAttribute("UdderZ", refs.Udder and refs.Udder.Position.Z or 1.0)

	-- alles an die richtige Stelle in der Welt schieben
	for _, g in pairs(groups) do
		g.WorldPivot = base * g.WorldPivot
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CFrame = base * d.CFrame
		end
	end

	clone:Destroy()
	addRarityEffects(rarity, body, model)
	model.PrimaryPart = body
	model.WorldPivot = base
	CollectionService:AddTag(model, "Cow")
	return model, refs
end

------------------------------------------------------------------------
-- Kuh-Mutationen sichtbar machen (CowData.CowMutations): wenige Partikel je Mutation,
-- bei Eis-Mutationen wird das Fell eisig, ein kleines Licht nur, wenn die Kuh noch keins hat.
------------------------------------------------------------------------
local ICE = Color3.fromRGB(190, 230, 255)

local function tintFur(model, color, amount, material)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part:GetAttribute("Tint") then
			part.Color = part.Color:Lerp(color, amount)
			if material then
				part.Material = material
			end
		end
	end
end

function Builder.ApplyCowMutations(model, torso, mutations)
	if not mutations or #mutations == 0 then
		return
	end
	local has = {}
	for _, id in ipairs(mutations) do
		has[id] = true
	end
	local function colorOf(id)
		return CowData.CowMutations[id].Color
	end

	if has.Wet then
		-- Tropfen, die herunterfallen; Fell glänzt nass
		particles(torso, {
			Color = ColorSequence.new(colorOf("Wet")),
			Rate = 4,
			Size = 0.15,
			Lifetime = NumberRange.new(0.5, 0.9),
			Speed = NumberRange.new(0.5, 1.5),
			Acceleration = Vector3.new(0, -14, 0),
		})
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part:GetAttribute("Tint") then
				part.Reflectance = math.max(part.Reflectance, 0.12)
			end
		end
	end
	if has.Chilled then
		particles(torso, {
			Color = ColorSequence.new(Color3.fromRGB(240, 250, 255)),
			Rate = 2,
			Size = 0.2,
			Lifetime = NumberRange.new(1.5, 2.5),
			Speed = NumberRange.new(0.2, 0.5),
			Acceleration = Vector3.new(0, -0.8, 0),
		})
		tintFur(model, ICE, 0.25)
	end
	if has.Frozen or has.Starfrost or has.Aurora then
		tintFur(model, ICE, 0.45, Enum.Material.Ice)
		particles(torso, {
			Color = ColorSequence.new(colorOf("Frozen")),
			LightEmission = 0.5,
			Rate = 2,
			Size = 0.25,
			Lifetime = NumberRange.new(1.5, 2.5),
			Speed = NumberRange.new(0.1, 0.4),
		})
	end
	if has.Sunkissed then
		particles(torso, {
			Color = ColorSequence.new(colorOf("Sunkissed")),
			LightEmission = 0.8,
			Rate = 2,
			Size = 0.22,
			Speed = NumberRange.new(0.4, 1),
			Acceleration = Vector3.new(0, 1, 0),
		})
	end
	if has.Moonlit or has.Starfrost then
		particles(torso, {
			Color = ColorSequence.new(colorOf("Moonlit"), Color3.fromRGB(255, 250, 230)),
			LightEmission = 1,
			Rate = 3,
			Size = 0.28,
			Lifetime = NumberRange.new(1.5, 2.5),
			Speed = NumberRange.new(0.2, 0.6),
			Acceleration = Vector3.new(0, 0.8, 0),
		})
	end
	if has.Shocked or has.Aurora then
		particles(torso, {
			Color = ColorSequence.new(colorOf("Shocked")),
			LightEmission = 1,
			Rate = 8,
			Size = 0.16,
			Lifetime = NumberRange.new(0.15, 0.35),
			Speed = NumberRange.new(4, 8),
		})
	end
	if has.Rainbowshine then
		particles(torso, {
			Color = RAINBOW_SEQUENCE,
			LightEmission = 0.6,
			Rate = 4,
			Size = 0.25,
			Lifetime = NumberRange.new(1.2, 2),
			Speed = NumberRange.new(0.3, 0.8),
			Acceleration = Vector3.new(0, 1, 0),
		})
	end
	if has.Aurora then
		particles(torso, {
			Color = ColorSequence.new(colorOf("Aurora"), Color3.fromRGB(170, 120, 255)),
			LightEmission = 1,
			Rate = 3,
			Size = 0.5,
			Transparency = 0.5,
			Lifetime = NumberRange.new(2, 3),
			Speed = NumberRange.new(0.3, 0.6),
			Acceleration = Vector3.new(0, 1.2, 0),
		})
	end

	-- kleines Licht in der Farbe der stärksten Mutation (nur, wenn die Kuh noch keins hat)
	if not torso:FindFirstChildOfClass("PointLight") then
		local strongest, best = nil, 0
		for _, id in ipairs(mutations) do
			local info = CowData.CowMutations[id]
			if info and info.Multiplier > best then
				strongest, best = info, info.Multiplier
			end
		end
		if strongest and best >= 3 then
			light(torso, strongest.Color, 0.8, 9)
		end
	end
	model:SetAttribute("HasEffects", true)
end

-- Ganze Kuh um den Boden-Punkt base verkleinern (Kälber). Skaliert Teile, Gruppen-Drehpunkte,
-- Attachments, Lichter, Strahlen, Datei-Meshes und die Maße für Schemel/Eimer (BodyHalfWidth, UdderZ).
local function scaleCow(model, base, scale)
	local function scaleCFrame(cframe)
		local relative = base:ToObjectSpace(cframe)
		return base * (CFrame.new(relative.Position * scale) * relative.Rotation)
	end
	-- Drehpunkte der Gruppen (Kopf, Ohren, Schwanz) VOR dem Verschieben der Teile merken
	local pivots = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Model") then
			pivots[d] = d.WorldPivot
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Size *= scale
			d.CFrame = scaleCFrame(d.CFrame)
		elseif d:IsA("Attachment") then
			d.Position *= scale
		elseif d:IsA("Light") then
			d.Range *= scale
		elseif d:IsA("Beam") then
			d.Width0 *= scale
			d.Width1 *= scale
		elseif d:IsA("SpecialMesh") and d.MeshType == Enum.MeshType.FileMesh then
			d.Scale *= scale
		end
	end
	for group, pivot in pairs(pivots) do
		group.WorldPivot = scaleCFrame(pivot)
	end
	model.WorldPivot = base -- Drehpunkt der Kuh bleibt am Boden unter der Mitte
	for _, name in ipairs({ "BodyHalfWidth", "UdderZ" }) do
		local value = model:GetAttribute(name)
		if type(value) == "number" then
			model:SetAttribute(name, value * scale)
		end
	end
	model:SetAttribute("GrowthScale", scale)
end

-- Gibt (model, refs) zurück. Nimmt das Blender-Modell, wenn es da ist, sonst die Ersatz-Kuh.
-- scale (optional): Größe für Kälber (1 = ausgewachsen, siehe CowData.Growth)
function Builder.BuildCow(rarity, seedId, base, scale)
	local model, refs = nil, nil
	local template = getTemplate()
	if template then
		local ok, builtModel, builtRefs = pcall(buildTemplateCow, template, rarity, base)
		if ok then
			model, refs = builtModel, builtRefs
		else
			warn("[CowModelBuilder] Blender-Kuh konnte nicht gebaut werden, nehme Ersatz-Kuh:", builtModel)
		end
	end
	if not model then
		model, refs = buildProceduralCow(rarity, seedId, base)
	end
	if scale and scale ~= 1 then
		scaleCow(model, base, scale)
	end
	return model, refs
end

function Builder.HasBlenderCow()
	return getTemplate() ~= nil
end

------------------------------------------------------------------------
-- Melkschemel
------------------------------------------------------------------------
-- base: Boden-Position, LookVector = Blickrichtung des sitzenden Spielers
-- Gibt (model, seat) zurück. Der Sitz ist deaktiviert, bis gemolken wird.
function Builder.BuildStool(base)
	local model = Instance.new("Model")
	model.Name = "Stool"

	local seat = Instance.new("Seat")
	seat.Name = "Seat"
	seat.Size = Vector3.new(1.5, 0.3, 1.5)
	seat.CFrame = base * CFrame.new(0, 1.15, 0)
	seat.Color = WOOD
	seat.Material = Enum.Material.Wood
	seat.Anchored = true
	seat.CanCollide = true
	seat.Disabled = true -- niemand setzt sich aus Versehen drauf
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.BottomSurface = Enum.SurfaceType.Smooth
	seat.Parent = model

	-- 3 schräge Beine
	for i = 0, 2 do
		local angle = math.rad(i * 120 + 30)
		local legCFrame = CFrame.new(math.cos(angle) * 0.45, 0.5, math.sin(angle) * 0.45)
			* CFrame.Angles(0, -angle, 0)
			* CFrame.Angles(0, 0, math.rad(10)) -- unten nach außen gespreizt
		newPart(
			model,
			base,
			"Leg",
			Enum.PartType.Block,
			Vector3.new(0.18, 1.05, 0.18),
			legCFrame,
			DARK_WOOD,
			Enum.Material.Wood
		)
	end

	model.PrimaryPart = seat
	return model, seat
end

------------------------------------------------------------------------
-- Melkeimer (Holzdauben + Milch, die sich füllt)
------------------------------------------------------------------------
-- Gibt (model, setFill) zurück. setFill(0..1) ändert den Milchstand.
function Builder.BuildBucket(base)
	local model = Instance.new("Model")
	model.Name = "Bucket"

	local height = 0.8
	local radius = 0.5

	local bottom = newPart(
		model,
		base,
		"Bottom",
		Enum.PartType.Cylinder,
		Vector3.new(0.08, radius * 2, radius * 2),
		upright(CFrame.new(0, 0.04, 0)),
		DARK_WOOD,
		Enum.Material.Wood
	)

	-- 10 Dauben im Kreis
	local staves = 10
	for i = 0, staves - 1 do
		local angle = (i / staves) * math.pi * 2
		newPart(
			model,
			base,
			"Stave",
			Enum.PartType.Block,
			Vector3.new(0.08, height, 0.34),
			CFrame.Angles(0, angle, 0) * CFrame.new(radius, height / 2, 0),
			WOOD,
			Enum.Material.Wood
		)
	end

	-- Metallreifen
	for _, y in ipairs({ 0.18, 0.62 }) do
		for i = 0, staves - 1 do
			local angle = (i / staves) * math.pi * 2
			newPart(
				model,
				base,
				"Band",
				Enum.PartType.Block,
				Vector3.new(0.1, 0.08, 0.35),
				CFrame.Angles(0, angle, 0) * CFrame.new(radius + 0.02, y, 0),
				METAL,
				Enum.Material.Metal
			)
		end
	end

	-- Henkel
	newPart(
		model,
		base,
		"Handle",
		Enum.PartType.Block,
		Vector3.new(radius * 2 + 0.1, 0.06, 0.06),
		CFrame.new(0, height + 0.25, 0),
		METAL,
		Enum.Material.Metal
	)

	-- Milch
	local milk = newPart(
		model,
		base,
		"Milk",
		Enum.PartType.Cylinder,
		Vector3.new(0.05, radius * 2 - 0.12, radius * 2 - 0.12),
		upright(CFrame.new(0, 0.1, 0)),
		MILK,
		Enum.Material.SmoothPlastic
	)
	milk.Transparency = 1

	local maxHeight = height - 0.15
	local function setFill(ratio)
		ratio = math.clamp(ratio, 0, 1)
		if ratio <= 0 then
			milk.Transparency = 1
			return
		end
		local h = maxHeight * ratio
		milk.Transparency = 0
		milk.Size = Vector3.new(h, milk.Size.Y, milk.Size.Z)
		milk.CFrame = base * upright(CFrame.new(0, 0.08 + h / 2, 0))
	end

	model.PrimaryPart = bottom
	return model, setFill
end

------------------------------------------------------------------------
-- Milch-Eimer zum Tragen (der Eimer aus der Hotbar in der Hand)
-- Gleicher Holz-Stil wie der Melkeimer oben, aber VOLL und:
--   Größe   nach Litern (CowData.GetBucketScale: klein 0,8 ... riesig 2,2)
--   Milch   Farbe der wertvollsten Mutation (ab x20 leuchtend, Eis glänzt)
--   Reifen  ein Reifen pro Mutation in ihrer Farbe (ohne Mutation: Metall)
--   Dauben  Holz; die wertvollste "besondere" Mutation färbt den ganzen Eimer:
--           Blitz = dunkles Metall, Regenbogen = bunte Dauben, Sterne = nachtblau,
--           Gold = goldener Eimer, Eis = Eis-Eimer, Schoko = dunkles Holz
--   Extras  Sahne-Häubchen, Erdbeere, Schokostück obendrauf
--   Effekte Partikel/Licht ab x2 (Frisch: Tropfen) bzw. ab x8 (Eis, Gold, Sterne, Regenbogen, Blitz)
------------------------------------------------------------------------
local RAINBOW_COLORS = {
	Color3.fromRGB(246, 128, 128),
	Color3.fromRGB(246, 178, 104),
	Color3.fromRGB(240, 224, 124),
	Color3.fromRGB(132, 208, 144),
	Color3.fromRGB(124, 182, 244),
	Color3.fromRGB(186, 144, 240),
}

-- Aussehen der Dauben je Mutation (die wertvollste mit Eintrag gewinnt)
local STAVE_THEMES = {
	Shocked = { Color = Color3.fromRGB(70, 74, 88), Material = Enum.Material.Metal },
	Prism = { Rainbow = true, Material = Enum.Material.SmoothPlastic },
	Starry = { Color = Color3.fromRGB(42, 46, 96), Material = Enum.Material.SmoothPlastic },
	Gold = { Color = Color3.fromRGB(240, 190, 60), Material = Enum.Material.Metal, Reflectance = 0.25 },
	Frozen = { Color = Color3.fromRGB(184, 226, 250), Material = Enum.Material.Ice },
	Choco = { Color = Color3.fromRGB(96, 60, 38), Material = Enum.Material.Wood },
}

-- Partikel je Mutation (am Milch-Spiegel)
local function addBucketEffects(milkPart, has, scale)
	local size = 0.18 * scale
	if has.Shocked then
		light(milkPart, Color3.fromRGB(255, 240, 120), 1.6, 8 * scale)
		particles(milkPart, {
			Color = ColorSequence.new(Color3.fromRGB(255, 244, 120)),
			LightEmission = 1,
			Rate = 14,
			Size = size,
			Lifetime = NumberRange.new(0.15, 0.35),
			Speed = NumberRange.new(4, 8),
		})
	end
	if has.Prism then
		light(milkPart, Color3.fromRGB(255, 160, 220), 1, 7 * scale)
		particles(milkPart, {
			Color = RAINBOW_SEQUENCE,
			LightEmission = 0.6,
			Rate = 6,
			Size = size,
			Speed = NumberRange.new(0.5, 1.2),
			Acceleration = Vector3.new(0, 1.5, 0),
		})
	end
	if has.Starry then
		light(milkPart, Color3.fromRGB(200, 180, 255), 1, 7 * scale)
		particles(milkPart, {
			Color = ColorSequence.new(Color3.fromRGB(255, 244, 210), Color3.fromRGB(190, 170, 255)),
			LightEmission = 1,
			Rate = 5,
			Size = size * 1.3,
			Lifetime = NumberRange.new(1.2, 2),
			Speed = NumberRange.new(0.3, 0.8),
			Acceleration = Vector3.new(0, 1, 0),
		})
	end
	if has.Gold then
		light(milkPart, Color3.fromRGB(255, 205, 70), 1, 7 * scale)
		particles(milkPart, {
			Color = ColorSequence.new(Color3.fromRGB(255, 215, 90)),
			LightEmission = 0.8,
			Rate = 5,
			Size = size,
			Speed = NumberRange.new(0.6, 1.4),
			Acceleration = Vector3.new(0, 1.2, 0),
		})
	end
	if has.Frozen then
		particles(milkPart, {
			Color = ColorSequence.new(Color3.fromRGB(235, 248, 255)),
			LightEmission = 0.4,
			Rate = 5,
			Size = size,
			Lifetime = NumberRange.new(1.2, 2),
			Speed = NumberRange.new(0.2, 0.6),
			Acceleration = Vector3.new(0, -1, 0),
		})
	end
	if has.Fresh then
		-- Regentropfen, die außen herunterlaufen
		particles(milkPart, {
			Color = ColorSequence.new(Color3.fromRGB(150, 210, 255)),
			Transparency = 0.2,
			Rate = 4,
			Size = size * 0.7,
			Lifetime = NumberRange.new(0.5, 0.8),
			Speed = NumberRange.new(1, 2),
			Spread = Vector2.new(60, 60),
			Acceleration = Vector3.new(0, -14, 0),
		})
	end
end

-- liters = Liter im Eimer, mutations = Liste (wertvollste zuerst), base = wohin (Standard: Ursprung)
-- Gibt das Modell zurück. PrimaryPart = "Grip" (unsichtbar, oben am Henkel – dort hält die Hand).
-- Alle Teile sind verankert (Anchored); zum Tragen schweißt der Server sie zusammen.
function Builder.BuildMilkBucket(liters, mutations, base)
	base = base or CFrame.new()
	mutations = mutations or {}
	local scale = CowData.GetBucketScale(liters)
	local has = {}
	for _, milkType in ipairs(mutations) do
		has[milkType] = true
	end
	local topInfo = CowData.MilkTypes[mutations[1] or "Normal"] or CowData.MilkTypes.Normal

	local theme = nil
	for _, milkType in ipairs(mutations) do
		if STAVE_THEMES[milkType] then
			theme = STAVE_THEMES[milkType]
			break
		end
	end

	local model = Instance.new("Model")
	model.Name = "MilkBucket"
	model:SetAttribute("Liters", liters)
	model:SetAttribute("Mutations", table.concat(mutations, ","))

	local radius = 0.55 * scale
	local height = 1.0 * scale
	local wall = 0.1 * scale

	-- Boden
	newPart(
		model,
		base,
		"Bottom",
		Enum.PartType.Cylinder,
		Vector3.new(wall, radius * 2, radius * 2),
		upright(CFrame.new(0, wall / 2, 0)),
		theme and theme.Color or DARK_WOOD,
		theme and theme.Material or Enum.Material.Wood
	)

	-- Dauben im Kreis
	local staves = 10
	local staveWidth = 2 * math.pi * radius / staves * 1.08
	for i = 0, staves - 1 do
		local angle = (i / staves) * math.pi * 2
		local color = WOOD
		local material = Enum.Material.Wood
		if theme then
			color = theme.Rainbow and RAINBOW_COLORS[i % #RAINBOW_COLORS + 1] or theme.Color
			material = theme.Material
		end
		local stave = newPart(
			model,
			base,
			"Stave",
			Enum.PartType.Block,
			Vector3.new(wall, height, staveWidth),
			CFrame.Angles(0, angle, 0) * CFrame.new(radius, height / 2, 0),
			color,
			material
		)
		stave.Reflectance = theme and theme.Reflectance or 0
	end

	-- Reifen: einer pro Mutation (max. 3), sonst zwei aus Metall.
	-- Ein flacher Zylinder um den Eimer – innen sieht man ihn nicht, weil der Eimer voll ist.
	local bandCount = math.clamp(#mutations, 2, 3)
	for i = 1, bandCount do
		local y = height * (bandCount == 2 and (i == 1 and 0.22 or 0.74) or (0.18 + (i - 1) * 0.28))
		local milkType = mutations[i]
		local info = milkType and CowData.MilkTypes[milkType]
		newPart(
			model,
			base,
			"Band",
			Enum.PartType.Cylinder,
			Vector3.new(0.1 * scale, radius * 2 + wall * 1.8, radius * 2 + wall * 1.8),
			upright(CFrame.new(0, y, 0)),
			info and info.Color or METAL,
			info and Enum.Material.SmoothPlastic or Enum.Material.Metal
		)
	end

	-- Milch (fast bis zum Rand)
	local milkMaterial = Enum.Material.SmoothPlastic
	if topInfo.Multiplier >= 20 then
		milkMaterial = Enum.Material.Neon
	elseif mutations[1] == "Frozen" then
		milkMaterial = Enum.Material.Ice
	end
	local milk = newPart(
		model,
		base,
		"Milk",
		Enum.PartType.Cylinder,
		Vector3.new(0.06 * scale, radius * 2 - wall * 1.2, radius * 2 - wall * 1.2),
		upright(CFrame.new(0, height - 0.1 * scale, 0)),
		mutations[1] and topInfo.Color or MILK,
		milkMaterial
	)

	-- Henkel: Bogen aus kurzen Stücken über der Öffnung
	local arcRadius = radius + wall * 0.3
	local arcHeight = 0.85
	local segments = 7
	local function arcPoint(t)
		local theta = math.pi * t
		return Vector3.new(arcRadius * math.cos(theta), height + arcRadius * arcHeight * math.sin(theta), 0)
	end
	for i = 0, segments - 1 do
		local a, b = arcPoint(i / segments), arcPoint((i + 1) / segments)
		newPart(
			model,
			base,
			"Handle",
			Enum.PartType.Block,
			Vector3.new(0.07 * scale, 0.07 * scale, (b - a).Magnitude + 0.02 * scale),
			CFrame.lookAt((a + b) / 2, b),
			METAL,
			Enum.Material.Metal
		)
	end
	for _, side in ipairs({ -1, 1 }) do
		newPart(
			model,
			base,
			"HandleMount",
			Enum.PartType.Block,
			Vector3.new(0.08 * scale, 0.16 * scale, 0.14 * scale),
			CFrame.new(side * (radius + wall * 0.4), height - 0.04 * scale, 0),
			METAL,
			Enum.Material.Metal
		)
	end

	-- Extras obendrauf
	local surfaceY = height - 0.06 * scale
	if has.Creamy then
		newPart(
			model,
			base,
			"Cream",
			Enum.PartType.Ball,
			Vector3.new(0.34, 0.34, 0.34) * scale,
			CFrame.new(radius * 0.3, surfaceY + 0.08 * scale, radius * 0.25),
			Color3.fromRGB(255, 250, 238),
			Enum.Material.SmoothPlastic
		)
	end
	if has.Berry then
		newPart(
			model,
			base,
			"Strawberry",
			Enum.PartType.Ball,
			Vector3.new(0.26, 0.26, 0.26) * scale,
			CFrame.new(-radius * 0.35, surfaceY + 0.08 * scale, -radius * 0.2),
			Color3.fromRGB(220, 50, 70),
			Enum.Material.SmoothPlastic
		)
		newPart(
			model,
			base,
			"StrawberryLeaf",
			Enum.PartType.Block,
			Vector3.new(0.16, 0.04, 0.16) * scale,
			CFrame.new(-radius * 0.35, surfaceY + 0.22 * scale, -radius * 0.2) * CFrame.Angles(0, math.rad(45), 0),
			Color3.fromRGB(80, 170, 80),
			Enum.Material.SmoothPlastic
		)
	end
	if has.Choco then
		newPart(
			model,
			base,
			"ChocoPiece",
			Enum.PartType.Block,
			Vector3.new(0.3, 0.07, 0.22) * scale,
			CFrame.new(radius * 0.15, surfaceY + 0.05 * scale, -radius * 0.4)
				* CFrame.Angles(math.rad(12), math.rad(30), 0),
			Color3.fromRGB(92, 56, 36),
			Enum.Material.SmoothPlastic
		)
	end

	addBucketEffects(milk, has, scale)

	-- Griff (unsichtbar) oben am Henkel
	local grip = newPart(
		model,
		base,
		"Grip",
		Enum.PartType.Block,
		Vector3.new(0.2, 0.2, 0.2),
		CFrame.new(arcPoint(0.5)),
		METAL,
		Enum.Material.SmoothPlastic
	)
	grip.Transparency = 1
	grip.CastShadow = false
	model.PrimaryPart = grip
	return model
end

return Builder
