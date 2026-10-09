-- CowManager.server.lua
-- Alles rund um die Kühe:
--   * eingezäunter Farm-Plot pro Spieler links/rechts der Allee (Workspace.CowFarmLayout.Plots)
--   * prozedurale Kuh-Modelle mit Schemel + Eimer daneben
--   * Melk-Minispiel: Kuh anklicken ODER auf die leuchtende Melk-Platte neben der Kuh laufen
--     -> Teleport auf den Schemel -> abwechselnd L/R ziehen
--   * Melk-Cooldown pro Kuh
--   * Milch verkaufen, Shop, Kisten (Coins/Robux), Breeding, Auto-Melker, ProcessReceipt
-- Idle-Animationen & Regenbogen-Farben laufen auf dem Client (WorldAnimator.client.lua).

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

local COLUMNS = 6
local COW_SPACING_X = 13
local COW_SPACING_Z = 12
local FIRST_ROW_Z = -45

local GRASS_LIGHT = Color3.fromRGB(118, 186, 86)
local GRASS_DARK = Color3.fromRGB(104, 170, 76)
local CURB = Color3.fromRGB(215, 210, 200)
local FENCE_WHITE = Color3.fromRGB(245, 245, 240)
local PATH = Color3.fromRGB(176, 140, 98)
local FENCE = Color3.fromRGB(140, 95, 55) -- Holzfarbe (Milch-Stand)
local FENCE_DARK = Color3.fromRGB(95, 62, 38) -- Tor + Pfosten Milch-Stand
local HAY = Color3.fromRGB(230, 200, 100)

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
--   Slot, Model, CowsFolder, Origin, SpawnCFrame, NextIndex,
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

-- Ungerade Slots links (Westen), gerade rechts (Osten). Das Tor zeigt immer zur Allee.
local function getPlotOrigin(slot)
	local side = slot % 2 == 1 and -1 or 1
	local row = math.floor((slot - 1) / 2)
	local z = Map.PlotRowStartZ + row * Map.PlotRowSpacing
	-- lokales +Z soll zur Mitte (x = 0) zeigen
	local yaw = side == -1 and math.rad(90) or math.rad(-90)
	return CFrame.new(side * Map.PlotCenterX, 0, z) * CFrame.Angles(0, yaw, 0)
end

-- Weißer Zaun: Pfosten alle 5 Studs + 2 durchgehende Latten
local function buildFenceLine(parent, origin, from, to)
	local delta = to - from
	local length = delta.Magnitude
	if length < 0.5 then
		return
	end
	local direction = delta.Unit
	local posts = math.max(1, math.floor(length / 5 + 0.5))
	for i = 0, posts do
		local position = from + direction * (length * i / posts)
		makePart({
			Name = "Post",
			Size = Vector3.new(0.5, 3.4, 0.5),
			CFrame = origin * CFrame.new(position + Vector3.new(0, GROUND + 1.7, 0)),
			Color = FENCE_WHITE,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
		makePart({
			Name = "PostCap",
			Size = Vector3.new(0.65, 0.2, 0.65),
			CFrame = origin * CFrame.new(position + Vector3.new(0, GROUND + 3.5, 0)),
			Color = FENCE_WHITE,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
	end
	local middle = from + delta / 2
	local lookAt = CFrame.lookAt(middle, middle + direction)
	for _, height in ipairs({ 1.3, 2.7 }) do
		makePart({
			Name = "Rail",
			Size = Vector3.new(0.2, 0.35, length),
			CFrame = origin * (lookAt + Vector3.new(0, GROUND + height, 0)),
			Color = FENCE_WHITE,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
	end
end

-- Milch-Stand: Theke mit gestreiftem Dach, Milchkannen und ProximityPrompt.
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

	local counter = standPart("Counter", Vector3.new(6, 3, 2.4), CFrame.new(0, 1.5, 0), FENCE)
	standPart("CounterTop", Vector3.new(6.4, 0.3, 2.8), CFrame.new(0, 3.15, 0), Color3.fromRGB(190, 140, 90))
	for _, x in ipairs({ -2.9, 2.9 }) do
		standPart("Post", Vector3.new(0.4, 4.6, 0.4), CFrame.new(x, 5.4, 1.0), FENCE_DARK)
	end

	-- rot-weiß gestreiftes Dach
	for i = 0, 6 do
		local stripeColor = i % 2 == 0 and Color3.fromRGB(215, 50, 50) or Color3.fromRGB(250, 250, 250)
		standPart("Roof", Vector3.new(1, 0.35, 3.8), CFrame.new(-3 + i, 7.8, 0.2) * CFrame.Angles(math.rad(-12), 0, 0),
			stripeColor, Enum.Material.Fabric)
	end

	-- Schild (weiße Schrift auf dunklem Grund)
	local sign = standPart("Sign", Vector3.new(5, 1.1, 0.2), CFrame.new(0, 6.8, -1.3), Color3.fromRGB(35, 40, 60))
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 50
	surface.LightInfluence = 0
	surface.Parent = sign
	local signText = Instance.new("TextLabel")
	signText.Size = UDim2.fromScale(1, 1)
	signText.BackgroundTransparency = 1
	signText.Font = Enum.Font.FredokaOne
	signText.TextScaled = true
	signText.TextColor3 = Color3.new(1, 1, 1)
	signText.Text = "🥛 Milch-Verkauf"
	signText.Parent = surface

	-- Milchkannen auf der Theke
	for i, x in ipairs({ -2, -1.2, 2 }) do
		local height = i == 2 and 1.0 or 1.3
		standPart("MilkCan", Vector3.new(height, 0.7, 0.7),
			CFrame.new(x, 3.3 + height / 2, 0.3) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(200, 205, 212), Enum.Material.Metal, Enum.PartType.Cylinder)
		standPart("MilkCanLid", Vector3.new(0.12, 0.5, 0.5),
			CFrame.new(x, 3.3 + height + 0.06, 0.3) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(250, 250, 245), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
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
		prompt.ObjectText = ("Milch-Stand · %s 🥛 = %s 🪙"):format(
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
			DataService.Notify(who, "Das ist nicht dein Milch-Stand! 🥛", "error")
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

	-- Torbogen mit Namensschild (weiße Schrift auf dunklem Holz)
	for _, x in ipairs({ -GATE_WIDTH / 2, GATE_WIDTH / 2 }) do
		makePart({
			Name = "GatePost",
			Size = Vector3.new(1, 9.5, 1),
			CFrame = origin * CFrame.new(x, GROUND + 4.75, fz),
			Color = FENCE_DARK,
			Material = Enum.Material.Wood,
			Parent = decor,
		})
	end
	local sign = makePart({
		Name = "Sign",
		Size = Vector3.new(GATE_WIDTH + 2, 2.4, 0.5),
		CFrame = origin * CFrame.new(0, GROUND + 9, fz),
		Color = FENCE_DARK,
		Material = Enum.Material.Wood,
		Parent = decor,
	})
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local surface = Instance.new("SurfaceGui")
		surface.Face = face
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 40
		surface.LightInfluence = 0
		surface.Parent = sign
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.FredokaOne
		text.TextScaled = true
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextStrokeTransparency = 0.4
		text.Text = "🐄 Farm von " .. player.DisplayName
		text.Parent = surface
	end

	-- Weg vom Tor bis zur ersten Kuhreihe
	makePart({
		Name = "Path",
		Size = Vector3.new(GATE_WIDTH - 2, 0.06, 26),
		CFrame = origin * CFrame.new(0, GROUND + 0.03, halfD - 13),
		Color = PATH,
		Material = Enum.Material.Ground,
		CanCollide = false,
		Parent = decor,
	})

	-- Heuballen in der hinteren linken Ecke
	for _, position in ipairs({
		Vector3.new(-halfW + 5, GROUND + 0.9, -halfD + 5),
		Vector3.new(-halfW + 8.6, GROUND + 0.9, -halfD + 5),
		Vector3.new(-halfW + 6.8, GROUND + 2.7, -halfD + 5),
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
		NextIndex = 0,
	}
	farms[player] = farm
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

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Info"
	billboard.Size = UDim2.fromOffset(170, 66)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4.4, 0)
	billboard.MaxDistance = 70
	billboard.LightInfluence = 0
	billboard.Parent = torso

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(25, 27, 38)
	background.BackgroundTransparency = 0.25
	background.Parent = billboard
	Instance.new("UICorner", background).CornerRadius = UDim.new(0, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = info.UiColor
	stroke.Thickness = 2
	stroke.Parent = background

	local function label(name, text, posY, height, color)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.05, posY)
		l.Size = UDim2.fromScale(0.9, height)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = text
		l.Parent = background
		return l
	end
	label("NameLabel", cow.Name, 0.04, 0.36, Color3.new(1, 1, 1))
	label("RarityLabel", (info.IsSpecial and "✦ " or "") .. info.DisplayName, 0.4, 0.26, info.UiColor)
	return label("Status", "", 0.68, 0.28, Color3.new(1, 1, 1))
end

local function showPopup(part, message, color)
	local popup = Instance.new("BillboardGui")
	popup.Size = UDim2.fromOffset(220, 50)
	popup.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	popup.AlwaysOnTop = true
	popup.MaxDistance = 80
	popup.LightInfluence = 0
	popup.Parent = part

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = color or Color3.new(1, 1, 1)
	text.TextStrokeColor3 = Color3.fromRGB(20, 20, 30)
	text.TextStrokeTransparency = 0
	text.Text = message
	text.Parent = popup

	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = text
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local rise = TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(popup, rise, { StudsOffsetWorldSpace = Vector3.new(0, 10, 0) }):Play()
	task.delay(1.0, function()
		TweenService:Create(text, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	Debris:AddItem(popup, 2)
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
		showPopup(spot.Torso, "+" .. CowData.FormatNumber(milk) .. " Milch!", Color3.new(1, 1, 1))
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
-- Kühe auf der Farm platzieren
------------------------------------------------------------------------
local function spawnCow(player, cow)
	local farm = getFarm(player)
	if farm.Spots[cow.Id] then
		return farm.Spots[cow.Id]
	end

	local index = farm.NextIndex
	farm.NextIndex += 1
	local column = index % COLUMNS
	local row = math.floor(index / COLUMNS)
	local x = (column - (COLUMNS - 1) / 2) * COW_SPACING_X
	local z = FIRST_ROW_Z + row * COW_SPACING_Z
	local yaw = math.rad(rng:NextNumber(-8, 8))
	local base = farm.Origin * CFrame.new(x, GROUND, z) * CFrame.Angles(0, yaw, 0)

	local spotModel = Instance.new("Model")
	spotModel.Name = cow.Id

	-- Kuh
	local cowModel, refs = CowModelBuilder.BuildCow(cow.Rarity, cow.Id, base)
	cowModel:SetAttribute("CowId", cow.Id)
	cowModel:SetAttribute("OwnerUserId", player.UserId)
	cowModel.Parent = spotModel

	-- Schemel links neben dem Euter, Blick zur Kuh (+X)
	local stoolPosition = base * Vector3.new(-3.7, 0, 1.0)
	local udderPosition = base * Vector3.new(0, 0, 1.0)
	local stoolModel, seat = CowModelBuilder.BuildStool(CFrame.lookAt(stoolPosition, udderPosition))
	stoolModel.Parent = spotModel

	-- Eimer unter dem Euter
	local bucketModel, setFill = CowModelBuilder.BuildBucket(base * CFrame.new(0, 0, 1.0))
	bucketModel.Parent = spotModel

	-- Melk-Platte: einfach drauflaufen (funktioniert auch prima am Handy)
	local pad = makePart({
		Name = "MilkPad",
		Size = Vector3.new(3, 0.2, 3.4),
		CFrame = base * CFrame.new(-6.2, 0.1, 1.0),
		Color = Color3.fromRGB(120, 200, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		Parent = spotModel,
	})
	local padLabel = Instance.new("BillboardGui")
	padLabel.Size = UDim2.fromOffset(110, 34)
	padLabel.StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0)
	padLabel.MaxDistance = 35
	padLabel.LightInfluence = 0
	padLabel.Parent = pad
	local padText = Instance.new("TextLabel")
	padText.Size = UDim2.fromScale(1, 1)
	padText.BackgroundColor3 = Color3.fromRGB(25, 27, 38)
	padText.BackgroundTransparency = 0.2
	padText.Font = Enum.Font.FredokaOne
	padText.TextScaled = true
	padText.TextColor3 = Color3.new(1, 1, 1)
	padText.Text = "🥛 Melken"
	padText.Parent = padLabel
	Instance.new("UICorner", padText).CornerRadius = UDim.new(0, 8)
	pad.Touched:Connect(function(hit)
		local character = hit.Parent
		if character and Players:GetPlayerFromCharacter(character) == player then
			startMilking(player, cow.Id, true)
		end
	end)

	-- Anklicken / Antippen zum Melken (nur der Besitzer)
	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 40
	clickDetector.Parent = cowModel
	clickDetector.MouseClick:Connect(function(clicker)
		if clicker ~= player then
			DataService.Notify(clicker, "Das ist nicht deine Kuh! 🐄", "error")
			return
		end
		startMilking(player, cow.Id)
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

	-- Konfetti in der Farbe der Seltenheit
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, info.UiColor),
		ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Speed = NumberRange.new(10, 20)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -20, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-200, 200)
	emitter.LightEmission = 0.5
	emitter.Enabled = false
	emitter.Parent = spot.Torso
	task.delay(0.5, function()
		if emitter.Parent then
			emitter:Emit(info.Tier >= 5 and 120 or 50)
		end
		if spot.Torso.Parent then
			if info.Tier >= 4 then
				playSound(spot.Torso, Config.RareCowSoundId, 1)
			else
				playSound(spot.Torso, Config.NewCowSoundId, 0.8, 1.2)
			end
		end
	end)
	Debris:AddItem(emitter, 3)
end

DataService.CowAdded:Connect(function(player, cow)
	if player.Parent then
		-- schon aufgestellt (z.B. beim Laden) -> keine Feier
		local farm = farms[player]
		local isNew = not (farm and farm.Spots[cow.Id])
		local spot = spawnCow(player, cow)
		refreshCowLabels(player)
		if isNew and spot then
			celebrateNewCow(spot, cow.Rarity)
		end
	end
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
			status.Text = "🪣 Wird gemolken..."
			status.TextColor3 = Color3.fromRGB(200, 230, 255)
		elseif breeding and (breeding.ParentA == cowId or breeding.ParentB == cowId) then
			status.Text = "💕 Zucht " .. formatTime(breeding.ReadyAt - now)
			status.TextColor3 = Color3.fromRGB(255, 150, 200)
		elseif (cow.MilkReadyAt or 0) > now then
			status.Text = "⏳ " .. formatTime(cow.MilkReadyAt - now)
			status.TextColor3 = Color3.fromRGB(255, 200, 100)
		else
			status.Text = "🥛 Bereit zum Melken"
			status.TextColor3 = Color3.fromRGB(130, 255, 140)
		end
	end
end

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
		showPopup(popupPart, "+" .. CowData.FormatNumber(coins) .. " 🪙", Color3.fromRGB(255, 215, 60))
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
		table.insert(cows, { Id = cow.Id, Rarity = cow.Rarity, Name = cow.Name, MilkReadyAt = cow.MilkReadyAt or 0 })
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
					total += CowData.Rarities[cow.Rarity].MilkPerPull
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
	if data.Receipts[receipt.PurchaseId] then
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

	DataService.Save(player)
	announceNewCow(player, cow, CowData.Crates[crateId].DisplayName)
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

	-- Kühe in fester Reihenfolge (nach ID) aufstellen
	local cowList = {}
	for _, cow in pairs(data.Cows) do
		table.insert(cowList, cow)
	end
	table.sort(cowList, function(a, b)
		return (tonumber(a.Id:sub(2)) or 0) < (tonumber(b.Id:sub(2)) or 0)
	end)
	for _, cow in ipairs(cowList) do
		spawnCow(player, cow)
	end
	refreshCowLabels(player)

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
