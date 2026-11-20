-- ToolModelBuilder.lua (ModuleScript, Server UND Client)
-- Baut die Werkzeuge für den Werkzeug-Shop und den Werkzeug-Schuppen aus den Blender-Teilen
-- in ReplicatedStorage.Assets.ToolParts (erzeugt von tools/make_tools.py, Maße in ToolMeshData.lua).
-- Fehlt das Modell oder passt ein Teil nicht, entstehen einfache Ersatz-Blöcke – das Spiel läuft trotzdem.
--
-- Benutzung:
--   local ToolModelBuilder = require(ReplicatedStorage.Shared.ToolModelBuilder)
--   local model = ToolModelBuilder.Build("Kuhglocke", CFrame.new(x, bodenY, z))
--   model.Parent = workspace
--
-- Arten: "Futtereimer", "Kuhglocke", "Buerste", "Schuppen"
-- Ursprung = Boden-Mitte (PrimaryPart "Root", unsichtbar). Der Schuppen hat die Tür vorne (-Z der base).
-- Für Animationen (WorldAnimator): Teil "Buerste_Rolle" kann sich um seine Y-Achse drehen,
-- "Glocke" pendeln. Das Schild am Schuppen beschriftet ToolModelBuilder.SetSign(model, text).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(script.Parent:WaitForChild("Palette"))
local ToolMeshData = require(script.Parent:WaitForChild("ToolMeshData"))

local Builder = {}

local World = Palette.World
local M = Enum.Material

-- Drehung je Werkzeug, damit "vorne" überall -Z ist (wie bei den Shop-Gebäuden).
-- Der Schuppen ist in Blender mit der Tür nach +Z gebaut -> umdrehen.
local YAW = { Schuppen = math.pi }

-- Farbe, Material und Kollision je Teil
local STYLE = {
	Futtereimer = { Color = Color3.fromRGB(170, 176, 184), Material = M.Metal },
	Futter = { Color = Color3.fromRGB(214, 170, 92), Material = M.SmoothPlastic },
	Glocke_Pfosten = { Color = World.Wood, Material = M.Wood },
	Glocke_Band = { Color = Color3.fromRGB(170, 50, 40), Material = M.SmoothPlastic },
	Glocke = { Color = Color3.fromRGB(222, 176, 64), Material = M.Metal, Reflectance = 0.2 },
	Buersten_Pfosten = { Color = World.Wood, Material = M.Wood },
	Buersten_Halter = { Color = Color3.fromRGB(90, 96, 106), Material = M.Metal },
	Buerste_Rolle = { Color = Color3.fromRGB(54, 120, 200), Material = M.Fabric },
	Schuppen_Wand = { Color = World.Wood, Material = M.Wood, Collide = true },
	Schuppen_Dach = { Color = Color3.fromRGB(170, 60, 48), Material = M.SmoothPlastic, Collide = true },
	Schuppen_Rahmen = { Color = World.Fence, Material = M.SmoothPlastic, Collide = true },
	Schuppen_Tuer = { Color = Color3.fromRGB(64, 116, 72), Material = M.Wood, Collide = true },
	Schuppen_Glas = { Color = Color3.fromRGB(170, 214, 240), Material = M.Glass, Transparency = 0.3 },
	Schuppen_Schild = { Color = World.WoodLight, Material = M.Wood, Collide = true },
}

------------------------------------------------------------------------
-- Vorlage prüfen (einmal)
------------------------------------------------------------------------
local template = nil -- nil = noch nicht geprüft, false = nicht benutzbar

local function getTemplate()
	if template ~= nil then
		return template or nil
	end
	template = false
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("ToolParts")
	if not folder then
		return nil
	end
	for name, data in pairs(ToolMeshData.Parts) do
		local part = folder:FindFirstChild(name, true)
		if not (part and part:IsA("MeshPart")) then
			warn(
				"[ToolModelBuilder] ToolParts: Teil fehlt oder ist kein MeshPart: "
					.. name
					.. " – nehme Ersatz-Blöcke"
			)
			return nil
		end
		-- Seitenverhältnis prüfen (falls der Importer das Teil gedreht hat)
		local a = part.Size / part.Size.Magnitude
		local b = data.Size / data.Size.Magnitude
		if (a - b).Magnitude > 0.05 then
			warn("[ToolModelBuilder] ToolParts: " .. name .. " hat falsche Maße/Drehung – nehme Ersatz-Blöcke")
			return nil
		end
	end
	template = folder
	return folder
end

-- true, wenn die Blender-Modelle benutzt werden (sonst Ersatz-Blöcke)
function Builder.HasModels()
	return getTemplate() ~= nil
end

------------------------------------------------------------------------
-- Bauen
------------------------------------------------------------------------
-- kind = "Futtereimer" | "Kuhglocke" | "Buerste" | "Schuppen"
-- base = CFrame der Boden-Mitte, scale = Zahl (Standard 1)
-- Gibt das Modell zurück (noch ohne Parent) oder nil bei unbekannter Art.
function Builder.Build(kind, base, scale)
	local names = ToolMeshData.Tools[kind]
	if not names then
		warn("[ToolModelBuilder] unbekanntes Werkzeug: " .. tostring(kind))
		return nil
	end
	base = base or CFrame.new()
	scale = scale or 1
	local placed = base * CFrame.Angles(0, YAW[kind] or 0, 0)
	local source = getTemplate()

	local model = Instance.new("Model")
	model.Name = kind
	model:SetAttribute("ToolKind", kind)

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.4, 0.4, 0.4)
	root.CFrame = base
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model

	for _, name in ipairs(names) do
		local data = ToolMeshData.Parts[name]
		local style = STYLE[name] or {}
		local part
		if source then
			part = source:FindFirstChild(name, true):Clone()
			part.TextureID = ""
		else
			part = Instance.new("Part") -- Ersatz: einfacher Block in der Größe des Teils
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
		end
		part.Name = name
		part.Size = data.Size * scale
		part.CFrame = placed * CFrame.new(data.Center * scale)
		part.Color = style.Color or World.Wood
		part.Material = style.Material or Enum.Material.SmoothPlastic
		part.Reflectance = style.Reflectance or 0
		part.Transparency = style.Transparency or 0
		part.Anchored = true
		part.CanCollide = style.Collide == true
		part.CastShadow = style.Transparency == nil
		part.Parent = model
	end

	model.PrimaryPart = root
	return model
end

-- Schreibt Text auf das Holzschild über der Schuppen-Tür (Vorderseite = -Z der base)
function Builder.SetSign(model, text)
	local board = model:FindFirstChild("Schuppen_Schild")
	if not board then
		return nil
	end
	local gui = board:FindFirstChild("SignGui") or Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	-- das Schild ist (wie der ganze Schuppen) um 180 Grad gedreht: seine Rückseite zeigt nach vorne
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.3
	gui.Parent = board
	local label = gui:FindFirstChild("Text") or Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Palette.Fonts.Heading
	label.TextScaled = true
	label.TextColor3 = Palette.Colors.Cream
	label.Text = text
	label.Parent = gui
	local stroke = label:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.Color = Palette.Colors.Outline
	stroke.Thickness = 3
	stroke.Parent = label
	return gui
end

return Builder
