-- WorldAnimator.client.lua
-- Alles, was sich in der Welt bewegt, läuft hier auf dem Client (flüssig, kein Netzwerkverkehr):
--   * Förderbänder (Tag "ConveyorTile"): RunService.Heartbeat, nach Serverzeit synchron
--   * Kühe (Tag "Cow"): schweben, Kopf dreht, Schwanz wedelt, Ohren flattern, schauen sich um
--     -> Werte per TweenService-Schleifen, angewendet einmal pro Frame mit workspace:BulkMoveTo
--   * Regenbogen-Kuh: sanfter Farbwechsel alle 3 Sekunden
--   * Shops: Hinweis "Klicken zum Öffnen" atmet ruhig, Verkäufer winkt
--   * Sounds: Hintergrund-Musik, Kühe muhen ab und zu

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local CowData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CowData"))
local Config = CowData.Config

local random = Random.new()
local ANIMATION_DISTANCE = 160 -- weiter entfernte Kühe bleiben still (spart Leistung)
local MOO_DISTANCE = 90

local function loopTween(instance, duration, goal, style)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, style or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		goal
	)
	tween:Play()
	return tween
end

local function cameraPosition()
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or Vector3.zero
end

------------------------------------------------------------------------
-- Förderbänder: 6 Kacheln pro Spur, Position aus der Serverzeit berechnet.
-- Erreicht eine Kachel das Ende, springt sie sofort an den Anfang (im Gehäuse unsichtbar).
------------------------------------------------------------------------
local conveyorTiles = {} -- [model] = { Parts, Offsets, ... }

local function registerTile(tile)
	local plate = tile.PrimaryPart or tile:WaitForChild("Plate", 5)
	if not plate then
		return
	end
	local pivot = tile:GetPivot()
	local entry = {
		Parts = {},
		Offsets = {},
		Index = tile:GetAttribute("Index") or 0,
		Direction = tile:GetAttribute("Direction") or 1,
		X = tile:GetAttribute("X") or 0,
		Y = tile:GetAttribute("Y") or 0,
		StartZ = tile:GetAttribute("StartZ") or 0,
		Cycle = tile:GetAttribute("Cycle") or 300,
		Length = tile:GetAttribute("Length") or 50,
		Speed = tile:GetAttribute("Speed") or 22,
	}
	entry.Facing = entry.Direction == 1 and CFrame.identity or CFrame.Angles(0, math.pi, 0)
	for _, part in ipairs(tile:GetDescendants()) do
		if part:IsA("BasePart") then
			table.insert(entry.Parts, part)
			table.insert(entry.Offsets, pivot:ToObjectSpace(part.CFrame))
		end
	end
	conveyorTiles[tile] = entry
end

for _, tile in ipairs(CollectionService:GetTagged("ConveyorTile")) do
	task.spawn(registerTile, tile)
end
CollectionService:GetInstanceAddedSignal("ConveyorTile"):Connect(function(tile)
	task.spawn(registerTile, tile)
end)
CollectionService:GetInstanceRemovedSignal("ConveyorTile"):Connect(function(tile)
	conveyorTiles[tile] = nil
end)

RunService.Heartbeat:Connect(function()
	local now = workspace:GetServerTimeNow()
	local parts, cframes = {}, {}
	for _, tile in pairs(conveyorTiles) do
		local u = (tile.Index * tile.Length + tile.Direction * now * tile.Speed) % tile.Cycle
		local pivot = CFrame.new(tile.X, tile.Y, tile.StartZ + u + tile.Length / 2) * tile.Facing
		for i, part in ipairs(tile.Parts) do
			table.insert(parts, part)
			table.insert(cframes, pivot * tile.Offsets[i])
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)

------------------------------------------------------------------------
-- Kühe
------------------------------------------------------------------------
local cows = {} -- [model] = state

local RAINBOW = {
	Color3.fromRGB(246, 128, 128),
	Color3.fromRGB(246, 178, 104),
	Color3.fromRGB(240, 224, 124),
	Color3.fromRGB(132, 208, 144),
	Color3.fromRGB(124, 182, 244),
	Color3.fromRGB(186, 144, 240),
}

local function newValue(state, initial)
	local value = Instance.new("NumberValue")
	value.Value = initial or 0
	table.insert(state.Instances, value)
	return value
end

local function stopCow(cow)
	local state = cows[cow]
	if not state then
		return
	end
	cows[cow] = nil
	state.Alive = false
	for _, tween in ipairs(state.Tweens) do
		tween:Cancel()
	end
	for _, instance in ipairs(state.Instances) do
		instance:Destroy()
	end
end

local function collect(container, relativeTo)
	local parts, offsets = {}, {}
	for _, part in ipairs(container:GetDescendants()) do
		if part:IsA("BasePart") then
			table.insert(parts, part)
			table.insert(offsets, relativeTo:ToObjectSpace(part.CFrame))
		end
	end
	return parts, offsets
end

local function startCow(cow)
	if cows[cow] then
		return
	end
	local torso = cow:WaitForChild("Torso", 10)
	local headGroup = cow:WaitForChild("HeadGroup", 10)
	local tailGroup = cow:WaitForChild("TailGroup", 10)
	local earLeft = cow:WaitForChild("EarLeft", 10)
	local earRight = cow:WaitForChild("EarRight", 10)
	if not (torso and headGroup and tailGroup and earLeft and earRight) then
		return
	end

	-- neue Kühe fallen erst noch vom Himmel (Server-Animation) -> kurz warten
	task.wait(1.2)
	if not cow:IsDescendantOf(workspace) then
		return
	end

	local base = cow:GetPivot()
	local headPivot = headGroup:GetPivot()
	local state = {
		Alive = true,
		Base = base,
		Tweens = {},
		Instances = {},
		Torso = torso,
		Rested = false,
	}

	-- Körper = alles, was nicht in einer der Gruppen steckt
	state.BodyParts, state.BodyOffsets = {}, {}
	for _, child in ipairs(cow:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(state.BodyParts, child)
			table.insert(state.BodyOffsets, base:ToObjectSpace(child.CFrame))
		end
	end
	state.HeadRel = base:ToObjectSpace(headPivot)
	state.HeadParts, state.HeadOffsets = collect(headGroup, headPivot)
	state.TailRel = base:ToObjectSpace(tailGroup:GetPivot())
	state.TailParts, state.TailOffsets = collect(tailGroup, tailGroup:GetPivot())
	state.EarLRel = headPivot:ToObjectSpace(earLeft:GetPivot())
	state.EarLParts, state.EarLOffsets = collect(earLeft, earLeft:GetPivot())
	state.EarRRel = headPivot:ToObjectSpace(earRight:GetPivot())
	state.EarRParts, state.EarROffsets = collect(earRight, earRight:GetPivot())

	-- Animationswerte (alle per TweenService)
	state.Float = newValue(state, 0) -- Studs nach oben
	state.Turn = newValue(state, 0) -- Grad (ganzer Körper)
	state.HeadYaw = newValue(state, -15) -- Grad
	state.Tail = newValue(state, -20) -- Grad
	state.Ear = newValue(state, 0) -- Grad

	local phase = random:NextNumber(0, 1.5)
	task.delay(phase, function()
		if not state.Alive then
			return
		end
		-- schweben: 0.2 Studs hoch und runter alle 1.5 s
		table.insert(state.Tweens, loopTween(state.Float, 1.5, { Value = 0.2 }))
		-- Kopf: langsam ±15° alle 3 s
		table.insert(state.Tweens, loopTween(state.HeadYaw, 3, { Value = 15 }))
		-- Schwanz: ±20° in 0.8 s (schnell = niedlich)
		table.insert(state.Tweens, loopTween(state.Tail, 0.4, { Value = 20 }))
	end)

	-- Ohren flattern alle 4 s
	task.spawn(function()
		task.wait(random:NextNumber(0, 4))
		while state.Alive do
			for _ = 1, 2 do
				local up = TweenService:Create(state.Ear, TweenInfo.new(0.12), { Value = 25 })
				up:Play()
				up.Completed:Wait()
				local down = TweenService:Create(state.Ear, TweenInfo.new(0.12), { Value = 0 })
				down:Play()
				down.Completed:Wait()
			end
			task.wait(4)
		end
	end)

	-- Alle 5-12 s: Körper 30° drehen (umschauen) und zurück
	task.spawn(function()
		while state.Alive do
			task.wait(random:NextNumber(5, 12))
			if not state.Alive then
				break
			end
			local target = 30 * (random:NextNumber() < 0.5 and -1 or 1)
			local turn = TweenService:Create(state.Turn, TweenInfo.new(0.8, Enum.EasingStyle.Back), { Value = target })
			turn:Play()
			turn.Completed:Wait()
			task.wait(random:NextNumber(1, 2))
			local back = TweenService:Create(state.Turn, TweenInfo.new(0.8, Enum.EasingStyle.Sine), { Value = 0 })
			back:Play()
			back.Completed:Wait()
		end
	end)

	-- Regenbogen: sanfter Farbwechsel (alle 3 s, mit langem Übergang)
	if cow:GetAttribute("Rarity") == "Rainbow" then
		local tintParts = {}
		for _, part in ipairs(cow:GetDescendants()) do
			if part:IsA("BasePart") and part:GetAttribute("Tint") then
				table.insert(tintParts, part)
			end
		end
		task.spawn(function()
			local index = 1
			while state.Alive do
				index = index % #RAINBOW + 1
				for _, part in ipairs(tintParts) do
					TweenService:Create(part, TweenInfo.new(2.8, Enum.EasingStyle.Sine), { Color = RAINBOW[index] }):Play()
				end
				task.wait(1)
			end
		end)
	end

	-- Muhen alle 15-30 s (nur wenn man in der Nähe ist)
	if Config.MooSoundId ~= "" then
		task.spawn(function()
			task.wait(random:NextNumber(2, 20))
			while state.Alive do
				if (cameraPosition() - torso.Position).Magnitude < MOO_DISTANCE then
					local moo = Instance.new("Sound")
					moo.SoundId = Config.MooSoundId
					moo.Volume = 0.6
					moo.PlaybackSpeed = random:NextNumber(0.9, 1.15)
					moo.RollOffMaxDistance = MOO_DISTANCE
					moo.Parent = torso
					moo:Play()
					moo.Ended:Connect(function()
						moo:Destroy()
					end)
				end
				task.wait(random:NextNumber(15, 30))
			end
		end)
	end

	cows[cow] = state
end

for _, cow in ipairs(CollectionService:GetTagged("Cow")) do
	task.spawn(startCow, cow)
end
CollectionService:GetInstanceAddedSignal("Cow"):Connect(function(cow)
	task.spawn(startCow, cow)
end)
CollectionService:GetInstanceRemovedSignal("Cow"):Connect(stopCow)

local function addGroup(parts, cframes, groupParts, groupOffsets, pivot)
	for i, part in ipairs(groupParts) do
		table.insert(parts, part)
		table.insert(cframes, pivot * groupOffsets[i])
	end
end

RunService.Heartbeat:Connect(function()
	local camPos = cameraPosition()
	local parts, cframes = {}, {}

	for cow, state in pairs(cows) do
		if not cow.Parent then
			stopCow(cow)
		elseif (state.Base.Position - camPos).Magnitude < ANIMATION_DISTANCE then
			local beingMilked = cow:GetAttribute("BeingMilked") == true

			-- Während des Melkens steht der Körper still (die Zitzen werden dann vom Melk-Script bewegt)
			local root
			if beingMilked then
				root = state.Base
				if not state.Rested then
					state.Rested = true
					addGroup(parts, cframes, state.BodyParts, state.BodyOffsets, root)
				end
			else
				state.Rested = false
				root = state.Base * CFrame.new(0, state.Float.Value, 0) * CFrame.Angles(0, math.rad(state.Turn.Value), 0)
				addGroup(parts, cframes, state.BodyParts, state.BodyOffsets, root)
			end

			local head = root * state.HeadRel * CFrame.Angles(0, math.rad(state.HeadYaw.Value), 0)
			addGroup(parts, cframes, state.HeadParts, state.HeadOffsets, head)

			local ear = math.rad(state.Ear.Value)
			addGroup(parts, cframes, state.EarLParts, state.EarLOffsets, head * state.EarLRel * CFrame.Angles(0, 0, -ear))
			addGroup(parts, cframes, state.EarRParts, state.EarROffsets, head * state.EarRRel * CFrame.Angles(0, 0, ear))

			local tail = root * state.TailRel * CFrame.Angles(0, 0, math.rad(state.Tail.Value))
			addGroup(parts, cframes, state.TailParts, state.TailOffsets, tail)
		end
	end

	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)

------------------------------------------------------------------------
-- Shops: Hinweis "Klicken zum Öffnen" atmet ruhig, Verkäufer winkt
------------------------------------------------------------------------
local function animateShop(building)
	local billboard = building:WaitForChild("SignAnchor", 10)
	billboard = billboard and billboard:WaitForChild("ShopBillboard", 10)
	local card = billboard and billboard:WaitForChild("Card", 5)
	if card then
		local bounce = card:FindFirstChild("Bounce")
		if bounce then
			bounce.Scale = 1
			loopTween(bounce, 1.2, { Scale = 1.04 }, Enum.EasingStyle.Sine) -- ruhiges Atmen statt Hüpfen
		end
		local hint = card:FindFirstChild("ClickHint")
		local hintShadow = card:FindFirstChild("ClickHintShadow")
		if hint then
			loopTween(hint, 1.2, { TextTransparency = 0.35 }, Enum.EasingStyle.Sine)
		end
		if hintShadow then
			loopTween(hintShadow, 0.5, { TextTransparency = 1 }, Enum.EasingStyle.Linear)
		end
	end
end

for _, building in ipairs(CollectionService:GetTagged("ShopBuilding")) do
	task.spawn(animateShop, building)
end
CollectionService:GetInstanceAddedSignal("ShopBuilding"):Connect(function(building)
	task.spawn(animateShop, building)
end)

local function animateShopKeeper(npc)
	local arm = npc:WaitForChild("RightArm", 10)
	if not arm then
		return
	end
	local home = arm.CFrame
	local shoulder = home * CFrame.new(0, 0.9, 0)
	local angle = Instance.new("NumberValue")
	angle.Value = 130
	angle.Changed:Connect(function(value)
		if arm.Parent then
			arm.CFrame = shoulder * CFrame.Angles(0, 0, math.rad(value)) * CFrame.new(0, -0.9, 0)
		end
	end)
	-- winken: Arm hoch und hin und her
	loopTween(angle, 0.35, { Value = 165 })
	npc.Destroying:Connect(function()
		angle:Destroy()
	end)
end

for _, npc in ipairs(CollectionService:GetTagged("ShopKeeper")) do
	task.spawn(animateShopKeeper, npc)
end
CollectionService:GetInstanceAddedSignal("ShopKeeper"):Connect(function(npc)
	task.spawn(animateShopKeeper, npc)
end)

------------------------------------------------------------------------
-- Hintergrund-Musik
------------------------------------------------------------------------
if Config.AmbientSoundId ~= "" then
	local ambient = Instance.new("Sound")
	ambient.Name = "FarmAmbient"
	ambient.SoundId = Config.AmbientSoundId
	ambient.Looped = true
	ambient.Volume = 0.25
	ambient.Parent = SoundService
	ambient:Play()
end
