-- CowManager.server.lua
-- Alles rund um die Kühe:
--   * eingezäunter Farm-Plot pro Spieler links/rechts der Allee (Workspace.CowFarmLayout.Plots)
--   * prozedurale Kuh-Modelle mit Schemel + Eimer daneben
--   * Melk-Minispiel: Kuh anklicken ODER auf die leuchtende Melk-Platte neben der Kuh laufen
--     -> Teleport auf den Schemel -> abwechselnd L/R ziehen
--   * Melk-Cooldown pro Kuh
--   * Milch verkaufen, Shop, Kisten (Coins/Robux), Breeding, Auto-Melker, ProcessReceipt
--   * Raster auf jeder Farm, Kühe aufheben / in Hotbar oder Inventar legen / neu platzieren
--   * Teleport zu den Häusern (aus der Übersicht)
-- Idle-Animationen & Regenbogen-Farben laufen auf dem Client (WorldAnimator.client.lua).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CowData = require(Shared:WaitForChild("CowData"))
local CowModelBuilder = require(Shared:WaitForChild("CowModelBuilder"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Config = CowData.Config
local Map = CowData.Map
local Palette = require(Shared:WaitForChild("Palette"))
local World = Palette.World
local rng = Random.new()

local sellMilk -- weiter unten definiert (wird vom Milch-Stand benutzt)

------------------------------------------------------------------------
-- Hilfsfunktionen
------------------------------------------------------------------------
local lastCall = {} -- [player][key] = os.clock()

-- Schutz gegen Spam von Remote-Aufrufen
local function debounce(player, key, cooldown)
	lastCall[player] = lastCall[player] or {}
	local now = os.clock()
	local last = lastCall[player][key]
	if last and now - last < cooldown then
		return false
	end
	lastCall[player][key] = now
	return true
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function announceNewCow(player, cow, source)
	local info = CowData.Rarities[cow.Rarity]
	local kind = info.Tier >= 4 and "rare" or "success"
	DataService.Notify(player, ("%s: %s (%s) ist jetzt auf deiner Farm!"):format(source, cow.Name, info.DisplayName), kind)

	-- Legendary und Special-Kühe werden allen Spielern angekündigt
	if info.Tier >= 5 then
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				DataService.Notify(other, ("🎉 %s hat eine %s-Kuh bekommen!"):format(player.DisplayName, info.DisplayName), "rare")
			end
		end
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

------------------------------------------------------------------------
-- Farm-Plots
-- Lokale Plot-Koordinaten: Tor bei +Z (zeigt zur Allee), Kühe Richtung -Z.
------------------------------------------------------------------------
local GROUND = Map.GroundTop
local PLOT_WIDTH = Map.PlotWidth -- lokal X (entlang der Allee)
local PLOT_DEPTH = Map.PlotDepth -- lokal Z (von der Allee weg)
local GATE_WIDTH = 10

local GRID_CELLS = CowData.GetGridCellCount() -- Felder pro Farm (6 x 6 = 36)
local HOTBAR_SIZE = Config.HotbarSize
local COW_OFFSET_X = 1.8 -- Kuh steht im Feld etwas rechts, links ist Platz für Schemel + Melk-Platte

local GRASS_LIGHT = World.GrassLight
local GRASS_DARK = World.GrassDark
local CURB = World.Stone
local FENCE_WHITE = World.Fence
local PATH = World.StonePath
local HAY = World.Hay

local layoutFolder = workspace:FindFirstChild("CowFarmLayout")
if not layoutFolder then
	layoutFolder = Instance.new("Folder")
	layoutFolder.Name = "CowFarmLayout"
	layoutFolder.Parent = workspace
end
local plotsFolder = layoutFolder:FindFirstChild("Plots")
if not plotsFolder then
	plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = layoutFolder
end

-- farms[player] = {
--   Slot, Model, CowsFolder, Origin, SpawnCFrame,
--   Spots = { [cowId] = { Model, Cow, Torso, Stool, Seat, Bucket, SetFill, Status } }
-- }
local farms = {}
local usedSlots = {}

local function getFreeSlot()
	local slot = 1
	while usedSlots[slot] do
		slot += 1
	end
	usedSlots[slot] = true
	return slot
end

-- Lage der Plots steht in CowData (der Client braucht sie auch für die Übersichtskarte)
local getPlotOrigin = CowData.GetPlotOrigin

-- Zaun: Pfosten alle ~6 Studs + 2 durchgehende Latten (ohne Pfostenkappen, spart Teile)
local function buildFenceLine(parent, origin, from, to)
	local delta = to - from
	local length = delta.Magnitude
	if length < 0.5 then
		return
	end
	local direction = delta.Unit
	local posts = math.max(1, math.floor(length / 6 + 0.5))
	for i = 0, posts do
		local position = from + direction * (length * i / posts)
		makePart({
			Name = "Post",
			Size = Vector3.new(0.6, 3.4, 0.6),
			CFrame = origin * CFrame.new(position + Vector3.new(0, GROUND + 1.7, 0)),
			Color = FENCE_WHITE,
			Material = Enum.Material.Wood,
			Parent = parent,
		})
	end
	local middle = from + delta / 2
	local lookAt = CFrame.lookAt(middle, middle + direction)
	for _, height in ipairs({ 1.3, 2.7 }) do
		makePart({
			Name = "Rail",
			Size = Vector3.new(0.22, 0.4, length),
			CFrame = origin * (lookAt + Vector3.new(0, GROUND + height, 0)),
			Color = FENCE_WHITE,
			Material = Enum.Material.Wood,
			Parent = parent,
		})
	end
end

-- kleine Deko-Teile: nie im Weg (CanCollide = false)
local function decorPart(parent, name, size, cframe, color, material, extra)
	local part = makePart({
		Name = name,
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		Parent = parent,
	})
	if extra then
		for key, value in pairs(extra) do
			part[key] = value
		end
	end
	return part
end

-- Blumenbeet am Eingang: Steinrand, Erde, Grün und wenige bunte Blüten
local function buildFarmFlowers(parent, origin, localCenter, sizeX, sizeZ, seed)
	local flowerRng = Random.new(seed)
	local at = function(x, y, z)
		return origin * CFrame.new(localCenter + Vector3.new(x, y, z))
	end
	decorPart(parent, "BedBorder", Vector3.new(sizeX + 0.8, 0.5, sizeZ + 0.8), at(0, GROUND + 0.25, 0), World.StoneDark, Enum.Material.Cobblestone)
	decorPart(parent, "BedSoil", Vector3.new(sizeX, 0.7, sizeZ), at(0, GROUND + 0.35, 0), World.Soil, Enum.Material.Ground)
	decorPart(parent, "BedGreen", Vector3.new(sizeX - 0.6, 0.7, sizeZ - 0.6), at(0, GROUND + 0.7, 0), World.Leaf, Enum.Material.Grass)
	for _ = 1, 6 do
		decorPart(parent, "Flower", Vector3.new(0.7, 0.7, 0.7),
			at(flowerRng:NextNumber(-sizeX / 2 + 0.6, sizeX / 2 - 0.6), GROUND + 1.2, flowerRng:NextNumber(-sizeZ / 2 + 0.6, sizeZ / 2 - 0.6)),
			World.Flowers[flowerRng:NextInteger(1, #World.Flowers)], Enum.Material.SmoothPlastic,
			{ Shape = Enum.PartType.Ball, CastShadow = false })
	end
end

-- Milch-Verkaufsstation: Holzpodest, Theke mit Preistafel, Kasse, Kannen, grün-cremefarbenes Dach
-- und ein großes Schild. ProximityPrompt (F) am Tresen.
-- base: Boden-Position, -Z = Kundenseite
local function buildSellStand(player, parent, base)
	local stand = Instance.new("Model")
	stand.Name = "MilkStand"

	local function standPart(name, size, offset, color, material, shape)
		return makePart({
			Name = name,
			Size = size,
			Shape = shape or Enum.PartType.Block,
			CFrame = base * offset,
			Color = color,
			Material = material or Enum.Material.Wood,
			Parent = stand,
		})
	end

	-- Podest, damit die Station als Einheit wirkt
	standPart("Deck", Vector3.new(8, 0.3, 5), CFrame.new(0, 0.15, 0.2), World.WoodLight, Enum.Material.WoodPlanks)

	local counter = standPart("Counter", Vector3.new(6, 3, 2.4), CFrame.new(0, 1.8, 0), World.Wood)
	standPart("CounterTop", Vector3.new(6.4, 0.3, 2.8), CFrame.new(0, 3.45, 0), World.WoodLight)
	for _, x in ipairs({ -2.9, 2.9 }) do
		standPart("Post", Vector3.new(0.4, 4.6, 0.4), CFrame.new(x, 5.6, 1.0), World.WoodDark)
	end
	standPart("BackPanel", Vector3.new(6, 3.4, 0.3), CFrame.new(0, 5.6, 1.9), World.WoodDark)

	-- gestreiftes Dach in Grün und Creme
	for i = 0, 6 do
		local stripeColor = i % 2 == 0 and Palette.Colors.Green or Palette.Colors.Cream
		standPart("Roof", Vector3.new(1, 0.35, 3.8), CFrame.new(-3 + i, 8.1, 0.2) * CFrame.Angles(math.rad(-12), 0, 0),
			stripeColor, Enum.Material.Fabric)
	end

	-- großes Schild unter dem Dach (Creme auf dunklem Holz)
	local sign = standPart("Sign", Vector3.new(5.6, 1.4, 0.3), CFrame.new(0, 6.9, -1.4), World.WoodDark)
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 60
	surface.LightInfluence = 0.2
	surface.Parent = sign
	local signText = Instance.new("TextLabel")
	signText.Size = UDim2.fromScale(1, 1)
	signText.BackgroundTransparency = 1
	signText.Font = Palette.Fonts.Heading
	signText.TextScaled = true
	signText.TextColor3 = Palette.Colors.Cream
	signText.Text = "🥛 MILCH-VERKAUF"
	signText.Parent = surface
	local signPadding = Instance.new("UIPadding")
	signPadding.PaddingLeft = UDim.new(0.05, 0)
	signPadding.PaddingRight = UDim.new(0.05, 0)
	signPadding.PaddingTop = UDim.new(0.14, 0)
	signPadding.PaddingBottom = UDim.new(0.14, 0)
	signPadding.Parent = signText

	-- Preistafel an der Theke (Gold nur für die Coins)
	local board = standPart("PriceBoard", Vector3.new(4.4, 1.5, 0.15), CFrame.new(0, 1.8, -1.28), Palette.Colors.Deep, Enum.Material.SmoothPlastic)
	local boardSurface = Instance.new("SurfaceGui")
	boardSurface.Face = Enum.NormalId.Front
	boardSurface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	boardSurface.PixelsPerStud = 60
	boardSurface.LightInfluence = 0.2
	boardSurface.Parent = board
	local boardText = Instance.new("TextLabel")
	boardText.Size = UDim2.fromScale(1, 1)
	boardText.BackgroundTransparency = 1
	boardText.Font = Palette.Fonts.Body
	boardText.TextScaled = true
	boardText.RichText = true
	boardText.TextColor3 = Palette.Colors.Cream
	boardText.Text = ('1 Milch = <font color="rgb(244,192,64)">%s Coins</font>'):format(CowData.FormatNumber(Config.MilkSellPrice))
	boardText.Parent = boardSurface
	local boardPadding = Instance.new("UIPadding")
	boardPadding.PaddingLeft = UDim.new(0.06, 0)
	boardPadding.PaddingRight = UDim.new(0.06, 0)
	boardPadding.PaddingTop = UDim.new(0.2, 0)
	boardPadding.PaddingBottom = UDim.new(0.2, 0)
	boardPadding.Parent = boardText

	-- Milchkannen auf der Theke
	for i, x in ipairs({ -2.2, -1.3, 1.2 }) do
		local height = i == 2 and 1.0 or 1.3
		standPart("MilkCan", Vector3.new(height, 0.7, 0.7),
			CFrame.new(x, 3.6 + height / 2, 0.3) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(200, 205, 212), Enum.Material.Metal, Enum.PartType.Cylinder)
		standPart("MilkCanLid", Vector3.new(0.12, 0.5, 0.5),
			CFrame.new(x, 3.6 + height + 0.06, 0.3) * CFrame.Angles(0, 0, math.rad(90)),
			Palette.Colors.Cream, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end

	-- Kasse mit Goldmünzen (Gold = Coins)
	standPart("CashBox", Vector3.new(1.2, 0.7, 0.9), CFrame.new(2.3, 3.8, -0.2), World.WoodDark)
	for k = 0, 2 do
		standPart("Coin", Vector3.new(0.12, 0.55, 0.55), CFrame.new(2.3, 4.2 + k * 0.13, -0.2) * CFrame.Angles(0, 0, math.rad(90)),
			Palette.Colors.Gold, Enum.Material.Metal, Enum.PartType.Cylinder)
	end

	-- zwei Kisten daneben
	for _, offset in ipairs({ Vector3.new(-4.6, 0.95, -0.2), Vector3.new(-4.6, 2.7, -0.2) }) do
		standPart("Crate", Vector3.new(1.7, 1.7, 1.7), CFrame.new(offset), World.WoodLight, Enum.Material.WoodPlanks)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Milch verkaufen"
	prompt.ObjectText = "Milch-Stand"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter

	-- aktuelle Milchmenge im Prompt anzeigen
	local function updatePrompt()
		local milk = player:GetAttribute("Milk") or 0
		prompt.ObjectText = ("Milch-Stand · %s Milch = %s Coins"):format(
			CowData.FormatNumber(milk),
			CowData.FormatNumber(math.floor(milk * Config.MilkSellPrice))
		)
	end
	updatePrompt()
	local connection = player:GetAttributeChangedSignal("Milk"):Connect(updatePrompt)
	stand.Destroying:Connect(function()
		connection:Disconnect()
	end)

	prompt.Triggered:Connect(function(who)
		if who ~= player then
			DataService.Notify(who, "Das ist nicht dein Milch-Stand!", "error")
			return
		end
		sellMilk(player, counter)
	end)

	stand.Parent = parent
	return stand
end

local function getFarm(player)
	if farms[player] then
		return farms[player]
	end

	local slot = getFreeSlot()
	local origin = getPlotOrigin(slot)
	local halfW, halfD = PLOT_WIDTH / 2, PLOT_DEPTH / 2

	local model = Instance.new("Model")
	model.Name = "Plot_" .. player.Name
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("Slot", slot)

	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = model

	local cowsFolder = Instance.new("Folder")
	cowsFolder.Name = "Cows"
	cowsFolder.Parent = model

	-- Wiese in gemähten Streifen (abwechselnd hell/dunkel)
	local stripes = 6
	local stripeWidth = PLOT_WIDTH / stripes
	for i = 0, stripes - 1 do
		makePart({
			Name = "Ground",
			Size = Vector3.new(stripeWidth, GROUND, PLOT_DEPTH),
			CFrame = origin * CFrame.new(-halfW + stripeWidth * (i + 0.5), GROUND / 2, 0),
			Color = i % 2 == 0 and GRASS_LIGHT or GRASS_DARK,
			Material = Enum.Material.Grass,
			Parent = decor,
		})
	end

	-- Steinkante rundherum (vorne mit Lücke fürs Tor)
	local curbHeight = GROUND + 0.2
	local function curb(size, position)
		makePart({
			Name = "Curb",
			Size = size,
			CFrame = origin * CFrame.new(position),
			Color = CURB,
			Material = Enum.Material.Concrete,
			Parent = decor,
		})
	end
	curb(Vector3.new(PLOT_WIDTH + 2, curbHeight, 1), Vector3.new(0, curbHeight / 2, -halfD - 0.5))
	curb(Vector3.new(1, curbHeight, PLOT_DEPTH + 2), Vector3.new(-halfW - 0.5, curbHeight / 2, 0))
	curb(Vector3.new(1, curbHeight, PLOT_DEPTH + 2), Vector3.new(halfW + 0.5, curbHeight / 2, 0))
	local frontPiece = (PLOT_WIDTH - GATE_WIDTH) / 2 + 1
	curb(Vector3.new(frontPiece, curbHeight, 1), Vector3.new(-halfW - 1 + frontPiece / 2, curbHeight / 2, halfD + 0.5))
	curb(Vector3.new(frontPiece, curbHeight, 1), Vector3.new(halfW + 1 - frontPiece / 2, curbHeight / 2, halfD + 0.5))

	-- Weißer Zaun, 1 Stud nach innen versetzt, mit Tor vorne (+Z)
	local fx, fz = halfW - 1, halfD - 1
	buildFenceLine(decor, origin, Vector3.new(-fx, 0, -fz), Vector3.new(fx, 0, -fz))
	buildFenceLine(decor, origin, Vector3.new(-fx, 0, -fz), Vector3.new(-fx, 0, fz))
	buildFenceLine(decor, origin, Vector3.new(fx, 0, -fz), Vector3.new(fx, 0, fz))
	buildFenceLine(decor, origin, Vector3.new(-fx, 0, fz), Vector3.new(-GATE_WIDTH / 2, 0, fz))
	buildFenceLine(decor, origin, Vector3.new(GATE_WIDTH / 2, 0, fz), Vector3.new(fx, 0, fz))

	-- Torbogen mit Namensschild (Creme auf dunklem Holz), Laternen auf den Pfosten
	for _, x in ipairs({ -GATE_WIDTH / 2, GATE_WIDTH / 2 }) do
		makePart({
			Name = "GatePost",
			Size = Vector3.new(1.2, 8.4, 1.2),
			CFrame = origin * CFrame.new(x, GROUND + 4.2, fz),
			Color = World.WoodDark,
			Material = Enum.Material.Wood,
			Parent = decor,
		})
		decorPart(decor, "GateCap", Vector3.new(1.7, 0.3, 1.7), origin * CFrame.new(x, GROUND + 8.55, fz), Color3.fromRGB(52, 54, 62), Enum.Material.Metal)
		decorPart(decor, "GateLamp", Vector3.new(1.1, 1.3, 1.1), origin * CFrame.new(x, GROUND + 9.2, fz), World.Lantern)
	end
	makePart({
		Name = "GateBeam",
		Size = Vector3.new(GATE_WIDTH + 2.4, 0.9, 1),
		CFrame = origin * CFrame.new(0, GROUND + 8.1, fz),
		Color = World.Wood,
		Material = Enum.Material.Wood,
		Parent = decor,
	})
	for _, x in ipairs({ -3, 3 }) do
		decorPart(decor, "GateStrut", Vector3.new(0.5, 0.4, 0.5), origin * CFrame.new(x, GROUND + 8.7, fz), World.WoodDark, Enum.Material.Wood)
	end
	local sign = makePart({
		Name = "Sign",
		Size = Vector3.new(GATE_WIDTH - 2, 2.4, 0.4),
		CFrame = origin * CFrame.new(0, GROUND + 10, fz),
		Color = World.WoodDark,
		Material = Enum.Material.Wood,
		Parent = decor,
	})
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
		text.Text = "🐄 Farm von " .. player.DisplayName
		text.Parent = surface
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 80
		limit.Parent = text
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0.05, 0)
		padding.PaddingRight = UDim.new(0.05, 0)
		padding.PaddingTop = UDim.new(0.1, 0)
		padding.Parent = text
		-- grüner Streifen unten
		local stripe = Instance.new("Frame")
		stripe.AnchorPoint = Vector2.new(0.5, 1)
		stripe.Position = UDim2.fromScale(0.5, 0.94)
		stripe.Size = UDim2.fromScale(0.8, 0.06)
		stripe.BackgroundColor3 = Palette.Colors.Green
		stripe.BorderSizePixel = 0
		stripe.Parent = surface
	end

	-- Weg vom Tor bis zur ersten Kuhreihe
	makePart({
		Name = "Path",
		Size = Vector3.new(GATE_WIDTH - 2, 0.06, 26),
		CFrame = origin * CFrame.new(0, GROUND + 0.03, halfD - 13),
		Color = PATH,
		Material = Enum.Material.Cobblestone,
		CanCollide = false,
		Parent = decor,
	})

	-- Deko VOR der Kuhfläche (Kühe stehen lokal in z = -50 .. 22; z > 28 ist frei)
	buildFarmFlowers(decor, origin, Vector3.new(-9, 0, halfD - 7), 6, 3, slot * 11)
	buildFarmFlowers(decor, origin, Vector3.new(9, 0, halfD - 7), 6, 3, slot * 11 + 1)
	for _, bale in ipairs({ Vector3.new(-26, 0.9, 46), Vector3.new(-29.6, 0.9, 46), Vector3.new(-27.8, 2.7, 46) }) do
		makePart({
			Name = "HayBale",
			Size = Vector3.new(3.4, 1.8, 3),
			CFrame = origin * CFrame.new(bale.X, GROUND + bale.Y, bale.Z),
			Color = HAY,
			Material = Enum.Material.Fabric,
			Parent = decor,
		})
	end
	for _, barrel in ipairs({ Vector3.new(-19, 40), Vector3.new(-21.4, 41.2), Vector3.new(-19.8, 43.2) }) do
		makePart({
			Name = "Barrel",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.2, 1.9, 1.9),
			CFrame = origin * CFrame.new(barrel.X, GROUND + 1.1, barrel.Y) * CFrame.Angles(0, 0, math.rad(90)),
			Color = World.Wood,
			Material = Enum.Material.Wood,
			Parent = decor,
		})
	end
	makePart({
		Name = "Trough",
		Size = Vector3.new(4.5, 1.2, 1.6),
		CFrame = origin * CFrame.new(27, GROUND + 0.6, 46),
		Color = World.Wood,
		Material = Enum.Material.Wood,
		Parent = decor,
	})
	decorPart(decor, "TroughWater", Vector3.new(4, 0.1, 1.1), origin * CFrame.new(27, GROUND + 1.2, 46), Palette.Colors.Blue,
		Enum.Material.Glass, { Transparency = 0.3 })

	-- Raster: ein helles Feld pro Kuh-Platz (Client hebt freie Felder beim Platzieren hervor)
	local grid = Instance.new("Folder")
	grid.Name = "Grid"
	grid.Parent = model
	for cell = 1, GRID_CELLS do
		local tile = makePart({
			Name = "Cell" .. cell,
			Size = Vector3.new(Map.GridCellX - 0.8, 0.05, Map.GridCellZ - 0.8),
			CFrame = origin * CowData.GetGridCellLocal(cell) * CFrame.new(0, 0.03, 0),
			Color = Color3.fromRGB(255, 255, 255),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.82,
			CanCollide = false,
			CanTouch = false,
			CastShadow = false,
			Parent = grid,
		})
		tile:SetAttribute("Cell", cell)
		tile:SetAttribute("OwnerUserId", player.UserId)
		CollectionService:AddTag(tile, "FarmCell")
	end

	-- Heuballen in der hinteren linken Ecke (außerhalb des Rasters)
	for _, position in ipairs({
		Vector3.new(-halfW + 4, GROUND + 0.9, -halfD + 3.2),
		Vector3.new(-halfW + 7.6, GROUND + 0.9, -halfD + 3.2),
		Vector3.new(-halfW + 5.8, GROUND + 2.7, -halfD + 3.2),
	}) do
		makePart({
			Name = "HayBale",
			Size = Vector3.new(3.4, 1.8, 3),
			CFrame = origin * CFrame.new(position),
			Color = HAY,
			Material = Enum.Material.Fabric,
			Parent = decor,
		})
	end

	-- Milch-Stand rechts vom Weg, Kundenseite zeigt zum Weg (-X)
	buildSellStand(player, decor, origin * CFrame.new(12, GROUND, halfD - 14) * CFrame.Angles(0, math.rad(90), 0))

	model.Parent = plotsFolder

	local farm = {
		Slot = slot,
		Model = model,
		CowsFolder = cowsFolder,
		Origin = origin,
		SpawnCFrame = origin * CFrame.new(0, GROUND + 4, halfD - 6), -- Blick Richtung Kühe (-Z)
		Spots = {},
	}
	farms[player] = farm
	player:SetAttribute("PlotSlot", slot) -- für die Übersichtskarte
	return farm
end

local function removeFarm(player)
	local farm = farms[player]
	if not farm then
		return
	end
	farm.Model:Destroy()
	usedSlots[farm.Slot] = nil
	farms[player] = nil
end

local function teleportToFarm(player, character)
	local farm = farms[player]
	if not farm then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if root then
		task.wait(0.1)
		character:PivotTo(farm.SpawnCFrame)
	end
end

------------------------------------------------------------------------
-- Namensschild über der Kuh + schwebende Texte
------------------------------------------------------------------------
local function createInfoBillboard(cow, torso)
	local info = CowData.Rarities[cow.Rarity]
	local accent = Palette.rarityColor(cow.Rarity)

	-- kleines Namensschild über dem Kopf (Marineblau, dünner Rahmen in der Seltenheitsfarbe)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Info"
	billboard.Size = UDim2.fromOffset(136, 52)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4.6, 0)
	billboard.MaxDistance = 55
	billboard.LightInfluence = 0
	billboard.Parent = torso

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Palette.Colors.Deep
	background.BackgroundTransparency = 0.18
	background.BorderSizePixel = 0
	background.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = background
	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
	stroke.Thickness = 1.5
	stroke.Transparency = 0.15
	stroke.Parent = background

	local function label(name, text, posY, height, font, color)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.06, posY)
		l.Size = UDim2.fromScale(0.88, height)
		l.Font = font
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = text
		l.Parent = background
		return l
	end
	label("NameLabel", cow.Name, 0.05, 0.38, Palette.Fonts.Heading, Palette.Colors.Cream)
	label("RarityLabel", (info.IsSpecial and "★ " or "") .. info.DisplayName, 0.44, 0.22, Palette.Fonts.Body, accent)
	return label("Status", "", 0.7, 0.24, Palette.Fonts.Body, Palette.Colors.SubText)
end

local function showPopup(part, message, color)
	-- kleine Schwebe-Schrift (Creme bzw. Gold für Coins), weicher Umriss statt dicker Kontur
	local popup = Instance.new("BillboardGui")
	popup.Size = UDim2.fromOffset(180, 38)
	popup.StudsOffsetWorldSpace = Vector3.new(0, 6.5, 0)
	popup.AlwaysOnTop = true
	popup.MaxDistance = 70
	popup.LightInfluence = 0
	popup.Parent = part

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Palette.Fonts.Heading
	text.TextScaled = true
	text.TextColor3 = color or Palette.Colors.Cream
	text.Text = message
	text.Parent = popup
	local stroke = Instance.new("UIStroke")
	stroke.Color = Palette.Colors.Deep
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = text

	local scale = Instance.new("UIScale")
	scale.Scale = 0.5
	scale.Parent = text
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local rise = TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(popup, rise, { StudsOffsetWorldSpace = Vector3.new(0, 9, 0) }):Play()
	task.delay(0.9, function()
		TweenService:Create(text, TweenInfo.new(0.7), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.7), { Transparency = 1 }):Play()
	end)
	Debris:AddItem(popup, 1.9)
end

local function playSound(parent, soundId, volume, speed)
	if not soundId or soundId == "" or soundId == "rbxassetid://0" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 1
	sound.PlaybackSpeed = speed or 1
	sound.RollOffMaxDistance = 60
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 4)
end

------------------------------------------------------------------------
-- Melk-Minispiel (Server-Seite, entscheidet über alles)
------------------------------------------------------------------------
-- sessions[player] = { CowId, Spot, Humanoid, Pulls, Actions, Needed, MilkPerPull,
--                      LastSide, StartedAt, Seated, Connections }
local sessions = {}
local refreshCowLabels -- weiter unten definiert

local MAX_DISTANCE_FROM_STOOL = 10 -- wer weiter weg ist, hat aufgehört

local function unseat(humanoid, seat)
	if seat then
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		seat.Disabled = true
	end
	if humanoid and humanoid.Parent then
		humanoid.Sit = false
	end
end

local function endMilking(player, completed)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil

	for _, connection in ipairs(session.Connections) do
		connection:Disconnect()
	end

	local spot = session.Spot
	local data = DataService.Get(player)
	local cow = data and data.Cows[session.CowId]
	local milk = session.Pulls * session.MilkPerPull

	if milk > 0 then
		DataService.AddMilk(player, milk)
		showPopup(spot.Torso, "+" .. CowData.FormatNumber(milk) .. " Milch", Palette.Colors.Cream)
	end
	if cow and session.Pulls > 0 then
		cow.MilkReadyAt = os.time() + CowData.Rarities[cow.Rarity].MilkCooldown
	end

	unseat(session.Humanoid, spot.Seat)
	spot.Cow:SetAttribute("BeingMilked", false)

	if completed then
		playSound(spot.Torso, Config.MilkDoneSoundId, 1, 0.8)
		DataService.Notify(player, ("🪣 Eimer voll! +%s Milch von %s"):format(CowData.FormatNumber(milk), cow and cow.Name or "deiner Kuh"), "success")
	elseif milk > 0 then
		DataService.Notify(player, ("Melken abgebrochen: +%s Milch"):format(CowData.FormatNumber(milk)), "info")
	end

	-- Eimer nach kurzer Zeit wieder leeren
	task.delay(1.5, function()
		spot.SetFill(0)
	end)

	if player.Parent then
		Remotes.MilkingEnded:FireClient(player, completed, milk)
	end
	refreshCowLabels(player)
end

-- silent = true: von der Melk-Platte ausgelöst -> keine Meldung, wenn die Kuh Pause hat
local function startMilking(player, cowId, silent)
	if sessions[player] then
		return
	end
	if not debounce(player, "StartMilking", 0.5) then
		return
	end

	local data = DataService.Get(player)
	local farm = farms[player]
	local cow = data and data.Cows[cowId]
	local spot = farm and farm.Spots[cowId]
	if not cow or not spot then
		return
	end

	local readyAt = cow.MilkReadyAt or 0
	if readyAt > os.time() then
		if not silent then
			DataService.Notify(player, ("⏳ %s braucht noch %s Pause."):format(cow.Name, formatTime(readyAt - os.time())), "error")
		end
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end

	-- Falls der Spieler schon woanders sitzt: aufstehen
	local currentSeat = humanoid.SeatPart
	if currentSeat then
		local weld = currentSeat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		humanoid.Sit = false
	end

	local info = CowData.Rarities[cow.Rarity]
	local seat = spot.Seat
	local session = {
		CowId = cowId,
		Spot = spot,
		Humanoid = humanoid,
		Root = root,
		Pulls = 0,
		Actions = 0,
		Needed = Config.PullsPerMilking,
		MilkPerPull = info.MilkPerPull,
		LastSide = nil,
		StartedAt = os.clock(),
		Seated = false,
		Connections = {},
	}
	sessions[player] = session

	-- Wer vom Schemel springt, bricht das Melken ab
	table.insert(session.Connections, seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if seat.Occupant == humanoid then
			session.Seated = true
		elseif session.Seated and sessions[player] == session then
			endMilking(player, false)
		end
	end))
	table.insert(session.Connections, humanoid.Died:Connect(function()
		endMilking(player, false)
	end))

	spot.Cow:SetAttribute("BeingMilked", true)

	-- Teleport direkt neben die Kuh und hinsetzen
	seat.Disabled = false
	character:PivotTo(seat.CFrame * CFrame.new(0, 2.5, 0))
	seat:Sit(humanoid)
	if seat.Occupant == humanoid then
		session.Seated = true
	end

	Remotes.MilkingStarted:FireClient(player, {
		CowId = cowId,
		CowName = cow.Name,
		Rarity = cow.Rarity,
		PullsNeeded = session.Needed,
		MilkPerPull = session.MilkPerPull,
		Penalty = Config.WrongPullPenalty,
		Spot = spot.Model,
	})
	refreshCowLabels(player)
end

-- Ein Zug. Richtige Seite (abwechselnd) = Fortschritt, gleiche Seite nochmal = Fortschritt verlieren.
Remotes.MilkPull.OnServerEvent:Connect(function(player, side)
	local session = sessions[player]
	if not session then
		return
	end
	if side ~= "Left" and side ~= "Right" then
		return
	end
	-- Anti-Cheat: nicht mehr Aktionen als zeitlich möglich (+2 Puffer für Netzwerk-Schwankungen)
	local allowed = math.floor((os.clock() - session.StartedAt) / Config.MinPullInterval) + 2
	if session.Actions >= allowed then
		return
	end
	session.Actions += 1

	if side == session.LastSide then
		session.Pulls = math.max(0, session.Pulls - Config.WrongPullPenalty)
	else
		session.LastSide = side
		session.Pulls += 1
	end

	session.Spot.SetFill(session.Pulls / session.Needed)
	Remotes.MilkingProgress:FireClient(player, session.Pulls, session.LastSide)

	if session.Pulls >= session.Needed then
		endMilking(player, true)
	end
end)

Remotes.StopMilking.OnServerEvent:Connect(function(player)
	endMilking(player, false)
end)

------------------------------------------------------------------------
-- Wo ist welche Kuh?
--   cow.Slot   = Feld auf der Farm (1 .. 36)
--   cow.Hotbar = Platz in der Hotbar (1 .. 6)
--   cow.Stored = true -> im Inventar
------------------------------------------------------------------------
local function sortedCows(data)
	local list = {}
	for _, cow in pairs(data.Cows) do
		table.insert(list, cow)
	end
	table.sort(list, function(a, b)
		return (tonumber(a.Id:sub(2)) or 0) < (tonumber(b.Id:sub(2)) or 0)
	end)
	return list
end

local function occupiedCells(data)
	local used = {}
	for _, cow in pairs(data.Cows) do
		if cow.Slot then
			used[cow.Slot] = cow
		end
	end
	return used
end

local function occupiedHotbar(data)
	local used = {}
	for _, cow in pairs(data.Cows) do
		if cow.Hotbar then
			used[cow.Hotbar] = cow
		end
	end
	return used
end

local function firstFree(used, count)
	for i = 1, count do
		if not used[i] then
			return i
		end
	end
	return nil
end

-- Neue Kuh: freies Feld, sonst Hotbar, sonst Inventar
local function assignLocation(data, cow)
	local cell = firstFree(occupiedCells(data), GRID_CELLS)
	if cell then
		cow.Slot = cell
		return "farm"
	end
	local hotbar = firstFree(occupiedHotbar(data), HOTBAR_SIZE)
	if hotbar then
		cow.Hotbar = hotbar
		return "hotbar"
	end
	cow.Stored = true
	return "inventory"
end

-- Alte Speicherstände (ohne Felder) und kaputte Werte reparieren
local function normalizeCows(data)
	local cells, hotbar = {}, {}
	local list = sortedCows(data)
	for _, cow in ipairs(list) do
		if cow.Slot ~= nil and (type(cow.Slot) ~= "number" or cow.Slot < 1 or cow.Slot > GRID_CELLS or cells[cow.Slot]) then
			cow.Slot = nil
		end
		if cow.Slot then
			cells[cow.Slot] = true
			cow.Hotbar = nil
			cow.Stored = nil
		else
			if cow.Hotbar ~= nil
				and (type(cow.Hotbar) ~= "number" or cow.Hotbar < 1 or cow.Hotbar > HOTBAR_SIZE or hotbar[cow.Hotbar])
			then
				cow.Hotbar = nil
			end
			if cow.Hotbar then
				hotbar[cow.Hotbar] = true
				cow.Stored = nil
			end
		end
	end
	for _, cow in ipairs(list) do
		if not cow.Slot and not cow.Hotbar and not cow.Stored then
			assignLocation(data, cow)
		end
	end
end

------------------------------------------------------------------------
-- Kühe auf der Farm aufstellen (nur Kühe mit cow.Slot)
------------------------------------------------------------------------
local function spawnCow(player, cow)
	if not cow.Slot then
		return nil
	end
	local farm = getFarm(player)
	if farm.Spots[cow.Id] then
		return farm.Spots[cow.Id]
	end

	local yaw = math.rad(rng:NextNumber(-8, 8))
	local base = farm.Origin * CowData.GetGridCellLocal(cow.Slot) * CFrame.new(COW_OFFSET_X, 0, 0) * CFrame.Angles(0, yaw, 0)

	local spotModel = Instance.new("Model")
	spotModel.Name = cow.Id

	-- Kuh
	local cowModel, refs = CowModelBuilder.BuildCow(cow.Rarity, cow.Id, base)
	cowModel:SetAttribute("CowId", cow.Id)
	cowModel:SetAttribute("OwnerUserId", player.UserId)
	cowModel.Parent = spotModel

	-- Maße kommen vom Modell (Blender-Kuh und Ersatz-Kuh sind unterschiedlich breit)
	local halfWidth = cowModel:GetAttribute("BodyHalfWidth") or 2.5
	local udderZ = cowModel:GetAttribute("UdderZ") or 1.0
	local stoolX = -(halfWidth + 1.2)

	-- Schemel links neben dem Euter, Blick zur Kuh (+X)
	local stoolPosition = base * Vector3.new(stoolX, 0, udderZ)
	local udderPosition = base * Vector3.new(0, 0, udderZ)
	local stoolModel, seat = CowModelBuilder.BuildStool(CFrame.lookAt(stoolPosition, udderPosition))
	stoolModel.Parent = spotModel

	-- Eimer unter dem Euter
	local bucketModel, setFill = CowModelBuilder.BuildBucket(base * CFrame.new(0, 0, udderZ))
	bucketModel.Parent = spotModel

	-- Melk-Platte: einfach drauflaufen (funktioniert auch prima am Handy)
	local pad = makePart({
		Name = "MilkPad",
		Size = Vector3.new(3, 0.2, 3.4),
		CFrame = base * CFrame.new(stoolX - 2.5, 0.1, udderZ),
		Color = Palette.Colors.Blue,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.3,
		CanCollide = false,
		Parent = spotModel,
	})
	local padLabel = Instance.new("BillboardGui")
	padLabel.Size = UDim2.fromOffset(84, 26)
	padLabel.StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0)
	padLabel.MaxDistance = 30
	padLabel.LightInfluence = 0
	padLabel.Parent = pad
	local padText = Instance.new("TextLabel")
	padText.Size = UDim2.fromScale(1, 1)
	padText.BackgroundColor3 = Palette.Colors.Deep
	padText.BackgroundTransparency = 0.2
	padText.Font = Palette.Fonts.Body
	padText.TextScaled = true
	padText.TextColor3 = Palette.Colors.Cream
	padText.Text = "Melken"
	padText.Parent = padLabel
	local padCorner = Instance.new("UICorner")
	padCorner.CornerRadius = UDim.new(0, 8)
	padCorner.Parent = padText
	local padPadding = Instance.new("UIPadding")
	padPadding.PaddingTop = UDim.new(0.15, 0)
	padPadding.PaddingBottom = UDim.new(0.15, 0)
	padPadding.Parent = padText
	pad.Touched:Connect(function(hit)
		local character = hit.Parent
		if character and Players:GetPlayerFromCharacter(character) == player then
			startMilking(player, cow.Id, true)
		end
	end)

	-- Anklicken / Antippen -> kleines Menü beim Besitzer (Melken / Aufheben)
	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 40
	clickDetector.Parent = cowModel
	clickDetector.MouseClick:Connect(function(clicker)
		if clicker ~= player then
			DataService.Notify(clicker, "Das ist nicht deine Kuh! 🐄", "error")
			return
		end
		local data = DataService.Get(player)
		local current = data and data.Cows[cow.Id]
		if current then
			Remotes.CowClicked:FireClient(player, {
				Id = current.Id,
				Name = current.Name,
				Rarity = current.Rarity,
				MilkReadyAt = current.MilkReadyAt or 0,
				ServerTime = os.time(),
			})
		end
	end)

	local status = createInfoBillboard(cow, refs.Torso)

	spotModel.Parent = farm.CowsFolder

	local spot = {
		Model = spotModel,
		Cow = cowModel,
		Torso = refs.Torso,
		Stool = stoolModel,
		Seat = seat,
		Bucket = bucketModel,
		SetFill = setFill,
		Status = status,
	}
	farm.Spots[cow.Id] = spot
	return spot
end

-- Neue Kuh: fällt von oben auf die Wiese + Konfetti + Sound
local function celebrateNewCow(spot, rarity)
	local info = CowData.Rarities[rarity]
	local cowModel = spot.Cow
	local finalPivot = cowModel:GetPivot()
	local dropHeight = 8

	-- Fall-Animation (Bounce)
	local alpha = Instance.new("NumberValue")
	alpha.Changed:Connect(function(value)
		if cowModel.Parent then
			cowModel:PivotTo(finalPivot + Vector3.new(0, dropHeight * (1 - value), 0))
		end
	end)
	cowModel:PivotTo(finalPivot + Vector3.new(0, dropHeight, 0))
	local tween = TweenService:Create(alpha, TweenInfo.new(0.7, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { Value = 1 })
	tween:Play()
	tween.Completed:Connect(function()
		if cowModel.Parent then
			cowModel:PivotTo(finalPivot)
		end
		alpha:Destroy()
	end)

	-- dezentes Konfetti in der Farbe der Seltenheit
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, info.UiColor),
		ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(10, 20)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -20, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-200, 200)
	emitter.LightEmission = 0.2
	emitter.Enabled = false
	emitter.Parent = spot.Torso
	task.delay(0.5, function()
		if emitter.Parent then
			emitter:Emit(info.Tier >= 5 and 40 or 20)
		end
		if spot.Torso.Parent then
			if info.Tier >= 4 then
				-- ohne eigene Fanfare: normaler Sound, nur tiefer
				local fanfare = Config.RareCowSoundId ~= "" and Config.RareCowSoundId or Config.NewCowSoundId
				playSound(spot.Torso, fanfare, 1, Config.RareCowSoundId ~= "" and 1 or 0.8)
			else
				playSound(spot.Torso, Config.NewCowSoundId, 0.8, 1.2)
			end
		end
	end)
	Debris:AddItem(emitter, 3)
end

DataService.CowAdded:Connect(function(player, cow)
	if not player.Parent then
		return
	end
	local data = DataService.Get(player)
	if data and not cow.Slot and not cow.Hotbar and not cow.Stored then
		local where = assignLocation(data, cow)
		if where == "hotbar" then
			DataService.Notify(player, ("Farm voll – %s wartet in deiner Hotbar."):format(cow.Name), "info")
		elseif where == "inventory" then
			DataService.Notify(player, ("Farm und Hotbar voll – %s ist im Inventar."):format(cow.Name), "info")
		end
	end
	-- schon aufgestellt (z.B. beim Laden) -> keine Feier
	local farm = farms[player]
	local isNew = not (farm and farm.Spots[cow.Id])
	local spot = spawnCow(player, cow)
	refreshCowLabels(player)
	if isNew and spot then
		celebrateNewCow(spot, cow.Rarity)
	end
	DataService.FireInventoryChanged(player)
end)

-- Statuszeile über jeder Kuh: Melken / Zucht / Cooldown / Bereit
function refreshCowLabels(player)
	local farm = farms[player]
	local data = DataService.Get(player)
	if not farm or not data then
		return
	end
	local breeding = data.Breeding
	local session = sessions[player]
	local now = os.time()

	for cowId, spot in pairs(farm.Spots) do
		local cow = data.Cows[cowId]
		local status = spot.Status
		if not cow then
			status.Text = ""
		elseif session and session.CowId == cowId then
			status.Text = "Wird gemolken"
			status.TextColor3 = Palette.Colors.Blue
		elseif breeding and (breeding.ParentA == cowId or breeding.ParentB == cowId) then
			status.Text = "Zucht " .. formatTime(breeding.ReadyAt - now)
			status.TextColor3 = Palette.Colors.Pink
		elseif (cow.MilkReadyAt or 0) > now then
			status.Text = "Pause " .. formatTime(cow.MilkReadyAt - now)
			status.TextColor3 = Palette.Colors.Orange
		else
			status.Text = "Bereit"
			status.TextColor3 = Color3.fromRGB(140, 214, 124)
		end
	end
end

------------------------------------------------------------------------
-- Inventar & Hotbar: Kuh aufheben, in Hotbar/Inventar legen, auf ein Feld setzen
------------------------------------------------------------------------
local function despawnCow(player, cowId)
	local farm = farms[player]
	local spot = farm and farm.Spots[cowId]
	if not spot then
		return
	end
	-- kleine Staubwolke, wo die Kuh stand
	local puff = makePart({
		Name = "Puff",
		Size = Vector3.new(1, 1, 1),
		CFrame = spot.Torso.CFrame,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Parent = workspace,
	})
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(245, 240, 225))
	emitter.Size = NumberSequence.new(1.6, 0)
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(4, 8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = puff
	emitter:Emit(14)
	Debris:AddItem(puff, 2)

	spot.Model:Destroy()
	farm.Spots[cowId] = nil
end

local function cowAction(player, action, cowId, arg)
	local data = DataService.Get(player)
	local cow = data and type(cowId) == "string" and data.Cows[cowId]
	if not cow then
		return false, "Kuh nicht gefunden."
	end
	local session = sessions[player]
	local beingMilked = session ~= nil and session.CowId == cowId

	if action == "milk" then
		if not cow.Slot then
			return false, "Die Kuh muss auf der Farm stehen."
		end
		startMilking(player, cowId)
		return true
	elseif action == "pickup" then
		if not cow.Slot then
			return false, "Die Kuh steht nicht auf der Farm."
		end
		if beingMilked then
			return false, "Die Kuh wird gerade gemolken."
		end
		despawnCow(player, cowId)
		cow.Slot = nil
		local hotbar = firstFree(occupiedHotbar(data), HOTBAR_SIZE)
		if hotbar and arg ~= "inventory" then
			cow.Hotbar = hotbar
		else
			cow.Stored = true
		end
		return true, cow.Hotbar and "hotbar" or "inventory"
	elseif action == "place" then
		local cell = tonumber(arg)
		if cow.Slot then
			return false, "Die Kuh steht schon auf der Farm."
		end
		if not cell or cell ~= math.floor(cell) or cell < 1 or cell > GRID_CELLS then
			return false, "Ungültiges Feld."
		end
		if occupiedCells(data)[cell] then
			return false, "Auf dem Feld steht schon eine Kuh."
		end
		cow.Slot = cell
		cow.Hotbar = nil
		cow.Stored = nil
		local spot = spawnCow(player, cow)
		if spot then
			celebrateNewCow(spot, cow.Rarity)
		end
		return true
	elseif action == "hotbar" then
		if cow.Slot then
			return false, "Heb die Kuh zuerst auf."
		end
		local index = tonumber(arg) or firstFree(occupiedHotbar(data), HOTBAR_SIZE)
		if not index or index ~= math.floor(index) or index < 1 or index > HOTBAR_SIZE then
			return false, "Die Hotbar ist voll."
		end
		local other = occupiedHotbar(data)[index]
		if other and other ~= cow then
			-- Plätze tauschen (kommt die Kuh aus dem Inventar, wandert die andere ins Inventar)
			other.Hotbar = cow.Hotbar
			if not other.Hotbar then
				other.Stored = true
			end
		end
		cow.Hotbar = index
		cow.Stored = nil
		return true
	elseif action == "store" then
		if cow.Slot then
			if beingMilked then
				return false, "Die Kuh wird gerade gemolken."
			end
			despawnCow(player, cowId)
			cow.Slot = nil
		end
		cow.Hotbar = nil
		cow.Stored = true
		return true
	end
	return false, "Unbekannte Aktion."
end

-- action: "milk" | "pickup" | "place" (arg = Feld) | "hotbar" (arg = Platz oder nil) | "store"
Remotes.CowAction.OnServerInvoke = function(player, action, cowId, arg)
	if not debounce(player, "CowAction", 0.15) then
		return false, "Nicht so schnell!"
	end
	local ok, message = cowAction(player, action, cowId, arg)
	if ok and action ~= "milk" then
		refreshCowLabels(player)
		DataService.Sync(player)
		DataService.FireInventoryChanged(player)
	end
	return ok, message
end

-- Teleport aus der Übersicht: zu einem Haus (Page-Name) oder zur eigenen Farm
Remotes.TeleportTo.OnServerEvent:Connect(function(player, destination)
	if type(destination) ~= "string" or not debounce(player, "Teleport", 1) then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local target = nil
	if destination == "Farm" then
		local farm = farms[player]
		target = farm and farm.SpawnCFrame
	else
		for _, building in ipairs(CollectionService:GetTagged("ShopBuilding")) do
			if building:GetAttribute("Page") == destination then
				target = building:GetAttribute("TeleportCFrame")
				break
			end
		end
	end
	if target then
		endMilking(player, false)
		character:PivotTo(target)
	end
end)

------------------------------------------------------------------------
-- Milch verkaufen
------------------------------------------------------------------------
-- popupPart (optional): dort erscheint "+X 🪙" (z.B. der Milch-Stand)
function sellMilk(player, popupPart)
	if not debounce(player, "SellMilk", 0.5) then
		return
	end
	local milk = DataService.TakeAllMilk(player)
	if milk <= 0 then
		DataService.Notify(player, "Du hast keine Milch zum Verkaufen. Melke deine Kühe!", "error")
		return
	end
	local coins = math.floor(milk * Config.MilkSellPrice)
	DataService.AddCoins(player, coins)
	DataService.Notify(
		player,
		("%s Milch für %s Coins verkauft!"):format(CowData.FormatNumber(milk), CowData.FormatNumber(coins)),
		"success"
	)
	if popupPart then
		showPopup(popupPart, "+" .. CowData.FormatNumber(coins) .. " Coins", Palette.Colors.Gold)
	end
end

Remotes.SellMilk.OnServerEvent:Connect(function(player)
	sellMilk(player)
end)

------------------------------------------------------------------------
-- Shop: Kühe direkt kaufen
------------------------------------------------------------------------
Remotes.BuyCow.OnServerInvoke = function(player, rarity)
	if not debounce(player, "BuyCow", 0.3) then
		return false, "Nicht so schnell!"
	end
	if not CowData.IsValidRarity(rarity) then
		return false, "Ungültige Kuh."
	end

	local info = CowData.Rarities[rarity]
	if not info.ShopPrice then
		return false, "Diese Kuh gibt es nicht im Shop."
	end
	if not DataService.HasCowSpace(player, 1) then
		return false, ("Deine Farm ist voll! (max. %d Kühe)"):format(Config.MaxCows)
	end
	if not DataService.SpendCoins(player, info.ShopPrice) then
		return false, "Nicht genug Coins!"
	end

	local cow = DataService.AddCow(player, rarity)
	announceNewCow(player, cow, "Gekauft")
	return true, cow.Id
end

------------------------------------------------------------------------
-- Kuh-Kisten
------------------------------------------------------------------------
local productToCrate = {} -- [ProductId] = crateId
for crateId, crate in pairs(CowData.Crates) do
	if crate.ProductId and crate.ProductId > 0 then
		productToCrate[crate.ProductId] = crateId
	end
end

local function rollCrate(crateId)
	return CowData.RollWeighted(CowData.Crates[crateId].Loot, rng)
end

-- payWithRobux = true -> Robux-Kaufdialog, sonst Coins
Remotes.OpenCrate.OnServerInvoke = function(player, crateId, payWithRobux)
	if not debounce(player, "OpenCrate", 0.5) then
		return false, "Nicht so schnell!"
	end
	if type(crateId) ~= "string" or not CowData.Crates[crateId] then
		return false, "Diese Kiste gibt es nicht."
	end

	local crate = CowData.Crates[crateId]

	if payWithRobux == true then
		if not crate.ProductId or crate.ProductId == 0 then
			return false, "Robux-Kauf für diese Kiste ist noch nicht eingerichtet."
		end
		MarketplaceService:PromptProductPurchase(player, crate.ProductId)
		return true, "prompt"
	end

	if not crate.CoinPrice then
		return false, "Diese Kiste gibt es nur für Robux."
	end
	if not DataService.HasCowSpace(player, 1) then
		return false, ("Deine Farm ist voll! (max. %d Kühe)"):format(Config.MaxCows)
	end
	if not DataService.SpendCoins(player, crate.CoinPrice) then
		return false, "Nicht genug Coins!"
	end

	local cow = DataService.AddCow(player, rollCrate(crateId))
	announceNewCow(player, cow, crate.DisplayName)
	return true, cow.Rarity, cow.Id
end

------------------------------------------------------------------------
-- Breeding
------------------------------------------------------------------------
local function finishBreeding(player, data)
	local breeding = data.Breeding
	local parentA = data.Cows[breeding.ParentA]
	local parentB = data.Cows[breeding.ParentB]
	local rarity = CowData.RollBreeding(
		parentA and parentA.Rarity or "Common",
		parentB and parentB.Rarity or "Common",
		rng
	)

	data.Breeding = nil
	local calf = DataService.AddCow(player, rarity)
	refreshCowLabels(player)

	if calf then
		local names = (parentA and parentA.Name or "?") .. " & " .. (parentB and parentB.Name or "?")
		announceNewCow(player, calf, "🍼 Kalb von " .. names)
	end
end

Remotes.StartBreeding.OnServerInvoke = function(player, cowIdA, cowIdB)
	if not debounce(player, "StartBreeding", 0.5) then
		return false, "Nicht so schnell!"
	end
	if type(cowIdA) ~= "string" or type(cowIdB) ~= "string" then
		return false, "Ungültige Auswahl."
	end

	local data = DataService.Get(player)
	if not data then
		return false, "Daten werden noch geladen..."
	end
	if data.Breeding then
		return false, "Es wird bereits gezüchtet! Warte, bis das Kalb da ist."
	end
	if cowIdA == cowIdB then
		return false, "Wähle zwei verschiedene Kühe."
	end

	local cowA, cowB = data.Cows[cowIdA], data.Cows[cowIdB]
	if not cowA or not cowB then
		return false, "Kuh nicht gefunden."
	end
	if not DataService.HasCowSpace(player, 1) then
		return false, ("Kein Platz für ein Kalb! (max. %d Kühe)"):format(Config.MaxCows)
	end

	local duration = CowData.GetBreedTime(cowA.Rarity, cowB.Rarity)
	local now = os.time()
	data.Breeding = {
		ParentA = cowIdA,
		ParentB = cowIdB,
		StartedAt = now,
		ReadyAt = now + duration,
	}

	refreshCowLabels(player)
	DataService.FireInventoryChanged(player)
	DataService.Notify(
		player,
		("💕 %s und %s züchten! Das Kalb kommt in %s."):format(cowA.Name, cowB.Name, formatTime(duration)),
		"info"
	)
	return true, data.Breeding.ReadyAt
end

------------------------------------------------------------------------
-- Inventar für den Client (Shop-/Zucht-UI)
------------------------------------------------------------------------
local autoMilker = {} -- [player] = true

Remotes.GetInventory.OnServerInvoke = function(player)
	local data = DataService.Get(player)
	if not data then
		return nil
	end

	local cows = {}
	for _, cow in pairs(data.Cows) do
		table.insert(cows, {
			Id = cow.Id,
			Rarity = cow.Rarity,
			Name = cow.Name,
			MilkReadyAt = cow.MilkReadyAt or 0,
			Slot = cow.Slot,
			Hotbar = cow.Hotbar,
			Stored = cow.Stored == true,
		})
	end
	table.sort(cows, function(a, b)
		return CowData.Rarities[a.Rarity].Tier > CowData.Rarities[b.Rarity].Tier
	end)

	return {
		Coins = data.Coins,
		Milk = data.Milk,
		Cows = cows,
		Breeding = data.Breeding,
		LoginStreak = data.LoginStreak.Streak,
		HasAutoMilker = autoMilker[player] == true,
		ServerTime = os.time(),
		HotbarSize = HOTBAR_SIZE,
		CellCount = GRID_CELLS,
	}
end

------------------------------------------------------------------------
-- Auto-Melker (Gamepass)
------------------------------------------------------------------------
local function setAutoMilker(player)
	autoMilker[player] = true
	player:SetAttribute("HasAutoMilker", true)
end

local function checkAutoMilker(player)
	local passId = Config.AutoMilkerGamePassId
	if passId == 0 then
		return
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	if ok and owns then
		setAutoMilker(player)
	end
end

Remotes.BuyAutoMilker.OnServerEvent:Connect(function(player)
	if not debounce(player, "BuyAutoMilker", 1) then
		return
	end
	if autoMilker[player] then
		DataService.Notify(player, "Du hast den Auto-Melker schon!", "info")
		return
	end
	if Config.AutoMilkerGamePassId == 0 then
		DataService.Notify(player, "Der Auto-Melker ist noch nicht eingerichtet.", "error")
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, Config.AutoMilkerGamePassId)
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if purchased and passId == Config.AutoMilkerGamePassId then
		setAutoMilker(player)
		DataService.Notify(player, "🤖 Auto-Melker aktiviert! Deine Kühe werden jetzt automatisch gemolken.", "rare")
	end
end)

task.spawn(function()
	while true do
		task.wait(Config.AutoMilkInterval)
		for player in pairs(autoMilker) do
			local data = DataService.Get(player)
			if data then
				local total = 0
				for _, cow in pairs(data.Cows) do
					if cow.Slot then -- nur Kühe, die auf der Farm stehen
						total += CowData.Rarities[cow.Rarity].MilkPerPull
					end
				end
				if total > 0 then
					DataService.AddMilk(player, total)
				end
			end
		end
	end
end)

------------------------------------------------------------------------
-- Robux-Käufe (Developer Products -> Kisten)
------------------------------------------------------------------------
local MAX_STORED_RECEIPTS = 50

MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local data = DataService.WaitForData(player)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Schon verarbeitet? (Schutz gegen doppelte Vergabe)
	-- Erst "gekauft" melden, wenn der Beleg wirklich gespeichert ist (sonst ginge die Kuh bei einem Absturz verloren)
	if data.Receipts[receipt.PurchaseId] then
		if DataService.IsPersistent(player) and not DataService.Save(player) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local crateId = productToCrate[receipt.ProductId]
	if not crateId then
		warn("[CowManager] Unbekanntes Produkt:", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Robux-Käufe werden immer gutgeschrieben, auch wenn die Farm voll ist
	local cow = DataService.AddCow(player, rollCrate(crateId))
	data.Receipts[receipt.PurchaseId] = os.time()

	-- Alte Belege aufräumen
	local count = 0
	local oldestId, oldestTime = nil, math.huge
	for id, time in pairs(data.Receipts) do
		count += 1
		if time < oldestTime then
			oldestId, oldestTime = id, time
		end
	end
	if count > MAX_STORED_RECEIPTS and oldestId then
		data.Receipts[oldestId] = nil
	end

	announceNewCow(player, cow, CowData.Crates[crateId].DisplayName)
	if DataService.IsPersistent(player) and not DataService.Save(player) then
		-- Kuh und Beleg liegen schon im Speicher; Roblox fragt später nochmal (dann greift die Prüfung oben)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

------------------------------------------------------------------------
-- Spieler betreten / verlassen
------------------------------------------------------------------------
local function onPlayerAdded(player)
	local data = DataService.WaitForData(player)
	if not data then
		return
	end

	getFarm(player)

	-- alte Speicherstände bekommen automatisch Felder; dann alle platzierten Kühe aufstellen
	normalizeCows(data)
	for _, cow in ipairs(sortedCows(data)) do
		spawnCow(player, cow)
	end
	refreshCowLabels(player)
	DataService.FireInventoryChanged(player)

	player.CharacterAdded:Connect(function(character)
		teleportToFarm(player, character)
	end)
	player.CharacterRemoving:Connect(function()
		endMilking(player, false)
	end)
	if player.Character then
		task.spawn(teleportToFarm, player, player.Character)
	end

	task.spawn(checkAutoMilker, player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	endMilking(player, false)
	removeFarm(player)
	lastCall[player] = nil
	autoMilker[player] = nil
end)

------------------------------------------------------------------------
-- Schleifen: Zucht-Timer, Statusanzeigen, Melk-Abstand
------------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(1)
		for player in pairs(farms) do
			local data = DataService.Get(player)
			if data then
				if data.Breeding and os.time() >= data.Breeding.ReadyAt then
					finishBreeding(player, data)
				end
				refreshCowLabels(player)
			end
		end
	end
end)

-- Wer beim Melken weggeht (z.B. weggelaufen statt gesessen), beendet die Session
task.spawn(function()
	while true do
		task.wait(0.5)
		for player, session in pairs(sessions) do
			local root = session.Root
			local seat = session.Spot.Seat
			if not root.Parent or (root.Position - seat.Position).Magnitude > MAX_DISTANCE_FROM_STOOL then
				endMilking(player, false)
			end
		end
	end
end)
